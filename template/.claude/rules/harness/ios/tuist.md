---
paths:
  - "**/Project.swift"
  - "**/Workspace.swift"
  - "Tuist.swift"
  - "Tuist/**"
---

# Tuist

이 규칙은 Tuist를 쓰는 프로젝트에만 적용한다. Tuist가 없는 프로젝트에 도입을 제안하거나 강제하지 않는다.

## 프로젝트 구성

- 타겟, 의존성, 빌드 설정, 리소스 변경은 manifest(`Project.swift`, `Tuist/ProjectDescriptionHelpers/`)에서 한다. Xcode에서 직접 바꾼 설정은 재생성하면 사라진다.
- 반복되는 설정은 ProjectDescriptionHelpers에 있는 기존 헬퍼를 먼저 찾아 재사용한다.
- 새 모듈은 프로젝트에 스캐폴딩 템플릿(`tuist scaffold`)이 있으면 그것으로 만든다.
- 외부 패키지는 `Tuist/Package.swift`에 선언한다.

## 생성

- `scripts/harness/`의 build·test·unit-test는 파일 구성이나 manifest가 바뀌면 install·generate를 다시 실행한다. 이 스크립트로 빌드·테스트할 때는 직접 generate하지 않는다.
- Xcode에서 열어 볼 때처럼 직접 생성해야 하면 `.harness/project.json`의 `commands.generate` 명령을 쓴다.
- 생성 산출물(`*.xcodeproj`, `*.xcworkspace`, `Derived/`)은 git에 없다. 직접 편집하지 않는다.
- 프로젝트가 고정한 Tuist 버전을 쓴다.
- `tuist clean`은 캐시 문제가 의심될 때만 쓴다.
