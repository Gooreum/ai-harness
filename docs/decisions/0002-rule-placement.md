# 0002. 규칙은 "무엇에 걸리는가"에 따라 놓을 곳을 정한다

- 상태: 채택
- 날짜: 2026-10-07

## 배경

- 지금까지 규칙 8개는 AGENTS.md의 "작업 전에 해당하는 규칙을 모두 읽는다"는 지시 하나로 불러왔다. 모델이 판단해서 읽는 방식이라 빠뜨릴 수 있다.
- Claude Code는 `.claude/rules/`의 규칙에 `paths:`를 달면, 해당 경로의 파일을 읽을 때 규칙을 자동으로 불러온다.
- 하지만 git처럼 파일이 아니라 행동에 걸린 규칙은 경로로 걸 수 없다.
- build 규칙의 절차(스킴·시뮬레이터 확인, 재생성 시점)는 이제 build·test·verify 스크립트가 대신한다.

## 결정

### 1. 파일 종류에 걸린 규칙 → 경로 규칙

`template/.claude/rules/harness/`에 두고 `paths:`를 단다.

| 규칙 | paths |
|---|---|
| `swift.md`, `swiftui.md`, `concurrency.md` | `**/*.swift` |
| `dependencies.md` | `**/*.swift`, `**/Podfile`, `**/Cartfile` |
| `testing.md` | `**/Tests/**`, `**/*Tests/**`, `**/*Tests.swift`, `**/*.xctestplan` |
| `project-settings.md` (구 build.md) | `**/*.pbxproj`, `**/*.xcconfig`, `**/*.xcscheme`, `**/*.entitlements`, `**/Info*.plist`, `**/Project.swift`, `**/Package.swift`, `Tuist/**` |
| `tuist.md` | `**/Project.swift`, `**/Workspace.swift`, `Tuist.swift`, `Tuist/**` |

- SwiftUI 뷰 파일은 경로로 구분할 수 없어서 `swiftui.md`도 모든 Swift 파일에 건다.
- `harness/` 하위 폴더는 하네스가 관리하는 규칙이다. 프로젝트 고유 규칙은 `.claude/rules/project/`에 둔다(단위 6).

### 2. 행동에 걸린 규칙 중 꼭 지킬 것 → AGENTS.md

항상 로드되는 AGENTS.md에 짧게 둔다.
- 검증: verify 실행, 결과 보고, 설정·테스트 약화 금지
- git: 승인, 파괴적 명령, 훅 우회, 스테이징·비밀 정보, 관례, 충돌

위험한 git 명령은 단위 7에서 권한 deny로도 막는다.

### 3. 절차와 세부 관례 → 스킬 (단위 12)

이번에 AGENTS.md로 옮기지 않은 git 관례는 워크플로 스킬에서 다룬다.
- 커밋 하나에 논리적 변경 하나, 제목은 무엇·본문은 왜
- 기본 브랜치에 직접 커밋하지 않고 작업 브랜치 만들기(프로젝트마다 다름)
- PR 본문에 변경 요약과 검증 방법·결과 넣기
- 여러 워크트리 환경에서 `git worktree list`·`git -C`로 위치 확인

### 4. 스크립트가 대신하는 절차는 규칙에서 지운다

- 스킴·시뮬레이터를 직접 확인하는 절차는 프로젝트 설정 파일과 스크립트가 대신한다.
- 재생성 시점은 스크립트가 파일 구성 변경을 감지해 판단한다.

### 5. 다른 에이전트를 위해 인덱스를 남긴다

Codex 같은 다른 에이전트는 `paths:`를 모른다. 그래서 AGENTS.md의 "상황별 규칙" 표로 같은 파일을 읽게 한다. 규칙 파일은 하나만 둔다.

## 결과

- 좋아지는 점
  - Swift 파일을 읽으면 Swift 규칙 4개가, 테스트·설정·manifest를 읽으면 해당 규칙이 자동으로 들어온다.
  - 무관한 작업(문서 수정 등)에서는 규칙이 컨텍스트를 차지하지 않는다.
- 비용
  - Swift 작업 중에는 규칙 약 90줄이 함께 로드된다.
  - 줄일지는 후보 17(평가)에서 측정한 뒤 정한다.
- 확인 방법
  - 이 저장소 안의 임시 프로젝트에 규칙을 두고 파일을 읽어 확인했다.
    - `.swift`: swift·swiftui·concurrency·dependencies
    - 테스트 파일: testing
    - `.xcconfig`: project-settings
    - `Project.swift`: tuist
    - README: 없음
  - 실제 프로젝트(MotoTrace)에서는 단위 9 설치 때 다시 확인한다.
