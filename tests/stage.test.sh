#!/usr/bin/env bash
# 단계 지시 훅(stage-context.sh): 상태 파일이 바뀔 때만, checks.json의 글을 단계에 맞춰 넣는지 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
hook="$here/../plugin/hooks/stage-context.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/.harness/state"
echo '{"schemaVersion":1,"generator":"xcodeproj"}' > "$p/.harness/project.json"
cat > "$p/.harness/checks.json" <<'JSON'
{ "schemaVersion": 1,
  "stages": { "plan": { "prompt": "계획에 MVI 흐름을 적는다" } },
  "checks": [
    { "name": "lint", "description": "팀 컨벤션", "prompt": "scripts/harness/lint를 실행해 통과시킨다" },
    { "name": "verify", "description": "빌드·테스트", "prompt": "scripts/harness/verify를 실행해 통과시킨다" } ] }
JSON

# 상태 파일을 쓰고 훅을 실행해 넣는 글을 출력한다. 출력이 없으면 빈 문자열.
ctx() { # 상태JSON [파일경로] [cwd]
  printf '%s' "$1" > "$p/.harness/state/task.json"
  jq -n --arg f "${2:-$p/.harness/state/task.json}" --arg cwd "${3:-/}" \
    '{hook_event_name: "PostToolUse", tool_name: "Write", cwd: $cwd, tool_input: {file_path: $f}}' \
    | "$hook" | jq -r '.hookSpecificOutput.additionalContext // empty'
}
has() { case "$2" in *"$1"*) echo yes ;; *) echo no ;; esac; }

out="$(ctx '{"title":"시트","mode":"plan","stage":"plan","checks":["lint"]}')"
assert_eq "plan: 첫 줄에 작업·모드·단계" '[하네스] 작업 "시트" · plan 모드 · plan 단계 (1/4)' "$(printf '%s\n' "$out" | sed -n 1p)"
assert_eq "plan: 코드는 고치지 않는다" "yes" "$(has "코드는 고치지 않는다" "$out")"
assert_eq "plan: checks.json의 단계 지시를 붙인다" "yes" "$(has "계획에 MVI 흐름을 적는다" "$out")"
assert_eq "plan: 다음 단계를 알려 준다" "yes" "$(has 'stage를 "implement"로' "$out")"
assert_eq "plan: 검증 단계가 아니면 검사 목록은 없다" "no" "$(has "이번에 고른 검사" "$out")"

out="$(ctx '{"title":"시트","mode":"plan","stage":"verify","checks":["lint","e2e"]}')"
assert_eq "verify: 고른 검사의 prompt만 넣는다" "yes" "$(has "- lint: scripts/harness/lint를 실행해 통과시킨다" "$out")"
assert_eq "verify: 고르지 않은 검사는 넣지 않는다" "no" "$(has "scripts/harness/verify" "$out")"
assert_eq "verify: 설정에 없는 검사는 알린다" "yes" "$(has "- e2e: .harness/checks.json에 없는 검사다" "$out")"

out="$(ctx '{"title":"문구","mode":"simple","stage":"implement","checks":[]}')"
assert_eq "simple: 계획 없이 구현부터" '[하네스] 작업 "문구" · simple 모드 · implement 단계 (1/3)' "$(printf '%s\n' "$out" | sed -n 1p)"
out="$(ctx '{"title":"문구","mode":"simple","stage":"verify","checks":[]}')"
assert_eq "simple: 고른 검사가 없으면 바로 넘어간다" "yes" "$(has "고른 검사가 없다" "$out")"
out="$(ctx '{"title":"문구","mode":"simple","stage":"finish","checks":[]}')"
assert_eq "finish: 정책·결정을 정리한다" "yes" "$(has "정책·결정" "$out")"
assert_eq "finish: 마지막에는 done" "yes" "$(has 'stage를 "done"으로' "$out")"
assert_eq "done: 끝났다고만 알린다" '[하네스] 작업 "문구"이 끝났습니다.' "$(ctx '{"title":"문구","mode":"simple","stage":"done"}')"

assert_eq "잘못된 단계는 고칠 방법을 알린다" "yes" \
  "$(has "simple 모드의 단계는 implement → verify → finish" "$(ctx '{"mode":"simple","stage":"plan"}')")"
assert_eq "잘못된 모드" "[하네스] task.json의 mode는 plan 또는 simple이어야 합니다." "$(ctx '{"mode":"big","stage":"plan"}')"
assert_eq "깨진 상태 파일" "yes" "$(has "JSON 형식이 아닙니다" "$(ctx 'not json')")"
assert_eq "상대 경로는 cwd 기준" "yes" \
  "$(has "implement 단계" "$(ctx '{"mode":"simple","stage":"implement"}' .harness/state/task.json "$p")")"

rm "$p/.harness/checks.json"
out="$(ctx '{"title":"x","mode":"simple","stage":"verify","checks":["lint"]}')"
assert_eq "checks.json이 없어도 동작하고 없는 검사를 알린다" "yes" "$(has "- lint: .harness/checks.json에 없는 검사다" "$out")"

# --- 끼어들지 않는 경우 --------------------------------------------------------
assert_eq "다른 파일은 무시" "" "$(ctx '{"mode":"simple","stage":"implement"}' "$p/App/A.swift")"
mkdir -p "$work/other/.harness/state"
echo '{"mode":"simple","stage":"implement"}' > "$work/other/.harness/state/task.json"
assert_eq "project.json이 없는 곳은 무시" "" \
  "$(jq -n --arg f "$work/other/.harness/state/task.json" '{tool_input:{file_path:$f}}' | "$hook")"
assert_eq "깨진 입력은 무시" "" "$(printf 'not json' | "$hook")"

finish
