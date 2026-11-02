# ios-ai-harness

여러 iOS 프로젝트에서 재사용하는 **AI 코딩 에이전트용 하네스**다.
처음 보는 사람이 이 문서 하나로 전체 구조와 동작 방식을 파악할 수 있게 썼다. 세부 스펙은 문서마다 링크로 연결해 두었다.

## 이게 뭔가

AI 코딩 에이전트(Claude Code, Codex 등)는 iOS 프로젝트에서 자주 같은 실수를 한다.

- `xcodebuild` 명령을 매번 추측해서 만든다. 스킴이나 시뮬레이터를 틀리기도 한다.
- 수 MB짜리 빌드 로그를 통째로 읽느라 컨텍스트를 낭비한다.
- Tuist가 만든 `.xcodeproj`나 `project.pbxproj`를 직접 고친다. 다시 생성하면 사라지거나 프로젝트 파일이 깨진다.
- 테스트를 통과시키려고 assertion을 약하게 바꾸거나 `@unchecked Sendable`로 경고를 덮는다.
- 사용자 확인 없이 `git push`나 `reset --hard`를 실행한다.

**하네스**는 에이전트에서 모델을 뺀 나머지 전부를 말한다. 에이전트가 읽는 지침, 쓰는 도구, 결과를 확인하는 수단, 행동을 막는 장치가 모두 하네스다.
이 저장소는 그중 iOS 프로젝트에 공통으로 쓸 수 있는 부분을 만들고, 각 프로젝트에 설치한다.

## 용어

| 용어 | 뜻 |
|---|---|
| 대상 프로젝트 | 하네스를 설치해서 쓰는 iOS 앱 저장소. 예: MotoTrace |
| 프로젝트 설정 파일 | 대상 프로젝트의 `.harness/project.json`. 스킴, 시뮬레이터, 생성 명령처럼 프로젝트마다 다른 값을 모아 둔 JSON |
| AGENTS.md | 에이전트가 세션을 시작할 때 읽는 지침 파일. Claude Code는 `CLAUDE.md`가 `@AGENTS.md`로 불러와야 읽는다 |
| 경로 규칙 | `.claude/rules/` 아래의 마크다운 규칙. 머리말의 `paths:`와 맞는 파일을 에이전트가 읽을 때만 컨텍스트에 들어온다. 예: `.swift` 파일을 열면 `swift.md`가 함께 들어온다 |
| 훅 | 에이전트가 도구를 쓰기 직전·직후에 Claude Code가 실행하는 스크립트. 여기서는 파일 편집 직전에 실행돼 금지된 파일이면 막는다 |
| 권한 규칙 | `.claude/settings.json`의 `deny`(항상 거부), `ask`(매번 사용자에게 물음) 목록 |
| 서브에이전트 | 메인 에이전트가 일을 맡기는 별도 에이전트. 자기만의 지시문과 도구 목록을 가진다 |
| 플러그인·마켓플레이스 | Claude Code 플러그인은 훅·서브에이전트·스킬을 묶어 여러 프로젝트에 배포하는 단위다. 마켓플레이스는 플러그인 목록이고, 이 저장소 자체가 마켓플레이스 역할을 한다 |
| 시험장 | 하네스를 실제로 돌려 보는 프로젝트. 지금은 ReadSharp(`EnglishStudy`)의 `EnglishStudy-harness` 워크트리다. 이전 단위는 MotoTrace에서 했다 |

## 하네스 계층

구성요소를 하는 일에 따라 다섯 층으로 나눈다. 자세한 기준은 [docs/principles.md](docs/principles.md)에 있다.

| 계층 | 하는 일 | 이 저장소에서 |
|---|---|---|
| Context (가이드) | 행동하기 전에 알려준다 | `AGENTS.md`, 경로 규칙 |
| Execution (실행 도구) | 에이전트가 일을 하는 손 | `scripts/harness/build`·`test`·`verify` |
| Validation (센서) | 결과가 맞는지 판정한다 | 결정적: 빌드·테스트 결과 요약 / 추론적: `ios-reviewer` 코드 리뷰 |
| Enforcement (강제) | 모델 판단과 상관없이 막는다 | 생성 파일 편집 차단 훅, 권한 규칙 |
| State (설정·상태) | 위 계층이 함께 쓰는 데이터 | `.harness/project.json`, 실패 기록 |

