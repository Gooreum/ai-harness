# 프로젝트 스크립트

각 프로젝트에 설치되는 하네스 스크립트(`template/scripts/harness/`)의 동작 방식이다. 설치되면 `scripts/harness/`가 된다.
에이전트·사람·CI가 같은 스크립트를 쓴다. 하네스는 빌드·테스트 도구를 갖지 않는다. 그런 명령은 프로젝트가 갖고, 하네스는 `record`로 돌려 결과를 남기고 `passed`로 확인한다([ADR 0024](decisions/0024-no-platform.md)).

| 스크립트 | 하는 일 |
|---|---|
| `record` | 아무 명령이나 돌려 결과를 남긴다 |
| `passed` | 결과가 통과했고 최신인지 본다. `checks.json`의 run에 쓴다 |
| `wiki` | 정책·결정 기록을 찾고 형식을 검사한다 |
| `doctor` | 하네스가 이 프로젝트에서 돌 수 있는지 점검한다 |
| `setup` | 설정을 사용자와 정하는 안내를 낸다 |
| `pr-video` | 이번 작업에서 찍은 영상을 PR에 올릴 크기로 바꾼다 |
| `lib.sh` | 위 스크립트가 `source`로 불러 쓰는 공통 함수 |
| `common-checks.json` | setup이 추천하는 검사(review)와 위키 단계 지시(`stages`) |

## 공통

- **프로젝트 루트**: 현재 디렉터리에서 git 최상위까지 올라가며 가장 가까운 `.harness/project.json`이 있는 폴더다. 없으면 git 최상위. `HARNESS_ROOT`로 바꿀 수 있다. 모노레포 하위 폴더(`apps/mobile/`)에 설치해도 그 폴더 기준으로 돈다. 바뀐 파일도 루트 안의 것만 루트 기준 경로로 본다(`git diff --relative`). 훅과 같은 기준이다([ADR 0020](decisions/0020-install-checks-permissions-root.md)).
- **출력**: 성공하면 한 줄, 실패하면 원인을 찾는 데 필요한 만큼만 출력한다. 전체 로그는 파일로 남기고 경로만 알려준다.
- **산출물 위치**

  | 경로 | 내용 |
  |---|---|
  | `.harness/out/` | 마지막 실행의 결과(`<이름>.json`)와 로그(`<이름>.log`). 실행할 때마다 덮어쓴다 |
  | `.harness/state/` | 다음 실행이 참고하는 로컬 상태(작업 상태, 작업 시작 시각·커밋, 검색 기록 등) |

  - `.harness/.gitignore`가 설정 파일과 설치 기록만 남기고 나머지를 무시한다.
- **종료 코드**: 스크립트마다 아래에 적었다. 설정·인자 오류는 모두 2다.

## record

```bash
scripts/harness/record typecheck npm run typecheck
scripts/harness/record lint "npm run lint -- --max-warnings 0"   # 하나로 묶으면 bash -c로 실행
scripts/harness/record unit-test scripts/ios/unit-test          # 저장소가 감싼 스크립트도 같다
```

- 저장소의 검사 명령(typecheck, jest, bats, 빌드 등)을 돌리고 결과를 남긴다. ai-bouncer `bouncer record`와 같은 짝이다([ADR 0018](decisions/0018-core-and-packs.md)).
- 프로젝트 루트에서 `CI=1`, 입력 없이 실행한다. 감시 모드나 질문으로 멈추지 않게 한다.
- 결과 파일 `.harness/out/<이름>.json`: `passed`, `summary`, `exit`(종료 코드), `command`, `seconds`. 시작할 때 이전 결과를 지운다.
- 전체 출력은 `.harness/out/<이름>.log`. 화면에는 성공하면 한 줄, 실패하면 끝 30줄(`HARNESS_RECORD_TAIL`)과 로그 경로를 보여 준다.

  ```
  ✓ typecheck · 통과 · 12s
  ✗ unit-test · 실패 (종료 코드 65) · 48s
    (출력 812줄 중 끝 30줄. 전체는 .harness/out/unit-test.log)
    …
    로그: .harness/out/unit-test.log
  ```

- 검사 이름은 영문·숫자·`-`·`_`만 쓴다. 종료 코드는 명령의 종료 코드, 인자 오류는 2.
- `checks.json`에는 prompt에 `record <이름> <명령>`을, run에 `passed <이름>`을 적는다.
- 출력이 길어 끝 30줄로도 원인이 안 보이는 명령(예: `xcodebuild`)은 프로젝트가 감싸는 스크립트를 둔다. setup이 만들어 줄지 묻는다. 성공하면 한 줄, 실패하면 첫 에러의 위치를 보여 주고 전체 로그는 파일로 남기는 형태다. 그 스크립트를 `record`로 부른다.
- 저장소의 도구가 같은 형식의 결과 파일(`passed`, `summary`)을 직접 남기면 `record` 없이 불러도 된다(예: 넘겨받은 iOS 스크립트).

## passed

