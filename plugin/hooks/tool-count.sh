#!/usr/bin/env bash
# PreToolUse 훅(모든 도구): 작업 주인 세션의 도구 호출 수를 센다.
#
# Stop 훅(stop-gate.sh)이 "직전에 막은 뒤로 에이전트가 아무 도구도 쓰지 않았다"를 알아야,
# 같은 차단을 끝없이 되풀이하지 않는다. ai-bouncer의 pre-tool.sh가 .tool_seq를 세는 것과 같다.
#
# - 입력은 stdin JSON만 읽는다 (session_id, cwd).
# - 막지 않는다. 아무것도 출력하지 않는다.
set -uo pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)" || exit 0
dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)" || exit 0
[ -n "$session" ] && [ -n "$dir" ] || exit 0
while [ -n "$dir" ] && [ "$dir" != "/" ]; do
  [ -f "$dir/.harness/project.json" ] && break
  dir="$(dirname "$dir")"
done
state_dir="$dir/.harness/state"
[ -f "$state_dir/task.owner" ] || exit 0
[ "$(cat "$state_dir/task.owner" 2>/dev/null)" = "$session" ] || exit 0
seq="$(cat "$state_dir/tool-seq" 2>/dev/null)"
case "$seq" in '' | *[!0-9]*) seq=0 ;; esac
printf '%s' "$((seq + 1))" > "$state_dir/tool-seq" 2>/dev/null || true
exit 0
