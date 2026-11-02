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

## verify

```bash
scripts/harness/verify               # 커밋하지 않은 변경을 검증
scripts/harness/verify --base main   # main에서 갈라진 뒤의 모든 변경을 검증 (PR 전)
scripts/harness/verify --all         # 앱과 테스트가 있는 모든 모듈
scripts/harness/verify --plan        # 실행하지 않고 무엇을 할지만 출력
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
  ✓ verify · 통과: CoreTracking · 29s
  ```

## lint

```bash
scripts/harness/lint               # 커밋하지 않은 변경 중 Swift 파일
scripts/harness/lint --base main   # main에서 갈라진 뒤 바뀐 Swift 파일
scripts/harness/lint --all         # git이 추적하는 모든 Swift 파일
```

- 팀 컨벤션 목록 `.harness/conventions.json`([conventions.md](conventions.md))의 규칙으로 검사한다. 파일이 없으면 건너뛰고 0으로 끝난다.
- 검사는 SwiftLint가 한다. 에이전트는 규칙 초안을 만들 때만 쓰고, 통과 여부는 AI가 판단하지 않는다([ADR 0006](decisions/0006-convention-lint.md)).
  - 실행할 때마다 컨벤션 목록을 SwiftLint 설정(`.harness/out/swiftlint.yml`)으로 옮긴다. 목록과 설정이 어긋날 일이 없다.
  - 컨벤션 규칙만 켠다. 프로젝트의 `.swiftlint.yml`이나 SwiftLint 기본 규칙은 판정에 넣지 않는다.
- 바뀐 파일은 verify와 같은 기준으로 고른다(지운 파일은 뺀다).
- 100점에서 위반마다 감점한다(기본 error 10, warning 5, info 1). `passScore`(기본 95) 이상이면 통과다.
- 출력: 첫 줄에 점수, 이어서 위반을 심각한 것부터 위치와 함께 `HARNESS_MAX_ERRORS`개(기본 5)까지 보여 준다.
  ```
  ✗ lint · 70점 (기준 95) · 파일 1개 · 위반 3개
    EnglishStudy/Features/Settings/View/LintProbeView.swift:2: [imports.no_mobile_core_services] MobileCoreServices 대신 UniformTypeIdentifiers를 쓴다 (−10)
  ```
- 결과 파일 `.harness/out/lint.json`: `passed`, `score`, `passScore`, `files`(검사한 파일 수), `violations`(`rule`·`severity`·`penalty`·`file`·`line`·`column`·`message`). 바뀐 파일이 없어도 남긴다.
- 종료 코드: 통과 0, 기준 미달 1, 설정 오류·SwiftLint 없음·SwiftLint 실행 실패 2
