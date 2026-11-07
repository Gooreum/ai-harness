#!/usr/bin/env bash
# PreToolUse 훅: 검증 단계를 지나 다음 단계로 넘어가려 할 때, 고른 검사의 run을 직접 돌려 확인한다.
#
# 발표 슬라이드 29·30·88: "prompt는 시키고, run은 확인해요."
#   다음 단계로 넘어가려 하면 훅이 run을 돌린다. 성공하면 넘어가고, 실패하면 못 넘어간다. 이유가 다음 지시가 된다.
#   run이 있는 검사는 통과해야 넘어간다.
#
# - 입력은 stdin JSON만 읽는다 (tool_name, tool_input, cwd). Codex에서도 재사용하기 위해서다.
# - 상태 파일(.harness/state/task.json)을 고치는 Edit·Write·MultiEdit만 본다. 고친 뒤의 내용을 계산해
#   stage가 verify 이전(또는 verify)에서 verify 다음(finish, done)으로 바뀌면 고른 검사의 run을 프로젝트 루트에서 실행한다.
# - 새 작업(상태 파일이 없거나 지난 작업이 done)을 첫 단계가 아닌 단계로 열면 막는다.
# - run이 하나라도 0이 아니면 이유를 stderr로 내고 2로 끝난다(슬라이드 25). 상태 파일은 바뀌지 않는다.
# - 훅은 검사 내용을 모른다. .harness/checks.json에 적힌 run을 돌릴 뿐이다.
# - 판단할 수 없으면(상태 파일이 아님, JSON 오류, 설정 없음) 막지 않는다.
set -uo pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
case "$file" in
  "") exit 0 ;;
  /*) ;;
  *)
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
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
checks="$root/.harness/checks.json"
[ -f "$checks" ] || exit 0
jq -e . "$checks" > /dev/null 2>&1 || exit 0

old=""
[ -f "$file" ] && old="$(cat "$file")"

# 고친 뒤의 상태 파일 내용
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
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
[ -n "$tool" ] && [ -n "$new" ] || exit 0

# 모드별 단계 순서는 flows.json 한 곳에 둔다(stage-context.sh와 같다). 마지막 단계 다음은 done이다.
flows="$(cat "$(dirname "$0")/flows.json" 2>/dev/null)" || exit 0

# 새 작업은 그 모드의 첫 단계에서 시작한다(ai-bouncer `bouncer start`도 첫 단계로 시작한다).
# 새 작업: 상태 파일이 없었거나, 읽을 수 없었거나, 지난 작업이 done이었다. 중간 단계로 열면 계획·구현 지시를 건너뛰고,
# 이미 커밋한 변경은 시작 커밋 뒤가 아니라 검사와 리뷰가 바뀐 파일 없이 통과한다(PetCycle #103).
first="$(jq -rn --arg old "$old" --arg new "$new" --argjson flows "$flows" '
  ($new | fromjson) as $n
  | (try ($old | fromjson) catch null) as $o
  | ($flows[$n.mode] // null) as $flow
  | if $flow == null then empty
    elif ($o != null and ($o.stage // "") != "" and $o.stage != "done") then empty
    elif $n.stage == $flow[0] then empty
    else $flow[0] end' 2> /dev/null)" || first=""
if [ -n "$first" ]; then
  {
    echo "[하네스] 새 작업은 첫 단계(\"$first\")에서 시작합니다. stage는 바뀌지 않았습니다."
    echo "중간 단계로 열면 그 앞 단계의 지시를 건너뛰게 됩니다. stage를 \"$first\"로 써서 다시 저장하세요."
    echo "이미 작업 밖에서 고치고 커밋한 변경이 있으면 사용자에게 알리고 어떻게 다시 검증할지 묻습니다."
  } >&2
  exit 2
fi

# 넘어가는지 판단: verify 단계를 지나 finish·done으로 가는가
gate="$(jq -rn --arg old "$old" --arg new "$new" --argjson flows "$flows" '
  ($new | fromjson) as $n
  | (try ($old | fromjson) catch {}) as $o
  | (($flows[$n.mode] // null) | if . then . + ["done"] else null end) as $flow
  | if $flow == null then empty
    else ($flow | index("verify")) as $v
      | ($flow | index($n.stage)) as $ni
      | (if ($o.mode // null) == $n.mode then ($flow | index($o.stage)) else null end) as $oi
      | if $ni == null or $ni <= $v then empty
        elif $oi != null and $oi > $v then empty
        else ($n.checks // []) | join("\n") end
    end' 2> /dev/null)" || exit 0
[ -n "$gate" ] || exit 0

# run에 시간 제한을 둔다. 합계가 훅 timeout(hooks.json, 1800초)보다 짧아야 한다(ai-bouncer와 같은 1700초).
run_timeout() { # 초 명령...
  local secs="$1" pid waited=0
  shift
  "$@" &
  pid=$!
  while kill -0 "$pid" 2> /dev/null; do
    if [ "$waited" -ge "$((secs * 5))" ]; then
      pkill -TERM -P "$pid" 2> /dev/null
      kill -TERM "$pid" 2> /dev/null
      wait "$pid" 2> /dev/null
      return 124
    fi
    sleep 0.2
    waited=$((waited + 1))
  done
  wait "$pid"
}
deadline=$(($(date +%s) + ${HARNESS_RUN_BUDGET:-1700}))

failures=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  # 고른 검사가 설정에 없으면(이름이 바뀌었거나 오타) run을 찾을 수 없다. 건너뛰면 검사 없이 통과로 보이므로 막는다.
  if ! jq -e --arg n "$name" 'any(.checks[]?; .name == $n)' "$checks" > /dev/null 2>&1; then
    failures="$failures- ${name}: .harness/checks.json에 없는 검사다. 고른 검사를 임의로 빼지 말고 사용자에게 알린다"$'\n'
    continue
  fi
  run="$(jq -r --arg n "$name" '[.checks[]? | select(.name == $n)][0].run // empty' "$checks")"
  [ -n "$run" ] || continue
  # 예산을 다 써도 남은 run은 1초로라도 돌려 시간 초과로 보고한다. 건너뛰면 통과로 보인다.
  left=$((deadline - $(date +%s)))
  [ "$left" -gt 0 ] || left=1
  out="$(cd "$root" && run_timeout "$left" bash -c "$run" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    case "$rc" in
      124) why="시간이 초과됐다 (${HARNESS_RUN_BUDGET:-1700}초). run은 결과 파일만 보게 하고, 검사 자체는 prompt대로 먼저 실행한다" ;;
      127) why="명령을 찾을 수 없다. 경로·도구 설치를 확인한다" ;;
      *) why="실패했다" ;;
    esac
    failures="$failures- ${name}: run \`$run\`이 $why (종료 코드 $rc)"$'\n'
    [ -z "$out" ] || failures="$failures$(printf '%s\n' "$out" | sed -n '1,10p' | sed 's/^/    /')"$'\n'
  fi
done <<EOF
$gate
EOF
[ -n "$failures" ] || exit 0

{
  echo "[하네스] 검사를 통과하지 못해 다음 단계로 넘어갈 수 없습니다. stage는 바뀌지 않았습니다."
  printf '%s' "$failures"
  echo "실패한 검사의 prompt대로 다시 실행해 원인을 고치고, 통과한 뒤에 stage를 바꾸세요."
} >&2
exit 2