```bash
scripts/harness/passed unit-test   # .harness/out/unit-test.json이 통과했고 최신이면 0
```

- `checks.json`의 `run`에 쓴다([ADR 0012](decisions/0012-run-gate.md)). 검사를 돌리지 않고 결과 파일만 본다.
- 통과 조건: 결과 파일이 있고, `passed`가 참이고, 최신이다.
  - 이번 작업을 시작한 뒤의 결과여야 한다. 작업 시작 시각은 단계 지시 훅이 `.harness/state/task.started`에 남긴다.
  - 바뀐 파일 중 결과 파일보다 나중에 고친 것이 없어야 한다. 바뀐 파일은 작업을 시작한 커밋(`.harness/state/task.base`)부터 본다.
  - 이 기준은 발표에 없어 ai-bouncer의 `bouncer passed`를 따랐다.
- 실패하면 이유 한 줄(없음, 통과 못 함, 어느 파일보다 오래됨)을 출력하고 2로 끝난다.

## wiki

```bash
scripts/harness/wiki search <단어>...   # 정책·결정 기록 찾기
scripts/harness/wiki check [파일...]     # 기록 형식 검사
```

- 기록 형식과 쓰는 때는 [wiki.md](wiki.md)에 있다.
- search 결과는 한 줄에 `종류	경로	제목`이다. 내용은 그 파일을 열어 읽는다. 검색마다 `.harness/state/wiki-search.log`에 남긴다.
- 종료 코드: search는 찾으면 0, 없으면 1. check는 문제가 없으면 0, 있으면 1. 인자 오류 2

## doctor

하네스가 이 프로젝트에서 돌 수 있는지 점검한다. 파일은 고치지 않는다.

```bash
scripts/harness/doctor
```

