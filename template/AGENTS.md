# 프로젝트 이름

<!--
  설치한 뒤 이 프로젝트에 맞게 채우는 영역이다. 하네스를 갱신해도 이 영역은 바뀌지 않는다.
  - 소개: 무엇을 하는 앱인지 한두 문장
  - 구조: 주요 모듈·디렉터리와 역할. 길면 별도 문서로 두고 링크만 남긴다
  - 프로젝트 규칙: 이 프로젝트에만 있는 규칙. 특정 파일에만 해당하면 .claude/rules/project/에 paths를 달아 둔다
-->

이 앱이 무엇을 하는지 한두 문장으로 적는다.

## 구조

- 주요 모듈·디렉터리와 역할을 적는다.

## 프로젝트 규칙

- 이 프로젝트에만 있는 규칙을 적는다.

<!-- harness:begin — 이 아래는 하네스가 관리한다. 고칠 내용은 하네스 저장소의 template/AGENTS.md에 반영한다. -->

## 빌드·테스트

| 할 일 | 명령 |
|---|---|
| 코드를 바꾼 뒤 검증 (앱 빌드 + 바뀐 모듈 테스트) | `scripts/harness/verify` |
| 무엇을 돌릴지 미리 보기 | `scripts/harness/verify --plan` |
| PR 전에 브랜치 전체 변경 검증 | `scripts/harness/verify --base <기본 브랜치>` |
| 빌드만 | `scripts/harness/build` |
| 앱 단위 테스트 / 특정 스킴 테스트 | `scripts/harness/test` / `scripts/harness/test --scheme <스킴>` |
| 팀 컨벤션 검사 (바뀐 Swift 파일) | `scripts/harness/lint` |
| E2E 시나리오 / 회귀 묶음 / 수정 전후 영상 | `scripts/harness/e2e <파일>` / `scripts/harness/e2e --tag regression` / `--record` |
| 정책·결정 기록 찾기 / 형식 검사 | `scripts/harness/wiki search <단어>` / `scripts/harness/wiki check` |

- 스킴, 시뮬레이터, 프로젝트 생성 명령은 `.harness/project.json`에 있고 스크립트가 이 파일을 읽는다. `xcodebuild`를 직접 구성하지 않는다.
- 코드를 고치는 작업은 `task` 스킬(ios-harness 플러그인)로 시작한다. 계획할지(plan/simple)와 돌릴 검사는 사용자가 고르고, 단계마다 할 일은 하네스가 알려 준다. 검사 목록은 `.harness/checks.json`에 있다.
- `task` 없이 작업했으면 코드를 바꾼 뒤 `verify`와 `lint`를 돌린다. 컨벤션을 지켰는지는 스스로 판단하지 말고 `lint` 결과로 확인한다.
- 실패하면 출력에 나온 첫 에러의 위치부터 고친다. 전체 로그와 결과 번들은 `.harness/out/`에 있다.
- 동작·스펙을 바꾸기 전에 `scripts/harness/wiki search <단어>`로 관련 정책·결정 기록(`docs/wiki/`)을 찾아 읽는다. 기록과 다르게 바꿔야 하면 사용자에게 먼저 묻는다.
- 결과는 실제로 실행한 명령과 출력으로 보고한다. 실행하지 못한 검증은 못 했다고 밝힌다.
- PR을 만들기 전에는 `ios-reviewer` 서브에이전트(ios-harness 플러그인)에 변경 검토를 맡기고, 차단 항목을 고친 뒤 올린다.

## 꼭 지킬 규칙

위의 프로젝트 규칙이 아래와 다르면 프로젝트 규칙을 따른다.

- 기존 아키텍처와 패턴을 우선 존중한다. 요청받지 않은 대규모 refactor는 하지 않고, 변경 범위를 작게 유지한다.
- 검증을 통과시키려고 설정을 완화하거나 테스트를 약화하지 않는다.
- 커밋, push, PR 생성·머지는 사용자가 요청하거나 승인한 뒤에 한다. 커밋 전에는 메시지와 대상 파일을 먼저 보여준다.
- 사용자가 명시적으로 요청하지 않으면 파괴적인 git 명령을 쓰지 않는다: `push --force`, `reset --hard`, `clean -fd`, `checkout -- .` / `restore .`, `branch -D`, 이미 push된 브랜치의 rebase.
- `--no-verify` 등으로 훅을 우회하지 않는다. 훅이 막으면 원인을 해결한다.
- 파일을 지정해 스테이징한다. 비밀 정보(API 키, 인증서, 프로비저닝 프로파일, `.env`)와 생성 산출물은 커밋하지 않는다.
- 커밋 메시지와 브랜치 이름은 프로젝트의 기존 관례를 따른다. 모르면 `git log`로 확인한다.
- 충돌을 해결할 때 상대 쪽 변경을 임의로 버리지 않는다. 의도가 불분명하면 확인한다.

## 상황별 규칙

Claude Code는 아래 규칙을 해당 파일을 읽을 때 자동으로 불러온다. 다른 에이전트는 작업 전에 해당하는 규칙 파일을 읽는다.

| 다루는 파일 | 규칙 |
|---|---|
| Swift 코드 | `.claude/rules/harness/swift.md`, `swiftui.md`, `concurrency.md`, `dependencies.md` |
| 테스트 코드, 테스트 플랜 | `.claude/rules/harness/testing.md` |
| 프로젝트 파일·빌드 설정(pbxproj, xcconfig, entitlements, Info.plist, manifest) | `.claude/rules/harness/project-settings.md` |
| Tuist manifest(`Project.swift`, `Workspace.swift`, `Tuist/`) | `.claude/rules/harness/tuist.md` |
| 팀 컨벤션 목록(`.harness/conventions.json`) | `.claude/rules/harness/conventions.md` |
| E2E 시나리오(`.maestro/`) | `.claude/rules/harness/maestro.md` |
| 정책·결정 기록(`docs/wiki/`) | `.claude/rules/harness/wiki.md` |
| 이 프로젝트에만 있는 규칙 | `.claude/rules/project/` |

<!-- harness:end -->
