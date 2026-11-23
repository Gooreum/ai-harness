#!/usr/bin/env bash
# PreToolUse 훅(ExitPlanMode): 계획을 사용자에게 승인받기 전에 프로젝트의 계획 확인을 돌린다(ADR 0030).
#
# 발표 슬라이드 29: prompt는 시키고 run은 확인한다. 계획 단계 지시(prompt)만으로는 기준을 적용했는지 알 수 없다.
# ai-bouncer는 stages.<단계>.run을 그 단계를 끝내려 할 때(Stop) 돌린다. plan 단계에서 Stop까지 기다리면
# 사용자가 기준이 빠진 계획을 이미 승인한 뒤라, 승인 창이 뜨기 전에 한 번 더 돌린다.
#   - 계획 글(tool_input.plan)을 .harness/state/plan.md에 저장한다. 프로젝트의 확인 명령과 Stop 훅이 이 파일을 본다.
#   - checks.json에 stages.plan.run이 있으면 프로젝트 루트에서 돌린다. 실패하면 이유를 stderr로 내고 2로 끝난다.
#     ExitPlanMode는 실행되지 않고(승인 창이 뜨지 않는다) 이유가 에이전트에게 돌아간다.
#   - run이 100초(HARNESS_PLAN_RUN_TIMEOUT) 안에 끝나지 않으면 막지 않는다. 기록에는 rc 124로 남고 Stop 훅이 다시 확인한다.
#   - 하네스는 계획이 무엇을 담아야 하는지 모른다. 프로젝트가 적은 명령을 돌릴 뿐이다(ADR 0024).
#
# - 입력은 stdin JSON만 읽는다 (session_id, cwd, tool_input.plan, tool_input.planFilePath).
#   Claude Code 2.1.330에서 ExitPlanMode의 PreToolUse 입력에 두 값이 모두 들어오는 것을 확인했다.
# - 작업 주인 세션이 plan 단계에 있을 때만 끼어든다. 하네스 작업이 아닌 계획 모드는 막지 않는다.
# - 판단할 수 없으면(상태 파일 없음, 계획 글 없음, 설정 오류) 막지 않는다. Stop 훅이 다시 확인한다.
set -uo pipefail

input="$(cat)"
command -v jq > /dev/null 2>&1 || exit 0

session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2> /dev/null)" || exit 0
dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2> /dev/null)" || exit 0
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
[ -f "$state_dir/task.json" ] || exit 0
[ "$(cat "$state_dir/task.owner" 2> /dev/null)" = "$session" ] || exit 0
[ "$(jq -r '.stage // empty' "$state_dir/task.json" 2> /dev/null)" = plan ] || exit 0

plan="$(printf '%s' "$input" | jq -r '.tool_input.plan // empty' 2> /dev/null)"
if [ -z "$plan" ]; then
  # 계획 글이 입력에 없으면 입력이 알려 준 계획 파일을 읽는다.
  file="$(printf '%s' "$input" | jq -r '.tool_input.planFilePath // empty' 2> /dev/null)"
  [ -z "$file" ] || [ ! -f "$file" ] || plan="$(cat "$file")"
fi
[ -n "$plan" ] || exit 0
printf '%s\n' "$plan" > "$state_dir/plan.md" 2> /dev/null || exit 0

checks="$root/.harness/checks.json"
srun="$(jq -r '.stages.plan.run // empty' "$checks" 2> /dev/null)" || exit 0
[ -n "$srun" ] || exit 0

# 훅 timeout(hooks.json, 120초)보다 짧게 끊는다. 끊기면 판단할 수 없으니 막지 않고 Stop 훅에 맡긴다.
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
out="$(cd "$root" && run_timeout "${HARNESS_PLAN_RUN_TIMEOUT:-100}" bash -c "$srun" 2>&1)"
rc=$?
jq -nc --arg at "$(date -u +%FT%TZ)" --argjson rc "$rc" \
  '{at: $at, event: "plan-check", stage: "plan", runs: [{name: "stages.plan.run", rc: $rc}]}' \
  >> "$state_dir/task.history" 2> /dev/null || true
[ "$rc" -eq 0 ] || [ "$rc" -eq 124 ] && exit 0

{
  echo "[하네스] 계획이 프로젝트의 계획 확인(stages.plan.run)을 통과하지 못해 승인을 요청하지 않았습니다."
  echo "- run \`$srun\`이 실패했다 (종료 코드 $rc)"
  [ -z "$out" ] || printf '%s\n' "$out" | sed -n '1,10p' | sed 's/^/    /'
  echo "plan 단계 지시의 기준대로 계획을 고친 뒤 ExitPlanMode를 다시 호출하세요. 계획 글은 .harness/state/plan.md에 저장됐습니다."
} >&2
exit 2
