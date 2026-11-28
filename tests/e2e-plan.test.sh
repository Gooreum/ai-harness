#!/usr/bin/env bash
# e2e-plan: 계획서의 e2e 판단(plan), 시나리오 작성(written), 계획한 시나리오 실행(ran)을 가짜 프로젝트로 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
e2e="$here/../template/scripts/harness/e2e-plan"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/.harness/state" "$p/.harness/out" "$p/.maestro"
echo '{"schemaVersion":1}' > "$p/.harness/project.json"
cat > "$p/.harness/checks.json" <<'JSON'
{ "schemaVersion": 1,
  "checks": [
    { "name": "unit", "run": "true" },
    { "name": "e2e-ios", "e2e": true, "run": "true" },
    { "name": "e2e-android", "e2e": true, "run": "true" } ] }
JSON
echo 'appId: x' > "$p/.maestro/home.yaml"
(cd "$p" && git init -q -b main && git add -A && git -c user.email=t@t -c user.name=t commit -qm init)
git -C "$p" rev-parse HEAD > "$p/.harness/state/task.base"
touch "$p/.harness/state/task.started"
task() { jq -nc --argjson c "$1" '{title: "t", mode: "plan", stage: "plan", checks: $c}' > "$p/.harness/state/task.json"; }
task '[]'
run() { (cd "$p" && "$e2e" "$@" 2>&1); }
code() { (cd "$p" && "$e2e" "$@" > /dev/null 2>&1) && echo 0 || echo $?; }
has() { case "$2" in *"$1"*) echo yes ;; *) echo no ;; esac; }
plan() { printf '%s\n' "$@" > "$p/.harness/state/plan.md"; }

# --- 꺼짐 ---------------------------------------------------------------------------------
assert_eq "e2e.scenarios가 없으면 확인하지 않는다" "0|yes" "$(code plan)|$(has "확인하지 않음" "$(run plan)")"
echo '{"schemaVersion":1,"e2e":{"scenarios":".maestro/"}}' > "$p/.harness/project.json"

# --- plan -----------------------------------------------------------------------------------
assert_eq "plan: 계획서가 없으면 실패" "1" "$(code plan)"
plan "# 계획" "- 화면을 고친다"
assert_eq "plan: 판단 줄이 없으면 실패" "1|yes" "$(code plan)|$(has "e2e 판단:" "$(run plan)")"
plan "- e2e 판단: 아마 (N1) 새 화면"
assert_eq "plan: 판단 종류가 틀리면 실패" "1" "$(code plan)"
plan "- e2e 판단: 필요 (N1)"
assert_eq "plan: 이유가 없으면 실패" "1" "$(code plan)"
plan "- e2e 판단: 불필요 (U1) 색만 바뀐다"
assert_eq "plan: 불필요는 시나리오 없이 통과" "0" "$(code plan)"
plan "- e2e 판단: 불필요 (N1) 색만 바뀐다"
assert_eq "plan: 불필요의 근거는 U 번호만" "1" "$(code plan)"
plan "- e2e 판단: 불필요 (U1) 색" "- e2e 시나리오: .maestro/a.yaml"
assert_eq "plan: 불필요인데 시나리오 줄이 있으면 실패" "1" "$(code plan)"
plan "- e2e 판단: 필요 (N1) 새 화면"
assert_eq "plan: 필요인데 시나리오 줄이 없으면 실패" "1" "$(code plan)"
plan "- e2e 판단: 필요 (N1) 새 화면" "- e2e 시나리오: flows/a.yaml" "  - 시작점: 홈" "  - 동작: 누름" "  - 확인: 보임" "- e2e 실행: 안 함"
assert_eq "plan: 시나리오는 시나리오 폴더 아래" "1|yes" "$(code plan)|$(has ".maestro/ 아래" "$(run plan)")"
plan "- e2e 판단: 필요 (N1) 새 화면" "- e2e 시나리오: .maestro/a.yaml" "  - 시작점: 홈" "  - 동작: 누름" "- e2e 실행: 안 함"
assert_eq "plan: 필요면 시작점·동작·확인이 다 있어야" "1|yes" "$(code plan)|$(has "a.yaml 확인" "$(run plan)")"
plan "- e2e 판단: 필요 (N1) 새 화면" "- e2e 시나리오: .maestro/a.yaml" "  - 시작점: 홈" "  - 동작: 누름" "  - 확인: 보임"
assert_eq "plan: e2e를 고르지 않았으면 '실행: 안 함' 줄이 있어야" "1|yes" "$(code plan)|$(has "e2e 실행: 안 함" "$(run plan)")"
plan "- e2e 판단: 필요 (N1) 새 화면" "- e2e 시나리오: .maestro/a.yaml" "  - 시작점: 홈" "  - 동작: 누름" "  - 확인: 보임" "- e2e 실행: 안 함 (검사를 고르지 않음)"
assert_eq "plan: 형식이 맞으면 통과" "0" "$(code plan)"
task '["unit"]'
plan "- e2e 판단: 기존 수정 (N4) 문구가 바뀐다" "- e2e 시나리오: .maestro/home.yaml"
assert_eq "plan: e2e가 아닌 검사만 골랐으면 여전히 '실행: 안 함'이 필요" "1" "$(code plan)"
task '["e2e-ios"]'
assert_eq "plan: e2e 검사를 골랐으면 '실행' 줄이 없어도 통과, 기존 수정은 상세 없이" "0" "$(code plan)"

