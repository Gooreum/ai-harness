#!/usr/bin/env bash
# SessionStart 훅(session-start.sh): 작업이 없으면 task 스킬로 시작하라고, 있으면 그 단계를 알려 준다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
hook="$here/../plugin/hooks/session-start.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

run() { jq -n --arg cwd "$1" '{session_id: "s", cwd: $cwd, hook_event_name: "SessionStart", source: "startup"}' | "$hook"; }
first() { printf '%s\n' "$1" | sed -n 1p; }

p="$work/p"
mkdir -p "$p/.harness/state" "$p/src"
echo '{"schemaVersion":2}' > "$p/.harness/project.json"

assert_eq "하네스 프로젝트가 아니면 아무것도 내지 않는다" "" "$(run "$work")"
assert_eq "작업이 없으면 task 스킬로 시작하라고 한다" \
  "[하네스] 코드를 고치는 작업은 파일을 고치기 전에 task 스킬(/harness:task)로 시작한다." "$(first "$(run "$p")")"
assert_eq "하위 폴더에서 열어도 프로젝트를 찾는다" \
  "[하네스] 코드를 고치는 작업은 파일을 고치기 전에 task 스킬(/harness:task)로 시작한다." "$(first "$(run "$p/src")")"

echo '{"title":"t","mode":"plan","stage":"done","checks":[]}' > "$p/.harness/state/task.json"
case "$(run "$p")" in
  *"done으로 닫은 뒤 이어서 고치는 것"*) ok=yes ;;
  *) ok=no ;;
esac
assert_eq "지난 작업이 done이면 이어서 고치는 것도 새 작업이라고 한다" "yes" "$ok"

echo '{"title":"알림 고치기","mode":"simple","stage":"verify","checks":[]}' > "$p/.harness/state/task.json"
assert_eq "진행 중인 작업이 있으면 그 단계를 알려 준다" \
  '[하네스] 진행 중인 작업이 있다: "알림 고치기" · simple 모드 · verify 단계' "$(first "$(run "$p")")"

echo '{' > "$p/.harness/state/task.json"
assert_eq "상태 파일이 깨졌으면 작업이 없는 것으로 본다" \
  "[하네스] 코드를 고치는 작업은 파일을 고치기 전에 task 스킬(/harness:task)로 시작한다." "$(first "$(run "$p")")"

assert_eq "jq가 없으면 아무것도 내지 않는다" "" \
  "$(printf '{"cwd":"%s"}' "$p" | PATH="$(nojq_path "$work")" "$hook")"

finish
