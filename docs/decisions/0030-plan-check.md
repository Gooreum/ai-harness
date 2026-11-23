# 0030. 단계 기준 문서를 지시에 넣고, 계획을 승인받기 전에 확인한다

- 상태: 채택 (2026-11-23)
- 관련: ADR 0007(작업 흐름), ADR 0012(run 확인), ADR 0024(플랫폼을 모른다), ADR 0027(Stop 훅이 단계를 넘긴다), `plugin/hooks/plan-gate.sh`, `plugin/hooks/stage-text.sh`, `plugin/hooks/stop-gate.sh`

## 배경

- PetCycle에서 개인 스트릭을 만들며 e2e-ios 검사를 골랐다. 스트릭 상세 화면에 새 칩과 전환이 생기는 작업이었다. `.maestro/`에는 `task-detail.yaml` 하나뿐이었다. 그래서 스트릭 화면은 한 번도 열지 않았는데도 검사가 통과했다.
- 사용자가 "신규 기능이면 시나리오를 써야 하는 것 아니냐"고 지적했다. 조사해 보니 e2e는 핵심 흐름에만 두고 새 기능은 단위·통합 테스트부터 쓰는 것이 보통이었다. 그래서 무조건 쓰게 하지 않고, plan 단계에서 필요한지 판단하게 했다.
- 사용자가 PetCycle 세션에서 정한 내용(2026-11-23):
  - plan 모드의 plan 단계에서만 다룬다. 계획서에 필요 여부와, 필요하면 시나리오 명세를 쓴다. 필요 없으면 이유를 한 줄 쓴다.
  - 이번 변경이 기존 시나리오에 영향을 주면 그 시나리오도 고친다.
  - 시나리오 파일은 implement에서 쓰고, 실행은 verify의 e2e 검사가 한다.
  - 판단 기준을 문서로 두고, 에이전트가 그 기준을 반드시 읽게 하는 장치를 둔다.
  - simple 모드는 plan 단계가 없어 이 규칙이 걸리지 않는다. 그대로 둔다.
- 발표: 슬라이드 29·30에 따르면 prompt는 에이전트에게 일을 시키는 글이다. run은 그 일을 정말 했는지 하네스가 확인하는 명령이다. e2e 검사의 prompt가 시나리오를 만들게 한다(슬라이드 29). plan 단계에서 e2e가 필요한지 판단하는 장치는 발표에 없다.
- ai-bouncer에는 단계마다 설정이 두 가지 있다(`engine/init.sh`, `engine/default.yaml`).
  - `stages.<단계>.prompt_file`: 단계 지시를 md 파일에서 읽는다.
  - `stages.<단계>.run`: 그 단계를 끝내려 할 때 도는 검사다.
- 하네스에는 `stages.<단계>.prompt`와 verify 검사의 `run`만 있었다.
- 확인한 것: Claude Code 2.1.330에서 ExitPlanMode의 PreToolUse 훅 입력에 `tool_input.plan`(계획 본문)과 `tool_input.planFilePath`가 들어온다.
  - `claude -p`에는 ExitPlanMode가 없어서 대화형 세션을 expect로 띄워 확인했다.
  - 훅이 2로 끝나면 승인 창이 뜨지 않고 stderr가 도구 에러로 에이전트에게 돌아간다.

