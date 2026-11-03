#!/usr/bin/env bash
# Stop 훅: 작업이 끝나기 전에는 멈추지 못하게 한다.
#
# 발표 슬라이드 14: Stop 훅이 state.json을 보고, 완료 단계가 아니면 멈추지 못하게 막는다.
# 발표 슬라이드 88: 통과하지 못하면 AI는 끝낼 수 없다.
# 발표가 다루지 않는 부분은 ai-bouncer(hooks/stop.sh)를 따른다.
#   - 작업 주인 세션만 막는다(.harness/state/task.owner). 다른 세션은 그냥 끝난다.
#   - 직전과 같은 이유로 다시 막히려는데 그 사이 도구를 하나도 쓰지 않았으면 끝내게 둔다.
#     막아 봐야 같은 답만 되풀이한다(ai-bouncer에서 도구 없는 반복 54건, 최대 939회 관찰).
#   - 같은 단계에서 연속으로 10번(HARNESS_MAX_CONTINUE) 막았으면 더 막지 않고 사용자에게 넘기게 한다.
# ai-bouncer와 다른 점(ADR 0013): 백그라운드 서브에이전트가 돌고 있으면 막지 않는다.
#
# - 입력은 stdin JSON만 읽는다 (session_id, cwd, stop_hook_active, background_tasks).
# - 막을 때는 이유를 stderr로 내고 2로 끝난다(슬라이드 25).
# - 판단할 수 없으면(상태 파일 없음, JSON 오류, 주인 없음) 막지 않는다.
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
# 서브에이전트가 돌고 있으면 기다리는 중이다. 막지 않는다(ADR 0013).
# 서브에이전트가 끝나면 그 알림으로 턴이 다시 열리고, 그때 다시 본다.
# 셸·모니터는 끝나지 않을 수 있어서 넣지 않는다.
waiting="$(printf '%s' "$input" | jq '[.background_tasks[]? | select(.type == "subagent")] | length' 2>/dev/null)"
[ "${waiting:-0}" -gt 0 ] 2>/dev/null && exit 0

title="$(jq -r '.title // ""' "$state" 2>/dev/null)"

reason="[하네스] 작업 \"$title\"이 아직 $stage 단계라 끝낼 수 없습니다.
이 단계의 일을 이어서 하고, 마치면 .harness/state/task.json의 stage를 다음 단계로 바꾸세요. 지금 단계의 지시가 필요하면 task.json을 같은 내용으로 다시 저장하세요.
마무리 보고까지 마치고 stage를 \"done\"으로 바꾸면 끝낼 수 있습니다."

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
  3. 작업을 중단한다 (task.json의 stage를 done으로 바꾸고 이유를 보고한다)" \
    '{hookSpecificOutput: {hookEventName: "Stop", additionalContext: $c}}'
  exit 0
fi
jq -n --arg k "$key" --arg q "$seq" --arg s "$stage" --argjson n "$((streak + 1))" \
  '{key: $k, seq: $q, stage: $s, streak: $n}' > "$gate"
printf '%s\n' "$reason" >&2
exit 2
