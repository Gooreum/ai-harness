#!/usr/bin/env bash
# Stop 훅(stop-gate.sh)과 도구 수 훅(tool-count.sh):
# 작업 주인 세션이 응답을 마치려 할 때 검증 단계면 고른 검사의 run을 돌리고, 통과하면 훅이 다음 단계로 넘기는지,
# 도구 없는 반복과 연속 차단은 ai-bouncer처럼 풀어 주는지 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
hook="$here/../plugin/hooks/stop-gate.sh"
count="$here/../plugin/hooks/tool-count.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/.harness/state" "$p/.harness/out" "$p/Sources"
echo '{"schemaVersion":1}' > "$p/.harness/project.json"
cat > "$p/.harness/checks.json" <<'JSON'
{ "schemaVersion": 1,
  "checks": [
    { "name": "lint", "prompt": "scripts/harness/lint를 실행한다", "run": "jq -e .passed .harness/out/lint.json" },
    { "name": "review", "prompt": "리뷰" } ] }
JSON
sd="$p/.harness/state"
state="$sd/task.json"
echo s1 > "$sd/task.owner"

stop() { # 세션 [cwd] [재진입]
  jq -n --arg s "$1" --arg cwd "${2:-$p}" --argjson r "${3:-false}" '{hook_event_name: "Stop", session_id: $s, cwd: $cwd, stop_hook_active: $r}' \
    | "$hook" > /dev/null 2>&1 && echo 0 || echo $?
}
reason() { jq -n --arg cwd "$p" '{session_id: "s1", cwd: $cwd}' | "$hook" 2>&1 >/dev/null || true; }
tool() { jq -n --arg s "$1" --arg cwd "$p" '{session_id: $s, cwd: $cwd, tool_name: "Read"}' | "$count"; }
set_task() { # 모드 단계 [검사JSON]
  printf '{"title":"시트","mode":"%s","stage":"%s","checks":%s}' "$1" "$2" "${3:-[]}" > "$state"; rm -f "$sd/stop-gate.json"
}
now() { jq -r .stage "$state"; }
has() { case "$2" in *"$1"*) echo yes ;; *) echo no ;; esac; }
lint() { echo "{\"passed\": $1}" > "$p/.harness/out/lint.json"; }

# --- 끼어들지 않는 경우 --------------------------------------------------------
rm -f "$state"
assert_eq "상태 파일이 없으면 막지 않는다" "0" "$(stop s1)"
set_task plan implement
rm "$sd/task.owner"
assert_eq "주인이 없으면 막지 않는다" "0" "$(stop s1)"
assert_eq "  (단계를 넘기지 않는다)" "implement" "$(now)"
echo s1 > "$sd/task.owner"
assert_eq "다른 세션은 막지 않는다" "0" "$(stop s2)"
assert_eq "  (단계를 넘기지 않는다)" "implement" "$(now)"
set_task plan done
assert_eq "done: 막지 않는다" "0" "$(stop s1)"
assert_eq "프로젝트 밖이면 막지 않는다" "0" "$(stop s1 "$work")"
printf 'not json' > "$state"
assert_eq "깨진 상태 파일은 막지 않는다" "0" "$(stop s1)"
set_task big plan
assert_eq "모르는 모드는 막지 않는다" "0" "$(stop s1)"

# --- 단계 넘기기 ---------------------------------------------------------------
set_task plan plan
assert_eq "plan: 막고 implement로 넘긴다" "2" "$(stop s1)"
assert_eq "  (stage가 implement)" "implement" "$(now)"
assert_eq "  (본 단계를 적는다)" "implement" "$(cat "$sd/task.seen")"
set_task plan plan
out="$(reason)"
assert_eq "  첫 줄에 넘긴 단계를 알린다" "[하네스] plan 단계를 마쳤습니다 → implement 단계로 넘어갑니다." "$(printf '%s\n' "$out" | sed -n 1p)"
assert_eq "  다음 단계 지시를 함께 준다" "yes" "$(has '작업 "시트" · plan 모드 · implement 단계 (2/4)' "$out")"
assert_eq "  task.json을 고치지 말라고 한다" "yes" "$(has "task.json은 고치지 않는다" "$out")"
assert_eq "implement → verify" "2|verify" "$(stop s1)|$(now)"
out="$(set_task plan implement '["lint","review"]'; reason)"
assert_eq "  verify 지시에 고른 검사의 prompt를 넣는다" "yes" "$(has "- lint: scripts/harness/lint를 실행한다" "$out")"
set_task plan finish
assert_eq "finish: done으로 쓰고 끝내게 둔다" "0|done" "$(stop s1)|$(now)"
set_task simple implement
assert_eq "simple: implement → verify" "2|verify" "$(stop s1)|$(now)"
assert_eq "하위 디렉터리에서도 프로젝트를 찾는다" "2|finish" "$(stop s1 "$p/Sources")|$(now)"
jq '. + {extra: "그대로"}' "$state" > "$state.x" && mv "$state.x" "$state"
stop s1 > /dev/null
assert_eq "넘길 때 다른 필드는 그대로 둔다" "done|그대로|시트" "$(jq -r '"\(.stage)|\(.extra)|\(.title)"' "$state")"

