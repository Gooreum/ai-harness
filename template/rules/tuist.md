# Tuist

이 규칙은 Tuist를 쓰는 프로젝트에만 적용한다. Tuist가 없는 프로젝트에 도입을 제안하거나 강제하지 않는다.

## 프로젝트 구성

- 타겟, 의존성, 빌드 설정, 리소스 변경은 manifest(`Project.swift`, `Tuist/ProjectDescriptionHelpers/`)에서 한다. Xcode에서 직접 바꾼 설정은 재생성하면 사라진다.
- 반복되는 설정은 ProjectDescriptionHelpers에 있는 기존 헬퍼를 먼저 찾아 재사용한다.
- 새 모듈은 프로젝트에 스캐폴딩 템플릿(`tuist scaffold`)이 있으면 그것으로 만든다.
- 외부 패키지는 `Tuist/Package.swift`에 선언하고 `tuist install`로 받는다.

## 생성

- 소스 파일을 추가·삭제·이동하거나 manifest를 바꾼 뒤에는 `tuist generate`로 재생성하고 빌드한다. 프로젝트가 감싼 명령(Makefile 등)이 있으면 그것을 쓴다.
- 생성 산출물(`*.xcodeproj`, `*.xcworkspace`, `Derived/`)은 git에 없다. 새 클론이나 워크트리에서는 먼저 재생성한다.
- 프로젝트가 고정한 Tuist 버전을 쓴다.
- `tuist clean`은 캐시 문제가 의심될 때만 쓴다.
