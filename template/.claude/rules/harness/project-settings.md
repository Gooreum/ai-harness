---
paths:
  - "**/*.pbxproj"
  - "**/*.xcconfig"
  - "**/*.xcscheme"
  - "**/*.entitlements"
  - "**/Info*.plist"
  - "**/Project.swift"
  - "**/Package.swift"
  - "Tuist/**"
---

# 프로젝트 파일·빌드 설정

## 설정 완화 금지

- 빌드·테스트를 통과시키려고 설정을 완화하지 않는다. 경고 억제, strict concurrency 검사 수준 낮추기, 배포 타겟·Swift 버전 변경, 린트 규칙 비활성화가 여기에 해당한다.

## 프로젝트 파일

- `.pbxproj`를 직접 편집하지 않는다. 프로젝트 생성 도구(Tuist, XcodeGen 등)가 있으면 manifest를 수정한다.
- 생성 도구가 없는데 파일 추가·삭제에 `.pbxproj` 변경이 필요하면, 직접 고치지 않고 사용자에게 알린다.
- 서명, 번들 ID, capabilities, entitlements 변경은 사용자 확인 후에 한다. 서명·프로비저닝 오류는 직접 해결하려 하지 않고 보고한다.
