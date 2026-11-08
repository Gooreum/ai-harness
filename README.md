# ai-harness

여러 프로젝트에서 재사용하는 **AI 코딩 에이전트용 하네스**다. 플랫폼(iOS, Android, 웹 등)을 가리지 않는다.
처음 보는 사람이 이 문서 하나로 전체 구조와 동작 방식을 파악할 수 있게 썼다. 세부 스펙은 문서마다 링크로 연결해 두었다.

> **하네스 노트:** 시험장에서 만난 문제(문제·원인·해결·결과와 비유)와 하네스를 만들며 물었던 질문과 답을 모았다 → [docs/problem-notes.md](docs/problem-notes.md)

## 이게 뭔가

AI 코딩 에이전트(Claude Code, Codex 등)는 프로젝트에서 자주 같은 실수를 한다.

- 빌드·테스트 명령을 매번 추측해서 만든다.
- 수 MB짜리 빌드 로그를 통째로 읽느라 컨텍스트를 낭비한다.
- 도구가 만든 파일(Tuist가 만든 `.xcodeproj`, Expo prebuild의 `ios/`, codegen 결과)을 직접 고친다. 다시 생성하면 사라진다.
- 테스트를 통과시키려고 assertion을 약하게 바꾸거나 경고를 덮는다.
- 검사를 돌리지 않고 "통과했다"고 보고한다.
- 사용자 확인 없이 `git push`나 `reset --hard`를 실행한다.

**하네스**는 에이전트에서 모델을 뺀 나머지 전부를 말한다. 에이전트가 읽는 지침, 쓰는 도구, 결과를 확인하는 수단, 행동을 막는 장치가 모두 하네스다.
이 저장소는 그중 어느 프로젝트에나 공통으로 쓸 수 있는 부분을 만들고, 각 프로젝트에 설치한다.

하네스는 프로젝트가 어떤 플랫폼·도구를 쓰는지 모른다([ADR 0024](docs/decisions/0024-no-platform.md)). 빌드·테스트 명령, 생성 파일, 고치면 안 되는 파일은 설치한 뒤 `scripts/harness/setup` 안내대로 사용자가 답해서 정한다.

## 용어

| 용어 | 뜻 |
|---|---|
| 대상 프로젝트 | 하네스를 설치해서 쓰는 앱 저장소. 예: ReadSharp(iOS) |
| 프로젝트 설정 파일 | 대상 프로젝트의 `.harness/project.json`. 생성 파일 목록(`generated`)처럼 프로젝트마다 다른 사실을 모아 둔 JSON |
| 검사 목록 | 대상 프로젝트의 `.harness/checks.json`. 작업마다 고를 수 있는 검사와, 각 검사의 할 일(`prompt`)·확인 명령(`run`)을 적은 JSON |
| AGENTS.md | 에이전트가 세션을 시작할 때 읽는 지침 파일. Claude Code는 `CLAUDE.md`가 `@AGENTS.md`로 불러와야 읽는다 |
| 경로 규칙 | `.claude/rules/` 아래의 마크다운 규칙. 머리말의 `paths:`와 맞는 파일을 에이전트가 읽을 때만 컨텍스트에 들어온다. 예: `docs/wiki/` 아래 파일을 열면 `wiki.md`가 함께 들어온다 |
| 훅 | 에이전트가 도구를 쓰기 직전·직후나 멈출 때 Claude Code가 실행하는 스크립트. 금지된 편집을 막거나, 단계 지시를 넣거나, 검사를 통과하기 전에 끝내지 못하게 한다 |
| 권한 규칙 | `.claude/settings.json`의 `deny`(항상 거부) 목록. `ask`(매번 물음)는 두지 않는다([ADR 0026](docs/decisions/0026-no-ask-rules.md)) |
| 서브에이전트 | 메인 에이전트가 일을 맡기는 별도 에이전트. 자기만의 지시문과 도구 목록을 가진다 |
| 플러그인·마켓플레이스 | Claude Code 플러그인은 훅·서브에이전트·스킬을 묶어 여러 프로젝트에 배포하는 단위다. 마켓플레이스는 플러그인 목록이고, 이 저장소 자체가 마켓플레이스 역할을 한다 |
| 시험장 | 하네스를 실제로 돌려 보는 프로젝트. 지금은 ReadSharp(`EnglishStudy`)의 `EnglishStudy-harness` 워크트리다. 이전 단위는 MotoTrace에서 했다 |

## 하네스 계층

구성요소를 하는 일에 따라 다섯 층으로 나눈다. 자세한 기준은 [docs/principles.md](docs/principles.md)에 있다.

| 계층 | 하는 일 | 이 저장소에서 |
|---|---|---|
| Context (가이드) | 행동하기 전에 알려준다 | `AGENTS.md`, 경로 규칙, 단계 지시 훅 |
| Execution (실행 도구) | 에이전트가 일을 하는 손 | `scripts/harness/record`(아무 명령이나 돌리고 결과를 남긴다). 빌드·테스트 도구는 프로젝트가 갖는다 |
| Validation (센서) | 결과가 맞는지 판정한다 | 결정적: `record`로 남긴 검사 결과와 `passed` / 추론적: `reviewer` 코드 리뷰 |
| Enforcement (강제) | 모델 판단과 상관없이 막는다 | 생성 파일 편집 차단 훅, run 확인·Stop 게이트 훅, 권한 규칙 |
| State (설정·상태) | 위 계층이 함께 쓰는 데이터 | `.harness/project.json`, `.harness/checks.json`, 작업 상태(`.harness/state/task.json`) |

