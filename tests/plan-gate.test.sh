#!/usr/bin/env bash
# 계획 확인 훅(plan-gate.sh): ExitPlanMode 직전에 계획 글을 저장하고, 프로젝트의 stages.plan.run이 실패하면 막는지 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
hook="$here/../plugin/hooks/plan-gate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
sd="$p/.harness/state"
mkdir -p "$sd" "$p/sub"
echo '{"schemaVersion":1}' > "$p/.harness/project.json"
cat > "$p/.harness/checks.json" <<'JSON'
{ "schemaVersion": 1,
  "stages": { "plan": { "run": "grep -q '^- e2e 판단: ' .harness/state/plan.md || { echo 'e2e 판단 줄이 없다'; exit 1; }" } } }
JSON
echo s1 > "$sd/task.owner"
set_stage() { printf '{"title":"스트릭","mode":"plan","stage":"%s","checks":[]}' "$1" > "$sd/task.json"; }

gate() { # 세션 계획글 [cwd] [계획 파일]
  jq -n --arg s "$1" --arg plan "$2" --arg cwd "${3:-$p}" --arg f "${4:-}" \
    '{hook_event_name: "PreToolUse", tool_name: "ExitPlanMode", session_id: $s, cwd: $cwd,
      tool_input: ({plan: $plan} + (if $f == "" then {} else {planFilePath: $f} end))}' \
    | "$hook" 2> "$work/err" && echo 0 || echo $?
}
has() { case "$2" in *"$1"*) echo yes ;; *) echo no ;; esac; }

good=$'# 계획\n- e2e 판단: 필요 (N1)\n- e2e 시나리오: .maestro/streak.yaml'
bad=$'# 계획\n- 스트릭 화면을 만든다'

# --- 끼어들지 않는 경우 --------------------------------------------------------
set_stage implement
assert_eq "plan 단계가 아니면 막지 않는다" "0" "$(gate s1 "$bad")"
set_stage plan
assert_eq "다른 세션은 막지 않는다" "0" "$(gate s2 "$bad")"
assert_eq "프로젝트 밖이면 막지 않는다" "0" "$(gate s1 "$bad" "$work")"
[ ! -e "$sd/plan.md" ] && saved=no || saved=yes
assert_eq "  끼어들지 않으면 계획 글도 저장하지 않는다" "no" "$saved"

# --- 확인 -----------------------------------------------------------------------
assert_eq "확인을 통과하지 못하면 2로 막는다" "2" "$(gate s1 "$bad")"
err="$(cat "$work/err")"
assert_eq "  첫 줄에 승인을 요청하지 않았다고 알린다" "[하네스] 계획이 프로젝트의 계획 확인(stages.plan.run)을 통과하지 못해 승인을 요청하지 않았습니다." "$(printf '%s\n' "$err" | sed -n 1p)"
assert_eq "  run의 출력을 보여 준다" "yes" "$(has "e2e 판단 줄이 없다" "$err")"
assert_eq "  계획 글을 plan.md에 저장한다" "$bad" "$(cat "$sd/plan.md")"
assert_eq "  단계 기록에 남긴다" '{"event":"plan-check","rc":1}' "$(tail -1 "$sd/task.history" | jq -c '{event, rc: .runs[0].rc}')"
assert_eq "확인을 통과하면 막지 않는다" "0" "$(gate s1 "$good")"
assert_eq "  새 계획 글로 바꿔 저장한다" "$good" "$(cat "$sd/plan.md")"
assert_eq "하위 폴더에서도 프로젝트를 찾는다" "2" "$(gate s1 "$bad" "$p/sub")"

printf '%s\n' "$good" > "$work/plan-file.md"
assert_eq "계획 글이 없으면 계획 파일을 읽는다" "0" "$(gate s1 "" "$p" "$work/plan-file.md")"
assert_eq "  (파일 내용을 저장한다)" "$good" "$(cat "$sd/plan.md")"

printf 'not json' > "$p/.harness/checks.json"
assert_eq "checks.json이 JSON이 아니면 막지 않는다" "0" "$(gate s1 "$bad")"
echo '{"stages":{"plan":{"run":"sleep 5"}}}' > "$p/.harness/checks.json"
assert_eq "run이 시간 제한을 넘으면 막지 않는다" "0" "$(HARNESS_PLAN_RUN_TIMEOUT=1 gate s1 "$bad")"
assert_eq "  기록에 124로 남긴다" "124" "$(tail -1 "$sd/task.history" | jq -r '.runs[0].rc')"
mv "$sd/task.json" "$work/task.bak"
assert_eq "상태 파일이 없으면 막지 않는다" "0" "$(gate s1 "$bad")"
mv "$work/task.bak" "$sd/task.json"
echo '{"schemaVersion":1}' > "$p/.harness/checks.json"
assert_eq "stages.plan.run이 없으면 막지 않는다" "0" "$(gate s1 "$bad")"
assert_eq "  (계획 글은 저장한다)" "$bad" "$(cat "$sd/plan.md")"

# --- 승인 기록 훅(plan-approved.sh, ADR 0031) -------------------------------------
approved_hook="$here/../plugin/hooks/plan-approved.sh"
post() { # 세션 [cwd]
  jq -n --arg s "$1" --arg cwd "${2:-$p}" '{hook_event_name: "PostToolUse", tool_name: "ExitPlanMode", session_id: $s, cwd: $cwd}' \
    | "$approved_hook" && echo 0 || echo $?
}
rm -f "$sd/plan.approved"
printf '%s\n' "$good" > "$sd/plan.md"
set_stage implement
assert_eq "승인 훅: plan 단계가 아니면 쓰지 않는다" "0|no" "$(post s1)|$([ -e "$sd/plan.approved" ] && echo yes || echo no)"
set_stage plan
assert_eq "승인 훅: 다른 세션이면 쓰지 않는다" "0|no" "$(post s2)|$([ -e "$sd/plan.approved" ] && echo yes || echo no)"
assert_eq "승인 훅: 승인되면 계획 글을 plan.approved로 남긴다" "0|yes" "$(post s1)|$(cmp -s "$sd/plan.md" "$sd/plan.approved" && echo yes || echo no)"
assert_eq "  단계 기록에 남긴다" '{"event":"approve","by":"ExitPlanMode"}' "$(tail -1 "$sd/task.history" | jq -c '{event, by}')"
rm -f "$sd/plan.approved" "$sd/plan.md"
assert_eq "승인 훅: 계획 글이 없으면 쓰지 않는다" "0|no" "$(post s1)|$([ -e "$sd/plan.approved" ] && echo yes || echo no)"

finish
