#!/usr/bin/env bash
# record: 아무 명령이나 돌려 결과를 남기고, iOS 스크립트(ios.sh) 없이 record·passed만으로 검증 게이트가 판정하는지 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
hook="$here/../plugin/hooks/stop-gate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# iOS 묶음 없이 공통 스크립트만 둔 저장소
p="$work/repo"
mkdir -p "$p/scripts/harness" "$p/.harness/state"
cp "$here/../template/scripts/harness/lib.sh" "$here/../template/scripts/harness/record" \
  "$here/../template/scripts/harness/passed" "$p/scripts/harness/"
echo '{"schemaVersion":1}' > "$p/.harness/project.json"
cat > "$p/.harness/checks.json" <<'JSON'
{ "schemaVersion": 1,
  "checks": [ { "name": "tests", "prompt": "scripts/harness/record tests \"bash check.sh\"", "run": "scripts/harness/passed tests" } ] }
JSON
printf 'exit 1\n' > "$p/check.sh"
echo 'a' > "$p/a.txt"
git -C "$p" init -q && git -C "$p" add -A && git -C "$p" -c user.email=t@t -c user.name=t commit -qm init

rec() { (cd "$p" && scripts/harness/record "$@"); }

# --- record ---------------------------------------------------------------------
out="$(rec ok echo hi)"; rc=$?
assert_eq "성공: 0으로 끝난다" "0" "$rc"
assert_eq "성공: 한 줄만 출력한다" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_eq "성공: 결과 passed" "true" "$(jq -r .passed "$p/.harness/out/ok.json")"
assert_eq "성공: 전체 출력은 로그에" "hi" "$(cat "$p/.harness/out/ok.log")"

rc=0; out="$(rec bad "seq 1 100; echo 마지막 에러 >&2; exit 3")" || rc=$?
assert_eq "실패: 명령의 종료 코드로 끝난다" "3" "$rc"
assert_eq "실패: 결과 passed false" "false" "$(jq -r .passed "$p/.harness/out/bad.json")"
assert_eq "실패: 결과에 종료 코드" "3" "$(jq -r .exit "$p/.harness/out/bad.json")"
case "$out" in *'마지막 에러'*) ok=yes ;; *) ok="$out" ;; esac
assert_eq "실패: 끝부분을 보여 준다" "yes" "$ok"
case "$out" in *$'\n  1\n'*) ok="$out" ;; *) ok=yes ;; esac
assert_eq "실패: 앞부분은 생략한다" "yes" "$ok"
assert_eq "실패: 전체 출력은 로그에" "101" "$(wc -l < "$p/.harness/out/bad.log" | tr -d ' ')"

rec ci 'test "$CI" = 1' > /dev/null && rc=0 || rc=$?
assert_eq "CI=1을 넣어 실행한다" "0" "$rc"
rec cwd 'test -f a.txt' > /dev/null && rc=0 || rc=$?
assert_eq "프로젝트 루트에서 실행한다" "0" "$rc"
rec stdin 'read -r x; test -z "$x"' > /dev/null && rc=0 || rc=$?
assert_eq "입력을 기다리며 멈추지 않는다" "0" "$rc"

rc=0; rec '../x' echo > /dev/null 2>&1 || rc=$?
assert_eq "이름에 경로를 쓸 수 없다" "2" "$rc"
rc=0; rec 'a b' echo > /dev/null 2>&1 || rc=$?
assert_eq "이름에 공백을 쓸 수 없다" "2" "$rc"
rc=0; rec onlyname > /dev/null 2>&1 || rc=$?
assert_eq "명령이 없으면 인자 오류" "2" "$rc"

# --- record·passed만으로 검증 게이트 ------------------------------------------------
state="$p/.harness/state/task.json"
gate() { # 검증 단계에서 응답을 마치려 할 때(Stop 훅) 넘어간 단계를 출력한다. 막히면 verify 그대로다
  printf '%s' '{"title":"t","mode":"simple","stage":"verify","checks":["tests"]}' > "$state"
  rm -f "$p/.harness/state/stop-gate.json"
  jq -n --arg cwd "$p" '{session_id: "s1", cwd: $cwd}' | "$hook" > /dev/null 2>&1 || true
  jq -r .stage "$state"
}
echo s1 > "$p/.harness/state/task.owner"
printf '%s' '{"title":"t","mode":"simple","stage":"verify","checks":["tests"]}' > "$state"
touch "$p/.harness/state/task.started"
sleep 1

assert_eq "게이트: 결과가 없으면 막는다" "verify" "$(gate)"
rec tests "bash check.sh" > /dev/null || true
assert_eq "게이트: 검사가 실패하면 막는다" "verify" "$(gate)"
printf 'exit 0\n' > "$p/check.sh"
rec tests "bash check.sh" > /dev/null
assert_eq "게이트: 검사가 통과하면 넘어간다" "finish" "$(gate)"
sleep 1
echo b > "$p/a.txt"
assert_eq "게이트: 그 뒤에 파일을 고치면 낡은 결과라 막는다" "verify" "$(gate)"
rec tests "bash check.sh" > /dev/null
assert_eq "게이트: 다시 돌리면 넘어간다" "finish" "$(gate)"

finish
