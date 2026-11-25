#!/usr/bin/env bash
# scripts/harness/approve-plan: plan 단계의 계획을 사용자가 승인하면 승인 기록(plan.approved)을 남기는지 검사한다(ADR 0031).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
approve="$here/../template/scripts/harness/approve-plan"
stop_hook="$here/../plugin/hooks/stop-gate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
sd="$p/.harness/state"
mkdir -p "$sd" "$p/sub"
echo '{"schemaVersion":1}' > "$p/.harness/project.json"
echo s1 > "$sd/task.owner"
set_stage() { printf '{"title":"스트릭","mode":"plan","stage":"%s","checks":[]}' "$1" > "$sd/task.json"; }

run() { (cd "${2:-$p}" && "$approve" ${1:+"$1"} 2>&1) && echo "rc=0" || echo "rc=$?"; }
last() { printf '%s\n' "$1" | sed -n '$p'; }
first() { printf '%s\n' "$1" | sed -n 1p; }

out="$(run)"
assert_eq "작업이 없으면 2" "rc=2" "$(last "$out")"
assert_eq "  이유" "harness: 진행 중인 작업이 없다 (.harness/state/task.json 없음)" "$(first "$out")"
set_stage implement
out="$(run)"
assert_eq "plan 단계가 아니면 2" "rc=2" "$(last "$out")"
assert_eq "  이유" 'harness: 작업 "스트릭"은 plan 단계가 아니다 (지금 단계: implement)' "$(first "$out")"
set_stage plan
out="$(run)"
assert_eq "계획 글이 없으면 2" "rc=2" "$(last "$out")"
printf '# 계획\n- 스트릭 화면\n' > "$sd/plan.md"
out="$(run --show)"
assert_eq "--show는 계획만 보여 준다" "# 계획" "$(first "$out")"
assert_eq "  승인하지 않는다" "no" "$([ -e "$sd/plan.approved" ] && echo yes || echo no)"
out="$(run "" "$p/sub")"
assert_eq "승인하면 0 (하위 폴더에서도)" "rc=0" "$(last "$out")"
assert_eq "  첫 줄에 승인했다고 알린다" "✓ 계획 승인 · 스트릭" "$(first "$out")"
assert_eq "  계획 글을 plan.approved로 남긴다" "yes" "$(cmp -s "$sd/plan.md" "$sd/plan.approved" && echo yes || echo no)"
assert_eq "  단계 기록에 남긴다" '{"event":"approve","by":"approve-plan"}' "$(tail -1 "$sd/task.history" | jq -c '{event, by}')"
out="$(run)"
assert_eq "이미 승인한 계획이면 그대로 0" "✓ 이미 승인한 계획이다 · 스트릭|rc=0" "$(first "$out")|$(last "$out")"
out="$(run --bogus)"
assert_eq "모르는 인자는 2" "rc=2" "$(last "$out")"

# Stop 훅과 이어서: 승인하면 다음 응답 끝에 implement로 넘어간다.
printf '# 고친 계획\n' > "$sd/plan.md"
stop() { jq -n --arg cwd "$p" '{session_id: "s1", cwd: $cwd}' | "$stop_hook" > /dev/null 2>&1 && echo 0 || echo $?; }
assert_eq "승인 전: Stop 훅은 넘기지 않는다" "0|plan" "$(stop)|$(jq -r .stage "$sd/task.json")"
run > /dev/null
assert_eq "승인 뒤: Stop 훅이 implement로 넘긴다" "2|implement" "$(stop)|$(jq -r .stage "$sd/task.json")"

finish
