#!/usr/bin/env bash
# scripts/harness/passed: 결과 파일이 통과했고 최신인지(ai-bouncer result_fresh와 같은 기준) 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
passed="$here/../template/scripts/harness/passed"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/.harness/out" "$p/.harness/state" "$p/App"
echo '{"schemaVersion":1}' > "$p/.harness/project.json"
echo '// a' > "$p/App/A.swift"
printf '.harness/out/\n.harness/state/\n' > "$p/.gitignore"
(cd "$p" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm init)
r="$p/.harness/out/unit-test.json"

run() { (cd "$p" && "$passed" "$@" 2>&1) && echo "rc=0" || echo "rc=$?"; }
last() { printf '%s\n' "$1" | sed -n '$p'; }
first() { printf '%s\n' "$1" | sed -n 1p; }

out="$(run unit-test)"
assert_eq "결과 파일이 없으면 2" "rc=2" "$(last "$out")"
assert_eq "  이유" "결과가 없다: .harness/out/unit-test.json — 검사를 먼저 실행한다 (scripts/harness/unit-test)" "$(first "$out")"

echo '{"passed": false, "summary": "실패: 앱"}' > "$r"
out="$(run unit-test)"
assert_eq "passed가 거짓이면 2" "rc=2" "$(last "$out")"
assert_eq "  요약을 보여 준다" "실패: 앱" "$(printf '%s\n' "$out" | sed -n 2p)"

echo '{"passed": true}' > "$r"
assert_eq "통과했고 바뀐 파일이 없으면 0" "rc=0" "$(run unit-test)"

echo '// b' >> "$p/App/A.swift"
touch -t 202601010000 "$p/App/A.swift"; touch -t 202601010100 "$r"
assert_eq "결과가 바뀐 파일보다 새것이면 0" "rc=0" "$(run unit-test)"
touch -t 202601010200 "$p/App/A.swift"
out="$(run unit-test)"
assert_eq "결과보다 나중에 고친 파일이 있으면 2" "rc=2" "$(last "$out")"
assert_eq "  어느 파일인지 알린다" "결과(.harness/out/unit-test.json)가 App/A.swift보다 오래됐다 — 고친 뒤 검사를 다시 실행한다" "$(first "$out")"

touch -t 202601010000 "$p/App/A.swift"
echo '// new' > "$p/App/B.swift"; touch -t 202601010300 "$p/App/B.swift"
assert_eq "새 파일도 본다" "rc=2" "$(last "$(run unit-test)")"
rm "$p/App/B.swift"

echo 'x' > "$p/.harness/state/task.started"; touch -t 202601010500 "$p/.harness/state/task.started"
out="$(run unit-test)"
assert_eq "작업을 시작하기 전 결과면 2" "rc=2" "$(last "$out")"
touch -t 202601010600 "$r"
assert_eq "작업 시작 뒤 결과면 0" "rc=0" "$(run unit-test)"

assert_eq "이름에 경로를 쓰면 거절" "rc=2" "$(last "$(run ../x)")"
assert_eq "이름이 없으면 2" "rc=2" "$(last "$(run)")"

finish