- **결정적 검증**은 같은 입력이면 항상 같은 결과를 낸다(컴파일러, 테스트). 코드가 동작하는지는 이것만 확실히 판정한다.
- **추론적 검증**은 LLM이 판단한다(코드 리뷰). 설계·규칙 위반을 잡지만 결정적 검증을 대신하지 못한다.

## 한눈에 보기

저장소는 세 덩어리로 나뉜다. **복사해서 설치하는 것**, **플러그인으로 켜는 것**, **설치하는 도구**다.

```
ai-harness (이 저장소)                         대상 프로젝트
───────────────────────────                       ─────────────────────────────
scripts/init·sync ──────┐
                        │  복사·병합
template/ ──────────────┴────────────────────────▶ AGENTS.md, CLAUDE.md
                                                    .claude/rules/harness/*.md
                                                    .claude/settings.json
                                                    scripts/harness/*
                                                    .harness/project.json, .gitignore, harness.json

plugin/ ─── GitHub 마켓플레이스에서 설치 (복사 안 함) ──▶ 훅, task 스킬, reviewer, 가짜 응답 MCP
            (.claude/settings.json에 등록)

                          설치 뒤 Claude 세션에서 setup ──▶ .harness/checks.json, project.json의 generated,
                          (사용자에게 묻고 답을 쓴다)          settings.json의 Edit 금지, AGENTS.md 빌드·테스트
```

- `template/`의 파일은 프로젝트에 **복사**된다. 프로젝트 저장소에 커밋되므로 사람·CI·다른 에이전트도 같은 스크립트를 쓴다.
- `plugin/`은 **복사하지 않는다.** 프로젝트의 `.claude/settings.json`에 이 저장소(GitHub)가 마켓플레이스로 등록돼 있어서, 팀원이 프로젝트를 열면 Claude Code가 플러그인 설치를 권한다. 여러 프로젝트에 같은 훅과 리뷰어를 적용하기 위해서다(발표 슬라이드 38).
- 프로젝트 파일과 플러그인은 같은 버전이어야 한다. 설치한 버전은 `.harness/harness.json`에 남고, 프로젝트 안에서 `scripts/harness/doctor`가 둘을 비교한다.
- 프로젝트마다 다른 것은 프로젝트의 설정 파일(`project.json`, `checks.json`)과 AGENTS.md 프로젝트 영역에만 있다. 그래서 하네스 스크립트·훅·지침은 모든 프로젝트에서 글자 하나 다르지 않다.

## 동작 흐름

### 1. 설치

```bash
scripts/init ~/path/to/MyApp     # 처음 설치
scripts/sync ~/path/to/MyApp     # 하네스를 고친 뒤 갱신
```

1. `.harness/project.json`이 없으면 `{ "schemaVersion": 2 }`만 쓴다. 플랫폼은 묻지 않는다.
2. `template/`의 파일을 프로젝트에 맞춘다.
   - `scripts/harness/`, `.claude/rules/harness/`, `.harness/.gitignore`는 template과 똑같이 맞춘다. 지난번에 설치했는데 template에서 사라진 파일만 지운다. 팀이 넣은 스크립트는 남는다.
   - `AGENTS.md`는 하네스 관리 블록만 넣거나 바꾼다. 프로젝트가 쓴 부분은 건드리지 않는다.
   - `.claude/settings.json`에는 권한 규칙을 중복 없이 합친다. 프로젝트의 기존 설정은 유지한다. 지난번에 하네스가 넣었는데 이제 없는 규칙만 지운다.
   - `.harness/checks.json`은 쓰지 않는다. 없으면 Claude 세션에서 `scripts/harness/setup` 안내대로 정하라고 알린다.
3. `.claude/settings.json`에 GitHub 마켓플레이스(`Gooreum/ai-harness`)를 등록하고 플러그인 `harness`를 켠다. 설치한 하네스 버전은 `.harness/harness.json`에 적는다.
   - `--dev`를 주면 `.claude/settings.local.json`에서 이 저장소 디렉터리를 마켓플레이스로 덮어쓴다. 하네스를 고치며 시험장에서 바로 확인할 때 쓴다.
4. 바꾼 파일 목록과 사람이 직접 할 일을 출력한다. 예: "AGENTS.md 프로젝트 영역을 채운다", "검사 목록이 없다. setup 안내대로 정한다"

`init`은 이미 설치된 프로젝트를, `sync`는 설치되지 않은 프로젝트를 거절한다. 둘 다 여러 번 실행해도 결과가 같다.

