# 팀 컨벤션 목록 (`.harness/conventions.json`)

팀이 고른 코드 규칙 목록이다. 예전 iOS 묶음의 `scripts/harness/lint`가 이 파일을 읽어 SwiftLint·swift-format·`tuist graph`로 검사하고, 100점에서 감점해 기준 점수로 판정했다([ADR 0006](decisions/0006-convention-lint.md), [ADR 0014](decisions/0014-layer-format-rules.md), [ADR 0015](decisions/0015-implicit-imports.md)).

## 지금은

- 단위 31에서 `lint`와 iOS 묶음이 하네스 밖으로 나갔다([ADR 0024](decisions/0024-no-platform.md)). 하네스는 이 파일을 읽지 않는다.
- 남은 것
  - `.harness/.gitignore`가 이 파일을 커밋 대상으로 둔다.
  - `scripts/harness/doctor`가 이 파일이 있으면 올바른 JSON인지만 본다.
- 예전 iOS 묶음을 쓰던 프로젝트는 sync가 `lint`를 `scripts/ios/lint`로, 규칙을 넣는 절차(`conventions.md` 규칙)를 `.claude/rules/project/ios/conventions.md`로 넘긴다. 그 프로젝트에서는 이 파일과 `scripts/ios/lint`가 그대로 돈다([template.md](template.md#예전-ios-묶음을-쓰던-프로젝트)).
- 코드와 파일 형식(규칙 종류 `pattern`·`format`·`dependency`, 필드, 점수 판정)은 git 기록(0.11.2)의 `template/scripts/harness/lint`와 `docs/conventions.md`에 있다.

## 다른 프로젝트에서 컨벤션 검사하기

발표의 andcon처럼 "규칙 뽑기 → 도구가 읽게 옮기기 → 검사"로 나누는 생각은 그대로 쓸 수 있다. 다만 도구는 프로젝트가 고른다.

- 규칙을 그 플랫폼의 린터 설정(ESLint, detekt, SwiftLint 등)으로 두고, `checks.json`에서 `scripts/harness/record lint <린트 명령>`으로 돌린다([checks.md](checks.md)).
- 파일 종류에 붙는 규칙은 `.claude/rules/project/`에 `paths`를 달아 둔다. 리뷰어도 이 규칙을 읽는다.
