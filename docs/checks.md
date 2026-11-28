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
- 모드별 단계 순서는 플러그인의 `plugin/hooks/flows.json` 한 곳에 있다. 단계 지시 훅, 상태 보호 훅, Stop 훅이 같이 읽는다.
- 단계 상태는 `.harness/state/task.json`에 있다(git이 무시한다). 에이전트는 작업을 시작할 때만 이 파일을 쓰고, 단계는 Stop 훅(`stop-gate.sh`)이 넘긴다. 에이전트가 단계의 일을 마치고 응답을 마치려 하면 훅이 확인하고 `stage`를 다음 단계로 쓴다([ADR 0027](decisions/0027-stop-advances-stage.md)).
- 시작할 때는 PostToolUse 훅(`stage-context.sh`)이, 단계를 넘길 때는 Stop 훅이 그 단계의 지시를 넣는다. 지시 글은 `plugin/hooks/stage-text.jq` 한 곳에 있다. 훅은 검사 내용을 모르고 아래 설정의 글을 옮길 뿐이다.

| 단계 | 하네스가 넣는 지시 |
|---|---|
| plan | EnterPlanMode로 계획하고 ExitPlanMode로 사용자 승인을 받는다. ExitPlanMode가 없는 세션은 계획을 `.harness/state/plan.md`에 쓰고 사용자가 `scripts/harness/approve-plan`으로 승인한다. 승인된 계획이 있어야 구현 단계로 넘어간다(ADR 0031) + `stages.plan.prompt` + `stages.plan.prompt_file`의 내용 |
| implement | 구현한다 + `stages.implement.prompt` |
| verify | 고른 검사의 `prompt`를 `checks.json`에 적힌 순서대로 하나씩 실행하고 실제 출력으로 확인한다 |
| finish | `stages.finish.prompt`(위키 기록 등)를 먼저 하고, 바꾼 파일을 하나씩 add해 커밋하고 push한다(기본 브랜치면 새 브랜치). Stop 훅이 커밋·push를 확인한 뒤 닫는다(ADR 0028). 추천 설정의 `stages.finish.run`에는 `scripts/harness/wiki done`이 들어 있다. 이 확인은 이번 작업에 위키 기록이 있거나, 기록이 없는 이유를 `.harness/state/wiki.skip`에 적었을 때 통과한다(ADR 0032). 그다음 작업 보고를 일곱 섹션(1. 상황 · 2. 조치 · 3. 평가 · 4. 단계 기록 · 5. 위키 · 6. 건의 · 7. 결정 사항)으로 쓴다. 섹션 사이는 구분선, 문장마다 줄을 바꾸고, 평가는 근거(결과 파일·명령)가 있는 표로, 단계 기록은 `.harness/state/task.history`에서, 위키는 시작 커밋 이후 `docs/wiki/` 변경에서 옮긴다 |

## 상태 파일 (`.harness/state/task.json`)

```json
{ "schemaVersion": 1, "title": "설정 화면 AI 모델 변경을 Processor로", "mode": "plan", "stage": "verify", "checks": ["lint", "unit-test"] }
```

`stage`는 모드의 단계 중 하나이거나, 끝나면 `done`이다. 사용자가 그만두자고 해서 취소한 작업은 `"stage": "done", "cancelled": true`다.

## 검사 목록 예시 (ReadSharp, 넘겨받은 iOS 스크립트)

ReadSharp는 예전 iOS 묶음의 스크립트를 `scripts/ios/`로 넘겨받아 쓴다([ADR 0024](decisions/0024-no-platform.md)). 이 스크립트들은 결과 파일(`.harness/out/<이름>.json`)을 직접 남기므로 `record` 없이 부른다.

