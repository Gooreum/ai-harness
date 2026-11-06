#!/usr/bin/env bash
# review-record.sh: 리뷰어(harness:reviewer)가 연 파일과 보고서로 .harness/out/review.json을 만드는지 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
hook="$here/../plugin/hooks/review-record.sh"
passed="$here/../template/scripts/harness/passed"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/.harness" "$p/App" "$p/Img"
echo '{"schemaVersion":1,"generator":"xcodeproj"}' > "$p/.harness/project.json"
echo 'let a = 1' > "$p/App/A.swift"
echo 'let b = 1' > "$p/App/B.swift"
# passed가 쓰는 lib.sh를 프로젝트에 둔다
mkdir -p "$p/scripts/harness" && cp "$here/../template/scripts/harness/lib.sh" "$here/../template/scripts/harness/passed" "$p/scripts/harness/"
(cd "$p" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm init)

readf() { # 파일 [agent_type] [agent_id]
  jq -n --arg f "$1" --arg t "${2:-harness:reviewer}" --arg id "${3-a1}" --arg cwd "$p" \
    '{hook_event_name: "PostToolUse", session_id: "s", cwd: $cwd, tool_name: "Read", tool_input: {file_path: $f}}
     + (if $id == "" then {} else {agent_id: $id, agent_type: $t} end)' | "$hook"
}
stopr() { # 보고서 [agent_type]
  jq -n --arg m "$1" --arg t "${2:-harness:reviewer}" --arg cwd "$p" \
    '{hook_event_name: "SubagentStop", session_id: "s", cwd: $cwd, agent_id: "a1", agent_type: $t,
      agent_transcript_path: "/x", last_assistant_message: $m, stop_hook_active: false}' | "$hook"
}
result() { jq -r "$1" "$p/.harness/out/review.json"; }

echo 'let a = 2' > "$p/App/A.swift"
echo 'let c = 1' > "$p/App/C.swift"
printf 'x' > "$p/Img/i.png"

# 메인 세션이나 다른 서브에이전트의 Read는 적지 않는다
readf "$p/App/A.swift" "" ""
readf "$p/App/A.swift" "Explore" "b2"
assert_eq "다른 에이전트의 Read는 적지 않는다" "no" "$([ -e "$p/.harness/state/review-a1.reads" ] && echo yes || echo no)"

readf "$p/App/A.swift"
stopr $'[차단] App/A.swift:1 — x\n  근거: y\n  제안: z\n요약 · 차단 1 · 권장 0 · 참고 0 · 검토한 파일 1개'
assert_eq "안 연 파일을 알린다 (바이너리 제외)" "false|App/C.swift" "$(result '"\(.passed)|\(.missing | join(","))"')"
assert_eq "요약: 안 연 파일이 먼저" "리뷰어가 바뀐 파일을 열지 않았다: App/C.swift" "$(result .summary)"
assert_eq "끝나면 읽은 목록을 지운다" "no" "$([ -e "$p/.harness/state/review-a1.reads" ] && echo yes || echo no)"

readf "$p/App/A.swift"
readf "App/C.swift"
stopr $'[차단] App/A.swift:1 — x\n요약 · 차단 1 · 권장 0 · 참고 0 · 검토한 파일 2개'
assert_eq "다 열었어도 차단이 있으면 실패" "false|1|차단 1개가 남았다 — 고친 뒤 리뷰를 다시 맡긴다" "$(result '"\(.passed)|\(.blocking)|\(.summary)"')"

readf "$p/App/A.swift"
readf "App/C.swift"
stopr $'[권장] App/A.swift:1 — x\n요약 · 차단 0 · 권장 1 · 참고 0 · 검토한 파일 2개'
assert_eq "다 열고 차단 0이면 통과 (상대 경로도 cwd 기준)" "true|리뷰 통과 · 검토한 파일 2개" "$(result '"\(.passed)|\(.summary)"')"
assert_eq "passed review: 통과" "0" "$(cd "$p" && scripts/harness/passed review >/dev/null; echo $?)"
sleep 1
echo 'let a = 3' > "$p/App/A.swift"
assert_eq "passed review: 리뷰 뒤에 고치면 다시 맡겨야 한다" "2" "$(cd "$p" && scripts/harness/passed review >/dev/null; echo $?)"

