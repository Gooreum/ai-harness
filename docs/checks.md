# 작업 흐름과 검사 목록 (`.harness/checks.json`)

코드를 고치는 작업은 플러그인의 `task` 스킬로 시작한다. 사람이 처음에 두 가지를 고른다: 계획이 필요한 일인지(모드)와 이번 작업에 돌릴 검사다.
그다음은 단계마다 하네스가 할 일을 알려 준다. 발표 V2의 흐름을 그대로 옮겼다([ADR 0007](decisions/0007-task-flow.md)).

## 흐름

| 모드 | 단계 | 고르는 기준 |
|---|---|---|
| `plan` | plan → implement → verify → finish | 여러 파일·화면을 건드리는 큰 작업 |
| `simple` | implement → verify → finish | 문구·한 곳 수정 같은 작은 작업 |

- 모드는 사람이 고른다. 발표에서 큰 작업을 계획 없이 하면 결함 비율이 78%(계획하면 25%)였고, 작업 크기는 AI도 미리 알기 어렵다.
- 구현을 페이지·스텝으로 나누지 않는다. 나눠도 완성도가 같거나 낮았다(93.1% / 94.4%).
- 단계 상태는 `.harness/state/task.json`에 있다(git이 무시한다). 에이전트가 단계를 마치면 `stage`를 바꾼다.
- 이 파일이 바뀔 때마다 PostToolUse 훅(`stage-context.sh`)이 그 단계의 지시를 `additionalContext`로 넣는다. 훅은 검사 내용을 모르고 아래 설정의 글을 옮길 뿐이다.

| 단계 | 하네스가 넣는 지시 |
|---|---|
| plan | EnterPlanMode로 계획하고 ExitPlanMode로 사용자 승인을 받는다 + `stages.plan.prompt` |
| implement | 구현한다 + `stages.implement.prompt` |
| verify | 고른 검사의 `prompt`를 하나씩 실행하고 실제 출력으로 확인한다 |
| finish | 바꾼 것과 검사 결과를 보고하고, 코드에 남지 않는 정책·결정을 정리한다 + `stages.finish.prompt` |

## 상태 파일 (`.harness/state/task.json`)

```json
{ "schemaVersion": 1, "title": "설정 화면 AI 모델 변경을 Processor로", "mode": "plan", "stage": "verify", "checks": ["lint", "verify"] }
```

`stage`는 모드의 단계 중 하나이거나, 끝나면 `done`이다.

## 검사 목록 예시 (ReadSharp)

```json
{
  "schemaVersion": 1,
  "stages": {
    "plan": { "prompt": "먼저 scripts/harness/wiki search로 관련 정책·결정 기록을 찾아 읽는다. 계획에는 View → Intent → Processor → State 중 어디를 바꾸는지 적는다" },
    "finish": { "prompt": "이번에 정한 정책·결정과 알게 된 사실을 docs/wiki/에 기록한다(비슷한 기록이 있으면 고친다). 쓴 뒤 scripts/harness/wiki check를 돌린다" }
  },
  "checks": [
    { "name": "lint", "description": "팀 컨벤션 검사", "prompt": "scripts/harness/lint를 실행하고 통과할 때까지 고친다", "run": "scripts/harness/passed lint" },
    { "name": "verify", "description": "앱 빌드와 단위 테스트", "prompt": "scripts/harness/verify를 실행하고 통과할 때까지 고친다", "run": "scripts/harness/passed verify" }
  ]
}
```

## 필드

| 필드 | 값 | 설명 |
|---|---|---|
| `schemaVersion` | `1` | 파일 형식 버전 |
| `stages.<단계>.prompt` | 문장, 선택 | 그 단계에 들어갈 때 기본 지시 뒤에 붙인다. 계획 기준 등 |
| `checks[].name` | 문자열 | 검사 이름. 상태 파일의 `checks`에 이 이름을 적는다 |
| `checks[].description` | 문장 | 검사를 고를 때 보여 주는 설명 |
| `checks[].prompt` | 문장 | verify 단계에서 에이전트에게 시킬 일 |
| `checks[].run` | 명령, 선택 | 정말 했는지 확인하는 명령(0이면 통과). verify 단계를 지나 넘어가려 할 때 훅이 돌린다(아래 "run 확인") |

- `project.json`은 프로젝트의 사실, `checks.json`은 팀이 정한 정책이라 나눈다(ADR 0005).
- 파일이 없어도 흐름은 동작한다. 고를 검사가 없을 뿐이다.

## run 확인 ([ADR 0012](decisions/0012-run-gate.md))

발표 슬라이드 29·30 그대로다: prompt는 시키고, run은 확인한다.

- 에이전트가 `stage`를 verify 이전·verify에서 finish·done으로 바꾸려 하면, PreToolUse 훅 `check-run.sh`가 고른 검사의 `run`을 프로젝트 루트에서 실행한다.
- 하나라도 0이 아니면 편집을 막는다. 실패한 검사, run, 출력 앞부분을 이유로 전한다. 에이전트는 고치고 다시 실행한 뒤 넘어간다.
- `run`이 없는 검사(리뷰 등)는 돌리지 않는다. 고른 검사가 없으면 막지 않는다.
- run은 결과 파일을 본다. `scripts/harness/passed <검사>`를 쓴다: `.harness/out/<검사>.json`의 `passed`가 참이고 결과가 최신이어야 통과다.
  - 최신이 아니라는 것은 이번 작업을 시작하기 전 결과이거나(`.harness/state/task.started`), 그 뒤에 고친 파일이 있다는 뜻이다. 기준은 ai-bouncer의 `bouncer passed`와 같다.
- run 합계는 1700초(`HARNESS_RUN_BUDGET`)까지다. 넘으면 시간 초과로 막는다.
- 끝내려 할 때는 Stop 훅 `stop-gate.sh`가 막는다. 작업 주인 세션(상태 파일을 마지막으로 고친 세션)은 done 전에 멈추지 못한다. 다른 세션은 막지 않는다.
  - 같은 이유로 다시 막히려는데 그 사이 도구를 쓰지 않았으면 끝내게 둔다. 같은 단계에서 10번 연속 막히면 사용자에게 넘기게 한다(ai-bouncer와 같다).
