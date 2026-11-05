# 하네스 실패 기록

에이전트가 하네스를 쓰면서 실수하거나 막힌 일을 기록한다. 이 기록은 다음에 무엇을 만들지 정하는 근거다.
기록할 때마다 [principles.md](principles.md)의 "실수 → 고칠 층" 기준표로 분류한다.

## 기록 방법

새 항목은 맨 위에 추가한다. 형식은 다음과 같다.

```markdown
### YYYY-MM-DD — 한 줄 요약
- 프로젝트·작업:
- 무슨 일이 있었나: 에이전트가 한 행동과 그 결과. 가능하면 명령과 메시지를 그대로 적는다.
- 원인: 부족했던 계층 (Context / Execution / Validation / Enforcement / State)
- 조치: 어느 층에 무엇을 추가하거나 고칠지. 고치지 않기로 했으면 "보류"와 이유를 적는다.
- 상태: 미해결 | 반영됨 (커밋 또는 단위 번호) | 보류
```

## 분류 (2026-11-04, 단위 9 완료 기준)

문제 14개(한 기록에 문제가 여럿이면 나눠 셌다)를 원인 계층과 상태로 나눴다. 하네스가 아니라 프로젝트 시나리오 문제(#217의 3·4)와 정상 동작 관찰(#8 plan 모드)은 뺐다.

| 계층 | 해결·반영 | 남음 |
|---|---|---|
| Context | 리뷰어가 규칙을 안 읽음(단위 8), 상태 파일을 Bash로 씀, Maestro 규칙에 클립보드 금지 없음(후보 10) | 응답 언어(보류) |
| Execution | Tests 폴더 ≠ 테스트 타깃(단위 4), DerivedData 위치(단위 4) | E2E가 부하에서 온보딩을 못 찾음(미해결), verify가 도구 10분 제한을 넘음(보류) |
| Validation | `wiki check`가 무시되는 기록을 못 잡음(0.4.1) | — |
| Enforcement | `git -C`로 ask를 피함(단위 7), verify 통과를 말로만 앎(후보 13) | — |
| State | detect의 Tuist 이름(후보 15), 테스트 스킴이 Release(단위 9), 서브에이전트를 기다릴 때 Stop 게이트가 막음(ADR 0013) | — |

- 강제 장치(Enforcement·State)에서 난 문제는 모두 고쳤다. 대부분 후보 12·13에서 새로 넣은 작업 흐름과 Stop 게이트에서 나왔고, 시험장에서 다시 돌려 확인했다.
- 남은 미해결 두 개는 모두 E2E(후보 10)다. 그래서 다음 순서는 E2E 정리가 먼저다.
- 2026-11-04 E2E 정리 뒤: 클립보드는 해결했다. 온보딩은 60초 대기를 넣었지만 효과를 아직 확인하지 못해 미해결로 남긴다.
- 운영 기간은 이틀(ReadSharp 2026-11-03~, IntervalTimer 2026-11-03~)이다. 1~2주를 채우지 않고 닫는다. 작업 6건에서 기록이 쌓였고 막힌 문제가 없어서다. 이후 실패도 계속 여기에 적는다.

## 기록

### 2026-11-05 — IntervalTimer #13: e2e가 예전에 빌드된 앱을 설치해 바뀐 코드 없이 통과할 수 있었다
- 프로젝트·작업: IntervalTimer 시험장, 이슈 #13 Live Activity (인터벌타이멍 탭, e2e 검사 포함)
- 무슨 일이 있었나
  - `app.scheme`(`IntervalTimer`)은 Release로 빌드해 `com.mingu.intervaltimer`를 만든다. 그런데 `app.bundleId`는 `com.mingu.intervaltimer.debug`였다.
  - `e2e`는 번들 ID로 앱을 찾아서, 전날 빌드된 `Debug-iphonesimulator/IntervalTimer-Dev.app`을 설치했다. 그 앱에는 새 위젯 확장이 없었다. 에이전트가 수정 시각을 보고 알아챘고, `build --scheme IntervalTimer-Dev` 뒤 `e2e --no-build`로 돌려 통과했다. 이 내용을 프로젝트 위키(`docs/wiki/harness/e2e-needs-dev-scheme-build.md`)에 남겼다.
  - 같은 작업에서 시스템 Java가 없어 Maestro가 끝나지 않고 멈췄다. 에이전트가 Homebrew `openjdk@17`을 `JAVA_HOME`으로 지정해 풀었다. `doctor`는 이를 잡지 못했다.
  - 오전에 같은 브랜치에서 simple 모드 후속 작업(unit-test·review만)으로 위젯 화면을 바꿨다. 그래서 남은 영상은 바뀌기 전 화면이다. 검사를 사람이 고르는 설계대로 동작한 것이라 하네스 문제로 보지 않는다.
- 원인: Validation — 결과를 프로그램으로 판정해도, 판정 대상이 바뀐 코드로 만든 앱인지는 확인하지 않았다. Execution — Java가 없는 환경을 미리 알리지 못했다.
- 조치
  - `e2e`는 빌드한 뒤 스킴의 실행 구성으로 빌드된 앱만 설치한다. 없으면 빌드된 앱의 번들 ID를 보여 주며 멈춘다.
  - `e2e`는 Java가 없으면 돌리기 전에 멈추고, `doctor`는 `.maestro/`가 있을 때 Java가 없으면 경고한다.
  - IntervalTimer의 `project.json`에서 스킴과 번들 ID를 같은 앱으로 맞추는 일은 시험장에서 따로 한다.
- 상태: 반영됨 (`feature/unit-10-e2e-app-check`)

### 2026-11-04 — IntervalTimer #8: plan 모드를 처음부터 끝까지 지켰고, 테스트도 시키지 않았는데 먼저 썼다
- 프로젝트·작업: IntervalTimer(`IntervalTimer-harness`, Tuist), 이슈 #8 SwiftData 저장 실패를 성공으로 처리함. 새 세션, plan 모드, 검사 unit-test·review. 약 20분(plan 5분, implement 3분, verify 9분)
- 무슨 일이 있었나
  - `task` 스킬로 시작해 모드와 검사를 사용자에게 물었다. plan 단계에서 `wiki search`를 했고(관련 기록 없음), 범위(서비스 throws + UI 알림)를 사용자에게 물은 뒤 계획 승인을 받았다.
  - 테스트를 쓰라는 지시는 하지 않았다. 에이전트가 서비스보다 먼저 save 실패 주입 테스트를 추가했다(테스트 41 → 47개).
  - 첫 `unit-test`에서 `updateSessionFailureRestoresName`이 실패했다. `ModelContext.rollback()`이 바뀐 속성 값을 되돌리지 않는다는 사실이 드러났다. 에이전트는 서비스를 고쳐 통과시켰고, finish에서 이 사실을 `kind: fact` 기록(`docs/wiki/data/swiftdata-rollback-keeps-property-changes.md`)으로 남긴 뒤 `wiki check`를 돌렸다.
  - verify → finish에서 검사 강제 훅은 run이 통과해 막지 않았다. 단계 지시는 plan·implement·verify·finish·done 다섯 번 모두 주입됐다.
- 원인: 해당 없음(정상 동작 관찰). 테스트 규칙(`testing.md`, "버그는 실패하는 테스트로 먼저 재현")은 테스트 파일을 열 때 로드된다. 이번에는 plan 단계(18:27:31)에 swift·swiftui·dependencies·concurrency 규칙과 함께 로드됐다.
- 조치: 없음. 테스트 작성을 검사나 AGENTS.md로 올리지 않는다. 테스트 파일을 열지 않아 규칙이 안 걸리는 일이 관찰되면 다룬다.
- 상태: 보류

### 2026-11-04 — IntervalTimer #8: 상태 파일을 Bash로 써서 첫 단계 지시가 주입되지 않았다
- 프로젝트·작업: IntervalTimer, 이슈 #8 시작. ReadSharp 세션 `8e3ca645`에서도 같은 일이 한 번 있었다(두 번째 관찰).
- 무슨 일이 있었나
  - 에이전트가 `task.json`을 `cat > .harness/state/task.json <<'EOF'`로 만들었다. 단계 지시 훅과 검사 강제 훅은 `Edit|Write|MultiEdit`에만 걸려 있어 아무것도 하지 않았다.
  - 훅이 돌지 않아 `task.owner`도 이 세션으로 바뀌지 않았다. 다시 쓰기 전까지는 Stop 게이트와 도구 수 세기도 이 세션을 보지 않았다.
  - 두 번 모두 에이전트가 바로 같은 내용을 Read → Write로 다시 저장해 첫 단계 지시를 받았다. 이후 단계 전환은 모두 Edit으로 했다.
- 원인: Context — task 스킬은 "`task.json`을 쓴다"고만 하고 무엇으로 쓰는지 말하지 않는다. auto 모드는 작은 수정은 Bash(heredoc·sed)로 해도 된다고 안내한다. 에이전트가 훅을 피하려던 것이 아니라, Write로 써야 훅이 돈다는 것을 몰랐다.
- 검토하고 쓰지 않은 방법
  - PreToolUse(Bash) 훅으로 상태 파일 쓰기를 막기: 관찰된 두 번은 경로가 명령에 그대로 보여 막을 수 있다. 하지만 에이전트가 스스로 바로잡았고, 지시 한 줄로 고칠 수 있는 실수에 훅을 늘리지 않는다(원칙: 강제 장치는 필요가 확인된 뒤에).
  - `task.json` 지문(해시)을 저장해 훅 밖에서 바뀐 것을 알아채기: 변수에 담은 경로, 스크립트 파일, Monitor·MCP 도구, 사람의 직접 편집까지 잡는다. 하지만 이런 경로는 일부러 돌아가야 생기고 관찰된 적이 없다.
  - ai-bouncer처럼 엔진(Stop 훅)이 단계를 넘기기: 에이전트가 상태 파일을 쓸 일이 없어진다. 하지만 발표 구조(에이전트가 state.json의 단계를 고쳐 적으면 PostToolUse 훅이 지시를 넣는다, 슬라이드 14·27)에서 벗어나고, 고칠 곳이 크다. ai-bouncer도 상태 파일 보호는 Edit·Write·MultiEdit·NotebookEdit에만 건다(`hooks/pre-tool.sh` "엔진 전용 파일 보호").
- 조치: Context — task 스킬의 시작·단계 전환 안내에 "`task.json`은 Write·Edit로 쓴다. Bash로 쓰면 훅이 돌지 않는다"를 넣는다. 그래도 Bash로 쓰는 일이 다시 관찰되면 PreToolUse(Bash) 훅을 검토한다.
- 결과: IntervalTimer #7(`2e039bc4`)과 #18(`e547cd96`)에서 `task.json`을 Write·Edit로만 썼다. 단계 지시가 단계마다 들어왔다.
- 상태: 해결

### 2026-11-04 — IntervalTimer #8: 리뷰어를 기다리는 동안 Stop 게이트가 다시 네 번 막았다
- 프로젝트·작업: IntervalTimer, 이슈 #8 verify 단계
- 무슨 일이 있었나
  - ios-reviewer를 백그라운드로 띄우고 턴을 끝내려다 Stop 게이트에 1분 사이 네 번 막혔다. 에이전트는 출력 파일을 확인하는 루프로 기다렸고, 결과가 오자 권장 2건을 반영하고 이어 갔다.
  - 첫 차단(18:40:46)과 두 번째 차단(18:40:51) 사이에 에이전트는 글만 썼고 도구를 쓰지 않았다. 그런데도 "도구 없이 같은 이유로 다시 막히면 끝내게 둔다" 규칙이 걸리지 않았다.
  - 그 사이 리뷰어 서브에이전트가 Bash 2번을 썼다(18:40:47·48, `subagents/agent-a78a57dd2408a6cdd.jsonl`). 서브에이전트의 도구 호출도 같은 `session_id`로 `tool-count.sh`에 들어와 호출 수가 올라갔다.
- 원인: State — 게이트는 메인 에이전트가 일을 그만두려는 것인지, 백그라운드 작업을 기다리며 잠깐 쉬려는 것인지 구분하지 못한다. 도구 호출 수는 메인 에이전트와 서브에이전트를 가리지 않아서 "도구 없이 다시 막히면 끝내게 둔다" 규칙도 기다릴 때 걸리지 않는다.
  - ai-bouncer도 구조가 같다. `pre-tool.sh`는 같은 `session_id`의 호출을 모두 세고, `stop.sh`는 백그라운드 작업을 보지 않는다. 이 규칙을 넣은 커밋(`6c6c90d`)의 테스트(`21-no-ask-and-bg-wait.sh`)는 기다리는 동안 도구 호출이 없는 경우만 다룬다. 코드로 본 것이고 돌려 보지는 않았다.
- 검토하고 쓰지 않은 방법: 서브에이전트의 도구 호출(입력에 `agent_id`가 있는 호출)은 세지 않기. 메인 세션 호출에도 `agent_id`가 붙는 경우가 있으면 메인 호출까지 빠져, 두 번째 차단부터 항상 풀린다. 포그라운드 서브에이전트는 메인이 기다리는 동안 Stop이 불리지 않아 얻는 것도 없다.
- 조치: State — Stop 게이트가 입력의 `background_tasks`에 서브에이전트(`type: "subagent"`)가 있으면 막지 않고 끝내게 둔다. 작업이 끝나면 알림으로 턴이 다시 열리고, 그때 게이트가 다시 판정한다. 셸·모니터는 끝나지 않을 수 있어 넣지 않는다. 도구 수 세기는 그대로 둔다. ai-bouncer에 없는 조건이라 [ADR 0013](decisions/0013-stop-wait-subagent.md)에 남겼다.
  - 서브에이전트를 중간에 취소·중단했을 때의 동작은 확인하지 않았다. 돌고 있는 작업이 없으면 다시 막으므로 빠져나가는 길은 없다고 본다. 문제가 관찰되면 다룬다.
- 결과: IntervalTimer #18(`e547cd96`) verify 단계에서 리뷰어가 도는 동안 Stop이 왔다(00:41:54, `background_tasks`에 `type: "subagent"`, `status: "running"`). 게이트가 막지 않았고, 작업 전체에서 차단은 0번이었다.
- 상태: 해결

### 2026-11-03 — #218: 백그라운드 작업을 기다리는 동안 Stop 게이트가 네 번 막았다
- 프로젝트·작업: ReadSharp(`EnglishStudy-harness`), 이슈 #218 (simple, 검사 lint·verify·e2e·review)
- 무슨 일이 있었나
  - 흐름은 끝까지 지켰다. `task` 스킬로 시작해 모드와 검사를 사용자에게 물었고, 시작할 때 `wiki search`를 했다. verify → finish에서 검사 강제 훅(`check-run.sh`)은 run이 모두 통과해 막지 않았고, finish에서 wiki 기록 2개를 쓰고 `wiki check`를 돌렸다.
  - verify 단계에서 ios-reviewer 서브에이전트와 백그라운드로 넘어간 빌드·E2E를 기다리며 턴을 끝내려 했다. Stop 게이트(`stop-gate.sh`)가 "아직 verify 단계라 끝낼 수 없습니다"로 네 번 막았다.
  - 막힐 때마다 에이전트는 출력 파일을 `sleep` 루프로 확인하며 기다렸다. 결과가 오자 정상적으로 이어 갔다.
- 원인: State — 게이트는 단계만 보고, 기다리는 중인 백그라운드 작업이 있는지는 모른다. 해는 없었고 연속 10회 상한(`HARNESS_MAX_CONTINUE`)도 있다.
- 조치: 보류. 한 번 관찰이고 결과를 해치지 않았다. ai-bouncer `stop.sh`도 백그라운드 작업을 따로 보지 않는다. 다시 나타나 비용이 커지면 다룬다.
  - 2026-11-04 IntervalTimer #8에서 다시 나타나 그 항목에서 고친다.
- 상태: 보류

### 2026-11-03 — #218: 머신 부하가 크면 E2E가 스플래시에서 멈춰 회귀 묶음이 실패했다
- 프로젝트·작업: ReadSharp, 이슈 #218 verify 단계 E2E
- 무슨 일이 있었나
  - 리뷰 반영 뒤 회귀 묶음이 3/4, 4/4 실패했다. 이번 변경과 무관한 시나리오도 공통 시작 단계 `onboarding_btn_skip`을 찾지 못했다. load average가 156이었다.
  - 에이전트는 스크린샷과 스플래시 코드를 확인하고, 통과로 치지 않고 사용자에게 물었다(부하 줄면 재실행 / 그대로 진행 / 멈춤). 부하가 내려간 뒤 3/4, 남은 하나는 단독으로 통과시켰다.
  - 이 사실을 `docs/wiki/xcode/e2e-splash-timeout-under-load.md`에 남겼다.
- 원인: Execution — 공통 시작 흐름(`common/fresh-start.yaml`)의 대기 시간이 부하를 견디지 못한다.
- 조치: 프로젝트 시나리오 — ReadSharp `common/fresh-start.yaml`이 `onboarding_btn_skip`을 `extendedWaitUntil`로 60초까지 기다린다. 하네스 규칙은 바꾸지 않았다. 발표대로 Maestro가 기다리는 것을 기본으로 두고(슬라이드 82), 늦게 뜨는 화면만 프로젝트 시나리오에서 기다린다.
- 결과 (2026-11-04): 확인하지 못했다.
  - 확인하려고 `yes` 프로세스로 부하를 일부러 걸었다(load 230~900). 이것이 잘못이었다. 원래 상황(156)보다 훨씬 높아 공정한 시험이 아니었고, 머신 전체를 9시간 느리게 하고 시뮬레이터 서비스를 멈추게 했다. 그 상태에서 4/4가 스플래시에서 실패했지만 60초 대기의 효과를 판단할 근거가 되지 못한다.
  - 앞으로는 부하를 일부러 걸지 않고, 평소 작업에서 부하가 높을 때 다시 나오는지 지켜본다.
- 상태: 미해결 (60초 대기는 그대로 두고 실제 작업에서 지켜본다)

### 2026-11-03 — #218: 응답 언어가 중간에 영어로 바뀌었다
- 프로젝트·작업: ReadSharp, 이슈 #218
- 무슨 일이 있었나: 첫 응답부터 일부가 영어였고, Stop 게이트에 막힌 뒤로는 계속 영어로 답했다. 마무리 보고 뒤 사용자가 "한국어"라고 해서 다시 썼다.
- 원인: Context — 설치된 `AGENTS.md`에 응답 언어 지시가 없다. 하네스 메시지는 한국어였다.
- 조치: 보류. 응답 언어는 사람마다 다른 설정이라 template에 넣지 않는다. 프로젝트 영역이나 개인 설정에 둔다. 다시 나타나면 다룬다.
- 상태: 보류

### 2026-11-03 — 위키 기록 폴더 이름이 `.gitignore`의 `build/`에 걸려 커밋에서 빠졌다
- 프로젝트·작업: ReadSharp(`EnglishStudy-harness`), 메모리에 흩어진 정책을 `docs/wiki/`로 옮기는 작업
- 무슨 일이 있었나
  - 빌드 관련 기록을 `docs/wiki/build/`에 만들었다. `wiki check`는 통과했지만 `git status`에 나오지 않았다.
  - iOS 프로젝트 `.gitignore`의 `build/` 규칙이 경로 어디에 있든 `build` 폴더를 무시했다. 커밋 직전에 알아채 `docs/wiki/xcode/`로 옮겼다.
- 원인: Validation — `wiki check`가 형식만 보고, 기록이 저장소에 올라가는지는 보지 않았다.
- 조치: `wiki check`가 `git check-ignore`로 무시되는 기록을 찾아 무시한 규칙과 함께 문제로 알리고 1로 끝난다(회귀 테스트 3개).
- 상태: 반영됨 (후보 13 마무리, 0.4.1)

### 2026-11-03 — 처음부터 끝까지 돌린 #217 작업이 verify에서 멈췄다. 통과는 말로만 알 수 있었다
- 프로젝트·작업: ReadSharp(`EnglishStudy-harness`), 이슈 #217 문장 이동 시 번역 초안 보존. 새 세션에서 `claude -p` 3턴, plan 모드, 검사 lint·verify·e2e·review. 약 49분, 약 $3.6
- 잘 된 것
  - `task` 스킬이 저절로 불렸다. 모드·검사는 사람이 골랐다. plan 단계에서 위키를 먼저 찾고, 바꿀 MVI 층을 적고, 승인을 기다렸다. 이슈의 정책 빈틈 2개를 계획에서 물었다.
  - lint 100점, verify 테스트 220개 통과(새 테스트 8개), review 차단 0건. e2e 실패를 숨기지 않고 멈춰서 물었다.
- 무슨 일이 있었나
  1. verify는 결과 파일을 남기지 않아 통과를 에이전트의 말로만 알 수 있었다. `run`도 실행되지 않았다(발표 슬라이드 28의 상황).
  2. verify 한 번이 약 12분이라 Bash 도구의 10분 제한을 넘었다. 에이전트가 백그라운드로 돌렸다.
  3. e2e 공통 흐름 `common/fresh-start.yaml`이 6번 중 4번 온보딩 "건너뛰기"(`onboarding_btn_skip`)를 찾지 못했다. 스크린샷에는 버튼이 보이는데 계층 덤프에는 없었다. 새 시나리오는 한 번도 끝까지 가지 못했다.
  4. 양방향 바인딩 입력창에서 Maestro `inputText`가 글자를 빠뜨렸다. 에이전트가 딥링크(`readsharp://analyze`)로 바꿨다.
  5. Maestro `setClipboard`가 시뮬레이터 클립보드를 바꾸지 못해, Mac 클립보드 내용이 앱에 붙고 `.harness/out/e2e/` 스크린샷에 남았다. `.harness/out/`은 git이 무시해 커밋되지는 않는다.
  6. finish 단계와 위키 기록까지 가지 못했다.
- 원인
  - 1: Validation·Enforcement — run 확인을 켜지 않았고(후보 13 조건부), verify 결과 파일이 없었다.
  - 2: Execution — 단일 앱이라 바뀐 모듈만 테스트해도 전체 테스트가 돈다. Claude Code 도구 제한이다.
  - 3·4: 프로젝트 시나리오 — 하네스가 아니라 ReadSharp 시나리오 문제다.
  - 5: Context — Maestro 규칙에 클립보드를 쓰지 말라는 내용이 없다.
- 조치
  - 1: 발표대로 run 확인을 켰다(ADR 0012). verify가 `.harness/out/verify.json`을 남기고, 시험장 `checks.json`의 verify에 run을 걸었다. 시험장에서 `claude -p`로 verify → finish를 시키자 훅이 verify(결과 파일 없음)와 e2e(`passed: false`)를 이유로 막았다. 처음 시도에서는 막지 못했다. jq 문자열 `index`가 바이트 위치를 돌려줘 한글 제목이 있는 상태 파일의 Edit 결과를 잘못 계산했기 때문이다. `split`으로 고치고 테스트를 넣었다.
  - 1(이어서): 발표대로 Stop 훅도 넣었다. 처음 만든 것은 상태 파일이 프로젝트에 하나뿐이라, 작업과 상관없는 세션("안녕만 답하라")도 9번 막혀 같은 답만 되풀이했다. ai-bouncer(`hooks/stop.sh`)를 따라 작업 주인 세션만 막고, 도구 없는 재진입은 끝내게 두고, 10번 연속이면 사용자에게 넘기게 고쳤다. 다시 해 보니 상관없는 세션은 1턴에 끝났고, simple 작업은 중간에 멈추려다 한 번 막힌 뒤 done까지 갔다. `claude -p`에는 Plan 모드 도구가 없어 plan 작업은 계획을 글로 보여 주고 한 번 막힌 뒤 멈췄고, 승인을 보내 이어 가자 done까지 갔다.
  - 2: 보류. 기록만 한다. 발표의 해법은 검사를 골라 돌리는 것(슬라이드 30)이다.
  - 3: ReadSharp에서 따로 고친다.
  - 5: Context — template `rules/harness/maestro.md` 작성 규칙에 "클립보드를 쓰지 않는다"를 넣었다. 글은 `inputText`로 넣고, 글자가 빠지면 딥링크로 넘긴다(4의 해법, 슬라이드 84 "딥링크로 진입").
- 상태: 1 반영됨 (후보 13, ADR 0012) · 2 보류 · 3 미해결 · 5 반영됨 (후보 10)
- 이어서 (2026-11-03): 같은 작업을 이어 verify → finish → done까지 마쳤다. 단계를 넘길 때 훅이 lint·verify·e2e의 `passed`를 확인했다. e2e의 온보딩 실패(3)는 다시 돌리자 고친 것 없이 통과해, 시나리오의 불안정함으로 남겼다

### 2026-11-03 — 이름이 상수인 Tuist manifest에서 detect가 워크스페이스 이름을 잘못 읽었다
- 프로젝트·작업: IntervalTimer(`IntervalTimer-harness`), 후보 15 설치
- 무슨 일이 있었나
  - `Project.swift`가 `let projectName = "IntervalTimer"`를 두고 `Project(name: projectName, settings: .settings(configurations: [.debug(name: "Debug"), …]))`로 쓴다.
  - detect는 파일에서 처음 나오는 `name: "..."`를 이름으로 읽어 `"workspace": "Debug.xcworkspace"`를 냈다. 생성한 뒤에도 스킴 목록을 확인하지 못했다.
  - 앱 manifest가 루트에 있어(`app.path: "."`) 생성 전 앱 스킴을 `.`로 추정했다.
- 원인: State — detect의 이름 규칙이 문자열 리터럴만 보고, 어느 호출의 인자인지는 보지 않았다.
- 조치
  - `Workspace(`·`Project(` 호출 뒤의 첫 `name:`을 읽고, 값이 상수면 같은 파일의 `let 상수 = "..."`에서 찾는다. 호출을 못 찾으면 예전 규칙을 쓴다.
  - 앱 manifest가 루트에 있으면 manifest에서 읽은 이름으로 스킴을 추정한다.
  - 회귀 테스트 3개를 더했다(`tests/detect.test.sh`).
- 상태: 반영됨 (후보 15)

### 2026-11-03 — 앱 스킴의 테스트 액션이 Release라 기본 test가 실패한다
- 프로젝트·작업: ReadSharp 시험장(`EnglishStudy-harness`), 단위 9 설치 확인
- 무슨 일이 있었나
  - detect가 앱 스킴으로 `EnglishStudy`를 골랐다. `scripts/harness/build`는 통과했다(170s, 경고 31).
  - `scripts/harness/test`는 테스트 실행 전에 `MockAIProvider.swift:2:18: Unable to find module dependency: 'EnglishStudy'`로 중단됐다.
  - 이 스킴은 테스트 액션을 포함한 모든 액션이 `buildConfiguration = "Release"`다. 배포용 스킴이라 `@testable import`가 되지 않는다.
  - `--scheme "EnglishStudy Dev"`(전부 Debug)는 공유 확장 산출물이 겹쳐 `Multiple commands produce …ReadSharpShareExtension.appex`로 실패했다. 프로젝트 쪽 문제다.
  - `--scheme EnglishStudyTests`(테스트 액션 Debug)는 212개 모두 통과했다(207s).
- 원인: State·Execution — `app.scheme` 하나로 빌드와 테스트를 모두 하는데, 이 앱은 빌드용 스킴과 테스트용 스킴이 다르다. detect는 스킴의 테스트 액션 구성을 보지 않는다.
- 조치
  - 설정 파일에 `app.testScheme`을 추가했다(없으면 `app.scheme`). `test`와 `verify`의 앱 테스트가 이 값을 쓴다.
  - detect는 앱 스킴의 테스트 액션이 Debug가 아닐 때만, 테스트 액션이 Debug이고 단위 테스트 타깃을 담은 공유 스킴을 고른다. ReadSharp에서는 `EnglishStudyTests`를 골랐다.
  - 프로젝트의 `EnglishStudy Dev` 산출물 중복은 프로젝트에서 따로 고친다.
- 상태: 반영됨 (단위 9)

### 2026-10-21 — 리뷰어가 "규칙 파일을 먼저 읽으라"는 지시를 따르지 않았다
- 프로젝트·작업: MotoTrace 시험장, 단위 8 `ios-reviewer` 확인 (위반 4종을 넣고 터미널 `claude -p`로 리뷰를 맡김)
- 무슨 일이 있었나
  - 1·2차 실행 모두 위반 4종을 잡았다.
  - 하지만 리뷰어는 `git diff`만 보고 바뀐 파일과 규칙 파일을 열지 않았다. 리뷰어 스스로 "규칙 파일은 열어 보지 않았다"고 밝혔다.
  - 처음에는 `;`로 이은 명령을 써서 같은 diff를 여러 번 다시 실행했다.
  - 새 파일 목록용 `git ls-files -o`는 승인이 필요한 명령이라 실행되지 않았다.
- 원인: Context — 지시가 "검토 전에 규칙을 읽는다"는 문장 하나라 다른 설명 사이에 묻혔다. 이번 위반은 프롬프트의 중점 항목만으로 잡혀서, 지시를 지켰는지가 결과에 드러나지 않았다.
- 조치
  - 리뷰어 지시를 번호 매긴 검토 순서로 바꿨다. 2단계에서 바뀐 파일을 Read로 열면 경로 규칙이 자동으로 따라 들어온다.
  - 명령은 하나씩 실행하게 했고, 새 파일 목록은 `git status --porcelain`으로 보게 했다.
  - 출력 마지막 줄에 "열어 본 파일·규칙"을 적게 해서 지시를 지켰는지 보이게 했다.
  - 3차 실행에서 4개 파일을 모두 열었고, 규칙 항목을 근거로 들었다.
- 상태: 반영됨 (단위 8)

### 2026-10-12 — 에이전트가 `git -C <경로>` 형식을 쓰면 ask 규칙을 피해 간다
- 프로젝트·작업: MotoTrace 시험장, 단위 7 권한 규칙 확인 (터미널 `claude -p` 세션)
- 무슨 일이 있었나
  - 대조 실험으로 `git update-index --refresh`를 시켰더니, 에이전트가 스스로 `git -C <워크트리 경로> update-index --refresh`로 실행했다.
  - 권한 규칙은 명령 문장의 앞부분으로 매칭한다. 그래서 같은 방식으로 `git -C <경로> reset --hard`라고 쓰면 `Bash(git reset --hard *)` 규칙에 걸리지 않는다.
- 원인: Enforcement — Bash 권한 규칙이 `git -C` 형식을 덮지 못했다.
- 조치
  - ask 규칙마다 `git -C * …` 형식을 추가했다.
  - `git -C <경로> reset --hard HEAD`가 확인 요청으로 막히는 것을 확인했다.
  - `sh -c`나 `/usr/bin/git`처럼 다르게 쓴 명령은 여전히 덮지 못한다. 실수를 막는 장치라는 한계를 ADR 0004에 적었다.
- 상태: 반영됨 (단위 7)

### 2026-10-02 — Tests 폴더가 있다고 테스트 타깃이 있는 것은 아니다
- 프로젝트·작업: MotoTrace 시험장, 단위 4 `verify --all` 확인
- 무슨 일이 있었나
  - AppDI·Shared 모듈 테스트가 `Unable to start testing`으로 실패했다.
  - 두 모듈에는 `Tests/Sources` 폴더가 있지만, manifest(`makeSingleModule`)가 테스트 타깃을 만들지 않아서 스킴의 테스트 액션이 비어 있었다.
- 원인: Execution — "Tests 폴더가 있으면 테스트가 있다"는 판단 규칙이 틀렸다.
- 조치
  - 생성된 스킴 파일의 테스트 액션에 테스트 대상이 있는지로 판단하도록 바꿨다.
  - 스킴 파일이 없을 때만 Tests 폴더로 판단한다(verify, detect).
- 상태: 반영됨 (단위 4)

### 2026-10-02 — DerivedData를 ~/Desktop 아래에 두면 테스트 번들을 읽지 못한다
- 프로젝트·작업: MotoTrace 시험장(`~/Desktop/MotoTrace/...`), 단위 4 test 스크립트 개발
- 무슨 일이 있었나
  - 프로젝트 안의 `.harness/DerivedData`를 쓰면 `xcodebuild test`가 `Failed to create a bundle instance representing '…/CoreTrackingTests.xctest'. Check that the bundle exists on disk.`로 실패했다. 번들은 실제로 있었다.
  - 같은 스킴(CoreTracking, 테스트 20개)을 Desktop 밖 DerivedData로 돌리면 20개 모두 통과했다.
- 원인: Execution — 시뮬레이터 쪽 테스트 프로세스가 macOS 보호 폴더(~/Desktop) 아래의 번들을 읽지 못하는 것으로 추정한다. 빌드는 터미널 권한으로 되기 때문에 테스트 단계에서만 드러난다.
- 조치
  - DerivedData 기본 위치를 `~/Library/Developer/Xcode/DerivedData/<워크트리 이름>-harness-<경로 해시>`로 바꿨다.
  - 워크트리마다 분리하는 것은 유지한다. `HARNESS_DERIVED_DATA`로 위치를 바꿀 수 있다.
- 상태: 반영됨 (단위 4)
