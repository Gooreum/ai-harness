# 프로젝트 스크립트

각 iOS 프로젝트에 설치되는 스크립트(`template/scripts/harness/`)의 동작 방식이다.
에이전트·사람·CI가 같은 스크립트를 쓴다. 모든 스크립트는 `.harness/project.json`을 읽는다([project-config.md](project-config.md)).

## 공통

- **출력**: 성공하면 한 줄, 실패하면 원인을 찾는 데 필요한 만큼만 출력한다. 전체 로그와 결과 번들은 파일로 남기고 경로만 알려준다.
- **산출물 위치**

  | 경로 | 내용 |
  |---|---|
  | `.harness/out/` | 마지막 실행의 로그(`*.log`)와 결과 번들(`*.xcresult`). 실행할 때마다 덮어쓴다 |
  | `.harness/state/` | 다음 실행이 참고하는 로컬 상태(생성 입력 지문 등) |
  | `~/Library/Developer/Xcode/DerivedData/<워크트리 이름>-harness-<경로 해시>` | 이 워크트리 전용 DerivedData. `HARNESS_DERIVED_DATA`로 바꿀 수 있다 |

  - `.harness/.gitignore`가 설정 파일만 남기고 나머지를 무시한다.
  - DerivedData를 프로젝트 안에 두지 않는 이유가 있다. 프로젝트가 `~/Desktop` 같은 macOS 보호 폴더 아래 있으면, 시뮬레이터의 테스트 프로세스가 테스트 번들을 읽지 못한다([harness-log.md](harness-log.md) 2026-10-02).
  - 경로 해시를 이름에 넣어서 워크트리끼리 빌드 캐시가 섞이지 않게 한다.
- **프로젝트 생성(Tuist·XcodeGen)**: 빌드 전에 생성이 필요한지 스스로 판단한다.
  - 생성 입력의 지문이 지난번과 다르면 install·generate를 다시 실행한다. 지문은 git이 보는 파일 목록과 manifest 내용으로 만든다.
  - 그래서 파일을 추가·삭제·이동하거나 manifest를 바꾸면 자동으로 다시 생성된다. 소스 내용만 바뀌었을 때는 건너뛴다.
  - 생성된 프로젝트 파일이 없으면 항상 생성한다. `--generate`를 주면 무조건 다시 생성한다.
  - Tuist가 생성 뒤 Xcode를 여는 동작은 `TUIST_GENERATE_OPEN=false`로 끈다.
- **시뮬레이터**: 설정의 기기 이름과 OS로 UDID를 찾는다. 없으면 설치된 iPhone 목록을 보여주고 멈춘다.
- **종료 코드**: 성공 0, 빌드·테스트 실패는 xcodebuild의 코드(보통 65), 설정·인자 오류 2

## build

```bash
scripts/harness/build                    # 앱 스킴 빌드
scripts/harness/build --scheme FeatureA  # 다른 스킴 빌드
scripts/harness/build --generate         # 프로젝트를 다시 생성한 뒤 빌드
```

- 순서: 필요하면 install·generate → `xcodebuild build -quiet` → `xcresulttool get build-results`로 요약
- 성공: `✓ build MotoTrace · iPhone 17 Pro · 4s · 경고 0`
- 실패: 첫 에러부터 최대 5개를 `경로:줄:열: 메시지`로 보여주고, 로그와 결과 번들 경로를 붙인다.
  - 최대 개수는 `HARNESS_MAX_ERRORS`로 바꾼다.
  - 결과 번들에 에러가 없는 실패(인자 오류, 스크립트 단계 실패)는 로그의 에러 줄을 보여준다.
- 결과 파일 `.harness/out/build.json`: `passed`, `summary`. 프로젝트 생성이 실패해도 `passed: false`로 남긴다. `checks.json`의 `run`에 `scripts/harness/passed build`로 쓴다.

## test

```bash
scripts/harness/test                          # 앱 단위 테스트 (app.unitTestTargets만, UI 테스트 제외)
scripts/harness/test --scheme CoreTracking    # 모듈 스킴의 테스트
scripts/harness/test --only CoreTrackingTests/LeanAngleAnalyzerTests   # 일부만
```

