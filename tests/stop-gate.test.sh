#!/usr/bin/env bash
# Stop 훅(stop-gate.sh)과 도구 수 훅(tool-count.sh):
# 작업 주인 세션만 done 전에 막고, 도구 없는 반복과 연속 차단은 ai-bouncer처럼 풀어 주는지 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
hook="$here/../plugin/hooks/stop-gate.sh"
count="$here/../plugin/hooks/tool-count.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/.harness/state" "$p/Sources"
echo '{"schemaVersion":1}' > "$p/.harness/project.json"
sd="$p/.harness/state"
state="$sd/task.json"

stop() { # 세션 [cwd] [재진입]
  jq -n --arg s "$1" --arg cwd "${2:-$p}" --argjson r "${3:-false}" '{hook_event_name: "Stop", session_id: $s, cwd: $cwd, stop_hook_active: $r}' \
    | "$hook" > /dev/null 2>&1 && echo 0 || echo $?
}
tool() { jq -n --arg s "$1" --arg cwd "$p" '{session_id: $s, cwd: $cwd, tool_name: "Read"}' | "$count"; }
set_stage() { printf '{"title":"시트","mode":"plan","stage":"%s","checks":[]}' "$1" > "$state"; rm -f "$sd/stop-gate.json"; }

assert_eq "상태 파일이 없으면 막지 않는다" "0" "$(stop s1)"
set_stage implement
assert_eq "주인이 없으면 막지 않는다" "0" "$(stop s1)"
echo s1 > "$sd/task.owner"
assert_eq "다른 세션은 막지 않는다" "0" "$(stop s2)"
set_stage plan;      assert_eq "plan: 막는다(승인은 Plan 모드에서 받는다)" "2" "$(stop s1)"
set_stage implement; assert_eq "implement: 막는다" "2" "$(stop s1)"
set_stage verify;    assert_eq "verify: 막는다" "2" "$(stop s1)"
set_stage finish;    assert_eq "finish: 막는다" "2" "$(stop s1)"
set_stage done;      assert_eq "done: 막지 않는다" "0" "$(stop s1)"
set_stage verify
assert_eq "하위 디렉터리에서도 프로젝트를 찾는다" "2" "$(stop s1 "$p/Sources")"
err="$(jq -n --arg cwd "$p" '{session_id: "s1", cwd: $cwd}' | "$hook" 2>&1 >/dev/null || true)"
assert_eq "이유에 작업과 단계를 적는다" '[하네스] 작업 "시트"이 아직 verify 단계라 끝낼 수 없습니다.' "$(printf '%s\n' "$err" | sed -n 1p)"

# 도구 없는 반복: 같은 이유로 재진입했는데 그 사이 도구를 안 썼으면 끝내게 둔다
set_stage verify
assert_eq "처음은 막는다" "2" "$(stop s1)"
assert_eq "도구 없이 재진입하면 끝내게 둔다" "0" "$(stop s1 "$p" true)"
tool s2
assert_eq "다른 세션의 도구는 세지 않는다" "0" "$(stop s1 "$p" true)"
tool s1
assert_eq "도구를 썼으면 다시 막는다" "2" "$(stop s1 "$p" true)"

# 연속 차단: 같은 단계에서 10번 막으면 11번째는 사용자에게 넘기게 하고 끝내게 둔다
set_stage verify
for _ in 1 2 3 4 5 6 7 8 9 10; do tool s1; stop s1 "$p" true > /dev/null; done
out="$(jq -n --arg cwd "$p" '{session_id: "s1", cwd: $cwd, stop_hook_active: true}' | (tool s1; "$hook") 2>/dev/null || true)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty')"
case "$ctx" in *"10번 연속"*"사용자에게 넘긴다"*) ok=yes ;; *) ok="$out" ;; esac
assert_eq "10번 연속이면 사용자에게 넘기라고 한다" "yes" "$ok"
tool s1
assert_eq "넘긴 뒤에는 횟수를 처음부터 센다" "2" "$(stop s1 "$p" true)"
set_stage implement; printf '{"stage":"verify","streak":9}' > "$sd/stop-gate.json"
assert_eq "단계가 바뀌면 횟수를 처음부터 센다" "2" "$(stop s1)"
assert_eq "  (횟수 1)" "1" "$(jq -r .streak "$sd/stop-gate.json")"

assert_eq "프로젝트 밖이면 막지 않는다" "0" "$(stop s1 "$work")"
printf 'not json' > "$state"
assert_eq "깨진 상태 파일은 막지 않는다" "0" "$(stop s1)"

finish
