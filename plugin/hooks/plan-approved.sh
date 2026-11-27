#!/usr/bin/env bash
# PostToolUse 훅(ExitPlanMode): 사용자가 계획 승인 창에서 승인하면 그 계획을 승인된 계획(.harness/state/plan.approved)으로 남긴다.
#
# 발표(슬라이드 17)와 ai-bouncer(engine/prompts/plan.md)는 계획 승인을 지시로만 둔다. 승인 없이도 다음 단계로 넘어간다.
# 하네스는 승인된 계획이 있어야 Stop 훅(stop-gate.sh)이 plan 단계를 넘긴다(ADR 0031). 승인은 두 길로만 생긴다.
#   - 대화형 세션: 이 훅. ExitPlanMode가 실제로 실행됐을 때(사용자가 승인했을 때)만 PostToolUse가 돈다.
#     거부하면 도구가 실행되지 않아 이 훅도 돌지 않는다.
#   - ExitPlanMode가 없는 세션(claude -p): 사용자가 scripts/harness/approve-plan을 실행한다.
#
# - 입력은 stdin JSON만 읽는다 (session_id, cwd). 계획 글은 plan-gate.sh가 ExitPlanMode 직전에 plan.md로 저장해 두었다.
# - 작업 주인 세션이 plan 단계에 있을 때만 쓴다. 하네스 작업이 아닌 계획 모드는 건드리지 않는다.
# - 판단할 수 없으면(상태 파일 없음, 계획 글 없음) 아무것도 하지 않는다. 그러면 Stop 훅이 넘기지 않고 승인을 기다린다.
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
[ -s "$state_dir/plan.md" ] || exit 0

cp "$state_dir/plan.md" "$state_dir/plan.approved" 2> /dev/null || exit 0
jq -nc --arg at "$(date -u +%FT%TZ)" '{at: $at, event: "approve", stage: "plan", by: "ExitPlanMode"}' \
  >> "$state_dir/task.history" 2> /dev/null || true
exit 0