## 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 기준을 둘 곳 | 프로젝트 위키(`docs/wiki/`, `kind: rule`)에 둔다. 하네스에는 넣지 않는다 | 핵심 흐름과 테스트 범위는 프로젝트마다 다르다. 하네스는 플랫폼과 테스트 도구를 모른다(ADR 0024) |
| 읽게 하기 | `stages.<단계>.prompt_file`: 그 단계에 들어갈 때 훅(`stage-text.sh`)이 파일 내용을 지시에 그대로 넣는다. 프로젝트 안의 상대 경로만 읽는다 | ai-bouncer의 prompt_file과 같다. 지시에 "읽어라"라고만 적으면 에이전트가 건너뛸 수 있다. 훅이 내용을 넣으면 에이전트는 따로 열지 않아도 기준을 받는다 |
| 적용 확인 | `stages.<단계>.run`: Stop 훅이 그 단계를 넘길 때마다 돌린다. 실패하면 막는다 | ai-bouncer의 stages.<단계>.run과 같다. 검사(checks)와 달리 사람이 고르지 않는다 |
| 승인 전 확인 | PreToolUse(ExitPlanMode) 훅 `plan-gate.sh`가 계획 글을 `.harness/state/plan.md`에 저장하고 `stages.plan.run`을 돌린다. 실패하면 2로 막는다 | Stop에서만 확인하면, 사용자가 기준이 빠진 계획을 이미 승인한 뒤에야 막는다. 승인 창이 뜨기 전에 막으면 사용자는 기준을 갖춘 계획만 보고 승인한다 |
| 계획 글 | 훅 입력의 `tool_input.plan`을 쓴다. 없으면 `tool_input.planFilePath`의 파일을 읽는다. 새 작업을 시작하면 지난 `plan.md`를 지운다 | 훅은 stdin JSON만 읽는다. 지난 계획으로 통과하면 안 된다 |
| 무엇을 볼지 | 하네스는 계획이 무엇을 담아야 하는지 모른다. 프로젝트의 명령(예: PetCycle `scripts/e2e-planned.sh plan`)이 `plan.md`를 본다 | 판단 기준과 줄 형식은 프로젝트의 정책이다 |
| 시간 | Stop 훅에서는 검사 run과 단계 확인을 합쳐 1700초 안에 끝내야 한다. `plan-gate.sh`의 run은 100초에서 끊고, 끊기면 막지 않는다 | Stop 훅의 제한 시간은 1800초, `plan-gate.sh`의 제한 시간은 120초다. 이 시간을 넘기면 Claude Code가 훅을 끊는다. 그러면 확인을 마치지 않은 채 단계가 지나간다 |
| 읽는 파일 | `prompt_file`이 링크면 훅은 링크가 가리키는 파일이 프로젝트 안에 있을 때만 읽는다 | 프로젝트 밖 파일이 지시에 들어가지 않게 한다 |
| 끼어드는 범위 | 작업 주인 세션이 plan 단계에 있을 때만. 판단할 수 없으면(상태 없음, 계획 글 없음) 막지 않는다 | 하네스 작업이 아닌 계획 모드를 막지 않는다. 다른 훅과 같은 원칙이다 |
| 기록 | `plan-gate.sh`의 확인은 `task.history`에 `plan-check`로, Stop의 단계 확인은 advance·blocked의 `runs`에 `stages.<단계>.run`으로 남긴다 | 에이전트가 마무리 보고의 단계 기록 표를 이 파일에서 옮긴다 |
| doctor | `prompt_file`이 없거나 프로젝트 밖 경로면 문제로 친다 | 없으면 기준 대신 "읽지 못했다"가 들어간다 |

## 발표·ai-bouncer와 다른 점

- 발표와 다르다: 발표는 e2e 검사의 prompt에서 시나리오를 만들게 한다. 계획에서 필요 여부를 정하는 장치는 발표에 없다. 사용자가 정했다.
- ai-bouncer와 다르다: ai-bouncer는 `stages.<단계>.run`을 Stop에서만 돌린다. 우리는 plan 단계면 ExitPlanMode 직전에도 돌린다. 이유는 위의 "승인 전 확인"이다.
- 에이전트가 `plan.md`를 직접 써서 Stop 확인을 통과하는 것은 막지 않는다. 그런 실패가 아직 관찰되지 않아서다(docs/principles.md의 강제 장치 원칙).

## 결과

- 프로젝트는 단계마다 기준 문서와 확인 명령을 둘 수 있다. 설정 형식은 [checks.md](../checks.md)에 있다.
- PetCycle은 e2e 판단 기준을 위키에 두고, plan 단계에서 판단 줄을 확인한다(`scripts/e2e-planned.sh plan`).
- PetCycle의 e2e-ios 검사 run은 `scripts/e2e-planned.sh verify`로 세 가지를 본다.
  - 계획한 시나리오 파일이 있다.
  - 그 파일이 이번 작업에서 생겼거나 고쳐졌다.
  - 검사 결과의 실행 명령에 그 파일이나 `.maestro/` 폴더가 들어 있다.
- 세 번째 확인은 설계안에 없던 것이다.
  - 설계안을 쓸 때는 PetCycle의 e2e가 시나리오를 전부 돌린다고 알았다. 그래서 파일이 있고 고쳐졌고 전체 실행이 통과했는지만 볼 생각이었다.
  - 실제 `scripts/e2e.sh`는 인자로 받은 시나리오만 돌린다. 인자가 없으면 `task-detail.yaml`만 돈다.
  - `record`가 실행 명령을 결과 파일에 남기므로, 스크립트가 어떤 시나리오를 돌렸는지 알 수 있다.
- simple 모드에는 plan 단계가 없어 이 확인이 걸리지 않는다.
- Claude Code는 훅 목록을 세션을 시작할 때 한 번 읽는다. 하네스를 갱신하기 전에 시작한 세션에서는 `plan-gate.sh`가 돌지 않아 `plan.md`가 생기지 않는다. 이때 Stop 훅은 세션을 다시 시작한 뒤 ExitPlanMode를 한 번 더 호출하라고 알린다(PetCycle, 2026-11-23).