- **결정적 검증**은 같은 입력이면 항상 같은 결과를 낸다(컴파일러, 테스트). 코드가 동작하는지는 이것만 확실히 판정한다.
- **추론적 검증**은 LLM이 판단한다(코드 리뷰). 설계·규칙 위반을 잡지만 결정적 검증을 대신하지 못한다.

## 한눈에 보기

저장소는 세 덩어리로 나뉜다. **복사해서 설치하는 것**, **플러그인으로 켜는 것**, **설치하는 도구**다.

```
ios-ai-harness (이 저장소)                         대상 iOS 프로젝트
───────────────────────────                       ─────────────────────────────
scripts/detect ─────────── 프로젝트를 훑어서 ───────▶ .harness/project.json
scripts/dev-install ────┐
                        │  복사·병합
template/ ──────────────┴────────────────────────▶ AGENTS.md, CLAUDE.md
                                                    .claude/rules/harness/*.md
                                                    .claude/settings.json
                                                    scripts/harness/*
                                                    .harness/.gitignore

plugin/ ─────────── 플러그인으로 켬 (복사 안 함) ───▶ 훅, ios-reviewer
                    (.claude/settings.local.json)
```

- `template/`의 파일은 프로젝트에 **복사**된다. 프로젝트 저장소에 커밋되므로 사람·CI·다른 에이전트도 같은 스크립트를 쓴다.
- `plugin/`은 **복사하지 않는다.** 프로젝트가 플러그인을 켜면 Claude Code가 이 저장소에서 바로 불러온다. 여러 프로젝트에 같은 훅과 리뷰어를 적용하기 위해서다.
- 프로젝트마다 다른 값은 `.harness/project.json` 하나에만 있다. 그래서 스크립트와 지침은 모든 프로젝트에서 글자 하나 다르지 않다.

## 동작 흐름

### 1. 설치

```bash
scripts/dev-install ~/path/to/MyApp
```

1. `.harness/project.json`이 없으면 `scripts/detect`가 프로젝트를 훑어 초안을 만든다.
   - 생성기 종류(Tuist / XcodeGen / xcodeproj / SPM), 워크스페이스, 앱 스킴, bundle ID, 단위 테스트 타깃, 시뮬레이터, 모듈 구조를 찾는다.
2. `template/`의 파일을 프로젝트에 맞춘다.
   - `scripts/harness/`, `.claude/rules/harness/`, `.harness/.gitignore`는 template과 똑같이 맞춘다. template에서 사라진 하네스 규칙은 지운다.
   - `AGENTS.md`는 하네스 관리 블록만 넣거나 바꾼다. 프로젝트가 쓴 부분은 건드리지 않는다.
   - `.claude/settings.json`에는 권한 규칙을 중복 없이 합친다. 프로젝트의 기존 설정은 유지한다.
3. `.claude/settings.local.json`에 이 저장소를 로컬 마켓플레이스로 등록하고 플러그인 `ios-harness`를 켠다.
4. 바꾼 파일 목록과 사람이 직접 할 일을 출력한다. 예: "AGENTS.md 프로젝트 영역을 채운다", "project.json 값을 확인한다"

여러 번 실행해도 결과가 같다. 하네스를 고친 뒤 다시 실행하면 프로젝트가 최신으로 맞춰진다.

### 2. 세션 시작: 항상 읽히는 지침

에이전트가 세션을 시작하면 `CLAUDE.md` → `@AGENTS.md` 순서로 지침을 읽는다. 대상 프로젝트의 AGENTS.md는 두 영역으로 나뉜다.

| 영역 | 내용 | 누가 고치나 |
|---|---|---|
| 프로젝트 영역 (위쪽) | 앱 소개, 구조, 프로젝트 고유 규칙 | 각 프로젝트 |
| 하네스 관리 블록 (`<!-- harness:begin -->` ~ `<!-- harness:end -->`) | 빌드·테스트 명령 표, 꼭 지킬 규칙, 상황별 규칙 표 | 이 저장소의 `template/AGENTS.md` |

- 두 영역이 충돌하면 프로젝트 규칙을 따른다.
- 매 세션 컨텍스트를 차지하므로 100줄 이하로 유지한다. 특정 파일에만 필요한 규칙은 경로 규칙으로 뺀다.

### 3. 코드 작업: 필요할 때만 들어오는 규칙

에이전트가 파일을 읽으면 그 파일에 맞는 경로 규칙이 자동으로 컨텍스트에 들어온다.

