# 0027. 단계는 Stop 훅이 넘기고, 에이전트는 상태 파일의 단계를 고치지 않는다

- 상태: 채택 (2026-11-08)
- 관련: ADR 0007(작업 흐름), ADR 0012(run 확인)의 "run을 돌리는 시점"을 대신한다, ADR 0013(서브에이전트 대기), `plugin/hooks/stop-gate.sh`, `plugin/hooks/guard-state.sh`

## 배경

- 발표(슬라이드 14·28 노트)는 AI가 단계를 넘길 때마다 state.json의 단계를 고쳐 적고, 그 쓰기에 걸린 훅이 지시를 넣는다. ADR 0012는 이를 따라 에이전트가 stage를 바꾸려 할 때 PreToolUse 훅(`check-run.sh`)이 run을 돌리게 했다.
- 훅은 Edit·Write에만 걸린다. Bash로 `task.json`을 쓰면 아무 훅도 돌지 않는다. stage를 바로 `done`으로 쓰면 검사 없이 Stop 게이트도 통과한다.
  - IntervalTimer #8과 ReadSharp에서 에이전트가 `cat > .harness/state/task.json <<'EOF'`로 쓴 일이 두 번 있었다. auto 모드가 작은 수정은 Bash로 해도 된다고 안내해서 생긴 실수였다. 그때는 task 스킬에 "Write로 쓴다" 한 줄만 넣었다.
- ai-bouncer는 에이전트가 단계를 쓰지 않는다. Stop 훅(`hooks/stop.sh`)이 "current_stage를 쓰는 유일한 곳"이다. 응답을 마치려 할 때 그 단계의 run을 돌리고, 통과하면 단계를 넘기며 다음 지시를 주고 막는다. 에이전트가 상태 파일을 건드릴 일이 없어 실수로 뚫리지 않는다.
- 사용자 결정(2026-11-08): "훅이 단계를 넘기자", Bash 쓰기도 막는다.

## 결정

- **단계는 Stop 훅(`stop-gate.sh`)만 넘긴다.** 작업 주인 세션이 응답을 마치려 할 때:
  - verify 단계면 고른 검사의 `run`을 돌린다. 하나라도 실패하면 이유를 주고 막는다. 단계는 그대로다.
  - 통과했거나 run이 없는 단계면 `task.json`의 `stage`를 다음 단계로 쓰고, 다음 단계 지시(`stage-text.jq`)를 주며 막는다.
  - finish를 마치면 `done`으로 쓰고 끝내게 둔다.
  - 반복 방지(도구 없는 재진입, 10번 연속), 서브에이전트 대기(ADR 0013)는 그대로다.
- **에이전트는 `task.json`을 셋일 때만 쓴다(PreToolUse 훅 `guard-state.sh`).**
  - 새 작업 시작: 그 모드의 첫 단계로만 연다(PetCycle #103 조치 그대로).
  - 이어서 하기: 단계·모드를 그대로 두고 다시 저장한다. 고른 검사는 더할 수만 있다.
  - 취소: `"stage": "done"`과 `"cancelled": true`. 사용자가 그만두자고 했을 때만 쓴다(ai-bouncer `bouncer cancel`).
  - 그 밖의 변경(단계·모드 바꾸기, 검사 빼기, JSON이 아닌 내용)은 막는다.
- **Bash로 `task.json`을 쓰거나 지우는 명령은 막는다.** 명령에 `task.json`과 `.harness/state`가 있고, 리다이렉션(`>`)·`tee`·`cp`·`mv`·`rm`·`sed -i`·`python`·`node` 같은 쓰기가 있으면 막는다. 출력 버리기(`2>/dev/null`, `2>&1`)와 읽기는 막지 않는다.
- `check-run.sh`는 `guard-state.sh`가 되고, run을 돌리는 일은 Stop 훅으로 옮긴다. Stop 훅 timeout은 1800초로 늘린다(run 합계 1700초).
- 단계 지시 글은 `plugin/hooks/stage-text.jq` 한 곳에 두고 `stage-context.sh`(시작할 때)와 `stop-gate.sh`(넘길 때)가 같이 쓴다.

## 발표·ai-bouncer와 다른 점

- 발표와 다르다: AI가 단계를 고쳐 적지 않는다. 지시를 넣는 시점이 "단계를 고쳐 적는 순간"에서 "응답을 마치려는 순간"으로 바뀐다. 지시와 검사의 내용(prompt·run, 고른 검사만)은 발표 그대로다.
- ai-bouncer와 다르다: 상태 파일 쓰기를 Bash까지 막는다. ai-bouncer는 Edit·Write만 막는다. 우리는 시작·취소를 상태 파일 쓰기로 하므로(ai-bouncer는 `bouncer start`·`cancel` CLI) 에이전트가 이 파일을 다룰 일이 남아 있어 Bash도 막는다.

## 결과

- 좋아지는 점: 에이전트가 단계를 건너뛰거나 검사를 피할 길이 없다. Bash로 쓰는 실수는 막히면서 Write로 쓰라는 안내를 받는다.
- 비용
  - 단계마다 응답을 한 번 마쳐야 다음 지시가 온다. 지시가 Stop 훅의 차단 사유로 들어온다.
  - 글로 사용자에게 묻고 응답을 마치면 다음 단계로 넘어간다(ai-bouncer와 같다). 지시에 "사용자에게 물을 것은 AskUserQuestion으로 묻는다"를 넣었다.
  - 계획 승인 뒤에는 바로 구현하지 말고 응답을 마치게 했다. 그래야 구현 단계 지시를 받고 시작한다.
  - Bash 쓰기 판정은 글자 패턴이라 드물게 읽기 명령을 막을 수 있다(예: jq 필터 안의 `>`). 그때는 Read 도구로 읽으라고 안내한다.
- 확인 방법: 회귀 테스트(`guard-state.test.sh`, `stop-gate.test.sh`, `stage.test.sh`, `record.test.sh`), 시험장 세션에서 plan 작업 한 번을 끝까지 돌려 단계가 훅으로 넘어가는지 본다.
