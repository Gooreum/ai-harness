#!/usr/bin/env bash
# PostToolUse(Read·Bash) 훅: 에이전트가 위키(docs/wiki/)를 검색하고 연 것을 세션별로 남긴다.
#
# 발표 슬라이드 52: 세션마다 검색 → 열람 → 반영을 기록해 위키가 정말 쓰이는지 쟀다.
# 여기서는 검색과 열람만 남긴다. 반영은 기계로 판정하기 어려워 재지 않는다.
# 검색 결과는 있었는데 아무것도 열지 않았다면, 에이전트가 제목만 보고 넘긴 것이다. scripts/harness/wiki stats가 이것을 센다.
#
# - 입력은 stdin JSON만 읽는다 (session_id, cwd, tool_name, tool_input, tool_response, agent_type).
# - Bash: 명령에 "wiki search"가 있으면 출력에서 "종류  경로  제목" 줄의 경로를 걸린 기록으로 남긴다.
# - Read: docs/wiki/ 아래 .md 파일을 열면 그 경로를 남긴다. Bash의 cat 같은 것으로 연 것은 세지 않는다.
# - 한 줄에 한 사건을 JSON으로 .harness/state/wiki-use.jsonl에 덧붙인다.
# - 막지 않는다. 아무것도 출력하지 않는다. 판단할 수 없으면 아무것도 하지 않고 0으로 끝난다.
set -uo pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

field() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
tool="$(field .tool_name)"
session="$(field .session_id)"
cwd="$(field .cwd)"
[ -n "$session" ] && [ -n "$cwd" ] || exit 0

dir="$cwd"
while [ "$dir" != "/" ] && [ ! -f "$dir/.harness/project.json" ]; do dir="$(dirname "$dir")"; done
[ -f "$dir/.harness/project.json" ] || exit 0
root="$dir"
log="$root/.harness/state/wiki-use.jsonl"
now="$(date '+%Y-%m-%dT%H:%M:%S')"
agent="$(field .agent_type)"

case "$tool" in
  Bash)
    cmd="$(field .tool_input.command)"
    case "$cmd" in *"wiki search"*) ;; *) exit 0 ;; esac
    # 출력: tool_response가 객체면 stdout, 글자면 그대로 쓴다.
    out="$(printf '%s' "$input" | jq -r '.tool_response | if type == "object" then (.stdout // "") elif type == "string" then . else "" end' 2>/dev/null)"
    hits="$(printf '%s\n' "$out" | awk -F '\t' '$2 ~ /^docs\/wiki\// { print $2 }' | LC_ALL=C sort -u)"
    query="$(printf '%s' "$cmd" | sed -n 's/.*wiki search[[:space:]]*\([^|;&]*\).*/\1/p' | sed 's/[[:space:]]*$//')"
    mkdir -p "$(dirname "$log")" || exit 0
    jq -cn --arg t "$now" --arg s "$session" --arg a "$agent" --arg q "$query" --arg h "$hits" \
      '{t: $t, session: $s, event: "search", query: $q, hits: ($h | split("\n") | map(select(. != "")))}
       + (if $a == "" then {} else {agent: $a} end)' >> "$log" 2>/dev/null
    ;;
  Read)
    file="$(field .tool_input.file_path)"
    [ -n "$file" ] || exit 0
    case "$file" in /*) ;; *) file="$cwd/$file" ;; esac
    case "$file" in
      "$root"/docs/wiki/*.md) rel="${file#"$root"/}" ;;
      *) exit 0 ;;
    esac
    mkdir -p "$(dirname "$log")" || exit 0
    jq -cn --arg t "$now" --arg s "$session" --arg a "$agent" --arg p "$rel" \
      '{t: $t, session: $s, event: "open", path: $p} + (if $a == "" then {} else {agent: $a} end)' >> "$log" 2>/dev/null
    ;;
esac
exit 0