```json
{
  "schemaVersion": 1,
  "stages": {
    "plan": { "prompt": "먼저 scripts/harness/wiki search로 관련 정책·결정 기록을 찾아 읽는다. 계획에는 View → Intent → Processor → State 중 어디를 바꾸는지 적는다" },
    "finish": { "prompt": "이번에 정한 정책·결정과 알게 된 사실을 docs/wiki/에 기록한다(비슷한 기록이 있으면 고친다). 쓴 뒤 scripts/harness/wiki check를 돌린다. 남길 것이 없으면 그 이유를 한 줄로 .harness/state/wiki.skip에 쓴다", "run": "scripts/harness/wiki done" }
  },
  "checks": [
    { "name": "build", "description": "앱 빌드만", "prompt": "scripts/ios/build를 실행하고 통과할 때까지 고친다", "run": "scripts/harness/passed build" },
    { "name": "lint", "description": "팀 컨벤션 검사", "prompt": "scripts/ios/lint를 실행하고 통과할 때까지 고친다", "run": "scripts/harness/passed lint" },
    { "name": "unit-test", "description": "앱 빌드와 단위 테스트", "prompt": "scripts/ios/unit-test를 실행하고 통과할 때까지 고친다", "run": "scripts/harness/passed unit-test" },
    { "name": "review", "description": "reviewer 코드 리뷰", "prompt": "harness:reviewer 서브에이전트에 변경 검토를 맡기고 차단 항목을 고친다. 고친 뒤에는 다시 맡긴다", "run": "scripts/harness/passed review" },
    { "name": "e2e", "description": "이번 기능과 영향 받는 흐름의 E2E", "prompt": ".claude/rules/project/ios/maestro.md의 '작업에서 무엇을 만들고 무엇을 돌리나'를 따른다. 이번 기능의 결과로 끝나는 기능 시나리오를 만들고(기능이 나오는 조건은 시나리오 안에서 만든다), 리뷰어가 적은 영향 받는 흐름의 기존 시나리오와 함께 scripts/ios/e2e --record <기능 시나리오> <영향 시나리오...>로 통과시킨다. QA 티켓이면 고치기 전에 같은 기능 시나리오를 --record로 돌리고 영상을 .harness/out/e2e-before.mp4로 옮겨 둔다", "run": "scripts/harness/passed e2e" }
  ]
}
```

- e2e의 기능 시나리오와 영향 시나리오는 그 프로젝트의 규칙 `.claude/rules/project/ios/maestro.md`가 정한다.
- 찍은 영상은 PR을 만들 때 `scripts/harness/pr-video`로 줄여 PR 본문에 넣는다. 수정 전 영상은 `e2e-before.mp4`로 옮겨 둬야 `--record`가 덮어쓰지 않는다([ADR 0029](decisions/0029-pr-video.md)).
- 회귀 묶음 전체(`--tag regression`)는 `e2e`에 넣지 않고 따로 `regression` 검사로 둔다. 배포 전 통합 검증이나 리팩터링 뒤에 작업을 시작하며 사용자가 고른다(발표 슬라이드 86, [ADR 0025](decisions/0025-regression-check.md)). 하네스가 따로 돌리는 때(훅·CI·git 훅)는 두지 않는다.
  ```json
  { "name": "regression", "description": "회귀 묶음 전체 (배포 전·리팩터링 뒤에 고른다)", "prompt": "scripts/harness/record regression scripts/ios/e2e --tag regression을 실행하고, 실패하면 이번 변경 때문인지 먼저 확인한 뒤 고친다", "run": "scripts/harness/passed regression" }
  ```

## e2e 계획 확인 (계획에서 정한 시나리오 쓰기·돌리기)

plan 단계에서 e2e 시나리오가 필요한지 정하게 한다. 필요하다고 정하면 e2e 검사를 고르지 않았어도 implement에서 시나리오를 쓴다. 돌릴지는 작업을 시작할 때 사람이 e2e 검사로 고른다([ADR 0033](decisions/0033-e2e-plan.md)). setup은 e2e 검사가 있는 프로젝트에 묻지 않고 이 설정을 넣는다.

`project.json`에 시나리오 폴더를 적는다.

```json
{ "e2e": { "scenarios": ".maestro" } }
```

`checks.json`에서 e2e 검사에 `"e2e": true`를 붙이고, 단계 확인을 둔다.

```json
{
  "checks": [
    { "name": "e2e-ios", "e2e": true, "description": "iOS 시뮬레이터 E2E (Maestro)",
      "prompt": "scripts/harness/e2e-plan list로 돌릴 시나리오를 보고 scripts/harness/record e2e-ios \"scripts/e2e.sh ios <시나리오들>\"를 실행해 통과할 때까지 고친다",
      "run": "scripts/harness/passed e2e-ios && scripts/harness/e2e-plan ran e2e-ios" }
  ],
  "stages": {
    "plan": {
      "prompt": "먼저 scripts/harness/wiki search로 관련 정책·결정 기록을 찾아 읽는다",
      "prompt_file": ["scripts/harness/e2e-criteria.md"],
      "run": "scripts/harness/e2e-plan plan"
    },
    "implement": { "run": "scripts/harness/e2e-plan written" }
  }
}
```

