# 0012. 검증 강제: 단계를 넘길 때 run을 돌리고, 끝나기 전에는 멈추지 못하게 한다

- 상태: 채택 (2026-11-03)
- 관련: ADR 0005(발표 기준), ADR 0007(작업 흐름), 로드맵 후보 13

## 배경

- 발표 슬라이드 28: prompt는 검사를 시키기만 하고 정말 했는지는 확인하지 않아서, AI가 "통과했어요"라고 하면 믿을 수밖에 없었다.
- 슬라이드 29·30: 그래서 config의 검사마다 `run`(확인 스크립트)을 두고, 다음 단계로 넘어가려는 순간 훅이 run을 돌린다. 성공하면 넘어가고, 실패하면 못 넘어가며 이유가 다음 지시가 된다. "run이 있는 검사는 통과해야 넘어가요."
- 슬라이드 88: 통과하지 못하면 AI는 끝낼 수 없다.
- ADR 0007은 `run` 필드만 정의하고 실행하지 않았다. 로드맵은 후보 13을 "검증을 건너뛰는 일이 관찰될 때만 켠다"는 조건부로 두었다. 이 조건은 발표에 없고 이 저장소의 원칙 2에서 나왔다.
- 2026-11-03 ReadSharp #217 실행에서 verify(빌드·테스트) 통과를 에이전트의 말로만 알 수 있었다. verify가 결과 파일을 남기지 않아서다. 슬라이드 28의 상황과 같다.
- 사용자가 발표를 그대로 따르고, 발표에 없는 것은 ai-bouncer를 따르며, 다른 점은 보고하라고 정했다(2026-11-03). 그래서 조건을 걷고 발표대로 켠다.

## 결정

| 항목 | 결정 | 근거 |
|---|---|---|
| 언제 | 상태 파일의 `stage`가 verify 이전·verify에서 verify 다음(finish·done)으로 바뀌려 할 때 | 슬라이드 29 "다음 단계로 넘어가려 해요 → 그때 훅이 떠요" |
| 무엇을 | 상태 파일에 고른 검사 중 `run`이 있는 것만, 프로젝트 루트에서 실행. 0이면 통과 | 슬라이드 30 "고른 검사만 들어가고, run이 있는 검사는 통과해야 넘어가요" |
| 실패하면 | 편집을 막고(exit 2) 실패한 검사·run·출력을 이유로 전한다. 상태 파일은 바뀌지 않는다 | 슬라이드 25 "exit 2 멈춰 세워요", 슬라이드 29 "이유가 다음 지시가 돼요" |
| 훅 | 플러그인 PreToolUse 훅 `check-run.sh`. 훅은 검사 내용을 모르고 config의 run을 돌릴 뿐이다 | 슬라이드 27과 같은 구조 |
| 끝내려 할 때 | 플러그인 Stop 훅 `stop-gate.sh`. 작업 주인 세션이 done 전(plan 포함)에 끝내려 하면 이유를 stderr로 내고 2로 끝나 멈추지 못하게 한다 | 슬라이드 14 "완료가 아니면 못 멈추게", 슬라이드 88 "통과하지 못하면 끝낼 수 없어요" |
| 계획 승인 | plan 단계 지시는 EnterPlanMode로 계획하고 ExitPlanMode로 승인받게 한다. 승인이 턴 안에서 끝나므로 Stop 훅에 예외가 필요 없다 | 슬라이드 17 "Plan 모드로 항상 계획부터", ai-bouncer `engine/prompts/plan.md` |
| verify 결과 파일 | `scripts/harness/verify`가 `.harness/out/verify.json`(`passed`, `summary`)을 남긴다. 시작할 때 먼저 실패로 적어, 파일은 늘 가장 최근 실행을 가리킨다 | 슬라이드 29의 run은 "가장 최근 실행이 통과했는지" 본다. andcon도 결과를 파일로 남긴다(슬라이드 67) |

### 발표가 다루지 않아 ai-bouncer를 따른 것

근거는 ai-bouncer 설치본(`~/.claude/ai-bouncer`, kangraemin/ai-bouncer main 173d39a)의 `hooks/stop.sh`, `hooks/pre-tool.sh`, `engine/lib/common.sh`다.

| 항목 | 결정 | ai-bouncer |
|---|---|---|
| 세션 구분 | 상태 파일을 고친 세션을 `.harness/state/task.owner`에 적고(`stage-context.sh`), Stop 훅은 그 세션만 막는다. 진행 중인 작업을 다시 저장한 세션이 이어받는다 | 작업의 `.active`에 세션 ID를 적고 `bouncer_my_task`로 내 작업만 본다 |
| 도구 없는 반복 | 직전과 같은 이유로 재진입(`stop_hook_active`)했는데 그 사이 도구를 하나도 안 썼으면 끝내게 둔다. 도구 수는 PreToolUse 훅 `tool-count.sh`가 주인 세션만 센다 | `guarded_block`의 `.block_key`·`.tool_seq` 비교. 도구 없는 반복 54건, 최대 939회 관찰 |
| 연속 차단 | 같은 단계에서 10번(`HARNESS_MAX_CONTINUE`) 막았으면 더 막지 않고 사용자에게 계속·접근 변경·중단을 묻게 한다. 단계가 바뀌면 처음부터 센다 | `MAX_CONTINUE=10`, `continue_streak` |
| 결과가 최신인지 | run에 `scripts/harness/passed <검사>`를 쓴다. 결과 파일이 이번 작업 시작(`.harness/state/task.started`) 전 것이거나, 결과보다 나중에 고친 바뀐 파일이 있으면 실패 | `bouncer passed`의 `result_fresh`(`.started`, base 이후 바뀐 파일의 mtime) |
| run 시간 | run 합계를 1700초(`HARNESS_RUN_BUDGET`)로 제한하고 넘으면 시간 초과(124)로 막는다. 훅 timeout은 1800초. 127은 명령 없음으로 알린다 | `BOUNCER_RUN_BUDGET=1700`, Stop timeout 1800, `bouncer_run_timeout` |

## 발표·ai-bouncer와 다른 점 (사용자에게 보고)

- **run을 돌리는 시점.** ai-bouncer는 Stop에서 run을 돌리고 엔진이 단계를 넘기며, 에이전트는 상태를 고칠 수 없다. 발표는 에이전트가 state.json의 단계를 고친다고 한다(슬라이드 14·27). 발표를 따라 에이전트가 stage를 바꾸려 할 때 PreToolUse에서 막는다(사용자 결정, 2026-11-03).
- **상태 파일을 Bash로 고치면 보지 못한다.** 훅은 Edit·Write·MultiEdit만 본다. `task` 스킬은 Edit·Write로 고치게 한다.
- **lint·e2e는 시작할 때 결과 파일을 실패로 적지 않는다.** verify만 그렇게 했다. 나머지도 맞출지는 정하지 않았다.
- 처음에는 Stop 훅이 plan 단계를 막지 않게 했다. 발표와 ai-bouncer 모두 Plan 모드로 승인받으므로 잘못이었고, 위 "계획 승인"으로 바꿨다.

## 결과

- verify를 고른 작업은 `checks.json`의 verify 검사에 `run: scripts/harness/passed verify`를 적으면, 빌드·테스트가 통과해야 finish로 넘어간다.
- `scripts/harness/passed`를 run에 쓰면 고친 뒤 다시 돌리지 않은 결과는 통과로 보지 않는다.
- 하네스 버전을 0.4.0으로 올린다.
