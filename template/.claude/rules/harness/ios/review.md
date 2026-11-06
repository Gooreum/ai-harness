---
paths:
  - "**/*.swift"
  - "**/*.pbxproj"
  - "**/*.xcconfig"
  - "**/*.entitlements"
  - "**/Info.plist"
  - "**/Project.swift"
  - "**/Package.swift"
  - "**/Tuist/**"
---

# iOS 리뷰 항목

`reviewer`가 iOS 변경을 검토할 때 공통 중점 항목에 더해 보는 것이다. 근거 규칙은 같은 폴더의 `swift.md`, `swiftui.md`, `concurrency.md`, `dependencies.md`, `testing.md`, `project-settings.md`, `tuist.md`다.

## 확인 항목

- **동시성**: UI 상태를 바꾸는 코드의 `@MainActor` 격리. 소유자와 취소 시점이 없는 `Task`.
- **의존 방향**: 다른 모듈의 구현체를 import하거나 참조하는 것(인터페이스가 아닌 것). Feature끼리 직접 의존. 새 싱글턴. import한 모듈이 구현체인지 인터페이스인지는 manifest(`Project.swift`, `Tuist/`, `Package.swift`)의 타깃 정의로 판단한다.
- **접근성**: 새로 만든 인터랙티브 요소에 접근성 식별자·라벨이 없는 것.

## 편법

- 경고를 덮는 것: `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `MainActor.assumeIsolated`, `// swiftlint:disable`
- 설정 낮추기: strict concurrency, 배포 타겟, Swift 버전, `SWIFT_TREAT_WARNINGS_AS_ERRORS` 끄기
