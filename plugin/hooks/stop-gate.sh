#!/usr/bin/env bash
# Stop 훅: 에이전트가 응답을 마치려 할 때 지금 단계를 확인하고 다음 단계로 넘긴다. 작업이 끝나기 전에는 멈추지 못한다.
#
# 발표 슬라이드 14: Stop 훅이 state.json을 보고, 완료 단계가 아니면 멈추지 못하게 막는다.
# 발표 슬라이드 29·30·88: 다음 단계로 넘어가려 하면 훅이 run을 돌린다. 통과하면 넘어가고, 실패하면 못 넘어간다.
# 단계는 이 훅만 넘긴다. 에이전트는 task.json의 단계를 고치지 않는다(guard-state.sh가 막는다).
#   발표는 AI가 단계를 고쳐 적었지만, Bash로 고치면 훅이 돌지 않아 검사를 건너뛸 수 있었다.
#   ai-bouncer(hooks/stop.sh)처럼 훅이 단계를 쓴다(ADR 0027).
#   - 검증 단계면 고른 검사의 run을 프로젝트 루트에서 돌린다. 하나라도 실패하면 이유를 주고 막는다. 단계는 그대로다.
#   - 통과했거나 run이 없는 단계면 task.json의 stage를 다음 단계로 쓰고, 다음 단계 지시를 주며 막는다.
#   - 마지막 단계(finish)를 마치면 stage를 done으로 쓰고 끝내게 둔다.
# 발표가 다루지 않는 부분은 ai-bouncer(hooks/stop.sh)를 따른다.
#   - 작업 주인 세션만 본다(.harness/state/task.owner). 다른 세션은 그냥 끝난다.
#   - 직전과 같은 이유로 다시 막히려는데 그 사이 도구를 하나도 쓰지 않았으면 끝내게 둔다.
#     막아 봐야 같은 답만 되풀이한다(ai-bouncer에서 도구 없는 반복 54건, 최대 939회 관찰).
#   - 같은 단계에서 연속으로 10번(HARNESS_MAX_CONTINUE) 막았으면 더 막지 않고 사용자에게 넘기게 한다.
# ai-bouncer와 다른 점(ADR 0013): 백그라운드 서브에이전트가 돌고 있으면 막지도 넘기지도 않는다.
#
# - 입력은 stdin JSON만 읽는다 (session_id, cwd, stop_hook_active, background_tasks).
# - 막을 때는 이유를 stderr로 내고 2로 끝난다(슬라이드 25).
# - 판단할 수 없으면(상태 파일 없음, JSON 오류, 주인 없음, 모르는 모드·단계) 막지 않는다.
set -uo pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)" || exit 0
dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)" || exit 0
reentry="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[ -n "$session" ] && [ -n "$dir" ] || exit 0
root=""
while [ -n "$dir" ] && [ "$dir" != "/" ]; do
  if [ -f "$dir/.harness/project.json" ]; then
    root="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done
[ -n "$root" ] || exit 0
state_dir="$root/.harness/state"
state="$state_dir/task.json"
[ -f "$state" ] || exit 0
[ "$(cat "$state_dir/task.owner" 2>/dev/null)" = "$session" ] || exit 0

stage="$(jq -r '.stage // empty' "$state" 2>/dev/null)" || exit 0
gate="$state_dir/stop-gate.json"
case "$stage" in
  "" | done)
    rm -f "$gate"
    exit 0
    ;;
esac
# 서브에이전트가 돌고 있으면 기다리는 중이다. 막지도 넘기지도 않는다(ADR 0013).
# 서브에이전트가 끝나면 그 알림으로 턴이 다시 열리고, 그때 다시 본다.
# 셸·모니터는 끝나지 않을 수 있어서 넣지 않는다.
waiting="$(printf '%s' "$input" | jq '[.background_tasks[]? | select(.type == "subagent")] | length' 2>/dev/null)"
[ "${waiting:-0}" -gt 0 ] 2>/dev/null && exit 0

