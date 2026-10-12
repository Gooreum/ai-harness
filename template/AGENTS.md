# 공용 에이전트 지침

## 원칙

- 기존 프로젝트의 아키텍처와 패턴을 우선 존중한다.
- 불필요한 대규모 refactor를 하지 않는다.
- 변경 범위를 가능한 작게 유지한다.

## 검증

- 코드를 바꾼 뒤에는 `scripts/harness/verify`로 빌드하고 바뀐 모듈의 테스트를 실행한다.
- 결과는 실제로 실행한 명령과 그 결과로 보고한다. 실행하지 못한 검증은 못 했다고 밝힌다.
- 검증을 통과시키려고 설정을 완화하거나 테스트를 약화하지 않는다.

## git

- 커밋, push, PR 생성·머지는 사용자가 요청하거나 승인한 뒤에 한다. 커밋 전에는 메시지와 대상 파일을 먼저 보여준다.
- 사용자가 명시적으로 요청하지 않으면 파괴적인 명령을 쓰지 않는다: `push --force`, `reset --hard`, `clean -fd`, `checkout -- .` / `restore .`, `branch -D`, 이미 push된 브랜치의 rebase.
- `--no-verify` 등으로 훅을 우회하지 않는다. 훅이 막으면 원인을 해결한다.
- 파일을 지정해 스테이징한다. 비밀 정보(API 키, 인증서, 프로비저닝 프로파일, `.env`)와 생성 산출물은 커밋하지 않는다.
- 커밋 메시지와 브랜치 이름은 프로젝트의 기존 관례를 따른다. 모르면 `git log`로 확인한다.
- 충돌을 해결할 때 상대 쪽 변경을 임의로 버리지 않는다. 의도가 불분명하면 확인한다.

## 상황별 규칙

Claude Code는 아래 규칙을 해당 파일을 읽을 때 자동으로 불러온다. 다른 에이전트는 작업 전에 해당하는 규칙 파일을 읽는다.

| 다루는 파일 | 규칙 (`.claude/rules/harness/`) |
|---|---|
| Swift 코드 | `swift.md`, `swiftui.md`, `concurrency.md`, `dependencies.md` |
| 테스트 코드, 테스트 플랜 | `testing.md` |
| 프로젝트 파일·빌드 설정(pbxproj, xcconfig, entitlements, Info.plist, manifest) | `project-settings.md` |
| Tuist manifest(`Project.swift`, `Workspace.swift`, `Tuist/`) | `tuist.md` |
