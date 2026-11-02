#!/usr/bin/env bash
# PostToolUse 훅: 작업 상태 파일(.harness/state/task.json)이 바뀌면 지금 단계에서 할 일을 지시로 넣는다.
#
# - 입력은 stdin JSON만 읽는다 (tool_input.file_path, cwd). Codex에서도 재사용하기 위해서다.
# - 훅은 검사 내용을 모른다. .harness/checks.json에 적힌 글을 단계에 맞춰 옮길 뿐이다(발표 슬라이드 27).
# - 지시는 hookSpecificOutput.additionalContext로 내보내고 0으로 끝난다. 막지 않는다.
# - 상태 파일이 아니거나 판단할 수 없으면 아무것도 출력하지 않는다.
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

emit() {
  jq -n --arg c "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
  exit 0
}

[ -f "$file" ] || exit 0
jq -e . "$file" >/dev/null 2>&1 || emit "[하네스] .harness/state/task.json이 JSON 형식이 아닙니다. 고쳐서 다시 저장하세요."
checks="$root/.harness/checks.json"
if [ -f "$checks" ]; then
  jq -e . "$checks" >/dev/null 2>&1 || emit "[하네스] .harness/checks.json이 JSON 형식이 아닙니다. 사용자에게 알리세요."
else
  checks=""
fi

context="$(jq -r --slurpfile conf <(if [ -n "$checks" ]; then cat "$checks"; else echo '{}'; fi) '
  ($conf[0]) as $c
  | { plan: ["plan", "implement", "verify", "finish"], simple: ["implement", "verify", "finish"] } as $flows
  | {
      plan: "계획만 세운다. 코드는 고치지 않는다. 바꿀 파일, 바꾸는 방법, 확인 방법을 정리해 사용자에게 보여 주고, 승인을 받은 뒤에 다음 단계로 넘어간다.",
      implement: "구현한다. 계획 단계를 거쳤으면 승인받은 계획대로 한다. 검사는 다음 단계에서 한다.",
      verify: "아래 검사를 하나씩 실행하고 실제 출력으로 결과를 확인한다. 실패하면 고친 뒤 다시 실행한다. 통과했다고 말하기 전에 출력을 확인한다.",
      finish: "무엇을 바꿨는지, 실행한 검사와 그 결과를 실제 출력으로 보고한다. 이번 작업에서 정한 정책·결정 중 코드에 남지 않는 것(왜 이렇게 했는지, 하지 않기로 한 것)을 보고에 따로 정리한다."
    } as $base
  | . as $t
  | if ($flows[$t.mode] | not) then "[하네스] task.json의 mode는 plan 또는 simple이어야 합니다."
    elif $t.stage == "done" then "[하네스] 작업 \"\($t.title // "")\"이 끝났습니다."
    elif (($flows[$t.mode] | index($t.stage)) == null) then
      "[하네스] \($t.mode) 모드의 단계는 \($flows[$t.mode] | join(" → "))입니다. task.json의 stage를 이 중 하나로 고치세요."
    else
      ($flows[$t.mode]) as $flow
      | ($flow | index($t.stage)) as $i
      | (($t.checks // []) | map(. as $n | (($c.checks // []) | map(select(.name == $n)) | first) // { name: $n, missing: true })) as $picked
      | ([ "[하네스] 작업 \"\($t.title // "")\" · \($t.mode) 모드 · \($t.stage) 단계 (\($i + 1)/\($flow | length))",
           $base[$t.stage] ]
         + (if $c.stages[$t.stage].prompt then [$c.stages[$t.stage].prompt] else [] end)
         + (if $t.stage == "verify" then
              if ($picked | length) == 0 then ["이번 작업은 고른 검사가 없다. 바로 다음 단계로 넘어간다."]
              else ["이번에 고른 검사:"] + ($picked | map(
                if .missing then "- \(.name): .harness/checks.json에 없는 검사다. 사용자에게 알린다"
                else "- \(.name): \(.prompt)" end))
              end
            else [] end)
         + [ if $i + 1 < ($flow | length)
             then "이 단계를 마치면 .harness/state/task.json의 stage를 \"\($flow[$i + 1])\"로 바꾼다. 단계를 건너뛰지 않는다."
             else "보고를 마치면 .harness/state/task.json의 stage를 \"done\"으로 바꾼다." end ])
      | join("\n")
    end' "$file" 2>/dev/null)" || exit 0
[ -n "$context" ] && emit "$context"
exit 0