title="$(jq -r '.title // ""' "$state" 2>/dev/null)"
here="$(dirname "$0")"
flows="$(cat "$here/flows.json" 2>/dev/null)" || exit 0
# 이 모드의 단계 순서에서 지금 단계 다음(마지막이면 done). 모르는 모드·단계면 빈 값.
next="$(jq -r --argjson flows "$flows" '
  .stage as $s
  | ($flows[.mode] // null) as $f
  | if $f == null then empty
    else ($f | index($s)) as $i
      | if $i == null then empty elif $i + 1 < ($f | length) then $f[$i + 1] else "done" end
    end' "$state" 2>/dev/null)" || exit 0
[ -n "$next" ] || exit 0

# 같은 이유로 막기를 되풀이하지 않게 한다(ai-bouncer guarded_block과 같다).
guarded_block() {
  local reason="$1" key seq prev streak max
  # 숫자는 뺀다. 횟수·시각이 바뀌어도 같은 차단은 같은 차단이다(ai-bouncer와 같다).
  key="$stage:$(printf '%s' "$reason" | tr -d '0-9' | cksum | cut -d' ' -f1)"
  seq="$(cat "$state_dir/tool-seq" 2>/dev/null)"
  case "$seq" in '' | *[!0-9]*) seq=0 ;; esac
  prev="$(cat "$gate" 2>/dev/null)"
  jq -e . > /dev/null 2>&1 <<<"$prev" || prev='{}'
  if [ "$reentry" = "true" ] \
    && [ "$(jq -r '.key // ""' <<<"$prev")" = "$key" ] \
    && [ "$(jq -r '.seq // ""' <<<"$prev")" = "$seq" ]; then
    exit 0
  fi
  streak="$(jq -r --arg s "$stage" 'if .stage == $s then (.streak // 0) else 0 end' <<<"$prev")"
  max="${HARNESS_MAX_CONTINUE:-10}"
  if [ "$streak" -ge "$max" ] 2> /dev/null; then
    jq -n --arg k "$key" --arg q "$seq" --arg s "$stage" '{key: $k, seq: $q, stage: $s, streak: 0}' > "$gate"
    jq -n --arg c "$reason

${max}번 연속으로 $stage 단계를 벗어나지 못했다. 더 밀지 않고 사용자에게 넘긴다.
AskUserQuestion으로 물어라(도구가 없으면 글로 보여 주고 답을 기다린다):
  1. 계속 시도한다
  2. 접근을 바꾼다
  3. 작업을 취소한다 (task.json의 stage를 \"done\"으로, \"cancelled\": true를 더해 Write로 저장하고 이유를 보고한다)" \
      '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: $c}}'
    exit 0
  fi
  jq -n --arg k "$key" --arg q "$seq" --arg s "$stage" --argjson n "$((streak + 1))" \
    '{key: $k, seq: $q, stage: $s, streak: $n}' > "$gate"
  printf '%s\n' "$reason" >&2
  exit 2
}

# run에 시간 제한을 둔다. 합계가 훅 timeout(hooks.json, 1800초)보다 짧아야 한다(ai-bouncer와 같은 1700초).
run_timeout() { # 초 명령...
  local secs="$1" pid waited=0
  shift
  "$@" &
  pid=$!
  while kill -0 "$pid" 2> /dev/null; do
    if [ "$waited" -ge "$((secs * 5))" ]; then
      pkill -TERM -P "$pid" 2> /dev/null
      kill -TERM "$pid" 2> /dev/null
      wait "$pid" 2> /dev/null
      return 124
    fi
    sleep 0.2
    waited=$((waited + 1))
  done
  wait "$pid"
}

checks="$root/.harness/checks.json"
jq -e . "$checks" > /dev/null 2>&1 || checks=""

# --- 1. 검사: 검증 단계면 고른 검사의 run을 돌린다 ----------------------------------------
if [ "$stage" = verify ]; then
  names="$(jq -r '(.checks // [])[]' "$state" 2>/dev/null)" || names=""
  failures=""
  if [ -n "$names" ] && [ -z "$checks" ]; then
    failures="- .harness/checks.json이 없거나 JSON 형식이 아니라 고른 검사를 확인할 수 없다. 사용자에게 알린다"$'\n'
    names=""
  fi
  deadline=$(($(date +%s) + ${HARNESS_RUN_BUDGET:-1700}))
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    # 고른 검사가 설정에 없으면(이름이 바뀌었거나 오타) run을 찾을 수 없다. 건너뛰면 검사 없이 통과로 보이므로 막는다.
    if ! jq -e --arg n "$name" 'any(.checks[]?; .name == $n)' "$checks" > /dev/null 2>&1; then
      failures="$failures- ${name}: .harness/checks.json에 없는 검사다. 고른 검사를 임의로 빼지 말고 사용자에게 알린다"$'\n'
      continue
    fi
    run="$(jq -r --arg n "$name" '[.checks[]? | select(.name == $n)][0].run // empty' "$checks")"
    [ -n "$run" ] || continue
    # 예산을 다 써도 남은 run은 1초로라도 돌려 시간 초과로 보고한다. 건너뛰면 통과로 보인다.
    left=$((deadline - $(date +%s)))
    [ "$left" -gt 0 ] || left=1
    out="$(cd "$root" && run_timeout "$left" bash -c "$run" 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      case "$rc" in
        124) why="시간이 초과됐다 (${HARNESS_RUN_BUDGET:-1700}초). run은 결과 파일만 보게 하고, 검사 자체는 prompt대로 먼저 실행한다" ;;
        127) why="명령을 찾을 수 없다. 경로·도구 설치를 확인한다" ;;
        *) why="실패했다" ;;
      esac
      failures="$failures- ${name}: run \`$run\`이 $why (종료 코드 $rc)"$'\n'
      [ -z "$out" ] || failures="$failures$(printf '%s\n' "$out" | sed -n '1,10p' | sed 's/^/    /')"$'\n'
    fi
  done <<< "$names"
  if [ -n "$failures" ]; then
    guarded_block "[하네스] 검사를 통과하지 못해 다음 단계로 넘어갈 수 없습니다. 작업 \"$title\"은 아직 verify 단계입니다.
