#!/usr/bin/env bash
# PostToolUse(Read)·SubagentStop 훅: ios-reviewer가 실제로 리뷰했는지 리뷰어의 말이 아니라 기록으로 남긴다.
#
# 발표 슬라이드 68: 지켰는지는 AI의 말이 아니라 검사 결과로 확인한다.
# 결과 파일 형식과 최신 판정은 다른 검사와 같다(scripts/harness/passed, ai-bouncer `bouncer passed`).
#
# - 입력은 stdin JSON만 읽는다 (hook_event_name, agent_id, agent_type, cwd, tool_input, last_assistant_message).
# - PostToolUse(SubagentHandback): 백그라운드 리뷰어가 넘긴 보고서를 .harness/state/review-<agent_id>.report에 둔다.
#   last_assistant_message에 요약 줄이 없으면 이것을 보고서로 쓴다.
# - PostToolUse(Read): 서브에이전트(agent_id 있음)이고 agent_type이 ios-reviewer면 연 파일을
#   .harness/state/review-<agent_id>.reads에 적는다.
# - SubagentStop: 같은 리뷰어가 끝나면 바뀐 파일을 다 열었는지, 차단 항목이 있는지로 .harness/out/review.json을 쓴다.
#   - passed: 바뀐 파일을 모두 열었고, 보고서의 차단이 0
#   - 바뀐 파일은 scripts/harness/unit-test와 같은 기준(작업을 시작한 커밋 이후, .harness/ 제외)이고,
#     지운 파일과 이미지·영상 같은 바이너리는 뺀다.
# - 막지 않는다. 판단할 수 없으면 아무것도 하지 않고 0으로 끝난다.
set -uo pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

field() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
event="$(field .hook_event_name)"
agent_id="$(field .agent_id)"
agent_type="$(field .agent_type)"
[ -n "$agent_id" ] || exit 0
case "$agent_type" in
  ios-reviewer | *:ios-reviewer) ;;
  *) exit 0 ;;
esac
case "$agent_id" in
  */* | .*) exit 0 ;;
esac

# 프로젝트 루트: cwd에서 위로 올라가며 .harness/project.json을 찾는다.
dir="$(field .cwd)"
[ -n "$dir" ] || exit 0
while [ "$dir" != "/" ] && [ ! -f "$dir/.harness/project.json" ]; do dir="$(dirname "$dir")"; done
[ -f "$dir/.harness/project.json" ] || exit 0
root="$dir"
state="$root/.harness/state"
reads="$state/review-$agent_id.reads"

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

# 목록(stdin)에서 리뷰어가 열어야 하는 파일만 남긴다: 있는 파일, 이미지·영상 같은 바이너리 제외. 루트 기준 경로.
reviewable() {
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "$f" in
      *.png | *.jpg | *.jpeg | *.gif | *.heic | *.pdf | *.mp4 | *.mov | *.zip | *.ttf | *.otf) continue ;;
    esac
    printf '%s\n' "$f"
  done
}

case "$event" in
  PostToolUse)
    tool="$(field .tool_name)"
    if [ "$tool" = SubagentHandback ]; then
      # 백그라운드 리뷰어는 보고서를 이 도구로 넘긴다. 그러면 SubagentStop의 last_assistant_message에 보고서가 없다.
      mkdir -p "$state" && field .tool_input.message > "$state/review-$agent_id.report"
      exit 0
    fi
    [ "$tool" = Read ] || exit 0
    file="$(field .tool_input.file_path)"
    [ -n "$file" ] || exit 0
    case "$file" in
      /*) ;;
      *) file="$(field .cwd)/$file" ;;
    esac
    case "$file" in
      "$root"/*) rel="${file#"$root"/}" ;;
      *) exit 0 ;;
    esac
    mkdir -p "$state" && printf '%s\n' "$rel" >> "$reads"
    ;;

  SubagentStop)
    git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || exit 0
    # 바뀐 파일: scripts/harness/lib.sh의 harness_changed_files와 같은 기준이다. 작업 중이면 작업을 시작한 커밋 이후의
    # 변경과, 추적 안 된 파일 중 작업을 시작한 뒤에 고친 것. 작업 전부터 있던 파일은 리뷰 대상이 아니다.
    # 루트가 git 하위 폴더(모노레포)면 --relative로 루트 기준 경로를 받는다. 없으면 저장소 기준 경로라 열어 본 파일과 맞지 않는다.
    from=HEAD started=""
    stage="$(jq -r '.stage // ""' "$state/task.json" 2>/dev/null)" || stage=""
    if [ -n "$stage" ] && [ "$stage" != done ] && [ -f "$state/task.base" ]; then
      sha="$(cat "$state/task.base")"
      if git -C "$root" cat-file -e "$sha^{commit}" 2>/dev/null; then
        from="$sha"
        [ -f "$state/task.started" ] && started="$(mtime "$state/task.started")"
      fi
    fi
    changed="$(cd "$root" && {
        git diff --name-only --relative "$from" 2>/dev/null
        git ls-files -o --exclude-standard | while IFS= read -r f; do
          if [ -n "$started" ] && [ "$(mtime "$f")" -lt "$started" ]; then continue; fi
          printf '%s\n' "$f"
        done
      } | { grep -v '^\.harness/' || true; } | LC_ALL=C sort -u | reviewable)"
    read_list=""
    [ -f "$reads" ] && read_list="$(LC_ALL=C sort -u "$reads")"
    report="$(field .last_assistant_message)"
    if ! printf '%s' "$report" | grep -qE '요약 · 차단 [0-9]+|^발견 없음' && [ -f "$state/review-$agent_id.report" ]; then
      report="$(cat "$state/review-$agent_id.report")"
    fi
    out="$root/.harness/out"
    mkdir -p "$out"
    jq -n --arg changed "$changed" --arg read "$read_list" --arg report "$report" --arg agent "$agent_id" '
      def lines: split("\n") | map(select(. != ""));
      ($changed | lines) as $c | ($read | lines) as $r
      | ($c - $r) as $missing
      | (first($report | capture("요약 · 차단 (?<n>[0-9]+)")? | .n | tonumber) // null) as $blocking
      | ($report | test("^발견 없음")) as $clean
      | (if $clean then 0 else $blocking end) as $b
      | { passed: (($missing | length) == 0 and $b == 0),
          blocking: $b, changed: $c, read: $r, missing: $missing, agentId: $agent,
          summary: (if ($missing | length) > 0 then "리뷰어가 바뀐 파일을 열지 않았다: \($missing | join(", "))"
                    elif $b == null then "리뷰어 보고서에서 요약 줄(요약 · 차단 N)을 찾지 못했다"
                    elif $b > 0 then "차단 \($b)개가 남았다 — 고친 뒤 리뷰를 다시 맡긴다"
                    else "리뷰 통과 · 검토한 파일 \($r | length)개" end) }' > "$out/review.json.tmp" \
      && mv "$out/review.json.tmp" "$out/review.json"
    rm -f "$reads" "$state/review-$agent_id.report"
    ;;
esac
exit 0
