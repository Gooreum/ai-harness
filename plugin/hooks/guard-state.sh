#!/usr/bin/env bash
# PreToolUse 훅: 작업 상태 파일(.harness/state/task.json)을 에이전트가 고쳐 단계를 넘기지 못하게 한다.
#
# 단계는 Stop 훅(stop-gate.sh)만 넘긴다. ai-bouncer(hooks/stop.sh: "current_stage를 쓰는 유일한 곳")를 따랐다(ADR 0027).
# 에이전트가 이 파일을 쓸 수 있는 때는 셋이다.
#   - 새 작업 시작: 파일이 없거나, 읽을 수 없거나, 지난 작업이 done이다. 그 모드의 첫 단계로만 연다(PetCycle #103).
#   - 이어서 하기: 단계·모드를 그대로 두고 다시 저장한다. 고른 검사는 더할 수만 있다(사용자가 바꾸자고 했을 때).
#   - 취소: stage "done"과 "cancelled": true. 사용자가 그만두자고 했을 때만 쓴다(ai-bouncer `bouncer cancel`).
# Bash로 이 파일을 쓰거나 지우는 명령은 늘 막는다. Bash로 쓰면 훅이 돌지 않는다(IntervalTimer #8, ReadSharp에서 관찰).
#
# - 입력은 stdin JSON만 읽는다 (tool_name, tool_input, cwd). Codex에서도 재사용하기 위해서다.
# - 막을 때는 이유를 stderr로 내고 2로 끝난다(슬라이드 25). 상태 파일은 바뀌지 않는다.
# - 판단할 수 없으면(상태 파일이 아님, 프로젝트가 아님, 단계 순서를 못 읽음) 막지 않는다.
set -uo pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)" || cwd=""

# --- Bash: 상태 파일을 쓰거나 지우는 명령을 막는다 --------------------------------------
if [ "$tool" = "Bash" ]; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
  case "$cmd" in *task.json*) ;; *) exit 0 ;; esac
  case "$cmd$cwd" in *.harness/state*) ;; *) exit 0 ;; esac
  # 출력을 버리거나 합치는 리다이렉션(2>/dev/null, 2>&1)은 쓰기가 아니다.
  rest="$(printf '%s' "$cmd" | sed -E 's#[0-9]*>&[0-9]##g; s#[0-9]*>>?[[:space:]]*/dev/null##g')"
  if printf '%s' "$rest" | grep -Eq '>|(^|[^[:alnum:]_-])(tee|cp|mv|rm|ln|dd|truncate|install|python3?|node|ruby|perl|sed[[:space:]]+-i)([^[:alnum:]_-]|$)'; then
    {
      echo "[하네스] .harness/state/task.json은 Bash로 쓰거나 지우지 않습니다. 명령은 실행되지 않았습니다."
      echo "단계는 하네스가 넘깁니다. 이 단계의 일을 마치면 응답을 마치세요."
      echo "새 작업 시작과 취소는 task 스킬대로 Write로 씁니다. 읽기만 할 때는 Read 도구를 씁니다."
    } >&2
    exit 2
  fi
  exit 0
fi

# --- Edit·Write·MultiEdit ------------------------------------------------------------
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
case "$file" in
  "") exit 0 ;;
  /*) ;;
  *)
    [ -n "$cwd" ] || exit 0
    file="$cwd/$file"
    ;;
esac
case "$file" in
  */.harness/state/task.json) ;;
  *) exit 0 ;;
esac
root="${file%/.harness/state/task.json}"
[ -f "$root/.harness/project.json" ] || exit 0

old=""
[ -f "$file" ] && old="$(cat "$file")"

# 고친 뒤의 상태 파일 내용
new="$(printf '%s' "$input" | jq -r --arg old "$old" '
  # 문자열 index는 바이트 위치를 돌려줘 한글이 있으면 어긋난다. split으로 바꾼다.
  def apply($s; $e):
    ($s | split($e.old_string)) as $parts
    | if ($parts | length) < 2 then $s
      elif ($e.replace_all // false) then $parts | join($e.new_string)
      else $parts[0] + $e.new_string + ($parts[1:] | join($e.old_string)) end;
  .tool_input as $in
  | if .tool_name == "Write" then $in.content // ""
    elif .tool_name == "Edit" then apply($old; $in)
    elif .tool_name == "MultiEdit" then reduce ($in.edits // [])[] as $e ($old; apply(.; $e))
    else empty end' 2> /dev/null)" || exit 0

# 모드별 단계 순서는 flows.json 한 곳에 둔다(stage-context.sh, stop-gate.sh와 같다).
flows="$(cat "$(dirname "$0")/flows.json" 2>/dev/null)" || exit 0

verdict="$(jq -rn --arg old "$old" --arg new "$new" --argjson flows "$flows" '
  (try ($old | fromjson) catch null) as $o
  | (try ($new | fromjson) catch null) as $n
  | ($o != null and ($o | type) == "object" and ($o.stage // "") != "" and $o.stage != "done") as $running
  | if $n == null or ($n | type) != "object" then (if $running then "broken" else "ok" end)
    elif ($running | not) then
      ($flows[$n.mode] // null) as $flow
      | if $flow == null then "mode"
        elif $n.stage == $flow[0] then "ok"
        else "first:" + $flow[0] end
    elif $n.stage == "done" and $n.cancelled == true then "ok"
    elif $n.stage == $o.stage and $n.mode == $o.mode then
      (if ((($o.checks // []) - ($n.checks // [])) | length) == 0 then "ok" else "drop" end)
    else "stage" end' 2> /dev/null)" || exit 0

case "$verdict" in
  ok | "") exit 0 ;;
  first:*)
    first="${verdict#first:}"
    {
      echo "[하네스] 새 작업은 첫 단계(\"$first\")에서 시작합니다. 상태 파일은 바뀌지 않았습니다."
      echo "중간 단계로 열면 그 앞 단계의 지시를 건너뛰게 됩니다. stage를 \"$first\"로 써서 다시 저장하세요."
      echo "이미 작업 밖에서 고치고 커밋한 변경이 있으면 사용자에게 알리고 어떻게 다시 검증할지 묻습니다."
    } >&2
    ;;
  mode) echo "[하네스] task.json의 mode는 plan 또는 simple이어야 합니다. 상태 파일은 바뀌지 않았습니다." >&2 ;;
  broken) echo "[하네스] 진행 중인 작업의 task.json을 JSON이 아닌 내용으로 바꿀 수 없습니다. 상태 파일은 바뀌지 않았습니다." >&2 ;;
  drop)
    {
      echo "[하네스] 진행 중인 작업에서 고른 검사를 뺄 수 없습니다. 상태 파일은 바뀌지 않았습니다."
      echo "검사를 바꿔야 하면 사용자에게 묻고, 사용자가 원하면 작업을 취소한 뒤 새로 시작합니다."
    } >&2
    ;;
  *)
    {
      echo "[하네스] 단계는 하네스가 넘깁니다. task.json의 stage·mode를 바꿀 수 없습니다. 상태 파일은 바뀌지 않았습니다."
      echo "이 단계의 일을 마치면 응답을 마치세요. 하네스가 확인하고 다음 단계로 넘기며 지시를 줍니다."
      echo "사용자가 작업을 그만두자고 했을 때만 stage를 \"done\"으로, \"cancelled\": true를 더해 저장합니다."
    } >&2
    ;;
esac
exit 2
