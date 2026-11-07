#!/usr/bin/env bash
# 상태 파일 보호 훅(guard-state.sh): 에이전트가 task.json으로 단계를 넘기지 못하게 하고,
# 시작·이어서 하기·취소만 허용하며, Bash로 쓰거나 지우는 명령을 막는지 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
hook="$here/../plugin/hooks/guard-state.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/.harness/state"
echo '{"schemaVersion":1}' > "$p/.harness/project.json"
state="$p/.harness/state/task.json"

# 훅을 실행하고 "종료코드|stderr 첫 줄"을 출력한다.
call() { # 입력JSON
  local err rc
  err="$(printf '%s' "$1" | "$hook" 2>&1 >/dev/null)" && rc=0 || rc=$?
  printf '%s|%s' "$rc" "$(printf '%s\n' "$err" | sed -n 1p)"
}
write() { # 새 내용 [파일]
  jq -n --arg f "${2:-$state}" --arg c "$1" '{tool_name: "Write", cwd: "/", tool_input: {file_path: $f, content: $c}}'
}
edit() { # old new
  jq -n --arg f "$state" --arg o "$1" --arg n "$2" '{tool_name: "Edit", cwd: "/", tool_input: {file_path: $f, old_string: $o, new_string: $n}}'
}
bash_cmd() { # 명령 [cwd]
  jq -n --arg c "$1" --arg cwd "${2:-$p}" '{tool_name: "Bash", cwd: $cwd, tool_input: {command: $c}}'
}
stage_block='2|[하네스] 단계는 하네스가 넘깁니다. task.json의 stage·mode를 바꿀 수 없습니다. 상태 파일은 바뀌지 않았습니다.'
first_plan='2|[하네스] 새 작업은 첫 단계("plan")에서 시작합니다. 상태 파일은 바뀌지 않았습니다.'
bash_block='2|[하네스] .harness/state/task.json은 Bash로 쓰거나 지우지 않습니다. 명령은 실행되지 않았습니다.'

# --- 새 작업 시작 ---------------------------------------------------------------
assert_eq "새 작업을 첫 단계로 연다" "0|" "$(call "$(write '{"title":"t","mode":"plan","stage":"plan","checks":["lint"]}')")"
assert_eq "새 작업을 중간 단계로 열면 막는다" "$first_plan" "$(call "$(write '{"title":"t","mode":"plan","stage":"verify","checks":["lint"]}')")"
assert_eq "새 작업을 done으로 열어도 막는다" "$first_plan" "$(call "$(write '{"title":"t","mode":"plan","stage":"done"}')")"
assert_eq "simple 새 작업은 implement부터 연다" "0|" "$(call "$(write '{"title":"t","mode":"simple","stage":"implement","checks":[]}')")"
assert_eq "모르는 모드는 막는다" "2|[하네스] task.json의 mode는 plan 또는 simple이어야 합니다. 상태 파일은 바뀌지 않았습니다." \
  "$(call "$(write '{"title":"t","mode":"big","stage":"plan"}')")"
printf '%s' '{"title":"t","mode":"plan","stage":"done","checks":["lint"]}' > "$state"
assert_eq "지난 작업이 done이면 새 작업: 첫 단계로 연다" "0|" "$(call "$(write '{"title":"u","mode":"plan","stage":"plan","checks":[]}')")"
assert_eq "지난 작업이 done이면 새 작업: 중간 단계는 막는다" "$first_plan" "$(call "$(write '{"title":"u","mode":"plan","stage":"finish","checks":[]}')")"
printf 'not json' > "$state"
assert_eq "깨진 상태 파일 위에는 새 작업으로 연다" "0|" "$(call "$(write '{"title":"u","mode":"simple","stage":"implement"}')")"

# --- 진행 중인 작업 -------------------------------------------------------------
printf '%s' '{"title":"#217 문장 이동 시 번역 초안 보존","mode":"plan","stage":"implement","checks":["lint"]}' > "$state"
assert_eq "다음 단계로 바꾸면 막는다 (한글 제목도 Edit 결과를 계산한다)" "$stage_block" "$(call "$(edit '"stage":"implement"' '"stage":"verify"')")"
assert_eq "done으로 건너뛰면 막는다" "$stage_block" "$(call "$(edit '"stage":"implement"' '"stage":"done"')")"
assert_eq "앞 단계로 되돌려도 막는다" "$stage_block" "$(call "$(edit '"stage":"implement"' '"stage":"plan"')")"
assert_eq "모드를 바꾸면 막는다" "$stage_block" "$(call "$(edit '"mode":"plan"' '"mode":"simple"')")"
assert_eq "같은 내용으로 다시 저장(이어서 하기)은 막지 않는다" "0|" \
  "$(call "$(write '{"title":"#217 문장 이동 시 번역 초안 보존","mode":"plan","stage":"implement","checks":["lint"]}')")"
assert_eq "검사를 더하는 것은 막지 않는다" "0|" "$(call "$(edit '["lint"]' '["lint","e2e"]')")"
assert_eq "검사를 빼면 막는다" "2|[하네스] 진행 중인 작업에서 고른 검사를 뺄 수 없습니다. 상태 파일은 바뀌지 않았습니다." \
  "$(call "$(edit '["lint"]' '[]')")"
assert_eq "취소(done + cancelled)는 막지 않는다" "0|" "$(call "$(edit '"stage":"implement"' '"stage":"done","cancelled":true')")"
assert_eq "JSON이 아닌 내용으로 바꾸면 막는다" "2|[하네스] 진행 중인 작업의 task.json을 JSON이 아닌 내용으로 바꿀 수 없습니다. 상태 파일은 바뀌지 않았습니다." \
  "$(call "$(edit '"stage":"implement"' '"stage":')")"

# --- Bash ---------------------------------------------------------------------
for c in "cat > .harness/state/task.json <<'EOF'
{}
EOF" \
  "echo '{}' > $p/.harness/state/task.json" \
  "jq '.stage=\"done\"' .harness/state/task.json > /tmp/x && mv /tmp/x .harness/state/task.json" \
  "sed -i '' 's/verify/done/' .harness/state/task.json" \
  "rm .harness/state/task.json" \
  "python3 -c 'open(\".harness/state/task.json\",\"w\").write(\"{}\")'" \
  "printf x | tee .harness/state/task.json"; do
  assert_eq "Bash 쓰기·지우기를 막는다: ${c%%$'\n'*}" "$bash_block" "$(call "$(bash_cmd "$c")")"
done
assert_eq "state 폴더 안에서 > task.json도 막는다" "$bash_block" "$(call "$(bash_cmd 'echo {} > task.json' "$p/.harness/state")")"
for c in "cat .harness/state/task.json" \
  "jq -r .stage .harness/state/task.json 2>/dev/null" \
  "cat .harness/state/task.json 2>&1 | head -3" \
  "jq . .harness/state/task.json > /dev/null && echo ok" \
  "echo hi > out.txt" \
  "rm App/task.json"; do
  assert_eq "Bash 읽기·다른 파일은 막지 않는다: $c" "0|" "$(call "$(bash_cmd "$c")")"
done

# --- 끼어들지 않는 경우 --------------------------------------------------------
assert_eq "상태 파일이 아니면 보지 않는다" "0|" "$(call "$(write 'x' "$p/Sources/A.swift")")"
mkdir -p "$work/other/.harness/state"
assert_eq "project.json이 없는 곳은 보지 않는다" "0|" "$(call "$(write '{"mode":"plan","stage":"verify"}' "$work/other/.harness/state/task.json")")"
assert_eq "깨진 입력은 막지 않는다" "0|" "$(call 'not json')"

finish