- 도구(jq, 가짜 응답 서버를 쓰면 python3), 설정 파일, 검사 목록의 run, 지침 연결(AGENTS.md 관리 블록, `@AGENTS.md`), 공유되지 않는 설정, 플러그인 버전을 본다. 항목은 [template.md](template.md#점검-scriptsharnessdoctor)에 있다.
- 문제(✕)가 있으면 1, 주의(!)만 있거나 문제가 없으면 0으로 끝난다. 문제마다 고치는 방법을 한 줄 붙인다.
- 설치 직후, setup을 마친 뒤, 팀원이 처음 프로젝트를 받았을 때, 훅이나 스킬이 동작하지 않을 때 돌린다.
- 플랫폼 도구(Xcode, Node 등)는 보지 않는다. 그 도구가 없으면 그 검사의 `record`가 실패해 알려 준다.

## setup

`scripts/harness/setup`은 이 저장소의 하네스 설정을 사용자와 정하는 안내를 출력한다. 파일은 쓰지 않는다. Claude 세션에서 "scripts/harness/setup 안내대로 설정해 줘"라고 하면 에이전트가 안내대로 묻고 답을 쓴다. ai-bouncer `bouncer setup`을 따른다([ADR 0020](decisions/0020-install-checks-permissions-root.md), [ADR 0024](decisions/0024-no-platform.md)).

- 보여 주는 것
  - 하네스 추천 검사: `common-checks.json`의 review
  - 위키 단계 지시가 `checks.json`에 있는지: 있다 / 쓰지 않기로 했다(`"wiki": false`) / 없다
  - 저장소에서 찾은 명령과 근거: package.json scripts(lock 파일로 npm·pnpm·yarn·bun을 고른다), jest·vitest가 있으면 바뀐 파일과 관련된 테스트만 도는 명령, Makefile, pytest·ruff, go, cargo, gradlew, `tests/run.sh`·`tests/run-all.sh`, `*.bats`, `Package.swift`, 그리고 `scripts/` 아래의 실행 파일(`scripts/harness/`와 `.sh`는 뺀다)
  - 생성 파일·보호할 파일의 단서: Tuist manifest, XcodeGen `project.yml`, xcodeproj(pbxproj), Expo이고 git이 무시하는 `ios/`·`android/`, OpenAPI·GraphQL·codegen 설정
  - 앱을 띄워 확인하는 테스트(E2E)의 단서: 찾은 명령의 e2e, `.maestro/`, Playwright·Cypress·Detox 설정. 없으면 없다고 보여 준다
- 묻는 것(AskUserQuestion, 한 번에 4개까지)과 쓰는 곳

  | 묻는 것 | 쓰는 곳 |
  |---|---|
  | 작업마다 고를 검사 | `.harness/checks.json`. 찾은 명령은 `record`로 돌리고 run은 `passed`로 본다 |
  | 자동 생성 파일 | `.harness/project.json`의 `generated` |
  | 에이전트가 직접 고치면 안 되는 파일 | `.claude/settings.json`의 `permissions.deny`에 `Edit(<글롭>)`. 예: `Edit(**/*.pbxproj)` |
  | 출력이 너무 길거나 여러 단계를 거치는 명령 | 감싸는 스크립트를 이 저장소의 `scripts/`에 만든다. `scripts/harness/`는 하네스가 관리하므로 피한다 |
  | E2E가 없으면 둘지 (앱·웹·서버처럼 띄워 볼 수 있는 저장소만) | 도구와 앱을 띄우는 방법을 묻고, 시나리오 하나를 통과시킨 뒤 `checks.json`에 e2e 검사로 적는다 |
  | 위키 단계 지시가 없으면 둘지 (추천) | 두면 `common-checks.json`의 `stages`(plan·implement: 찾기, finish: 쓰기)를 `checks.json`의 `stages`에 합친다. 이미 있는 prompt는 지우지 않고 위키 문장을 앞에 붙인다. 두지 않으면 `"wiki": false` |
  | (정한 결과) 빌드·테스트 명령 | AGENTS.md 프로젝트 영역의 "빌드·테스트" |

- 단서는 보여 주기만 한다. 맞는지는 사용자에게 묻고, 정하는 것은 사용자의 답이다.
- 팀 코딩 규칙이 있다고 하면 `.claude/rules/project/<이름>.md`에 `paths`를 달아 둔다.
- 이미 `checks.json`이 있으면 지금 검사와 `generated`를 보여 주고 바꿀 부분만 묻게 한다.
- 마지막에 `doctor`로 확인하고, 쓴 내용을 보여 주고 커밋해야 한다고 알린다.
- AskUserQuestion을 쓸 수 없는 세션이면 묻지 않고 추천 검사만으로 `checks.json`을 쓴다. 다른 설정은 쓰지 않는다.

## pr-video

PR을 만들 때 이번 작업에서 찍은 영상을 올릴 수 있게 준비한다. 발표 슬라이드 87처럼 리뷰어가 앱을 실행하지 않고 PR에서 수정 결과를 보게 한다([ADR 0029](decisions/0029-pr-video.md)).

```bash
scripts/harness/pr-video
```

- 고르는 영상: `.harness/out/*.mp4` 중 이번 작업을 시작한 뒤(`.harness/state/task.started`)에 생긴 것. `task.started`가 없으면 전부 고른다.
- 바꾸는 방법: macOS 기본 도구 `avconvert`로 H.264로 바꾼다. HEVC로 녹화한 영상은 Chrome에서 재생되지 않을 수 있어서다. 960×540 프리셋으로 바꾸고, 9.5MB 이상이면 640×480으로 다시 바꾼다. 9.5MB는 GitHub 무료 요금제의 영상 한도 10MB에 여유를 둔 값이다. 그래도 크면 같은 길이로 나눈다.
- 출력: 한 줄에 하나씩 `<제목><탭><파일 경로>`. `<이름>-before.mp4`는 `수정 전`, 나머지는 `수정 후`이고 수정 전이 먼저 나온다. `수정 후`가 둘 이상이면 영상마다 제목 뒤에 파일 이름을 붙인다(`수정 후 (e2e)`). 나눈 영상은 끝에 `(1/3)`처럼 순서를 붙인다. 파일은 `.harness/out/pr-video/`에 둔다.
- 종료 코드: 올릴 영상이 없으면 아무것도 출력하지 않고 0. `avconvert`가 없거나, 변환에 실패하거나, 나눠야 하는데 길이를 읽지 못하거나, 나눠도 9.5MB 이상이면 2.
- 올리는 일은 에이전트가 template `AGENTS.md`의 안내대로 한다. GitHub PR 본문에서 영상으로 재생되는 링크는 웹에서 올린 첨부(`user-attachments`)뿐이고 `gh`나 API로는 올릴 수 없다. 그래서 Chrome으로 PR 본문 편집 칸을 열어 파일을 첨부하고 저장한다.

## 예전 iOS 스크립트

0.11.x까지는 iOS 묶음의 `build`·`test`·`unit-test`·`lint`·`e2e`(와 `ios.sh`·`ios-doctor.sh`)가 여기 있었다. 프로젝트 생성 판단(Tuist·XcodeGen), 시뮬레이터·Xcode 고르기, `xcresulttool` 요약, 바뀐 모듈의 테스트 고르기, SwiftLint·swift-format·`tuist graph`로 컨벤션 검사, Maestro e2e와 행동 로그 판정을 했다.

- 단위 31에서 하네스 밖으로 옮겼다([ADR 0024](decisions/0024-no-platform.md)). 코드와 이 문서의 예전 스펙은 git 기록(0.11.2)에 있다.
- 그 묶음을 쓰던 프로젝트는 sync가 스크립트를 `scripts/ios/`로 넘긴다(쓰던 `lib.sh` 사본과 함께). 그 뒤로는 프로젝트 코드라 하네스가 갱신하지 않는다([template.md](template.md#예전-ios-묶음을-쓰던-프로젝트)).
- 넘어간 스크립트는 결과 파일(`.harness/out/<이름>.json`)을 직접 남긴다. 그래서 `checks.json`에서 `record` 없이 부르고 run은 `passed <이름>`이다.
