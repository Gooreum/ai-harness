# 0031. 승인된 계획이 있어야 plan 단계를 넘기고, 승인 창이 없는 세션은 사용자가 스크립트로 승인한다

- 상태: 채택 (2026-11-25)
- 관련: ADR 0007(작업 흐름), ADR 0027(Stop 훅이 단계를 넘긴다), ADR 0030(계획 확인), `plugin/hooks/stop-gate.sh`, `plugin/hooks/plan-approved.sh`, `plugin/hooks/guard-state.sh`, `template/scripts/harness/approve-plan`

## 배경

- project-manager(사용자의 개인 프로젝트 매니저)는 승인된 GitHub 이슈를 `claude -p`로 작업한다. 사용자는 이 작업에도 하네스의 작업 흐름을 그대로 쓰기를 원했다. pm이 계획 단계를 따로 만들면 관리할 흐름이 둘이 된다.
- PetCycle 임시 워크트리에서 `claude -p`로 하네스 plan 모드를 돌려 봤다(2026-11-25, Claude Code 2.1.331).
  - 권한 모드 `bypassPermissions`: EnterPlanMode·ExitPlanMode가 세션에 없었다. ToolSearch로도 찾지 못했다. 에이전트가 응답을 마칠 때마다 Stop 훅이 단계를 넘겼다. 승인 없이 plan부터 done까지 모든 단계가 37초 만에 지나갔다.
  - 권한 모드 `plan`: 이 모드에서도 ExitPlanMode가 없었다. 쓰기가 막혀 `task.json`을 쓰지 못했고 작업이 시작되지 않았다.
- PetCycle에는 `stages.plan.run`이 없어 Stop 훅이 plan 단계에서 막을 근거가 없었다. 로드맵의 "관찰되면 할 것"에 적어 둔 "계획 승인은 지시뿐이라 승인 없이도 plan에서 implement로 넘어간다"가 일어났다.
- 발표: v1 하네스는 Plan 모드로 계획부터 세운다(슬라이드 17). v2는 사람이 plan과 simple을 고른다(슬라이드 32·39). 승인 창이 없는 세션은 다루지 않는다.
- ai-bouncer: plan 단계 지시(`engine/prompts/plan.md`)가 "ExitPlanMode가 실제로 승인된 뒤에만 구현한다"고 적는다. 지시만 있고, 승인을 확인하는 훅은 없다. Stop 훅(`hooks/stop.sh`)은 그 단계에 run이 없으면 넘긴다.

## 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 넘기는 조건 | Stop 훅은 승인된 계획(`.harness/state/plan.approved`)이 계획 글(`plan.md`)과 내용이 같을 때만 plan 단계를 넘긴다 | 승인이 지시에만 있을 때는 승인 없이 넘어갔다. 승인 뒤에 계획이 바뀌면 바뀐 계획은 승인받지 않은 것이다 |
| 계획 글이 없을 때 | 막는다. ExitPlanMode로 승인받으라고 알리고, ExitPlanMode가 없는 세션이면 `plan.md`에 Write로 쓰라고 알린다 | 계획 없이 넘어가지 않게 한다 |
| 승인을 기다릴 때 | 막지 않고 끝내게 둔다. 단계는 plan 그대로다. `task.history`에 `wait`를 계획마다 한 번 남기고, 사용자에게 `systemMessage`로 승인 방법을 알린다 | 막아도 에이전트가 할 일이 없다. 같은 답만 되풀이하게 된다 |
| 대화형 세션의 승인 | PostToolUse(ExitPlanMode) 훅 `plan-approved.sh`가 `plan.md`를 `plan.approved`로 복사한다 | 사용자가 승인 창에서 승인해야 도구가 실행되고 PostToolUse가 돈다. 거부하면 이 훅은 돌지 않는다 |
| 승인 창이 없는 세션의 승인 | 사용자가 `scripts/harness/approve-plan`을 실행한다. `--show`는 계획만 보여 준다. 승인한 뒤 세션을 이어 가면(`claude -p --resume`) 다음 응답 끝에 구현 단계로 넘어간다 | 승인할 사람이 세션 밖에 있다. 승인 기록을 남기는 길을 하네스가 하나로 정해 두면, 승인을 전달하는 도구(pm 등)는 이 스크립트만 부르면 된다 |
| 에이전트가 승인을 만들지 못하게 | `guard-state.sh`가 막는다. 대상은 `plan.approved`·`plan.waiting` 쓰기(Edit·Write·Bash)와 `approve-plan` 실행이다. `plan.md`는 plan 단계에서 아직 승인되지 않았을 때만 쓸 수 있다 | 에이전트가 승인 기록을 쓸 수 있으면 승인 대기가 의미 없어진다. 승인 창이 없는 세션은 에이전트가 `plan.md`를 직접 써야 해서 이 파일은 열어 둔다 |
| 승인 기록의 형식 | 해시 대신 계획 글을 그대로 복사하고 `cmp`로 비교한다 | macOS(`shasum`)와 Linux(`sha256sum`)의 도구 차이가 없다. 계획 글은 몇 KB라 복사해도 부담이 없다 |
| 새 작업 | `stage-context.sh`가 지난 `plan.md`·`plan.approved`·`plan.waiting`을 지운다 | 지난 승인으로 새 계획이 넘어가면 안 된다 |

## 발표·ai-bouncer와 다른 점

- 발표와 ai-bouncer는 계획 승인을 ExitPlanMode 승인 창에 맡기고 확인하지 않는다. 하네스는 승인을 기록하고, 그 기록이 있어야 넘긴다. 승인 창이 없는 세션에서 승인 없이 넘어간 것이 관찰됐고, 사용자가 이 방향으로 정했다(2026-11-25).
- 승인을 기다릴 때 막지 않고 끝내게 두는 것은 ai-bouncer의 반복 방지(도구 없이 같은 이유로 재진입하면 풀어 줌)와 같은 이유다.

## 결과

- 대화형 세션의 흐름은 그대로다. ExitPlanMode로 승인받으면 지금처럼 구현으로 넘어간다.
- 대화형 세션에서도 ExitPlanMode를 부르지 않고 응답을 마치면 이제 plan 단계에 머문다. 전에는 그대로 implement로 넘어갔다.
- `claude -p`로 plan 모드를 돌리면 계획을 `plan.md`에 남기고 멈춘다. 승인을 전달하는 도구는 이 파일을 사람에게 보여 주고, 승인을 받으면 `approve-plan`을 실행한 뒤 세션을 이어 간다.
- 이 버전으로 올리기 전에 시작한 plan 단계 작업은 승인 기록이 없다. ExitPlanMode로 다시 승인받거나 `approve-plan`으로 승인해야 넘어간다.
