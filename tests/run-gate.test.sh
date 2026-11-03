#!/usr/bin/env bash
# 검증 강제 훅(check-run.sh): verify를 지나 넘어가려 할 때 고른 검사의 run을 돌려, 실패하면 막는지 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
hook="$here/../plugin/hooks/check-run.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/.harness/state" "$p/.harness/out"
echo '{"schemaVersion":1,"generator":"xcodeproj"}' > "$p/.harness/project.json"
cat > "$p/.harness/checks.json" <<'JSON'
{ "schemaVersion": 1,
  "checks": [
    { "name": "lint", "prompt": "lint", "run": "jq -e .passed .harness/out/lint.json" },
    { "name": "review", "prompt": "리뷰" } ] }
JSON
state="$p/.harness/state/task.json"

# 훅을 실행하고 "종료코드|stderr 첫 줄"을 출력한다.
call() { # 입력JSON
  local err rc
  err="$(printf '%s' "$1" | "$hook" 2>&1 >/dev/null)" && rc=0 || rc=$?
  printf '%s|%s' "$rc" "$(printf '%s\n' "$err" | sed -n 1p)"
}
write() { # 새 내용
  jq -n --arg f "$state" --arg c "$1" '{tool_name: "Write", cwd: "/", tool_input: {file_path: $f, content: $c}}'
}
edit() { # old new
  jq -n --arg f "$state" --arg o "$1" --arg n "$2" '{tool_name: "Edit", cwd: "/", tool_input: {file_path: $f, old_string: $o, new_string: $n}}'
}
blocked='2|[하네스] 검사를 통과하지 못해 다음 단계로 넘어갈 수 없습니다. stage는 바뀌지 않았습니다.'

echo '{"passed": false}' > "$p/.harness/out/lint.json"
printf '%s' '{"title":"t","mode":"simple","stage":"verify","checks":["lint","review"]}' > "$state"
assert_eq "verify → finish: run이 실패하면 막는다" "$blocked" \
  "$(call "$(edit '"stage":"verify"' '"stage":"finish"')")"
err="$(edit '"stage":"verify"' '"stage":"finish"' | "$hook" 2>&1 >/dev/null || true)"
case "$err" in *'- lint: run `jq -e .passed .harness/out/lint.json`이 실패했다'*) ok=yes ;; *) ok="$err" ;; esac
assert_eq "실패 이유에 검사 이름과 run을 적는다" "yes" "$ok"
case "$err" in *review*) ok=no ;; *) ok=yes ;; esac
assert_eq "run이 없는 검사는 돌리지 않는다" "yes" "$ok"

printf '%s' '{"title":"#217 문장 이동 시 번역 초안 보존","mode":"simple","stage":"verify","checks":["lint"]}' > "$state"
assert_eq "제목에 한글이 있어도 Edit 결과를 바르게 계산한다" "$blocked" \
  "$(call "$(edit '"stage":"verify"' '"stage":"finish"')")"

echo '{"passed": true}' > "$p/.harness/out/lint.json"
assert_eq "verify → finish: run이 통과하면 넘어간다" "0|" "$(call "$(edit '"stage":"verify"' '"stage":"finish"')")"

echo '{"passed": false}' > "$p/.harness/out/lint.json"
printf '%s' '{"title":"t","mode":"simple","stage":"implement","checks":["lint"]}' > "$state"
assert_eq "implement → verify: 아직 검증 전이라 돌리지 않는다" "0|" "$(call "$(edit '"stage":"implement"' '"stage":"verify"')")"
assert_eq "implement → done(건너뛰기)도 막는다" "$blocked" "$(call "$(edit '"stage":"implement"' '"stage":"done"')")"

printf '%s' '{"title":"t","mode":"simple","stage":"finish","checks":["lint"]}' > "$state"
assert_eq "finish → done: 이미 지난 검증은 다시 돌리지 않는다" "0|" "$(call "$(edit '"stage":"finish"' '"stage":"done"')")"

rm "$state"
assert_eq "새 작업 시작(Write)은 막지 않는다" "0|" \
  "$(call "$(write '{"title":"t","mode":"plan","stage":"plan","checks":["lint"]}')")"
assert_eq "Write로 바로 finish를 써도 막는다" "$blocked" \
  "$(call "$(write '{"title":"t","mode":"plan","stage":"finish","checks":["lint"]}')")"

printf '%s' '{"title":"t","mode":"plan","stage":"verify","checks":[]}' > "$state"
assert_eq "고른 검사가 없으면 막지 않는다" "0|" "$(call "$(edit '"stage":"verify"' '"stage":"finish"')")"

other="$(jq -n --arg f "$p/Sources/A.swift" '{tool_name: "Write", cwd: "/", tool_input: {file_path: $f, content: "x"}}')"
assert_eq "상태 파일이 아니면 보지 않는다" "0|" "$(call "$other")"
printf '%s' '{"title":"t","mode":"simple","stage":"verify","checks":["lint"]}' > "$state"
assert_eq "고친 결과가 JSON이 아니면 막지 않는다(단계 지시 훅이 알린다)" "0|" "$(call "$(edit '"stage":"verify"' '"stage":')")"
# run 시간 제한: 예산을 넘기면 시간 초과(124)로 막는다
cp "$p/.harness/checks.json" "$p/.harness/checks.bak"
echo '{"schemaVersion":1,"checks":[{"name":"slow","prompt":"x","run":"sleep 5"}]}' > "$p/.harness/checks.json"
printf '%s' '{"title":"t","mode":"simple","stage":"verify","checks":["slow"]}' > "$state"
err="$(edit '"stage":"verify"' '"stage":"finish"' | HARNESS_RUN_BUDGET=1 "$hook" 2>&1 >/dev/null || true)"
case "$err" in *'시간이 초과됐다'*'종료 코드 124'*) ok=yes ;; *) ok="$err" ;; esac
assert_eq "run이 예산을 넘기면 시간 초과로 막는다" "yes" "$ok"
mv "$p/.harness/checks.bak" "$p/.harness/checks.json"

rm "$p/.harness/checks.json"
assert_eq "checks.json이 없으면 막지 않는다" "0|" "$(call "$(edit '"stage":"verify"' '"stage":"finish"')")"

finish