예전 버전(0.11.x까지)에는 iOS 묶음(빌드·테스트·린트·e2e 스크립트와 Swift 규칙)이 있었다. 그 묶음을 설치한 프로젝트를 sync하면 지우지 않고 프로젝트 코드로 넘긴다. 스크립트는 `scripts/ios/`로, 규칙은 `.claude/rules/project/ios/`로 옮기고, 그 뒤로는 하네스가 갱신하지 않는다([template.md](docs/template.md#예전-ios-묶음을-쓰던-프로젝트)).

### 2. 설정: setup

설치한 뒤 프로젝트에서 Claude를 열고 이렇게 말한다.

```
scripts/harness/setup 안내대로 설정해 줘
```

`setup`은 파일을 쓰지 않고 안내만 출력한다. 에이전트가 안내대로 사용자에게 묻고(AskUserQuestion), 답을 파일에 쓴다. ai-bouncer의 `bouncer setup`을 따랐다([ADR 0020](docs/decisions/0020-install-checks-permissions-root.md), [ADR 0024](docs/decisions/0024-no-platform.md)).

- 보여 주는 것: 하네스 추천 검사(review), 저장소에서 찾은 명령(`package.json` scripts, Makefile, pytest, go, cargo, gradlew, `Package.swift` 등과 `scripts/` 아래 실행 파일), 생성 파일 단서(Tuist manifest, `project.yml`, xcodeproj, Expo가 무시하는 `ios/`·`android/`, codegen 설정)
- 묻는 것과 쓰는 곳

  | 묻는 것 | 쓰는 곳 |
  |---|---|
  | 작업마다 고를 검사 | `.harness/checks.json` |
  | 도구가 만드는 파일 | `.harness/project.json`의 `generated` (훅이 편집을 막는다) |
  | 에이전트가 직접 고치면 안 되는 파일(예: `project.pbxproj`) | `.claude/settings.json`의 `permissions.deny`에 `Edit(<글롭>)` |
  | 출력이 너무 긴 명령 | 감싸는 스크립트를 저장소의 `scripts/`에 만든다 (하네스가 관리하는 `scripts/harness/`는 피한다) |
  | 앱을 띄워 확인하는 테스트(E2E)가 없을 때 둘지 | 시나리오 하나를 통과시킨 뒤 `.harness/checks.json`에 e2e 검사로 |
  | 정한 빌드·테스트 명령 | `AGENTS.md` 프로젝트 영역의 "빌드·테스트" |

- 단서는 보여 주기만 한다. 정하는 것은 사용자의 답이다.
- 마지막에 `scripts/harness/doctor`로 문제가 없는지 확인한다. 쓴 파일은 커밋해야 팀원에게 간다.

### 3. 세션 시작: 항상 읽히는 지침

에이전트가 세션을 시작하면 `CLAUDE.md` → `@AGENTS.md` 순서로 지침을 읽는다. 대상 프로젝트의 AGENTS.md는 두 영역으로 나뉜다.

| 영역 | 내용 | 누가 고치나 |
|---|---|---|
| 프로젝트 영역 (위쪽) | 앱 소개, 구조, 빌드·테스트 명령, 프로젝트 고유 규칙 | 각 프로젝트 |
| 하네스 관리 블록 (`<!-- harness:begin -->` ~ `<!-- harness:end -->`) | 하네스 명령 표, 꼭 지킬 규칙, 상황별 규칙 표 | 이 저장소의 `template/AGENTS.md` |

- 두 영역이 충돌하면 프로젝트 규칙을 따른다.
- 매 세션 컨텍스트를 차지하므로 100줄 이하로 유지한다. 특정 파일에만 필요한 규칙은 경로 규칙으로 뺀다.

### 4. 코드 작업: 필요할 때만 들어오는 규칙

에이전트가 파일을 읽으면 그 파일에 맞는 경로 규칙이 자동으로 컨텍스트에 들어온다.

| 에이전트가 읽은 파일 | 함께 들어오는 규칙 |
|---|---|
| `docs/wiki/` 아래 정책·결정 기록 | `.claude/rules/harness/wiki.md` (하네스가 관리) |
| 프로젝트가 정한 경로 | `.claude/rules/project/**/*.md` (프로젝트가 관리. 예: Swift 규칙, 리뷰 항목) |

### 5. 검증: record · passed

하네스는 빌드·테스트 도구를 갖지 않는다. 에이전트는 프로젝트의 명령을 `record`로 돌리고, 하네스는 그 결과 파일만 본다(발표 슬라이드 27 "훅은 검사 내용을 몰라요").

```bash
scripts/harness/record typecheck npm run typecheck
scripts/harness/record unit-test scripts/ios/unit-test      # 저장소가 감싼 스크립트도 그대로
scripts/harness/passed typecheck                            # 결과가 통과했고 최신이면 0
```

- `record`는 명령을 프로젝트 루트에서 돌리고 결과를 `.harness/out/<이름>.json`에, 전체 출력을 `.harness/out/<이름>.log`에 남긴다.
- 화면 출력은 에이전트가 읽기 좋게 줄인다. 성공하면 한 줄, 실패하면 로그 끝 30줄과 로그 경로다.

  ```
  ✓ typecheck · 통과 · 12s
  ✗ unit-test · 실패 (종료 코드 65) · 48s
    …
    로그: .harness/out/unit-test.log
  ```

- `passed`는 결과 파일의 `passed`가 참이고, 이번 작업을 시작한 뒤의 결과이며, 그 뒤에 고친 파일이 없을 때만 통과다. 기준은 ai-bouncer의 `bouncer passed`와 같다.
- 출력이 너무 긴 명령(예: `xcodebuild`)은 setup에서 정한 감싸는 스크립트로 줄인다. 첫 에러의 위치부터 보여 주고 전체 로그는 파일로 남긴다. 그 스크립트는 프로젝트 코드다.

자세한 내용은 [docs/scripts.md](docs/scripts.md)에 있다.

### 6. 막는 장치: 훅과 권한 규칙

모델이 지침을 잊어도 위험하거나 되돌리기 어려운 행동은 막는다. 왜 이렇게 나눴는지는 [ADR 0004](docs/decisions/0004-enforcement.md)에 있다.

| 장치 | 막는 것 | 방식 |
|---|---|---|
| 훅 `protect-generated.sh` (플러그인) | `.harness/project.json`의 `generated` 글롭에 맞는 파일 편집 | 편집 직전에 거부하고, 생성하는 쪽을 고치라고 알려준다 |
| 권한 `deny` (`settings.json`) | 서명·시크릿 파일 읽기(`.env*`(Bash로 읽기 포함), `*.jks`, `*.keystore`, `keystore.properties`, `.npmrc`, `credentials.json`). setup에서 정한 `Edit(<글롭>)`(예: `Edit(**/*.pbxproj)`) | 항상 거부 |

- 훅은 stdin으로 받은 JSON만 읽는다. 나중에 Codex에서도 같은 스크립트를 쓰기 위해서다.
- 훅은 판단할 수 없으면(설정 파일 없음, 입력 오류) 막지 않는다. 실수를 줄이는 장치이지 보안 경계가 아니라서, 고장 난 훅이 정상 작업을 막으면 안 된다.
- 무엇이 생성 파일인지 훅은 모른다. 프로젝트가 `generated`에 적은 것만 막는다. 생성물은 아니지만 손으로 고치면 깨지는 파일(pbxproj 등)은 권한 규칙으로 막는다.
- 검사를 통과했는지는 Stop 훅 `stop-gate.sh`가 확인한다. 아래 7의 run 확인이다.

### 7. 작업 흐름: task

코드를 고치는 작업은 플러그인 스킬 `task`로 시작한다. 사람이 처음에 두 가지만 정한다: 계획이 필요한 일인지(plan / simple)와 이번 작업에 돌릴 검사다.

- plan: 계획 → 구현 → 검증 → 마무리, simple: 구현 → 검증 → 마무리
- 에이전트가 단계의 일을 마치고 응답을 마치려 하면, Stop 훅이 확인하고 `.harness/state/task.json`의 `stage`를 다음 단계로 넘기며 그 단계의 지시를 준다. 검증 단계에는 고른 검사의 지시만 들어간다. 에이전트는 `stage`를 고칠 수 없다(`guard-state.sh`, Bash 쓰기 포함, [ADR 0027](docs/decisions/0027-stop-advances-stage.md)).
- 검사 목록은 프로젝트의 `.harness/checks.json`에 있다. 훅은 검사 내용을 모르고 이 파일의 글을 옮길 뿐이다([docs/checks.md](docs/checks.md), [ADR 0007](docs/decisions/0007-task-flow.md)).
- 검증 단계에서 응답을 마치려 하면 Stop 훅 `stop-gate.sh`가 고른 검사의 `run`(결과 파일 확인)을 돌린다. 실패하면 넘어가지 못한다(발표 슬라이드 29, [ADR 0012](docs/decisions/0012-run-gate.md)). 작업을 시작한 세션만 done 전에 막는다. 계획 승인은 Plan 모드로 받는다.
- 마무리 단계에서는 바꾼 파일을 커밋하고 push한다(기본 브랜치면 새 브랜치). Stop 훅이 커밋·push를 확인한 뒤 작업을 닫는다. 시작 전부터 있던 무관한 변경은 그대로 둔다([ADR 0028](docs/decisions/0028-finish-commit-push.md)).
- 마무리 보고는 일곱 섹션으로 쓴다: 상황 · 조치 · 평가 · 단계 기록 · 위키 · 건의 · 결정 사항. 평가는 검사마다 결과 파일을 근거로 쓰고, 마지막 줄은 커밋·push(브랜치·해시)다.
- "단계 기록"은 에이전트의 기억이 아니라 훅이 남긴 `.harness/state/task.history`(시작·넘김·차단·막은 쓰기·풀어 줌)를 옮긴다([docs/checks.md](docs/checks.md#단계-기록-harnessstatetaskhistory)).

### 8. 리뷰: reviewer

PR을 만들기 전에 메인 에이전트가 플러그인의 서브에이전트 `reviewer`에게 변경 검토를 맡긴다.

1. `git diff HEAD`, `git status --porcelain`으로 바뀐 파일을 찾는다.
2. 바뀐 파일을 하나씩 연다. 이때 경로 규칙이 함께 들어와서 그 규칙에 비춰 본다.
3. 바뀐 것의 참조처를 찾아 기존 동작 영향을 본다. 의심되는 부분은 주변 코드와 빌드 설정을 읽어 확인한다.
4. `[차단|권장|참고] 경로:줄 — 문제`, 근거, 제안을 보고한다. 마지막에 실제로 연 파일과 규칙을 적는다.

- 공통 중점 항목: 버그·로직 오류, 기존 동작 영향, 테스트 약화·검사 끄기 같은 편법, 의존·구조, 과설계
- 플랫폼별 항목은 프로젝트 규칙(`.claude/rules/project/**/*.md`)에서 읽는다. 예: 넘겨받은 iOS 프로젝트의 `.claude/rules/project/ios/review.md`
- 리뷰어를 정말 불렀고 바뀐 파일을 다 열었는지는 훅 `review-record.sh`가 기록하고, `passed review`가 그 기록을 본다([ADR 0016](docs/decisions/0016-review-record.md)).
- 도구는 Read·Grep·Glob·Bash뿐이고 코드를 고치지 않는다.
- Claude Code 안에서 도는 서브에이전트다. 메인 세션과 같은 모델을 쓰고(`model: inherit`), Codex를 부르지 않는다.
- Codex로 하는 리뷰(예: Codex 플러그인의 `/codex:review`)와는 별개다. 프로젝트가 원하면 둘을 함께 쓸 수 있지만, Codex 리뷰는 하네스에 포함되지 않는다.

### 9. 개선: 같은 실수는 한 번만

시험장에서 에이전트가 실패하면 [docs/harness-log.md](docs/harness-log.md)에 기록한다. 그리고 [docs/principles.md](docs/principles.md)의 기준표에 따라 알맞은 층을 고친다.
반복되는 실수일수록 강한 수단으로 옮긴다: 문장 지침 → 경로 규칙 → 스크립트가 딸린 스킬 → 린트·테스트 → 훅·권한.
고칠 곳이 특정 플랫폼·도구에만 해당하면 하네스가 아니라 그 프로젝트의 규칙·스크립트·설정을 고친다.

실제 예: 리뷰어가 바뀐 파일을 열지 않고 diff만 보고 판단했다 → 검토 순서를 명시하고, 연 파일을 훅이 기록하게 했다.

## 파일별 역할

### 루트

| 파일 | 역할 |
|---|---|
| `README.md` | 이 문서. 처음 보는 사람을 위한 개요 |
| `AGENTS.md` | **이 저장소를 개발할 때** 에이전트가 따르는 지침. 대상 프로젝트에 설치되는 지침은 `template/AGENTS.md`다 |
| `CLAUDE.md` | `@AGENTS.md`를 불러온다 |
| `.claude-plugin/marketplace.json` | 이 저장소를 마켓플레이스 `ai-harness`로 만든다. 플러그인 위치는 `./plugin` |

### template/ — 대상 프로젝트에 복사되는 원본

template 안의 경로가 그대로 대상 프로젝트 루트 기준 경로가 된다. 설치·갱신 방식은 [docs/template.md](docs/template.md)에 있다.

| 파일 | 계층 | 역할 |
|---|---|---|
| `AGENTS.md` | Context | 프로젝트 지침. 위쪽 프로젝트 영역(빈 자리, "빌드·테스트" 칸 포함)과 아래쪽 하네스 관리 블록 |
| `CLAUDE.md` | Context | `@AGENTS.md` import. Claude Code가 AGENTS.md를 읽게 한다 |
| `.claude/rules/harness/wiki.md` | Context | 기록을 열 때 읽히는 규칙: 두 종류의 형식, 쓰는 때, 기록과 반대되는 요청은 묻기 |
| `.claude/rules/project/.gitkeep` | Context | 프로젝트 고유 규칙을 두는 자리. 하네스가 건드리지 않는다 |
| `.claude/settings.json` | Enforcement | 공통 권한 규칙(비밀 파일 읽기 deny). `ask`는 비워 둔다(ADR 0026) |
| `scripts/harness/record` | Execution + Validation | 아무 명령이나 돌려 결과를 `.harness/out/<이름>.json`에 남긴다. run은 `passed <이름>` |
| `scripts/harness/passed` | Validation | 결과 파일이 통과했고 지금 코드에 대한 최신 결과인지 본다. `checks.json`의 run에 쓴다 |
| `scripts/harness/wiki` | Context + Validation | 정책·결정 기록(`docs/wiki/`)을 찾고 형식을 검사한다 |
| `scripts/harness/doctor` | Validation | 하네스가 이 프로젝트에서 돌 수 있는지 점검한다: 도구, 설정 파일, 검사 목록의 run, 지침 연결, 플러그인 버전 |
| `scripts/harness/setup` | Context | 검사·생성 파일·고치면 안 되는 파일·빌드·테스트 명령을 사용자와 정하는 안내. 찾은 명령과 단서를 보여 준다. 파일은 쓰지 않는다 |
| `scripts/harness/common-checks.json` | Context | setup이 추천하는 검사(review) |
| `scripts/harness/lib.sh` | Execution | 공통 함수: 루트 찾기, 설정 읽기, 바뀐 파일 목록, 작업 시작 커밋, 위키 형식 |
| `.harness/.gitignore` | State | `.harness/`에서 설정 파일(`project.json`·`conventions.json`·`checks.json`)과 설치 기록(`harness.json`)만 커밋되게 한다 |

### plugin/ — Claude Code 플러그인 harness

복사하지 않는다. Claude Code가 GitHub 마켓플레이스(이 저장소)에서 설치한다. 구성은 [docs/plugin.md](docs/plugin.md)에 있다.

| 파일 | 계층 | 역할 |
|---|---|---|
| `.claude-plugin/plugin.json` | — | 플러그인 이름(`harness`)과 버전 |
| `hooks/hooks.json` | Enforcement + Context | 세션 시작 때 `session-start.sh`, 모든 도구 전에 `tool-count.sh`, 편집·Bash 직전에 `protect-generated.sh`·`guard-state.sh`, 편집 직후에 `stage-context.sh`, Read 직후·서브에이전트가 끝날 때 `review-record.sh`, 끝낼 때 `stop-gate.sh`를 실행하도록 등록 |
| `hooks/session-start.sh` | Context | 세션을 열 때 작업이 없으면 task 스킬로 시작하라고, 있으면 그 단계를 알려 주는 훅 |
| `hooks/protect-generated.sh` | Enforcement | `project.json`의 `generated`에 적힌 생성 파일 편집을 막는 훅 |
| `hooks/guard-state.sh` | Enforcement | 에이전트가 작업 상태 파일로 단계를 넘기지 못하게 막는 훅. 시작(첫 단계로만)·이어서 하기·취소만 허용하고 Bash 쓰기는 막는다. 막은 일은 `task.history`에 남긴다 |
| `hooks/stop-gate.sh` | Enforcement + Validation | 응답을 마치려 할 때 검증 단계면 고른 검사의 `run`을 돌리고, 통과하면 다음 단계로 넘기는 훅. 마무리 단계면 커밋·push를 확인한다. done 전에는 끝내지 못한다. 넘김·차단은 `task.history`에 남긴다 (반복 방지는 ai-bouncer와 같다. 백그라운드 서브에이전트를 기다리는 동안은 막지 않는다) |
| `hooks/stage-text.jq` | Context | 단계 지시 글. `stage-context.sh`와 `stop-gate.sh`가 같이 쓴다 |
| `hooks/tool-count.sh` | State | 작업 주인 세션의 도구 호출 수를 세는 훅 (stop-gate.sh가 쓴다) |
| `hooks/stage-context.sh` | Context + State | 작업 상태 파일(`.harness/state/task.json`)을 시작하거나 이어서 할 때 그 단계의 지시를 `.harness/checks.json`에서 꺼내 넣는 훅. 새 작업이면 주인 세션·시작 시각·시작 커밋(`task.base`)·이미 바뀌어 있던 파일(`task.wip`)을 적고 `task.history`를 새로 연다 |
| `hooks/review-record.sh` | Validation | reviewer가 Read로 연 파일과 보고서의 차단 수로 `.harness/out/review.json`을 남기는 훅. `passed review`가 이 파일을 본다 |
| `skills/task/SKILL.md` | State | 작업 시작: 계획 여부(plan/simple)와 검사를 사용자에게 묻고 상태 파일을 만든다 |
| `.mcp.json`, `mcp/network.py` | Validation 보조 | 가짜 응답 서버 MCP `harness-network`. AI가 건 지연·400·500·빈 응답을 실제 서버 대신 앱에 돌려준다. `e2e.network.port`를 적은 프로젝트에서만 켜진다 |
| `agents/reviewer.md` | Validation (추론적) | 읽기 전용 리뷰 서브에이전트의 지시문 |

### scripts/ — 하네스를 설치하는 도구

대상 프로젝트 경로를 인자로 받는다. 대상 프로젝트에는 복사되지 않는다.

| 파일 | 역할 |
|---|---|
| `init` | 하네스를 처음 설치한다. 이미 설치된 프로젝트는 거절한다 |
| `sync` | 설치된 하네스를 이 저장소의 버전으로 갱신한다. 예전 iOS 묶음은 프로젝트 코드로 넘긴다. `--dev`면 플러그인을 이 저장소 디렉터리에서 읽게 한다 |

### tests/ — 스크립트 회귀 테스트

임시 디렉터리에 가짜 프로젝트와 가짜 입력을 만들어 스크립트와 훅의 판단 로직을 검사한다.

| 파일 | 검사하는 것 |
|---|---|
| `run.sh` | 모든 `*.test.sh`를 실행한다 |
| `lib.sh` | `assert_eq`, `finish` 같은 테스트 도우미 |
| `hooks.test.sh` | 훅이 막을 것만 막고, 판단할 수 없으면 통과시키는지 |
| `stage.test.sh` | 단계 지시 훅이 상태 파일이 바뀔 때만, 고른 검사의 지시만 넣는지. 시작 때 `task.wip`·`task.history`를 적는지 |
| `run-gate.test.sh` | 검증 강제 훅이 verify를 지나 넘어갈 때 고른 검사의 run을 돌려, 실패하면 막는지 |
| `stop-gate.test.sh` | Stop 훅이 작업 주인 세션만 막고, 도구 없는 반복과 연속 차단을 ai-bouncer처럼 풀어 주는지. 마무리에서 커밋 안 한 변경·기본 브랜치 커밋·push 안 함을 막고 무관한 WIP는 두는지 |
| `guard-state.test.sh` | 상태 파일 보호 훅: 시작(첫 단계로만)·이어서 하기·취소만 허용하고, 단계 바꾸기와 Bash 쓰기를 막는지 |
| `session-start.test.sh` | 세션 시작 훅: 작업이 없으면 task 스킬 안내, 있으면 지금 단계를 알리는지 |
| `review-record.test.sh` | 리뷰 기록 훅: reviewer의 Read만 적기, 안 연 파일·차단 수로 판정, `passed review`의 최신 판정 |
| `record.test.sh` | record의 결과·로그·출력, record·passed만으로 검증 게이트가 판정하는지 |
| `passed.test.sh` | passed가 결과 파일이 통과했고 최신인지 보는지 |
| `wiki.test.sh` | 기록 찾기·검색 로그·형식 검사 |
| `network-mcp.test.sh` | 가짜 응답 MCP: 켠 프로젝트에서만 도구, 상태·지연·본문 응답, 구체적인 match 우선, 프로젝트끼리 독립 |
| `setup.test.sh` | setup이 파일을 쓰지 않고, 찾은 명령·추천 검사·생성 파일 단서를 보여 주는지 |
| `sync.test.sh` | init·sync의 파일 배치, AGENTS.md 관리 블록 교체, 설정 병합, 플러그인 등록, `--dev`, iOS 묶음 넘기기, 반복 실행 |
| `doctor.test.sh` | doctor가 플러그인 버전 차이·미설치·꺼짐, 지침 연결, 검사 목록의 run, 공유되지 않는 설정을 잡는지 |
| `script-style.test.sh` | 스크립트의 공통 실수(변수 바로 뒤의 한글 등) |

### docs/ — 설계 문서

| 파일 | 내용 |
|---|---|
| `roadmap.md` | 작업 단위와 순서, 진행 상황 |
| `principles.md` | 하네스 계층, 설계 원칙, 실수를 어느 층에서 고칠지 정한 기준표, 용어 |
| `references.md` | 레퍼런스 조사 요약, 플랫폼 제약, 로컬 환경, 출처 |
| `project-config.md` | `.harness/project.json` 필드 스펙 |
| `scripts.md` | record·passed·wiki·doctor·setup의 동작과 출력 형식, 산출물 위치 |
| `conventions.md` | `.harness/conventions.json`: 예전 iOS lint가 읽던 팀 컨벤션 목록(ADR 0024로 하네스 밖) |
| `template.md` | template 파일이 어디에 설치되고 어떻게 갱신되는지, 예전 iOS 묶음을 넘기는 방식, 기존 지침이 있는 프로젝트에 적용하는 절차 |
| `plugin.md` | 플러그인 구성, 훅이 막는 것, 단계 지시 훅과 task 스킬, 리뷰어 동작, 프로젝트에서 켜는 방법 |
| `wiki.md` | 정책·결정 기록의 두 종류, 형식, 찾고 쓰는 때 |
| `checks.md` | 작업 흐름(plan/simple)과 `.harness/checks.json` 필드 스펙 |
| `harness-log.md` | 시험장에서 관찰한 에이전트 실패와 그에 따른 수정 |
| `problem-notes.md` | 시험장에서 만난 문제의 기술 설명(문제·원인·해결·결과)과 비유, 하네스 문답 |
| `decisions/` | 설계 결정 기록(ADR). 아래 표 |

0006·0009·0010·0014·0015는 단위 31에서 하네스 밖으로 옮긴 iOS 도구(lint·e2e)의 결정 기록이다. 그 코드는 git 기록(0.11.2)과 넘겨받은 프로젝트의 `scripts/ios/`에 있다.

| ADR | 내용 |
|---|---|
| `0001-layers.md` | 다섯 계층과 산출물 위치(template·plugin·scripts)를 나눈 이유 |
| `0002-rule-placement.md` | 규칙을 무엇에 붙는지(파일 종류 / 행동)에 따라 경로 규칙·AGENTS.md·스킬·권한으로 나누는 기준 |
| `0003-agents-md-areas.md` | AGENTS.md를 프로젝트 영역과 관리 블록으로 나누고 명령 블록을 고정 문장으로 둔 이유 |
| `0004-enforcement.md` | 무엇을 훅으로, 무엇을 deny·ask로 막는지 |
| `0005-talk-criteria.md` | 여기어때 안드로이드 팀 발표의 기준으로 이후 후보를 다시 정하고, 워크플로 엔진을 함께 쓰지 않는 이유 |
| `0006-convention-lint.md` | 컨벤션 목록을 JSON으로 두고 SwiftLint와 점수로 판정하는 이유 |
| `0007-task-flow.md` | 사람이 고른 모드·검사와 단계 지시 훅으로 작업 흐름을 만들고, 강제는 미룬 이유 |
| `0008-wiki.md` | 정책·결정 기록을 프로젝트 안 파일과 검색 스크립트로 시작한 이유와 비교 결과 |
| `0009-e2e-maestro.md` | 동작 확인을 Maestro 시나리오 파일과 e2e 스크립트로 하는 이유와 첫 시나리오에서 겪은 실패 |
| `0010-e2e-events.md` | 시나리오가 끝난 뒤 행동 로그(이벤트·횟수·값·업로드)를 판정하는 방식과 Firebase 로그를 읽는 근거 |
| `0011-plugin-distribution.md` | 플러그인을 GitHub 마켓플레이스로 배포하고 init·sync·doctor를 둔 이유 |
| `0012-run-gate.md` | 검증 단계를 넘길 때 run을 돌려 확인하고, Stop 게이트로 끝내지 못하게 하는 이유 |
| `0013-stop-wait-subagent.md` | 백그라운드 서브에이전트를 기다리는 동안 Stop 게이트가 막지 않는 이유 |
| `0014-layer-format-rules.md` | 모듈 의존은 tuist graph로, 형식은 swift-format으로 검사하는 이유 |
| `0015-implicit-imports.md` | 의존 목록에 없는 import도 모듈 의존 검사에 넣는 이유 |
| `0016-review-record.md` | 리뷰를 했는지 리뷰어의 말이 아니라 훅 기록으로 확인하는 이유 |
| `0017-network-mock.md` | 서버 응답 조작을 프록시 대신 실제 서버를 대신하는 가짜 응답 MCP로 만든 이유 |
| `0018-core-and-packs.md` | 공통 핵심과 플랫폼 묶음으로 나누고, 아무 명령의 결과를 record로 남기는 이유 (묶음 부분은 0024로 대체) |
| `0019-pack-install.md` | 묶음을 pack.json 목록으로 정한 이유 (0024로 대체) |
| `0020-install-checks-permissions-root.md` | 검사 목록은 setup 안내로 사용자와 정하고, sync가 넣었던 권한 규칙을 지우고, 스크립트가 가장 가까운 설정을 루트로 쓰는 이유 |
| `0021-rename.md` | 이름에서 iOS를 빼고(플러그인 `harness`, 리뷰어 `reviewer`), sync가 예전 이름의 항목을 지우는 이유 |
| `0022-common-reviewer-permissions.md` | 리뷰어는 공통 절차만 두고, 생성 파일 목록(`generated`)과 공통 권한을 둔 이유 |
| `0023-no-pack-repo.md` | 묶음 없는 저장소는 공통 핵심만으로 돈다. macOS만 지원한다 |
| `0024-no-platform.md` | 하네스는 플랫폼을 모른다. 플랫폼 도구는 저장소가 갖고, setup이 사용자와 함께 정한다. 예전 iOS 묶음은 sync가 프로젝트로 넘긴다 |
| `0025-regression-check.md` | 회귀 묶음은 고를 수 있는 검사 하나로 둔다 |
| `0026-no-ask-rules.md` | 권한 규칙의 `ask` 목록을 두지 않는 이유 |
| `0027-stop-advances-stage.md` | 단계는 Stop 훅이 넘기고, 에이전트는 상태 파일의 단계를 고치지 않는 이유 |
| `0028-finish-commit-push.md` | 마무리 단계에서 커밋·push하고 Stop 훅이 확인하는 이유 |

## 설치하면 대상 프로젝트는 이렇게 된다

```
MyApp/
├── AGENTS.md                      프로젝트 영역 + 하네스 관리 블록
├── CLAUDE.md                      @AGENTS.md
├── .harness/
│   ├── .gitignore                 설정 파일과 설치 기록만 커밋
│   ├── project.json               프로젝트 설정 파일 (처음에는 schemaVersion만, setup이 generated를 더한다)
│   ├── checks.json                검사 목록 (setup이 사용자와 정해 쓴다)
│   ├── harness.json               설치 기록 (하네스 버전, 설치한 파일, 넣은 권한 규칙)
│   ├── out/                       마지막 실행의 결과·로그 (무시됨)
│   └── state/                     작업 상태 (무시됨)
├── .claude/
│   ├── settings.json              권한 규칙, 플러그인 등록 (기존 설정과 합침)
│   ├── settings.local.json        개발용 플러그인 (--dev, 커밋하지 않음)
│   └── rules/
│       ├── harness/*.md           공통 규칙 (하네스가 관리)
│       └── project/**/*.md        프로젝트 고유 규칙 (프로젝트가 관리)
├── scripts/harness/
│   ├── record, passed, wiki, doctor, setup
│   ├── common-checks.json         setup이 추천하는 검사
│   └── lib.sh                     공통 함수
└── scripts/                       (선택) 프로젝트가 가진 빌드·테스트 스크립트. 하네스가 관리하지 않는다
```

## 직접 해 보기

```bash
bash tests/run.sh
```

```bash
scripts/init ~/path/to/MyApp
```

그다음 `MyApp`에서 Claude를 열고 이렇게 말한다.

```
scripts/harness/setup 안내대로 설정해 줘
```

```bash
claude plugin validate plugin
```

- `bash tests/run.sh`: 회귀 테스트 전체.
- `scripts/init`: 실제로 설치한다. 설치한 뒤 출력된 "직접 할 일"을 처리한다.
- setup: 검사·생성 파일·고치면 안 되는 파일·빌드·테스트 명령을 정한다. 끝나면 `scripts/harness/doctor`로 점검하고, 쓴 파일을 커밋한다.
- 지원 OS: macOS만([ADR 0023](docs/decisions/0023-no-pack-repo.md)). Linux에서는 확인하지 않았다.
- 필요한 도구: macOS 기본 bash·jq. 가짜 응답 MCP를 쓰면 python3. 빌드·테스트 도구는 프로젝트가 쓰는 것

## 진행 상황

- 단위 1~8 완료: 저장소 구조, 프로젝트 설정 파일·detect, build·test·verify, 경로 규칙, AGENTS.md 템플릿, 훅·권한·플러그인, reviewer
- 단위 9 완료: MotoTrace에 설치해 확인한 뒤 시험장을 ReadSharp로 옮겼다. 실패 기록 14개를 계층별로 분류해 이후 순서를 정했다
- 후보 11 완료: 팀 컨벤션 목록과 `lint`(SwiftLint + 점수 판정). 레이어 의존·형식 검사는 후보 20에서 더했다(ADR 0014)
- 후보 12 완료: 사람이 모드·검사를 고르는 작업 흐름(`task` 스킬 + 단계 지시 훅)
- 후보 19 완료: 정책·결정 기록(`docs/wiki/`, `wiki` search·check)
- 후보 15 완료: 두 번째 프로젝트 IntervalTimer(Tuist, 루트 manifest 하나)에 설치했다. 하네스는 detect만 고쳤고 나머지는 설정 파일만 달랐다
- 후보 14 완료: 플러그인을 GitHub 마켓플레이스로 배포하고 `init`·`sync`·`doctor`를 만들었다
- 후보 10 일부: Maestro E2E(`e2e`, 작성 규칙, 회귀 묶음, 녹화, 행동 로그 판정). 서버 응답 조작(가짜 응답 MCP). 화면 검증은 Figma 시안이 없어 미룸
- 후보 13 완료: 검증 강제(Stop 게이트가 고른 검사의 run을 돌린다). 0.13.0부터는 단계도 Stop 훅이 넘긴다(ADR 0027)
- 후보 20: 모듈 의존(`tuist graph`·`tuist inspect implicit-imports`)·형식(swift-format) 검사. 빌드·Tuist 절차 스킬과 후보 18은 뺐다
- 단위 21~30 완료: 범용 하네스로 넓혔다(공통 핵심과 `record`·`passed`, 플랫폼 묶음, 이름 변경, 공통 리뷰어·권한, 묶음 없는 저장소, JS·RN 저장소)
- 단위 31 완료: 하네스에서 플랫폼 코드를 뺐다. iOS 묶음(build·test·unit-test·lint·e2e, Swift 규칙)과 detect를 지우고, setup이 사용자와 설정을 정한다. 이미 쓰던 프로젝트는 sync가 iOS 파일을 넘긴다(ADR 0024)
- 0.14.0: 마무리 단계에서 커밋·push하고 Stop 훅이 확인한다(ADR 0028). 마무리 보고는 일곱 섹션이고, 단계 기록은 훅이 남긴 `task.history`를 옮긴다

자세한 내용은 [docs/roadmap.md](docs/roadmap.md)에 있다. 이 저장소에 기여하는 방법(브랜치, 커밋 규칙)은 [AGENTS.md](AGENTS.md)에 있다.
