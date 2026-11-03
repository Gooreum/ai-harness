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

## 기록

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