- 판단 기준은 `scripts/harness/e2e-criteria.md`(하네스 문서)다. 훅이 plan 단계 지시에 그 내용을 넣는다. 무엇이 핵심 흐름인지(기준 N3)는 프로젝트 위키에 rule로 둔다.
- `e2e-plan plan`은 계획서(`.harness/state/plan.md`)의 판단 줄, 시나리오 줄, 시작점·동작·확인을 본다. e2e 검사를 고르지 않았고 판단이 필요·기존 수정이면 `- e2e 실행: 안 함` 줄도 있어야 한다. 사람은 승인 창에서 이 줄을 보고 돌릴지 정한다.
- `e2e-plan written`은 계획한 시나리오가 이번 작업에서 쓰이거나 고쳐졌는지 본다. e2e 검사를 고르지 않았으면 그 시나리오를 `.harness/e2e-unrun`에 남긴다. 이 파일은 커밋한다.
- `e2e-plan ran <검사>`는 그 검사의 실행 명령(`record`가 결과 파일에 남긴 `command`)에 계획한 시나리오와 `.harness/e2e-unrun`의 시나리오가 들어 있는지 본다. 시나리오 폴더를 통째로 넣어도 된다. 통과하면 돌린 시나리오를 목록에서 지운다.
- 빠진 설정은 doctor가 알린다.

## 검사 목록 예시 (저장소의 명령을 record로: RN·Android·웹)

하네스는 어느 플랫폼의 빌드·테스트·e2e 도구도 고르지 않는다. 저장소가 쓰는 명령을 `record`로 돌리고 `passed`로 확인한다([ADR 0023](decisions/0023-no-pack-repo.md), [ADR 0024](decisions/0024-no-platform.md)).

```json
{
  "schemaVersion": 1,
  "checks": [
    { "name": "typecheck", "description": "타입 검사", "prompt": "scripts/harness/record typecheck \"npm run typecheck\"를 실행하고 통과할 때까지 고친다", "run": "scripts/harness/passed typecheck" },
    { "name": "test-related", "description": "바뀐 파일과 관련된 jest 테스트", "prompt": "scripts/harness/record test-related \"npx jest --findRelatedTests <이번에 바꾼 파일들>\"를 실행하고 통과할 때까지 고친다", "run": "scripts/harness/passed test-related" },
    { "name": "review", "description": "reviewer 코드 리뷰", "prompt": "harness:reviewer 서브에이전트에 변경 검토를 맡기고 차단 항목을 고친다. 고친 뒤에는 다시 맡긴다", "run": "scripts/harness/passed review" },
    { "name": "e2e-android", "description": "Android 에뮬레이터 E2E (Maestro)", "prompt": "앱을 에뮬레이터에 설치한 뒤 scripts/harness/record e2e-android \"maestro test .maestro/<이번 기능 시나리오>\"를 실행하고 통과할 때까지 고친다", "run": "scripts/harness/passed e2e-android" },
    { "name": "e2e-web", "description": "웹 E2E (Playwright)", "prompt": "scripts/harness/record e2e-web \"npx playwright test <이번 기능 테스트>\"를 실행하고 통과할 때까지 고친다", "run": "scripts/harness/passed e2e-web" }
  ]
}
```

- 10분 넘게 걸리는 명령은 `record`를 백그라운드로 돌리고 결과 파일을 본다.

## 필드

| 필드 | 값 | 설명 |
|---|---|---|
| `schemaVersion` | `1` | 파일 형식 버전 |
| `stages.<단계>.prompt` | 문장, 선택 | 그 단계에 들어갈 때 기본 지시 뒤에 붙인다. 계획 기준, 위키 찾기·쓰기 등. setup이 위키 지시(`common-checks.json`의 `stages`)를 추천한다 |
| `stages.<단계>.prompt_file` | 프로젝트 루트 기준 상대 경로나 그 배열, 선택 | 그 단계에 들어갈 때 훅이 이 파일(배열이면 파일마다)의 내용을 지시에 그대로 넣는다. 에이전트가 기준 문서를 읽지 않고 넘어가지 못하게 하려는 것이다. 파일이 없으면 지시에 그 사실을 넣고 doctor가 문제로 친다. 파일 내용이 지시에 통째로 들어가니 파일을 짧게 쓴다([ADR 0030](decisions/0030-plan-check.md)) |
| `stages.<단계>.run` | 명령, 선택 | 그 단계를 지날 때마다 Stop 훅이 돌리는 확인(0이면 통과). 사람이 고르지 않는다. plan 단계면 `plan-gate.sh`가 ExitPlanMode 직전에도 돌린다. 이 명령이 볼 계획 글은 `.harness/state/plan.md`에 있다(ADR 0030) |
| `wiki` | `false`, 선택 | 위키를 쓰지 않기로 한 프로젝트. doctor가 위키 단계 지시가 없다고 주의를 주지 않는다 |
| `checks[].name` | 문자열 | 검사 이름. 상태 파일의 `checks`에 이 이름을 적는다 |
| `checks[].description` | 문장 | 검사를 고를 때 보여 주는 설명 |
| `checks[].prompt` | 문장 | verify 단계에서 에이전트에게 시킬 일 |
| `checks[].e2e` | `true`, 선택 | e2e 검사 표시. `e2e-plan`이 이 검사를 골랐는지 보고 e2e 계획 확인을 한다(위 "e2e 계획 확인") |
| `checks[].run` | 명령, 선택 | 정말 했는지 확인하는 명령(0이면 통과). verify 단계를 지나 넘어가려 할 때 훅이 돌린다(아래 "run 확인") |

