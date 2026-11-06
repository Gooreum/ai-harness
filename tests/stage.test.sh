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
    { "name": "unit-test", "description": "빌드·테스트", "prompt": "scripts/harness/unit-test를 실행해 통과시킨다" } ] }
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
assert_eq "plan: 승인 전에는 코드를 고치지 않는다" "yes" "$(has "승인 전에는 코드를 고치지 않는다" "$out")"
assert_eq "plan: Plan 모드로 승인받는다" "yes" "$(has "ExitPlanMode로 사용자 승인" "$out")"
assert_eq "plan: checks.json의 단계 지시를 붙인다" "yes" "$(has "계획에 MVI 흐름을 적는다" "$out")"
assert_eq "plan: 다음 단계를 알려 준다" "yes" "$(has 'stage를 "implement"로' "$out")"
assert_eq "plan: 검증 단계가 아니면 검사 목록은 없다" "no" "$(has "이번에 고른 검사" "$out")"

out="$(ctx '{"title":"시트","mode":"plan","stage":"verify","checks":["lint","e2e"]}')"
assert_eq "verify: 고른 검사의 prompt만 넣는다" "yes" "$(has "- lint: scripts/harness/lint를 실행해 통과시킨다" "$out")"
assert_eq "verify: 고르지 않은 검사는 넣지 않는다" "no" "$(has "scripts/harness/unit-test" "$out")"
out="$(ctx '{"title":"시트","mode":"plan","stage":"verify","checks":["unit-test","lint"]}')"
assert_eq "verify: 고른 순서가 아니라 checks.json 순서로 넣는다" "- lint: scripts/harness/lint를 실행해 통과시킨다|- unit-test: scripts/harness/unit-test를 실행해 통과시킨다" \
  "$(printf '%s\n' "$out" | grep '^- ' | paste -sd'|' -)"
out="$(ctx '{"title":"시트","mode":"plan","stage":"verify","checks":["lint","e2e"]}')"
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

# 상태 파일을 고친 세션을 작업 주인으로 남긴다 (stop-gate.sh가 읽는다)
printf '%s' '{"mode":"simple","stage":"implement"}' > "$p/.harness/state/task.json"
jq -n --arg f "$p/.harness/state/task.json" '{session_id: "s-1", cwd: "/", tool_input: {file_path: $f}}' | "$hook" > /dev/null
assert_eq "owner: 고친 세션을 주인으로 적는다" "s-1" "$(cat "$p/.harness/state/task.owner")"
jq -n --arg f "$p/.harness/state/task.json" '{session_id: "s-2", cwd: "/", tool_input: {file_path: $f}}' | "$hook" > /dev/null
assert_eq "owner: 다른 세션이 다시 저장하면 그 세션이 이어받는다" "s-2" "$(cat "$p/.harness/state/task.owner")"

# 작업 시작 표시: 새 작업일 때만 시각과 시작 커밋을 다시 적는다 (scripts/harness/passed가 읽는다)
sfile="$p/.harness/state/task.started"; bfile="$p/.harness/state/task.base"
rm -f "$sfile" "$bfile" "$p/.harness/state/task.seen"
(cd "$p" && git init -q -b main && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init)
head1="$(git -C "$p" rev-parse HEAD)"
ctx '{"title":"A","mode":"simple","stage":"implement"}' > /dev/null
assert_eq "started: 작업을 시작하면 적는다" "yes" "$([ -f "$sfile" ] && echo yes || echo no)"
assert_eq "base: 시작 커밋을 적는다" "$head1" "$(cat "$bfile")"
touch -t 202601010000 "$sfile"
(cd "$p" && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m mid)
ctx '{"title":"A","mode":"simple","stage":"verify"}' > /dev/null
assert_eq "started: 단계만 바뀌면 그대로 둔다" "202601010000" "$(stat -f %Sm -t %Y%m%d%H%M "$sfile")"
assert_eq "base: 작업 중 커밋해도 그대로 둔다" "$head1" "$(cat "$bfile")"
ctx '{"title":"B","mode":"simple","stage":"implement"}' > /dev/null
assert_eq "started: 끝나지 않은 작업은 제목이 바뀌어도 이어서 본다" "202601010000" "$(stat -f %Sm -t %Y%m%d%H%M "$sfile")"
ctx '{"title":"A","mode":"simple","stage":"done"}' > /dev/null
assert_eq "started: done이 돼도 그대로 둔다" "202601010000" "$(stat -f %Sm -t %Y%m%d%H%M "$sfile")"
ctx '{"title":"A","mode":"simple","stage":"implement"}' > /dev/null
assert_eq "started: 끝난 뒤 같은 제목으로 다시 시작해도 새로 적는다" "no" "$([ "$(stat -f %Sm -t %Y%m%d%H%M "$sfile")" = 202601010000 ] && echo yes || echo no)"
assert_eq "base: 새 작업이면 지금 커밋을 적는다" "$(git -C "$p" rev-parse HEAD)" "$(cat "$bfile")"
rm -rf "$p/.git"