# --- 검증: 고른 검사의 run -------------------------------------------------------
lint false
set_task simple verify '["lint","review"]'
assert_eq "verify: run이 실패하면 막고 단계는 그대로" "2|verify" "$(stop s1)|$(now)"
set_task simple verify '["lint","review"]'
out="$(reason)"
assert_eq "  첫 줄" '[하네스] 검사를 통과하지 못해 다음 단계로 넘어갈 수 없습니다. 작업 "시트"은 아직 verify 단계입니다.' "$(printf '%s\n' "$out" | sed -n 1p)"
assert_eq "  실패 이유에 검사 이름과 run을 적는다" "yes" "$(has '- lint: run `jq -e .passed .harness/out/lint.json`이 실패했다' "$out")"
assert_eq "  run이 없는 검사는 돌리지 않는다" "no" "$(has "review" "$out")"
lint true
set_task simple verify '["lint","review"]'
assert_eq "verify: run이 통과하면 finish로 넘긴다" "2|finish" "$(stop s1)|$(now)"
set_task simple verify '[]'
assert_eq "고른 검사가 없으면 바로 넘긴다" "2|finish" "$(stop s1)|$(now)"
set_task simple verify '["lint","unit-tset"]'
out="$(reason)"
assert_eq "고른 검사가 설정에 없으면 막는다" "yes|verify" "$(has "- unit-tset: .harness/checks.json에 없는 검사다" "$out")|$(now)"
cp "$p/.harness/checks.json" "$p/.harness/checks.bak"
echo '{"schemaVersion":1,"checks":[{"name":"slow","prompt":"x","run":"sleep 5"}]}' > "$p/.harness/checks.json"
set_task simple verify '["slow"]'
out="$(jq -n --arg cwd "$p" '{session_id: "s1", cwd: $cwd}' | HARNESS_RUN_BUDGET=1 "$hook" 2>&1 >/dev/null || true)"
assert_eq "run이 예산을 넘기면 시간 초과로 막는다" "yes|verify" "$(has "시간이 초과됐다" "$out")|$(now)"
rm "$p/.harness/checks.json"
set_task simple verify '["lint"]'
assert_eq "검사를 골랐는데 checks.json이 없으면 막는다" "2|verify" "$(stop s1)|$(now)"
set_task simple verify '[]'
assert_eq "검사를 안 골랐으면 checks.json이 없어도 넘긴다" "2|finish" "$(stop s1)|$(now)"
mv "$p/.harness/checks.bak" "$p/.harness/checks.json"

# --- 도구 없는 반복: 같은 이유로 재진입했는데 그 사이 도구를 안 썼으면 끝내게 둔다 -------------
lint false
set_task simple verify '["lint"]'
assert_eq "처음은 막는다" "2" "$(stop s1)"
assert_eq "도구 없이 재진입하면 끝내게 둔다" "0" "$(stop s1 "$p" true)"
tool s2
assert_eq "다른 세션의 도구는 세지 않는다" "0" "$(stop s1 "$p" true)"
tool s1
assert_eq "도구를 썼으면 다시 막는다" "2" "$(stop s1 "$p" true)"

# --- 연속 차단: 같은 단계에서 10번 막으면 11번째는 사용자에게 넘기게 하고 끝내게 둔다 -------------
set_task simple verify '["lint"]'
for _ in 1 2 3 4 5 6 7 8 9 10; do tool s1; stop s1 "$p" true > /dev/null; done
out="$(jq -n --arg cwd "$p" '{session_id: "s1", cwd: $cwd, stop_hook_active: true}' | (tool s1; "$hook") 2>/dev/null || true)"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty')"
assert_eq "10번 연속이면 사용자에게 넘기라고 한다" "yes|yes" "$(has "10번 연속" "$ctx")|$(has '"cancelled": true' "$ctx")"
tool s1
assert_eq "넘긴 뒤에는 횟수를 처음부터 센다" "2" "$(stop s1 "$p" true)"
set_task simple verify '["lint"]'; printf '{"stage":"implement","streak":9}' > "$sd/stop-gate.json"
assert_eq "단계가 바뀌면 횟수를 처음부터 센다" "2" "$(stop s1)"
assert_eq "  (횟수 1)" "1" "$(jq -r .streak "$sd/stop-gate.json")"
lint true; stop s1 > /dev/null
assert_eq "넘기면 차단 기록을 지운다" "no" "$([ -f "$sd/stop-gate.json" ] && echo yes || echo no)"

# --- 백그라운드 서브에이전트를 기다리는 중이면 막지도 넘기지도 않는다 (ADR 0013) -------------------
bg() { # background_tasks JSON
  jq -n --arg cwd "$p" --argjson b "$1" '{session_id: "s1", cwd: $cwd, stop_hook_active: false, background_tasks: $b}' \
    | "$hook" > /dev/null 2>&1 && echo 0 || echo $?
}
lint false
set_task simple verify '["lint"]'
assert_eq "서브에이전트가 돌고 있으면 막지 않는다" "0|verify" "$(bg '[{"id":"a1","type":"subagent","status":"running","description":"리뷰"}]')|$(now)"
assert_eq "  (차단 기록을 남기지 않는다)" "no" "$([ -f "$sd/stop-gate.json" ] && echo yes || echo no)"
set_task simple implement
assert_eq "  (단계도 넘기지 않는다)" "0|implement" "$(bg '[{"id":"a1","type":"subagent","status":"running","description":"리뷰"}]')|$(now)"
set_task simple verify '["lint"]'
assert_eq "기다리는 작업이 없으면 막는다" "2" "$(bg '[]')"
assert_eq "셸만 돌고 있으면 막는다" "2" "$(bg '[{"id":"b1","type":"shell","status":"running","description":"서버"}]')"

finish