${failures}실패한 검사의 prompt대로 다시 실행해 원인을 고치고, 통과한 뒤에 응답을 마치세요. 그때 다시 확인합니다."
  fi
fi

# --- 2. 전이: 다음 단계를 쓴다 -----------------------------------------------------------
tmp="$state.tmp.$$"
if ! jq --arg n "$next" '.stage = $n' "$state" > "$tmp" 2> /dev/null || ! mv "$tmp" "$state"; then
  rm -f "$tmp"
  guarded_block "[하네스] 작업 \"$title\"을 다음 단계로 넘기지 못했습니다(.harness/state/task.json을 쓰지 못함). 사용자에게 알리세요."
fi
# 단계 지시 훅(stage-context.sh)이 새 작업인지 가릴 때 보는 값이다. 훅이 쓴 단계도 본 것으로 적는다.
printf '%s\n' "$next" > "$state_dir/task.seen" 2> /dev/null || true
rm -f "$gate"

# 마지막 단계까지 마쳤다. 이제야 멈출 수 있다.
[ "$next" = done ] && exit 0

text="$(jq -r --argjson flows "$flows" --slurpfile conf <(if [ -n "$checks" ]; then cat "$checks"; else echo '{}'; fi) \
  -f "$here/stage-text.jq" "$state" 2> /dev/null)" || text=""
printf '%s\n' "[하네스] $stage 단계를 마쳤습니다 → $next 단계로 넘어갑니다." "$text" >&2
exit 2