- 순서: 필요하면 install·generate → `xcodebuild test -quiet` → `xcresulttool get test-results`로 요약
- 성공: `✓ test CoreTracking · 통과 20 · 7s`. 테스트가 0개면 `실행된 테스트 없음`으로 표시한다.
- 실패: 실패한 테스트마다 두 줄을 출력하고, 로그와 결과 번들 경로를 붙인다.
  ```
    Modules/Core/CoreTracking/Tests/Sources/LeanAngleAnalyzerTests.swift:70: XCTAssertEqual failed: ("1") is not equal to ("2")
      ↳ LeanAngleAnalyzerTests/test_updateAttitude_첫데이터_영점_캘리브레이션()
  ```
  - 결과 번들에는 파일 이름만 기록된다. git이 아는 파일 중 하나로 특정되면 루트 기준 경로로 바꿔 보여준다.
  - 테스트가 시작되기 전에 멈췄으면(테스트 쪽 빌드 실패 등) 빌드 에러를 build와 같은 형식으로 보여준다.
- 앱에 단위 테스트 타깃이 없으면 실행하지 않고 그 사실만 출력한다.

## unit-test

```bash
scripts/harness/unit-test               # 커밋하지 않은 변경을 검증
scripts/harness/unit-test --base main   # main에서 갈라진 뒤의 모든 변경을 검증 (PR 전)
scripts/harness/unit-test --all         # 앱과 테스트가 있는 모든 모듈
scripts/harness/unit-test --plan        # 실행하지 않고 무엇을 할지만 출력
```

- 바뀐 파일(기본: HEAD 대비 수정 + 새 파일)을 모듈별로 묶는다.
  - 파일이 속한 모듈은 `modules.manifest`(Project.swift)가 있는 가장 가까운 상위 디렉터리다.
  - 앱 디렉터리(`app.path`)의 변경은 앱 단위 테스트로 이어진다.
  - `Tuist/`, `Workspace.swift`, 루트 manifest가 바뀌면 영향 범위를 알 수 없어서 전체를 테스트한다.
  - 모듈 구조가 없는 프로젝트(xcodeproj 단일 앱)는 모든 변경을 앱 변경으로 본다.
- 앱을 먼저 빌드하고, 성공하면 바뀐 모듈의 테스트를 실행한다.
  - 앱을 먼저 빌드하는 이유: 모듈끼리의 컴파일 오류는 앱 빌드가 먼저 잡는다. 또 선언하지 않은 의존(implicit import) 때문에 모듈 스킴만으로는 빌드가 깨지는 프로젝트도 있다.
  - 바뀐 모듈에 의존하는 다른 모듈의 테스트는 돌리지 않는다. 이런 테스트 회귀가 실제로 문제가 되면 그때 추가한다.
- 테스트할 대상이 있는지는 생성된 스킴 파일의 테스트 액션으로 판단한다. `Tests` 폴더만 있고 테스트 타깃이 없는 모듈도 있어서다. 스킴 파일이 없으면 `modules.testsDir` 폴더로 판단한다.
- 단계마다 build·test가 한 줄씩 출력하고, 마지막 줄에 전체 결과를 출력한다.
  ```
  ✓ build MotoTrace · iPhone 17 Pro · 21s · 경고 1
  ✓ test CoreTracking · 통과 20 · 7s
  ✓ unit-test · 통과: CoreTracking · 29s
  ```
- 결과 파일 `.harness/out/unit-test.json`: `passed`, `summary`. 시작할 때 먼저 `passed: false`로 적고 끝나면 결과로 바꾼다. 중간에 끊겨도 이전 실행의 통과가 남지 않는다. `--plan`은 남기지 않는다. `checks.json`의 run이 이 파일을 본다([ADR 0012](decisions/0012-run-gate.md)).

## lint

```bash
scripts/harness/lint               # 커밋하지 않은 변경 중 Swift 파일
scripts/harness/lint --base main   # main에서 갈라진 뒤 바뀐 Swift 파일
scripts/harness/lint --all         # git이 추적하는 모든 Swift 파일
```