| 에이전트가 읽은 파일 | 함께 들어오는 규칙 |
|---|---|
| `*.swift` | `swift.md`, `swiftui.md`, `concurrency.md`, `dependencies.md` |
| `Tests/` 아래, `*Tests.swift`, `*.xctestplan` | `testing.md` |
| pbxproj, xcconfig, xcscheme, entitlements, Info.plist, `Project.swift`, `Package.swift` | `project-settings.md` |
| `Project.swift`, `Workspace.swift`, `Tuist/` | `tuist.md` |
| 프로젝트가 정한 경로 | `.claude/rules/project/*.md` |

### 4. 검증: build · test · verify

에이전트는 `xcodebuild`를 직접 구성하지 않고 프로젝트 스크립트를 부른다. 스크립트가 `.harness/project.json`을 읽어 명령을 만든다.

```bash
scripts/harness/verify               # 앱 빌드 + 바뀐 모듈의 테스트
scripts/harness/verify --plan        # 무엇을 돌릴지만 출력
scripts/harness/verify --base main   # main에서 갈라진 뒤의 변경 전체 (PR 전)
scripts/harness/build                # 빌드만
scripts/harness/test --scheme CoreTracking
```

내부 동작은 다음과 같다. 자세한 내용은 [docs/scripts.md](docs/scripts.md)에 있다.

1. **프로젝트 생성이 필요한지 판단**: Tuist·XcodeGen 프로젝트라면 파일 목록과 manifest로 지문(fingerprint)을 만든다. 지난번과 다를 때만 install·generate를 다시 돌린다. 소스 내용만 바뀌었으면 건너뛴다.
2. **바뀐 파일을 모듈로 묶기**(verify): 파일마다 `Project.swift`가 있는 가장 가까운 상위 디렉터리를 모듈로 본다. 앱 디렉터리 변경은 앱 테스트로, `Tuist/`나 루트 manifest 변경은 전체 테스트로 이어진다.
3. **실행**: 앱을 먼저 빌드하고, 성공하면 바뀐 모듈의 테스트를 돌린다. `xcodebuild -quiet`에 결과 번들(`.xcresult`)을 남기게 한다.
4. **판정과 요약**: `xcresulttool`로 결과 번들에서 에러와 실패만 뽑는다.

출력은 에이전트가 읽기 좋게 줄인다.

```
✓ build MotoTrace · iPhone 17 Pro · 21s · 경고 1
✓ test CoreTracking · 통과 20 · 7s
✓ verify · 통과: CoreTracking · 29s
```

실패하면 첫 에러의 `파일:줄`부터 보여주고, 전체 로그와 결과 번들 경로를 붙인다.

```
  Modules/Core/CoreTracking/Tests/Sources/LeanAngleAnalyzerTests.swift:70: XCTAssertEqual failed: ("1") is not equal to ("2")
    ↳ LeanAngleAnalyzerTests/test_updateAttitude_첫데이터_영점_캘리브레이션()
```

- 로그와 결과 번들은 `.harness/out/`, 생성 지문은 `.harness/state/`에 둔다. 둘 다 git이 무시한다.
- DerivedData는 `~/Library/Developer/Xcode/DerivedData/<워크트리 이름>-harness-<경로 해시>`에 둔다. 프로젝트가 `~/Desktop` 같은 macOS 보호 폴더 아래 있으면 시뮬레이터가 테스트 번들을 읽지 못해서다.
- 종료 코드: 성공 0, 빌드·테스트 실패는 xcodebuild의 코드(보통 65), 설정·인자 오류 2

### 5. 막는 장치: 훅과 권한 규칙

모델이 지침을 잊어도 위험하거나 되돌리기 어려운 행동은 막는다. 왜 이렇게 나눴는지는 [ADR 0004](docs/decisions/0004-enforcement.md)에 있다.

| 장치 | 막는 것 | 방식 |
|---|---|---|
| 훅 `protect-generated.sh` (플러그인) | Tuist·XcodeGen 프로젝트: `*.xcodeproj/`, `*.xcworkspace/`, `Derived/` 안의 파일 편집 / 그 외: `*.pbxproj` 편집 | 편집 직전에 거부하고 고치는 방법(manifest 수정 등)을 알려준다 |
| 권한 `deny` (`settings.json`) | 서명·시크릿 파일 읽기(`*.p12`, `*.p8`, `*.mobileprovision`, `.env*`), `*.pbxproj` 편집 | 항상 거부 |
| 권한 `ask` (`settings.json`) | `git push`, `reset --hard`, `clean`, `checkout --`, `restore`, `branch -D`, `rebase`, `commit --no-verify`, `gh pr create/merge` (`git -C <경로>` 형식 포함) | 매번 사용자에게 묻는다 |