readf "$p/App/A.swift"
readf "$p/App/C.swift"
stopr $'발견 없음 · 검토한 파일 2개\n열어 본 파일·규칙: …'
assert_eq "발견 없음 보고도 통과" "true|0" "$(result '"\(.passed)|\(.blocking)"')"

readf "$p/App/A.swift"
readf "$p/App/C.swift"
stopr "다 봤고 문제 없어요"
assert_eq "요약 줄이 없으면 실패" "false|리뷰어 보고서에서 요약 줄(요약 · 차단 N)을 찾지 못했다" "$(result '"\(.passed)|\(.summary)"')"

readf "$p/App/A.swift"
readf "$p/App/C.swift"
jq -n --arg cwd "$p" '{hook_event_name: "PostToolUse", cwd: $cwd, agent_id: "a1", agent_type: "harness:reviewer",
  tool_name: "SubagentHandback", tool_input: {message: "[권장] x\n요약 · 차단 0 · 권장 1 · 참고 0 · 검토한 파일 2개"}}' | "$hook"
stopr ""
assert_eq "백그라운드 리뷰어: SubagentHandback으로 넘긴 보고서를 쓴다" "true|0" "$(result '"\(.passed)|\(.blocking)"')"
assert_eq "끝나면 보고서 사본을 지운다" "no" "$([ -e "$p/.harness/state/review-a1.report" ] && echo yes || echo no)"

rm -f "$p/.harness/out/review.json"
stopr "발견 없음" "Explore"
assert_eq "다른 서브에이전트가 끝나면 결과를 쓰지 않는다" "no" "$([ -e "$p/.harness/out/review.json" ] && echo yes || echo no)"

readf "/etc/hosts"
assert_eq "프로젝트 밖 파일은 적지 않는다" "no" "$([ -e "$p/.harness/state/review-a1.reads" ] && echo yes || echo no)"

# 작업 중이면 작업을 시작한 커밋 이후 변경과, 작업 시작 뒤에 고친 추적 안 된 파일만 리뷰 대상이다
mkdir -p "$p/.harness/state" "$p/.agents"
echo 'old' > "$p/.agents/note.md"; touch -t 202601010000 "$p/.agents/note.md"
git -C "$p" rev-parse HEAD > "$p/.harness/state/task.base"
echo '{"stage":"verify"}' > "$p/.harness/state/task.json"
touch "$p/.harness/state/task.started"
git -C "$p" add App/A.swift App/C.swift && git -C "$p" -c user.name=t -c user.email=t@t commit -qm mid
readf "$p/App/A.swift"
readf "$p/App/C.swift"
stopr "발견 없음"
assert_eq "작업 중 커밋한 파일은 대상, 작업 전부터 있던 파일은 제외" "true|App/A.swift,App/C.swift" "$(result '"\(.passed)|\(.changed | join(","))"')"

# 모노레포: git 하위 폴더에 설치한 프로젝트도 루트 기준 경로로 바뀐 파일을 본다 (바뀐 파일 0개로 통과하지 않는다)
mono="$work/mono"
mkdir -p "$mono/apps/ios/.harness" "$mono/apps/ios/App"
echo '{"schemaVersion":2,"platforms":[]}' > "$mono/apps/ios/.harness/project.json"
echo 'let a = 1' > "$mono/apps/ios/App/A.swift"
(cd "$mono" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm init)
echo 'let a = 2' > "$mono/apps/ios/App/A.swift"
p="$mono/apps/ios"
stopr "발견 없음"
assert_eq "mono: 하위 폴더의 바뀐 파일을 루트 기준으로 본다" "false|App/A.swift" "$(result '"\(.passed)|\(.missing | join(","))"')"

finish