# --- written --------------------------------------------------------------------------------
task '[]'
plan "- e2e 판단: 필요 (N1) 새 화면" "- e2e 시나리오: .maestro/a.yaml" "  - 시작점: 홈" "  - 동작: 누름" "  - 확인: 보임" "- e2e 실행: 안 함"
assert_eq "written: 계획한 파일이 없으면 실패" "1|yes" "$(code written)|$(has "아직 쓰지 않았다" "$(run written)")"
echo 'appId: x' > "$p/.maestro/a.yaml"
assert_eq "written: 쓰면 통과" "0" "$(code written)"
assert_eq "written: e2e를 고르지 않았으면 e2e-unrun에 남긴다" ".maestro/a.yaml" "$(cat "$p/.harness/e2e-unrun")"
run written > /dev/null
assert_eq "written: 다시 돌려도 한 번만 남긴다" "1" "$(grep -c . "$p/.harness/e2e-unrun")"
plan "- e2e 판단: 기존 수정 (N4) 문구" "- e2e 시나리오: .maestro/home.yaml" "- e2e 실행: 안 함"
assert_eq "written: 기존 시나리오를 이번 작업에서 고치지 않았으면 실패" "1|yes" "$(code written)|$(has "고치지 않았다" "$(run written)")"
echo '- tapOn: x' >> "$p/.maestro/home.yaml"
task '["e2e-ios"]'
assert_eq "written: 고치면 통과" "0" "$(code written)"
assert_eq "written: e2e를 골랐으면 e2e-unrun에 더하지 않는다" ".maestro/a.yaml" "$(cat "$p/.harness/e2e-unrun")"
plan "- e2e 판단: 불필요 (U2) 로직만"
assert_eq "written: 불필요면 통과" "0" "$(code written)"
rm -f "$p/.harness/state/plan.md"
assert_eq "written: 계획서가 없으면(simple) 통과" "0" "$(code written)"

# --- list · ran -----------------------------------------------------------------------------
plan "- e2e 판단: 기존 수정 (N4) 문구" "- e2e 시나리오: .maestro/home.yaml"
assert_eq "list: 계획한 것과 돌리지 않은 것" "$(printf '.maestro/home.yaml\n.maestro/a.yaml')" "$(run list)"
assert_eq "ran: 결과가 없으면 실패" "1" "$(code ran e2e-ios)"
echo '{"passed":true,"command":"scripts/e2e.sh ios .maestro/home.yaml"}' > "$p/.harness/out/e2e-ios.json"
assert_eq "ran: 돌리지 않은 시나리오가 빠지면 실패" "1|yes" "$(code ran e2e-ios)|$(has ".maestro/a.yaml" "$(run ran e2e-ios)")"
assert_eq "ran: 실패하면 e2e-unrun을 그대로 둔다" ".maestro/a.yaml" "$(cat "$p/.harness/e2e-unrun")"
echo '{"passed":true,"command":"scripts/e2e.sh ios .maestro/home.yaml ./.maestro/a.yaml"}' > "$p/.harness/out/e2e-ios.json"
assert_eq "ran: 모두 돌렸으면 통과" "0" "$(code ran e2e-ios)"
assert_eq "ran: 돌린 시나리오를 e2e-unrun에서 지운다" "no" "$([ -f "$p/.harness/e2e-unrun" ] && echo yes || echo no)"
echo '.maestro/a.yaml' > "$p/.harness/e2e-unrun"
echo '{"passed":true,"command":"scripts/e2e.sh ios .maestro/"}' > "$p/.harness/out/e2e-ios.json"
assert_eq "ran: 시나리오 폴더를 돌렸으면 통과" "0" "$(code ran e2e-ios)"
echo '.maestro/gone.yaml' > "$p/.harness/e2e-unrun"
rm -f "$p/.harness/state/plan.md"
assert_eq "ran: 지운 시나리오만 남았으면 통과하고 목록을 지운다" "0|no" "$(code ran e2e-ios)|$([ -f "$p/.harness/e2e-unrun" ] && echo yes || echo no)"
assert_eq "ran: 검사 이름에 경로를 쓸 수 없다" "2" "$(code ran ../x)"

finish