- 훅은 stdin으로 받은 JSON만 읽는다. 나중에 Codex에서도 같은 스크립트를 쓰기 위해서다.
- 훅은 판단할 수 없으면(설정 파일 없음, 입력 오류) 막지 않는다. 실수를 줄이는 장치이지 보안 경계가 아니라서, 고장 난 훅이 정상 작업을 막으면 안 된다.
- "검증을 돌렸는지 확인하는 게이트" 같은 장치는 일부러 넣지 않았다. 그런 실패가 실제로 관찰되면 그때 넣는다.

### 6. 리뷰: ios-reviewer

PR을 만들기 전에 메인 에이전트가 플러그인의 서브에이전트 `ios-reviewer`에게 변경 검토를 맡긴다.

1. `git diff HEAD`, `git status --porcelain`으로 바뀐 파일을 찾는다.
2. 바뀐 파일을 하나씩 연다. 이때 경로 규칙이 함께 들어와서 그 규칙에 비춰 본다.
3. 의심되는 부분은 주변 코드와 manifest를 읽어 확인한다.
4. `[차단|권장|참고] 경로:줄 — 문제`, 근거, 제안을 보고한다. 마지막에 실제로 연 파일과 규칙을 적는다.

- 중점 항목: 동시성 격리, 모듈 의존 방향, 접근성, 테스트 약화·설정 완화 같은 편법, 과설계
- 도구는 Read·Grep·Glob·Bash뿐이고 코드를 고치지 않는다.
- Claude Code 안에서 도는 서브에이전트다. 메인 세션과 같은 모델을 쓰고(`model: inherit`), Codex를 부르지 않는다.
- Codex로 하는 리뷰(예: Codex 플러그인의 `/codex:review`)와는 별개다. 프로젝트가 원하면 둘을 함께 쓸 수 있지만, Codex 리뷰는 하네스에 포함되지 않는다.

### 7. 개선: 같은 실수는 한 번만

시험장에서 에이전트가 실패하면 [docs/harness-log.md](docs/harness-log.md)에 기록한다. 그리고 [docs/principles.md](docs/principles.md)의 기준표에 따라 알맞은 층을 고친다.
반복되는 실수일수록 강한 수단으로 옮긴다: 문장 지침 → 경로 규칙 → 스크립트가 딸린 스킬 → 린트·테스트 → 훅·권한.

실제 예: 리뷰어가 바뀐 파일을 열지 않고 diff만 보고 판단했다 → 검토 순서를 명시하고, 연 파일을 출력에 적게 했다.

## 파일별 역할

### 루트

| 파일 | 역할 |
|---|---|
| `README.md` | 이 문서. 처음 보는 사람을 위한 개요 |
| `AGENTS.md` | **이 저장소를 개발할 때** 에이전트가 따르는 지침. 대상 프로젝트에 설치되는 지침은 `template/AGENTS.md`다 |
| `CLAUDE.md` | `@AGENTS.md`를 불러온다 |
| `.claude-plugin/marketplace.json` | 이 저장소를 마켓플레이스 `ios-ai-harness`로 만든다. 플러그인 위치는 `./plugin` |

### template/ — 대상 프로젝트에 복사되는 원본

template 안의 경로가 그대로 대상 프로젝트 루트 기준 경로가 된다. 설치·갱신 방식은 [docs/template.md](docs/template.md)에 있다.

