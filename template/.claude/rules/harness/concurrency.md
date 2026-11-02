---
paths:
  - "**/*.swift"
---

# 동시성

## 먼저 확인

- 수정할 타겟의 동시성 설정(Swift 6 language mode, strict concurrency 검사 수준, 기본 격리)을 확인한다. 모듈마다 다를 수 있다.
- 새 코드는 async/await를 우선한다. 기존 GCD·Combine 코드는 이유 없이 바꾸지 않는다.

## 격리

- UI 상태를 바꾸는 타입·함수는 `@MainActor`로 격리한다. `DispatchQueue.main.async`를 새로 쓰지 않는다.
- 공유 가변 상태는 actor로 보호하거나, 값 타입으로 복사해서 넘긴다.
- actor 안에서 `await` 이후에는 상태가 바뀌었을 수 있다(재진입). `await` 뒤에 필요한 조건을 다시 확인한다.

## 컴파일러 진단

- 동시성 경고·에러를 없애려고 `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `MainActor.assumeIsolated`를 쓰지 않는다. 먼저 격리와 타입 설계로 해결한다.
- 불가피하게 쓸 때는 왜 안전한지 주석으로 남기고, 사용자에게 알린다.

## Task

- 구조화된 동시성(`async let`, `TaskGroup`)을 우선한다.
- `Task {}`로 만든 작업은 소유자와 취소 시점을 정한다. 필요하면 핸들을 저장해 `cancel()`한다. `Task.detached`는 이유가 있을 때만 쓴다.
- 끝나지 않는 작업(스트림 구독 등)이 `self`를 강하게 잡지 않게 하거나, 소유자가 해제 시점에 취소한다.
- 오래 걸리는 루프는 취소 여부를 확인한다(`Task.checkCancellation()`, `Task.isCancelled`).

## 콜백·스트림 브리지

- 콜백 API는 `withCheckedContinuation` / `withCheckedThrowingContinuation`으로 감싸고, 모든 경로에서 정확히 한 번 resume한다.
- `AsyncStream`은 `onTermination`에서 구독과 리소스를 해제하고, 버퍼 정책을 의도적으로 정한다.
