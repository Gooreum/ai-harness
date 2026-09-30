# 공용 에이전트 지침

## 원칙

- 기존 프로젝트의 아키텍처와 패턴을 우선 존중한다.
- 불필요한 대규모 refactor를 하지 않는다.
- 변경 범위를 가능한 작게 유지한다.

## 상황별 규칙

작업을 시작하기 전에 해당하는 규칙 파일을 모두 읽는다. 경로는 이 파일 기준이다.

- Swift 코드를 작성·수정할 때 → [rules/swift.md](rules/swift.md)
- SwiftUI 뷰를 작성·수정할 때 → [rules/swiftui.md](rules/swiftui.md)
- async/await, actor, Task, Sendable 등 동시성 코드를 다룰 때 → [rules/concurrency.md](rules/concurrency.md)
- 새 타입·모듈을 설계하거나, 모듈 간 의존·외부 라이브러리를 추가·변경할 때 → [rules/dependencies.md](rules/dependencies.md)
- 테스트를 작성·수정할 때 → [rules/testing.md](rules/testing.md)
- 빌드·테스트를 실행해 검증할 때, 빌드 설정·프로젝트 파일을 다룰 때 → [rules/build.md](rules/build.md)
- Tuist 프로젝트(`Tuist.swift`, `Project.swift`가 있음)에서 파일 구성·타겟·설정을 바꾸거나 빌드할 때 → [rules/tuist.md](rules/tuist.md)
- 커밋, 브랜치, PR 등 git 작업을 할 때 → [rules/git.md](rules/git.md)