- `project.json`은 프로젝트의 사실, `checks.json`은 팀이 정한 정책이라 나눈다(ADR 0005).
- 검사 이름은 결과 파일 이름과 같게 둔다(`unit-test` → `.harness/out/unit-test.json` → `passed unit-test`). ai-bouncer의 `bouncer record <이름>`·`bouncer passed <이름>`과 같은 짝이다.
- 저장소의 명령은 `scripts/harness/record <이름> <명령>`으로 돌린다. 예: `{ "name": "typecheck", "prompt": "scripts/harness/record typecheck npm run typecheck를 실행하고 통과할 때까지 고친다", "run": "scripts/harness/passed typecheck" }`([scripts.md](scripts.md#record)). 저장소의 도구가 같은 형식의 결과 파일을 직접 남기면 `record` 없이 부른다(위 ReadSharp 예시).
- 파일을 고치는 검사(포매터, `--fix`, 설치)는 먼저 돌린다. 나중에 돌리면 앞 검사 결과가 낡은 것이 돼 `passed`가 막는다. 10분 넘게 걸리는 검사는 백그라운드로 돌리고 결과 파일을 본다. 둘 다 verify 단계 지시에 들어 있다.
- 검사는 `checks.json`에 적힌 순서대로 돈다(발표 슬라이드 88 "차례로 수행"). 싸고 빠른 것을 앞에, 코드를 바꿀 수 있는 리뷰를 E2E 앞에, 가장 오래 걸리는 E2E를 맨 뒤에 둔다. 그래야 리뷰를 반영한 최종 코드로 E2E를 한 번만 돌린다.
- `verify`는 단계 이름으로만 쓴다. 빌드·단위 테스트 검사는 발표(슬라이드 38·88)대로 `unit-test`라 부른다.
- 파일이 없어도 흐름은 동작한다. 고를 검사가 없을 뿐이다.
- 처음 정할 때는 Claude 세션에서 `scripts/harness/setup` 안내를 따른다. 저장소에서 찾은 명령(ai-bouncer `setup`과 같은 규칙, `scripts/` 아래 실행 파일 포함)과 하네스 추천 검사(review)를 보여 주고, 에이전트가 사용자에게 고르게 한 뒤 이 파일을 쓴다. 생성 파일·고치면 안 되는 파일·빌드·테스트 명령도 함께 정한다. setup 자체는 아무것도 쓰지 않는다([scripts.md](scripts.md#setup), [ADR 0020](decisions/0020-install-checks-permissions-root.md), [ADR 0024](decisions/0024-no-platform.md)).
- `scripts/harness/doctor`가 run 명령이 있는지, `passed <이름>`이 확인하는 결과를 만드는 곳이 있는지 본다. 만드는 곳은 prompt의 `record <이름>`, prompt가 부르는 실행 파일 중 이름이 `<이름>`인 것(예: `scripts/ios/unit-test`), 리뷰(`review`) 중 하나다.

## run 확인 ([ADR 0012](decisions/0012-run-gate.md))

발표 슬라이드 29·30 그대로다: prompt는 시키고, run은 확인한다.

- 검증 단계에서 에이전트가 응답을 마치려 하면, Stop 훅 `stop-gate.sh`가 고른 검사의 `run`을 프로젝트 루트에서 실행한다. 단계는 훅만 넘긴다. 에이전트는 `stage`를 고칠 수 없다([ADR 0027](decisions/0027-stop-advances-stage.md)).
- 하나라도 0이 아니면 막는다. 실패한 검사, run, 출력 앞부분을 이유로 전한다. 에이전트는 고치고 다시 실행한 뒤 다시 응답을 마친다. 모두 통과하면 훅이 finish로 넘긴다.
- `run`이 없는 검사는 돌리지 않는다. 고른 검사가 없으면 막지 않는다.
- 리뷰의 결과 파일 `.harness/out/review.json`은 리뷰어가 아니라 플러그인 훅 `review-record.sh`가 쓴다. 리뷰어가 바뀐 파일을 Read로 다 열었고 차단이 0이어야 통과다([plugin.md](plugin.md), [ADR 0016](decisions/0016-review-record.md)).
- 고른 검사가 `checks.json`에 없으면(이름이 바뀌었거나 오타) 막는다. 건너뛰면 검사 없이 통과로 보이기 때문이다.
- 새 작업은 그 모드의 첫 단계(plan은 `plan`, simple은 `implement`)로만 연다. `guard-state.sh`가 중간 단계로 여는 것과 진행 중인 단계를 고치는 것, Bash로 상태 파일을 쓰는 것을 막는다.
- 어느 단계든 `stages.<단계>.run`이 있으면 그 단계를 넘길 때 돌린다. 실패하면 막는다. plan 단계에서는 ExitPlanMode 직전에 `plan-gate.sh`가 먼저 돌린다. 실패하면 승인 창이 뜨지 않는다(ADR 0030).
- run은 결과 파일을 본다. `scripts/harness/passed <검사>`를 쓴다: `.harness/out/<검사>.json`의 `passed`가 참이고 결과가 최신이어야 통과다.
  - 최신이 아니라는 것은 이번 작업을 시작하기 전 결과이거나(`.harness/state/task.started`), 그 뒤에 고친 파일이 있다는 뜻이다. 바뀐 파일은 작업을 시작한 커밋(`.harness/state/task.base`)부터 본다. 작업 중에 커밋해도 빠지지 않는다. 기준은 ai-bouncer의 `bouncer passed`와 같다.

### 단계 기록 (`.harness/state/task.history`)

훅이 작업마다 한 줄에 JSON 하나씩 남긴다. 에이전트는 쓰지 않는다. 마무리 보고의 "4. 단계 기록" 표가 이 파일을 옮긴다(ai-bouncer `state.json`의 `history`). `task.json`에 넣지 않은 것은 에이전트가 이어서 하기·취소로 그 파일을 다시 쓰기 때문이다.

| event | 쓰는 훅 | 내용 |
|---|---|---|
| `start` | stage-context | 새 작업. 지난 기록을 지우고 `stage`·`mode`·`checks` |
| `resume` · `cancel` | stage-context | 같은 단계로 다시 저장 / 사용자가 취소 (`from`) |
| `advance` | stop-gate | `from` → `to`. verify면 `runs`(검사별 `rc`, run 없음은 `run: false`, 설정에 없음은 `missing`), finish면 `commit`·`push` 확인 결과 |
| `blocked` | stop-gate | 막은 이유 첫 줄(`why`)과 `runs`(단계 확인은 `stages.<단계>.run`) |
| `plan-check` | plan-gate | ExitPlanMode 직전 계획 확인의 `runs`(`stages.plan.run`의 `rc`) |
| `wait` | stop-gate | 계획이 아직 승인되지 않아 Stop 훅이 단계를 넘기지 않고 끝내게 둠. 같은 계획이면 한 번만 |
| `approve` | plan-approved · approve-plan | 계획 승인. `by`는 `ExitPlanMode` 또는 `approve-plan` |
| `release` · `handoff` | stop-gate | 도구 없이 재진입해 풀어 줌 / 10번 연속이라 사용자에게 넘김 |
| `guard` | guard-state | 막은 `task.json` 쓰기와 Bash로 상태 파일(`task.json`·`plan.approved`·`plan.waiting`) 쓰기(`tool`, `why`). Edit·Write로 승인 기록을 쓰거나 `approve-plan`을 실행하려 한 것은 기록하지 않는다 |
- run 합계는 1700초(`HARNESS_RUN_BUDGET`)까지다. 넘으면 시간 초과로 막는다.
- run은 묻지 않고 실행된다. `checks.json`은 저장소에 커밋되므로, 남의 저장소를 내려받아 하네스 작업을 하면 그 저장소가 적은 명령이 그대로 돈다. 처음에는 `checks.json`을 열어 확인한다. `scripts/harness/doctor`는 `scripts/harness/passed`가 아닌 run을 "참고"로 보여 준다.
- 같은 Stop 훅이 done 전에는 끝내지 못하게 한다. 작업 주인 세션(상태 파일을 마지막으로 쓴 세션)만 보고 다른 세션은 막지 않는다.
  - 같은 이유로 다시 막히려는데 그 사이 도구를 쓰지 않았으면 끝내게 둔다. 같은 단계에서 10번 연속 막히면 사용자에게 넘기게 한다(ai-bouncer와 같다).