- 팀 컨벤션 목록 `.harness/conventions.json`([conventions.md](conventions.md))의 규칙으로 검사한다. 파일이 없으면 건너뛰고 0으로 끝난다.
- 검사는 규칙 종류(`kind`)마다 도구가 한다. 에이전트는 규칙 초안을 만들 때만 쓰고, 통과 여부는 AI가 판단하지 않는다([ADR 0006](decisions/0006-convention-lint.md), [ADR 0014](decisions/0014-layer-format-rules.md)).
  - `pattern`: SwiftLint. 실행할 때마다 컨벤션 목록을 SwiftLint 설정(`.harness/out/swiftlint.yml`)으로 옮긴다. 컨벤션 규칙만 켜고, 프로젝트의 `.swiftlint.yml`이나 SwiftLint 기본 규칙은 판정에 넣지 않는다.
  - `format`: Xcode에 들어 있는 swift-format. 기본 설정에서 모든 규칙을 끄고 고른 규칙만 켠 설정(`.harness/out/swift-format.json`)으로 돌린다. 들여쓰기·줄 길이 같은 지적은 설정으로 끌 수 없어, 고르지 않은 것은 결과에서 걸러낸다.
  - `dependency`: 두 군데서 의존을 모은다. Tuist 프로젝트가 아니면 2로 끝난다.
    - 의존 목록에 적은 것: `tuist graph -f dot`으로 모듈 그래프(`.harness/out/graph/graph.dot`)를 뽑아 직접 의존만 본다. manifest(`Project.swift`·`Workspace.swift`·`Package.swift`·`Tuist/`)가 바뀌었거나 `--all`일 때만 돈다(IntervalTimer 6~22초).
    - import만 한 것: `tuist inspect implicit-imports`(결과 `.harness/out/lint-implicit-imports.txt`). 위의 경우와 바뀐 Swift 파일의 `import` 줄이 늘거나 줄었을 때 돈다(IntervalTimer 26초).
    - 그래프를 뽑았을 때 어느 규칙에도 없는 내부 모듈을 `· 의존 규칙에 없는 모듈:` 줄로 알린다. 감점하지 않는다.
  - 그 종류의 규칙이 있을 때만 그 도구가 필요하다.
- 바뀐 파일은 unit-test와 같은 기준으로 고른다(지운 파일은 뺀다).
- 100점에서 위반마다 감점한다(기본 error 10, warning 5, info 1). `passScore`(기본 95) 이상이면 통과다.
- 출력: 첫 줄에 점수, 이어서 위반을 심각한 것부터 위치와 함께 `HARNESS_MAX_ERRORS`개(기본 5)까지 보여 준다.
  ```
  ✗ lint · 70점 (기준 95) · 파일 1개 · 위반 3개
    EnglishStudy/Features/Settings/View/LintProbeView.swift:2: [imports.no_mobile_core_services] MobileCoreServices 대신 UniformTypeIdentifiers를 쓴다 (−10)
  ```
- 결과 파일 `.harness/out/lint.json`: `passed`, `score`, `passScore`, `files`(검사한 파일 수), `violations`(`rule`·`severity`·`penalty`·`file`·`line`·`column`·`message`), `uncoveredModules`(의존 규칙에 없는 모듈). 바뀐 파일이 없어도 남긴다.
- 종료 코드: 통과 0, 기준 미달 1, 설정 오류·도구 없음·도구 실행 실패 2

## wiki

```bash
scripts/harness/wiki search <단어>...   # 정책·결정 기록 찾기
scripts/harness/wiki check [파일...]     # 기록 형식 검사
```

- 기록 형식과 쓰는 때는 [wiki.md](wiki.md)에 있다.
- search 결과는 한 줄에 `종류	경로	제목`이다. 내용은 그 파일을 열어 읽는다. 검색마다 `.harness/state/wiki-search.log`에 남긴다.
- 종료 코드: search는 찾으면 0, 없으면 1. check는 문제가 없으면 0, 있으면 1. 인자 오류 2

## e2e

