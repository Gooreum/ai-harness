# 지금 단계에서 할 일(지시 글). 입력은 task.json, 인자는 $flows(flows.json)와 $conf(checks.json을 --slurpfile로).
# stage-context.sh(작업을 시작할 때)와 stop-gate.sh(단계를 넘길 때)가 같이 쓴다.
# 훅은 검사 내용을 모른다. checks.json에 적힌 글을 단계에 맞춰 옮길 뿐이다(발표 슬라이드 27).
($conf[0]) as $c
| {
    plan: "계획만 세운다. 승인 전에는 코드를 고치지 않는다. 먼저 EnterPlanMode를 호출한다. 바꿀 파일, 바꾸는 방법, 확인 방법을 계획에 담고 ExitPlanMode로 사용자 승인을 받는다. 승인되면 구현하지 말고 응답을 마친다. 하네스가 구현 단계로 넘기며 지시를 준다. 거부되면 피드백을 반영해 계획을 다시 쓴다. ExitPlanMode가 에러를 내면 승인되지 않은 것이다.",
    implement: "구현한다. 계획 단계를 거쳤으면 승인받은 계획대로 한다. 검사는 다음 단계에서 한다.",
    verify: "요청받은 범위가 전부 구현됐는지 다시 대조하고, 빠진 것은 지금 마저 한다. 아래 검사를 위에서부터 차례로 하나씩 실행하고 실제 출력으로 결과를 확인한다. 실패하면 고친 뒤 다시 실행한다. 통과했다고 말하기 전에 출력을 확인한다. 파일을 고치는 검사(포매터, --fix, 의존성 설치)는 순서와 상관없이 먼저 돌린다. 나중에 돌리면 앞 검사의 결과가 낡은 것이 된다. 10분 넘게 걸리는 검사는 백그라운드로 돌리고 끝난 뒤 결과 파일(.harness/out/<이름>.json)을 확인한다.",
    finish: "이 단계의 다른 지시(아래의 위키 기록 등)가 있으면 그것부터 마친다. 그다음 커밋하고 push한다. 이번 작업에서 바꾼 파일(위키 포함)을 하나씩 git add 한다(git add . · -A 금지). 비밀 정보(.env, 키, 인증서)와 이번 작업과 무관한 변경은 커밋하지 않고 그대로 둔다(stash·삭제 금지). 지금 브랜치가 기본 브랜치(origin/HEAD, 없으면 main·master·develop·development)면 커밋 전에 새 브랜치를 만든다. 커밋 메시지와 브랜치 이름은 프로젝트 관례(git log)를 따른다. push하고, upstream이 없으면 git push -u origin <브랜치>로 한다. PR은 만들지 않는다. 응답을 마칠 때 하네스가 커밋·push를 확인한다. 그다음 작업 보고를 아래 일곱 섹션으로 쓴다. 섹션은 이 순서와 제목 그대로 쓰고, 섹션 사이에 구분선(---)을 넣는다. 문단을 쓰지 않는다. 문장마다 줄을 바꾸고, 한 줄에 두 문장을 쓰지 않는다. 탐색 과정은 쓰지 않는다. 내용이 없는 섹션도 지우지 않고 \"없음\"이라고 쓴다.\n### 1. 상황\n| 구분 | 내용 | 표. 결과(무엇을 끝냈고 무엇이 남았는지)를 첫 줄에, 이어서 무엇이 문제였고 무엇을 요청받았는지. 한 칸에 한 문장만 써서 줄을 맞춘다. 2~5줄.\n### 2. 조치\n| 파일 | 변경 | 표. 바꾼 파일마다 한 줄. 위키 파일은 5에 쓴다.\n### 3. 평가\n| 항목 | 상태 | 근거 | 표. 고른 검사는 모두 넣고, 확인하지 못한 것도 넣는다. 상태는 ✅ 통과 · ❌ 실패 · ⚠️ 못 함 · ➖ 안 고름 중 하나다. 근거는 결과 파일(.harness/out/<이름>.json)이나 실행한 명령이다. 근거가 없으면 통과로 쓰지 않는다. 마지막 줄은 커밋·push이고 근거에 브랜치와 커밋 해시를 쓴다.\n### 4. 단계 기록\n| 시각 | 단계 | 하네스 동작 | 표. .harness/state/task.history를 Read로 읽고 한 줄씩 옮긴다. 기억으로 채우지 않는다. 시작(start), 넘김(advance, verify면 검사별 run 종료 코드), 차단(blocked), 막은 쓰기(guard), 풀어 줌(release), 사용자에게 넘김(handoff)을 그대로 쓴다. 마지막 줄에 \"finish → done: 이 보고 뒤에 하네스가 닫음\"을 쓴다. 파일이 없으면 \"기록 없음\"이라고 쓴다.\n### 5. 위키\n| 파일 | 변경 | 종류 | 표. 이번 작업에서 docs/wiki/에 새로 쓰거나 고친 기록. git status --short -- docs/wiki 와 git diff --stat <.harness/state/task.base의 커밋> -- docs/wiki 로 확인한다. 변경은 새로 씀 · 고침 · 지움 중 하나, 종류는 rule · fact. 없으면 \"없음\".\n### 6. 건의\n| # | 할 일 | 비고 | 표. 사용자가 정하거나 해야 할 일(PR, 배포, 커밋하지 않고 둔 변경, 확인 못 한 것). 첫 열은 번호다.\n### 7. 결정 사항\n- 이번 작업에서 정한 정책·결정 중 코드에 남지 않는 것(왜 이렇게 했는지, 하지 않기로 한 것). 굵은 라벨 + 한 문장. 위키에 남겼으면 끝에 (📝 경로)를 붙인다.",
  } as $base