rm "$p/.harness/checks.json"
out="$(ctx '{"title":"x","mode":"simple","stage":"verify","checks":["lint"]}')"
assert_eq "checks.json이 없어도 동작하고 없는 검사를 알린다" "yes" "$(has "- lint: .harness/checks.json에 없는 검사다" "$out")"

# 단계 순서는 flows.json 한 곳에서 읽는다 (check-run.sh도 같은 파일)
cp -R "$here/../plugin/hooks" "$work/hooks"
echo '{"plan":["plan","implement","verify","finish"],"simple":["implement","verify","qa","finish"]}' > "$work/hooks/flows.json"
printf '%s' '{"mode":"simple","stage":"x"}' > "$p/.harness/state/task.json"
out="$(jq -n --arg f "$p/.harness/state/task.json" '{cwd: "/", tool_input: {file_path: $f}}' | "$work/hooks/stage-context.sh" | jq -r '.hookSpecificOutput.additionalContext')"
assert_eq "flows: flows.json의 단계 순서를 쓴다" "yes" "$(has "implement → verify → qa → finish" "$out")"
mkdir -p "$p/.harness/out"
echo '{"checks":[{"name":"lint","prompt":"x","run":"false"}]}' > "$p/.harness/checks.json"
printf '%s' '{"mode":"simple","stage":"verify","checks":["lint"]}' > "$p/.harness/state/task.json"
gate() { jq -n --arg f "$p/.harness/state/task.json" '{tool_name: "Write", cwd: "/", tool_input: {file_path: $f, content: "{\"mode\":\"simple\",\"stage\":\"qa\",\"checks\":[\"lint\"]}"}}' | "$1" > /dev/null 2>&1 && echo 0 || echo $?; }
assert_eq "flows: check-run.sh도 flows.json을 읽는다 (verify 다음 단계로 가면 run을 돌린다)" "2" "$(gate "$work/hooks/check-run.sh")"
assert_eq "flows: 원래 flows.json에는 qa가 없어 막지 않는다" "0" "$(gate "$here/../plugin/hooks/check-run.sh")"

# --- 끼어들지 않는 경우 --------------------------------------------------------
assert_eq "다른 파일은 무시" "" "$(ctx '{"mode":"simple","stage":"implement"}' "$p/App/A.swift")"
mkdir -p "$work/other/.harness/state"
echo '{"mode":"simple","stage":"implement"}' > "$work/other/.harness/state/task.json"
assert_eq "project.json이 없는 곳은 무시" "" \
  "$(jq -n --arg f "$work/other/.harness/state/task.json" '{tool_input:{file_path:$f}}' | "$hook")"
assert_eq "깨진 입력은 무시" "" "$(printf 'not json' | "$hook")"

# --- jq가 없을 때 --------------------------------------------------------------
nojq() { printf '%s' "$1" | env PATH="$(nojq_path "$work")" /bin/bash "$hook"; }
out="$(nojq "{\"tool_input\":{\"file_path\":\"$p/.harness/state/task.json\"}}")"
assert_eq "jq 없음: 상태 파일을 고치면 꺼졌다고 알린다" "yes" "$(has "jq가 없어" "$(printf '%s' "$out" | /usr/bin/jq -r '.hookSpecificOutput.additionalContext')")"
assert_eq "jq 없음: 다른 파일은 조용히 넘긴다" "" "$(nojq '{"tool_input":{"file_path":"/x/A.swift"}}')"

finish