| 파일 | 계층 | 역할 |
|---|---|---|
| `AGENTS.md` | Context | 프로젝트 지침. 위쪽 프로젝트 영역(빈 자리)과 아래쪽 하네스 관리 블록 |
| `CLAUDE.md` | Context | `@AGENTS.md` import. Claude Code가 AGENTS.md를 읽게 한다 |
| `.claude/rules/harness/swift.md` | Context | Swift 코드 작성 규칙 |
| `.claude/rules/harness/swiftui.md` | Context | SwiftUI 상태 관리, 뷰 작성, 접근성 규칙 |
| `.claude/rules/harness/concurrency.md` | Context | Swift Concurrency 격리, 컴파일러 진단 대응, Task, 콜백 브리지 규칙 |
| `.claude/rules/harness/dependencies.md` | Context | 모듈 경계, 외부 라이브러리 추가·노출, 과한 추상화 금지 |
| `.claude/rules/harness/testing.md` | Context | 테스트 작성·격리 규칙, 테스트를 약화하는 편법 금지 |
| `.claude/rules/harness/project-settings.md` | Context | 프로젝트 파일·빌드 설정을 바꿀 때의 규칙, 설정 완화 금지 |
| `.claude/rules/harness/tuist.md` | Context | Tuist 프로젝트 구성과 생성 규칙 |
| `.claude/rules/project/.gitkeep` | Context | 프로젝트 고유 규칙을 두는 자리. 하네스가 건드리지 않는다 |
| `.claude/settings.json` | Enforcement | 권한 규칙(deny 6개, ask 20개) |
| `scripts/harness/build` | Execution + Validation | 빌드하고 첫 에러를 요약한다 |
| `scripts/harness/test` | Execution + Validation | 테스트하고 실패만 요약한다 |
| `scripts/harness/verify` | Execution + Validation | 바뀐 파일로 대상을 정해 빌드와 테스트를 한 번에 돌린다 |
| `scripts/harness/lib.sh` | Execution | 세 스크립트의 공용 함수: 설정 읽기, 시뮬레이터 찾기, 생성 지문, DerivedData 경로, `xcresulttool` 결과 정리 |
| `.harness/.gitignore` | State | `.harness/`에서 `project.json`만 커밋되게 한다 |

### plugin/ — Claude Code 플러그인 ios-harness

복사하지 않고 Claude Code가 이 저장소에서 바로 불러온다. 구성은 [docs/plugin.md](docs/plugin.md)에 있다.

| 파일 | 계층 | 역할 |
|---|---|---|
| `.claude-plugin/plugin.json` | — | 플러그인 이름(`ios-harness`)과 버전 |
| `hooks/hooks.json` | Enforcement | Edit·Write·MultiEdit·NotebookEdit 직전에 `protect-generated.sh`를 실행하도록 등록 |
| `hooks/protect-generated.sh` | Enforcement | 생성 파일·pbxproj 편집을 막는 훅 |
| `agents/ios-reviewer.md` | Validation (추론적) | 읽기 전용 리뷰 서브에이전트의 지시문 |

### scripts/ — 하네스를 설치하는 도구

대상 프로젝트 경로를 인자로 받는다. 대상 프로젝트에는 복사되지 않는다.

| 파일 | 역할 |
|---|---|
| `detect` | 프로젝트를 훑어 `.harness/project.json` 초안을 만든다. `--write`로 저장, `--force`로 덮어쓰기 |
| `dev-install` | 개발 중인 하네스를 프로젝트에 설치·갱신한다. 정식 설치·갱신 도구(init/sync/doctor)는 후보 14에서 만든다 |

### tests/ — 스크립트 회귀 테스트

임시 디렉터리에 가짜 프로젝트와 가짜 결과를 만들어 스크립트의 판단 로직을 검사한다. Xcode 없이 돈다.

| 파일 | 검사하는 것 |
|---|---|
| `run.sh` | 모든 `*.test.sh`를 실행한다 |
| `lib.sh` | `assert_eq`, `finish` 같은 테스트 도우미 |
| `detect.test.sh` | 생성기(Tuist·XcodeGen·xcodeproj·SPM)별로 detect가 만든 초안 |
| `build.test.sh` | build가 쓰는 공용 함수: 시뮬레이터 선택, 에러 요약 형식, 다시 생성할지 판단 |
| `verify.test.sh` | test·verify의 공용 함수(실패 요약 등)와 verify의 실행 계획: 바뀐 파일 → 모듈 → 돌릴 테스트 |
| `hooks.test.sh` | 훅이 막을 것만 막고, 판단할 수 없으면 통과시키는지 |
| `dev-install.test.sh` | 파일 배치, AGENTS.md 관리 블록 교체, 설정 병합, 반복 실행 |

### docs/ — 설계 문서

