#!/usr/bin/env bash
# setup: 검사 목록을 정하는 안내만 내고 파일은 쓰지 않는지, 찾은 명령과 묶음 추천 검사를 보여 주는지 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
t="$here/../template/scripts/harness"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/scripts/harness" "$p/.harness"
cp "$t/lib.sh" "$t/setup" "$t/ios-checks.json" "$t/common-checks.json" "$p/scripts/harness/"
echo '{"schemaVersion":2,"platforms":["ios"],"ios":{}}' > "$p/.harness/project.json"
echo '{"scripts":{"test":"jest","typecheck":"tsc"}}' > "$p/package.json"
touch "$p/pnpm-lock.yaml"
(cd "$p" && git init -q -b main)
has() { case "$out" in *"$1"*) echo yes ;; *) echo no ;; esac; }

out="$(cd "$p" && scripts/harness/setup)"
assert_eq "파일을 쓰지 않는다" "no" "$([ -f "$p/.harness/checks.json" ] && echo yes || echo no)"
assert_eq "찾은 명령을 보여 준다 (패키지 관리자 반영)" "yes" "$(has "pnpm test")"
assert_eq "근거를 보여 준다" "yes" "$(has "package.json scripts.typecheck")"
assert_eq "묶음 추천 검사를 보여 준다" "yes" "$(has "unit-test")"
assert_eq "사용자에게 묻게 한다" "yes" "$(has "AskUserQuestion")"
assert_eq "record로 돌리게 한다" "yes" "$(has "scripts/harness/record test")"

echo '{"schemaVersion":1,"checks":[]}' > "$p/.harness/checks.json"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "이미 있으면 바꿀 부분만 묻게 한다" "yes" "$(has "이미 검사 목록이 있다")"

rm "$p/package.json" "$p/.harness/checks.json"
echo '{"schemaVersion":2,"platforms":[]}' > "$p/.harness/project.json"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "찾은 것이 없으면 사용자에게 묻게 한다" "yes" "$(has "찾지 못했다")"
assert_eq "묶음이 없어도 공통 추천 검사(review)를 보여 준다" "yes|no" "$(has "review")|$(has "unit-test")"

mkdir -p "$p/tests" && touch "$p/tests/run.sh" "$p/tests/a.bats" "$p/Package.swift"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "tests/run.sh를 찾는다" "yes" "$(has "bash tests/run.sh")"
assert_eq "bats 파일을 찾는다" "yes" "$(has "bats -r .")"
assert_eq "Swift 패키지는 swift test를 찾는다" "yes" "$(has "swift test")"

finish
