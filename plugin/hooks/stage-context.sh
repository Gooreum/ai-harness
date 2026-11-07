#!/usr/bin/env bash
# PostToolUse 훅: 작업 상태 파일(.harness/state/task.json)을 쓰면 지금 단계에서 할 일을 지시로 넣는다.
# 에이전트가 이 파일을 쓰는 것은 작업을 시작할 때, 이어서 할 때(같은 내용으로 다시 저장), 취소할 때뿐이다.
# 단계는 Stop 훅(stop-gate.sh)이 넘기고, 그때 다음 단계 지시도 함께 준다(ai-bouncer hooks/stop.sh, ADR 0027).
#
# - 입력은 stdin JSON만 읽는다 (tool_input.file_path, cwd). Codex에서도 재사용하기 위해서다.
# - 훅은 검사 내용을 모른다. .harness/checks.json에 적힌 글을 단계에 맞춰 옮길 뿐이다(발표 슬라이드 27).
# - 지시는 hookSpecificOutput.additionalContext로 내보내고 0으로 끝난다. 막지 않는다.
# - 상태 파일을 고친 세션을 작업의 주인으로 .harness/state/task.owner에 적는다. Stop 훅(stop-gate.sh)은
#   주인 세션만 막는다. 다른 세션까지 막지 않기 위해서다(ai-bouncer의 .active 세션 소유와 같다).
# - 상태 파일이 아니거나 판단할 수 없으면 아무것도 출력하지 않는다.
set -uo pipefail

input="$(cat)"
# jq가 없으면 하네스의 훅이 모두 아무것도 하지 않는다. 상태 파일을 고친 때만 jq 없이 고정 문구로 알린다.
if ! command -v jq >/dev/null 2>&1; then
  case "$input" in
    *'.harness/state/task.json'*)
      printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"jq가 없어 harness 플러그인의 훅(단계 지시, Stop 게이트, 생성 파일 보호)이 모두 꺼져 있다. 사용자에게 jq를 설치하라고 알린다(macOS 15 이상은 /usr/bin/jq 기본 포함). scripts/harness/doctor로 확인한다."}}'
      ;;
  esac
  exit 0
fi

file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
case "$file" in
  "") exit 0 ;;
  /*) ;;
  *)
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
    [ -n "$cwd" ] || exit 0
    file="$cwd/$file"
    ;;
esac
case "$file" in
  */.harness/state/task.json) ;;
  *) exit 0 ;;
esac
root="${file%/.harness/state/task.json}"
[ -f "$root/.harness/project.json" ] || exit 0

emit() {
  jq -n --arg c "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
  exit 0
}

[ -f "$file" ] || exit 0
session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
[ -z "$session" ] || printf '%s\n' "$session" > "$root/.harness/state/task.owner" 2>/dev/null || true
# 새 작업을 시작하면 시작 시각(task.started의 수정 시각)과 시작 커밋(task.base)을 적는다.
# scripts/harness/passed는 시작 전 결과를 거절하고, 바뀐 파일을 시작 커밋부터 본다(ai-bouncer start의 .started·base_sha).
# 새 작업인지는 지난번에 본 단계(task.seen)로 정한다: 본 적이 없거나 done이었는데 지금은 done이 아니면 새 작업이다.
# 제목으로 구분하면 같은 제목으로 다시 시작한 작업이 지난 결과로 통과한다.
stage_now="$(jq -r '.stage // ""' "$file" 2>/dev/null)" || stage_now=""
seen_file="$root/.harness/state/task.seen"
seen="$(cat "$seen_file" 2>/dev/null || true)"
if [ -n "$stage_now" ] && [ "$stage_now" != done ] && { [ -z "$seen" ] || [ "$seen" = done ]; }; then
  date -u +%FT%TZ > "$root/.harness/state/task.started" 2>/dev/null || true
  git -C "$root" rev-parse --verify -q HEAD > "$root/.harness/state/task.base" 2>/dev/null \
    || rm -f "$root/.harness/state/task.base"
fi
[ -z "$stage_now" ] || printf '%s\n' "$stage_now" > "$seen_file" 2>/dev/null || true
jq -e . "$file" >/dev/null 2>&1 || emit "[하네스] .harness/state/task.json이 JSON 형식이 아닙니다. 고쳐서 다시 저장하세요."
checks="$root/.harness/checks.json"
if [ -f "$checks" ]; then
  jq -e . "$checks" >/dev/null 2>&1 || emit "[하네스] .harness/checks.json이 JSON 형식이 아닙니다. 사용자에게 알리세요."
else
  checks=""
fi

# 모드별 단계 순서는 flows.json, 단계 지시 글은 stage-text.jq 한 곳에 둔다. stop-gate.sh도 같은 파일을 읽는다.
here="$(dirname "$0")"
flows="$(cat "$here/flows.json" 2>/dev/null)" || exit 0
context="$(jq -r --argjson flows "$flows" --slurpfile conf <(if [ -n "$checks" ]; then cat "$checks"; else echo '{}'; fi) \
  -f "$here/stage-text.jq" "$file" 2>/dev/null)" || exit 0
[ -n "$context" ] && emit "$context"
exit 0