| . as $t
| if ($flows[$t.mode] | not) then "[하네스] task.json의 mode는 plan 또는 simple이어야 합니다."
  elif $t.stage == "done" then
    if $t.cancelled then "[하네스] 작업 \"\($t.title // "")\"을 취소했습니다. 무엇을 하다 멈췄는지 사용자에게 보고한다."
    else "[하네스] 작업 \"\($t.title // "")\"이 끝났습니다." end
  elif (($flows[$t.mode] | index($t.stage)) == null) then
    "[하네스] \($t.mode) 모드의 단계는 \($flows[$t.mode] | join(" → "))입니다. task.json의 stage를 이 중 하나로 고치세요."
  else
    ($flows[$t.mode]) as $flow
    | ($flow | index($t.stage)) as $i
    # 고른 검사는 checks.json에 적힌 순서로 넣는다. 발표처럼 적힌 순서대로 차례로 돈다(슬라이드 88).
    | ($t.checks // []) as $names
    | ((($c.checks // []) | map(select(.name as $n | $names | index($n))))
       + ($names | map(. as $n | select((($c.checks // []) | map(.name) | index($n)) == null) | { name: $n, missing: true }))) as $picked
    | ([ "[하네스] 작업 \"\($t.title // "")\" · \($t.mode) 모드 · \($t.stage) 단계 (\($i + 1)/\($flow | length))",
         $base[$t.stage] ]
       + (if $c.stages[$t.stage].prompt then [$c.stages[$t.stage].prompt] else [] end)
       + (if $t.stage == "verify" then
            if ($picked | length) == 0 then ["이번 작업은 고른 검사가 없다."]
            else ["이번에 고른 검사:"] + ($picked | map(
              if .missing then "- \(.name): .harness/checks.json에 없는 검사다. 사용자에게 알린다"
              else "- \(.name): \(.prompt)" end))
            end
          else [] end)
       + [ if $i + 1 < ($flow | length) then
             (if $t.stage == "verify" then "검사를 마치면 응답을 마친다. 하네스가 고른 검사의 run을 돌려 통과하면 \"\($flow[$i + 1])\" 단계로 넘긴다."
              else "이 단계를 마치면 응답을 마친다. 하네스가 \"\($flow[$i + 1])\" 단계로 넘기며 지시를 준다." end)
           else "보고를 마치고 응답을 마치면 작업이 끝난다." end,
           "단계는 하네스가 넘긴다. task.json은 고치지 않는다. 사용자에게 물을 것은 AskUserQuestion으로 묻는다. 글로 묻고 응답을 마치면 하네스가 다음 단계로 넘긴다." ])
    | join("\n")
  end