```bash
scripts/harness/e2e                         # .maestro/ 바로 아래 시나리오 전부
scripts/harness/e2e .maestro/settings-open.yaml
scripts/harness/e2e --tag regression        # 회귀 묶음
scripts/harness/e2e --record <파일>          # 화면 녹화 (.harness/out/e2e.mp4)
scripts/harness/e2e --no-build              # 이미 빌드된 앱으로
```

- 앱을 빌드(`build`)해 설정의 시뮬레이터에 설치하고 Maestro 시나리오를 돌린다. 시뮬레이터가 꺼져 있으면 켠다.
  - 설치하는 앱은 `app.scheme`의 실행(Run) 빌드 구성으로 빌드된 앱 중 번들 ID가 `app.bundleId`인 것이다. 구성은 공유된 스킴 파일(`xcshareddata/xcschemes/<스킴>.xcscheme`)의 `LaunchAction`에서 읽는다. 그런 앱이 없으면 멈춘다. 스킴과 번들 ID가 다른 앱을 가리키면, 다른 구성으로 예전에 빌드된 앱을 설치해 바뀐 코드 없이 통과하기 때문이다(IntervalTimer #13에서 관찰).
  - `--no-build`이면 구성을 가리지 않고 번들 ID가 맞는 가장 최근 앱을 설치한다.
  - Maestro가 쓸 Java가 없으면 돌리기 전에 멈춘다. Maestro는 `JAVA_HOME`이 있으면 그 java를, 없으면 PATH의 java를 쓴다. macOS의 `/usr/bin/java`는 JDK가 없어도 있으므로 실행해 확인한다.
  - 설치할 앱은 이 워크트리의 DerivedData에서 `app.bundleId`가 맞는 가장 최근 시뮬레이터용 `.app`이다. 앱 스킴의 빌드 구성(Debug·Release)을 따른다.
- 시나리오는 `appId: ${APP_ID}`로 쓴다. 스크립트가 `-e APP_ID=<app.bundleId>`를 넘긴다. 비밀 값은 `MAESTRO_`로 시작하는 환경 변수로 넘기면 Maestro가 읽는다.
- `.maestro/` 아래 폴더(`common/` 등)는 `runFlow`로 부르는 공통 흐름이라 따로 돌지 않는다. Maestro가 폴더를 받으면 바로 아래 파일만 돌린다.
- 작성 규칙은 template 규칙 `.claude/rules/harness/maestro.md`에 있다(id 우선, 딥링크 진입, 계정은 환경 변수, 공통 흐름, 결과 확인, 통과한 것만 저장).
- 출력: 통과하면 한 줄, 실패하면 시나리오마다 Maestro의 실패 메시지와 산출물 위치.
  ```
  ✗ e2e · 실패 1 / 2 · 96s
    .maestro/settings-open.yaml: Assertion is false: "AI 모델" is visible
    스크린샷·로그: .harness/out/e2e/ · 전체 출력: .harness/out/e2e.log
  ```
- 행동 로그 판정: 시나리오 옆에 `<이름>.events.json`을 두면, 그 흐름이 시작해서 다음 흐름이 시작하기 전까지 나간 이벤트를 판정한다. `.harness/project.json`의 `e2e.events`가 `firebase`일 때만 한다.
  - 실행 동안 시뮬레이터 로그를 `log stream --level debug`로 받는다(`e2e-events.ndjson`). Maestro가 남기는 기기 로그에는 debug 수준이 빠져 있어 따로 받는다.
  - Firebase Analytics는 앱을 `-FIRAnalyticsDebugEnabled`로 실행해야 이벤트를 로그에 남긴다. 시나리오의 `launchApp`에 `arguments: { "-FIRAnalyticsDebugEnabled": true }`를 넣는다(공통 흐름에 두면 된다).
  - 형식: `{ "events": [ { "name": "tab_select", "count": 1, "params": { "tab": "profile" } } ], "uploaded": true }`
    - `count`: 정확히 이 횟수만큼 나가야 한다. 없으면 1. `0`은 나가면 안 되는 이벤트다.
    - `params`: 적은 값만 비교한다(문자열로). 적지 않은 파라미터는 보지 않는다.
    - `uploaded`: 마지막으로 맞은 이벤트 뒤에 수집 서버 업로드가 성공(`Successful upload`)했는지 본다. 없으면 `true`. 스크립트는 Maestro가 끝난 뒤 업로드를 최대 20초 기다린다.
  - 실패 출력: `  .maestro/profile-empty.yaml: 행동 로그 tab_select 1회 (기대 2회), onboarding_complete 1회 (기대 0회)`
  - 시험 실행의 이벤트도 실제 Firebase 프로젝트로 올라간다(디버그 표시가 붙어 DebugView에 보인다).
- 서버 응답 바꾸기: `.harness/project.json`에 `e2e.network.port`가 있으면 maestro에 `NETWORK_BASE_URL=http://127.0.0.1:<포트>`를 넘긴다. 시나리오가 `launchApp`의 `"-HarnessNetworkBaseURL": "${NETWORK_BASE_URL}"`로 앱에 준다.
  - 응답은 플러그인 MCP `harness-network`가 준다([plugin.md](plugin.md)). 서버가 그 포트에 떠 있지 않으면 한 줄로 알린다(막지는 않는다).
  - 서버 응답 판정: 시나리오 옆 `<이름>.network.json`의 `expect`(`match`·`status`)마다, 그 흐름 동안 서버 기록(`.harness/state/network-requests.ndjson`)에 같은 응답이 한 번 이상 있어야 한다. 없으면 그 흐름은 실패다.
    - 실패 출력: `  .maestro/analyze-server-error.yaml: 서버 응답 POST …/v1beta 500 응답이 없었다 — mock_set으로 응답을 걸고 돌린다 (받은 요청: POST …:generateContent 404)`
    - 화면만으로는 "500을 받아 실패 화면이 떴다"와 "연결이 안 돼 실패 화면이 떴다"를 구분할 수 없어서다.
- 결과 파일 `.harness/out/e2e.json`: `passed`, `tag`, `flows`(`name`·`file`·`status`·`seconds`·`tags`·`failure`, 판정했으면 `events`·`network`). Maestro JUnit 결과(`e2e-junit.xml`)에서 만든다. 행동 로그를 판정한 흐름은 `events.passed`가 거짓이면 실패로 센다.
- 종료 코드: 통과 0, 실패한 시나리오가 있거나 돌린 시나리오가 없으면 1, Maestro 없음·설정 오류·결과 없음 2

## doctor

하네스가 이 프로젝트에서 돌 수 있는지 점검한다. 파일은 고치지 않는다.

```bash
scripts/harness/doctor
```

- 도구, 설정 파일, 지침 연결(AGENTS.md 관리 블록, `@AGENTS.md`), 공유되지 않는 설정, 플러그인 버전을 본다. 항목은 [template.md](template.md#점검-scriptsharnessdoctor)에 있다.
- 문제(✕)가 있으면 1, 주의(!)만 있거나 문제가 없으면 0으로 끝난다. 문제마다 고치는 방법을 한 줄 붙인다.
- 설치 직후, 팀원이 처음 프로젝트를 받았을 때, 훅이나 스킬이 동작하지 않을 때 돌린다.

## passed

```bash
scripts/harness/passed unit-test   # .harness/out/unit-test.json이 통과했고 최신이면 0
```

- `checks.json`의 `run`에 쓴다([ADR 0012](decisions/0012-run-gate.md)). 검사를 돌리지 않고 결과 파일만 본다.
- 통과 조건: 결과 파일이 있고, `passed`가 참이고, 최신이다.
  - 이번 작업을 시작한 뒤의 결과여야 한다. 작업 시작 시각은 단계 지시 훅이 `.harness/state/task.started`에 남긴다.
  - 바뀐 파일(unit-test와 같은 기준) 중 결과 파일보다 나중에 고친 것이 없어야 한다.
  - 이 기준은 발표에 없어 ai-bouncer의 `bouncer passed`를 따랐다.
- 실패하면 이유 한 줄(없음, 통과 못 함, 어느 파일보다 오래됨)을 출력하고 2로 끝난다.