| 파일 | 내용 |
|---|---|
| `roadmap.md` | 작업 단위와 순서, 진행 상황 |
| `principles.md` | 하네스 계층, 설계 원칙, 실수를 어느 층에서 고칠지 정한 기준표, 용어 |
| `references.md` | 레퍼런스 조사 요약, 플랫폼 제약, 로컬 환경, 출처 |
| `project-config.md` | `.harness/project.json` 필드 스펙과 detect가 값을 찾는 방법 |
| `scripts.md` | build·test·verify의 출력 형식, 산출물 위치, 생성 판단 |
| `template.md` | template 파일이 어디에 설치되고 어떻게 갱신되는지, 기존 지침이 있는 프로젝트에 적용하는 절차 |
| `plugin.md` | 플러그인 구성, 훅이 막는 것, 리뷰어 동작, 프로젝트에서 켜는 방법 |
| `harness-log.md` | 시험장에서 관찰한 에이전트 실패와 그에 따른 수정 |
| `decisions/0001-layers.md` | 다섯 계층과 산출물 위치(template·plugin·scripts)를 나눈 이유 |
| `decisions/0002-rule-placement.md` | 규칙을 무엇에 붙는지(파일 종류 / 행동)에 따라 경로 규칙·AGENTS.md·스킬·권한으로 나누는 기준 |
| `decisions/0003-agents-md-areas.md` | AGENTS.md를 프로젝트 영역과 관리 블록으로 나누고 명령 블록을 고정 문장으로 둔 이유 |
| `decisions/0004-enforcement.md` | 무엇을 훅으로, 무엇을 deny·ask로 막는지 |
| `decisions/0005-talk-criteria.md` | 여기어때 안드로이드 팀 발표의 기준으로 이후 후보를 다시 정하고, 워크플로 엔진을 함께 쓰지 않는 이유 |

## 설치하면 대상 프로젝트는 이렇게 된다

```
MyApp/
├── AGENTS.md                      프로젝트 영역 + 하네스 관리 블록
├── CLAUDE.md                      @AGENTS.md
├── .harness/
│   ├── .gitignore                 project.json만 커밋
│   ├── project.json               프로젝트 설정 파일 (detect 초안 → 사람이 확인)
│   ├── out/                       마지막 실행의 로그·결과 번들 (무시됨)
│   └── state/                     생성 지문 (무시됨)
├── .claude/
│   ├── settings.json              권한 규칙 (기존 설정과 합침)
│   ├── settings.local.json        로컬 플러그인 켜기 (커밋하지 않음)
│   └── rules/
│       ├── harness/*.md           하네스 경로 규칙 (하네스가 관리)
│       └── project/*.md           프로젝트 고유 규칙 (프로젝트가 관리)
└── scripts/harness/
    ├── build, test, verify
    └── lib.sh
```

## 직접 해 보기

```bash
bash tests/run.sh
```

```bash
scripts/detect ~/path/to/MyApp
```

```bash
scripts/dev-install ~/path/to/MyApp
```

```bash
claude plugin validate plugin
```

- `bash tests/run.sh`: 회귀 테스트 전체. Xcode 없이 돈다.
- `scripts/detect`: 설정 파일 초안을 출력만 한다. 파일은 쓰지 않는다.
- `scripts/dev-install`: 실제로 설치한다. 설치한 뒤 출력된 "직접 할 일"을 처리하고, 프로젝트에서 `scripts/harness/verify`를 돌려 본다.
- 필요한 도구: macOS 기본 bash·jq, Xcode(빌드·테스트), 해당 프로젝트의 생성기(Tuist 등)

## 진행 상황

- 단위 1~8 완료: 저장소 구조, 프로젝트 설정 파일·detect, build·test·verify, 경로 규칙, AGENTS.md 템플릿, 훅·권한·플러그인, ios-reviewer
- 단위 9 진행 중: MotoTrace에 설치해 확인한 뒤, 시험장을 ReadSharp로 옮겼다. 1~2주 운영하며 실패를 기록하고, 이 기록으로 이후 순서를 정한다.
- 이후 후보: 동작·화면 검증(Maestro, 스냅샷+Figma), 결정적 컨벤션 센서, 사람이 검사를 고르는 작업 흐름, (조건부) 검증 강제, 정책·결정 기록, 플러그인 배포, Codex 어댑터, 평가 등. 기준은 [ADR 0005](docs/decisions/0005-talk-criteria.md)에 있다

자세한 내용은 [docs/roadmap.md](docs/roadmap.md)에 있다. 이 저장소에 기여하는 방법(브랜치, 커밋 규칙)은 [AGENTS.md](AGENTS.md)에 있다.
