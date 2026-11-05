# 로드맵

여러 iOS 프로젝트에서 재사용할 범용 하네스를 작업 단위로 나눠 하나씩 쌓아간다.
단위 하나는 세션 하나 분량이다. 커밋 1~3개로 마무리하고, 끝나면 여기 체크박스를 갱신한다.

지금: 10 — 서버 응답 조작

(위 줄은 로드맵 패널이 읽는다. 작업 단위를 바꾸면 함께 고친다.)

## 정해진 것

- 에이전트: Claude Code만 지원한다. Codex 어댑터(후보 16)는 뺐다(2026-11-05).
- 스크립트: bash + jq로 작성한다. 둘 다 macOS에 기본으로 들어 있어 따로 설치할 필요가 없다.
- 설계 근거: 레퍼런스에서 도출한 범용 원칙을 따른다. 출처는 OpenAI, Anthropic, Böckeler, HumanLayer, Sentry 등이다.
- 시험장: ReadSharp(`~/Code/EnglishStudy`, xcodeproj 단일 앱)의 `~/Code/EnglishStudy-harness` 워크트리에서 각 단위를 실제로 돌려본다.
  - 시험장에 이미 있는 하네스 구성은 설계 근거로 삼지 않는다.
  - 단위 1~9의 MotoTrace 기록은 그대로 둔다.
- 설계 기준: 여기어때 안드로이드 팀 발표에서 가져온 기준을 따른다 ([ADR 0005](decisions/0005-talk-criteria.md)).
  - 완료는 에이전트의 말이 아니라 실행 결과로 판정한다.
  - 검사와 계획 여부는 사람이 작업마다 고른다. 검사 목록은 프로젝트 설정에 둔다.
  - 필요 없어진 장치는 뺀다. 코드에 남지 않는 결정은 기록한다.
- 워크플로 엔진(ai-bouncer 등)은 함께 쓰지 않는다. 작업 흐름은 후보 12에서 하네스 안에 만든다.

## 하네스 계층

| 계층 | 하는 일 | 이 하네스에서 |
|---|---|---|
| Context (가이드) | 행동 전에 알려준다 | AGENTS.md, 규칙, 스킬 |
| Execution (실행 도구) | 에이전트가 일을 하는 손 | 빌드·테스트 실행 래퍼, 시뮬레이터 조작 |
| Validation (센서) | 결과가 맞는지 판정한다 | 결정적: 컴파일러, 테스트, 린트 / 추론적: 코드 리뷰 |
| Enforcement (강제) | 모델 판단과 상관없이 막는다 | 훅, 권한 deny |
| State (설정·상태) | 위 계층이 함께 쓰는 데이터 | 프로젝트 설정 파일(`.harness/project.json`), 실행 계획, 실패 로그 |

## 진행 원칙

1. **최소 구성부터 만든다.**
   - Enforcement는 위험하거나 되돌리기 어려운 행동을 막는 것만 처음에 넣는다.
   - 검증 여부를 확인하는 게이트 같은 나머지 강제 장치는 실패가 실제로 관찰될 때만 추가한다.
2. **Validation은 결정적 검증과 추론적 검증을 함께 둔다.**
   - 결정적 검증(빌드·테스트)은 컴파일·동작 오류를 잡는다.
   - 추론적 검증(코드 리뷰)은 설계·규칙 위반을 잡는다.
3. **Execution·Validation을 먼저 만들고, Context는 그다음에 만든다.** AGENTS.md의 명령 블록이 스크립트 이름을 참조하기 때문이다.
4. **각 단위는 시험장에서 실제로 돌려보고 끝낸다.** 단위 9의 운영 기록을 근거로 이후 순서를 다시 정한다.
5. **훅 스크립트는 stdin JSON만 읽게 짠다.** Codex 어댑터에서 그대로 재사용하기 위해서다.

## 파일럿까지 (순서 고정)

- [x] **1. 저장소 구조와 설계 문서**
  - 하는 일
    - 루트 `AGENTS.md` 작성
    - `common/` → `template/` 이동
    - `docs/principles.md`, `docs/references.md`, `docs/decisions/0001-layers.md`, `docs/harness-log.md` 작성
  - 완료 기준: 새 세션이 루트 AGENTS.md만 읽고 저장소 구조와 진행 방식을 파악한다.
- [x] **2. 프로젝트 설정 파일과 detect** (State)
  - 하는 일
    - `.harness/project.json` 스펙 작성
    - `scripts/detect` 작성 (하네스 설치 도구라 저장소 `scripts/`에 둔다)
  - 완료 기준: MotoTrace, coinness-ios, xcodeproj 앱 하나에서 초안이 실제 구성과 일치한다.
- [x] **3. 빌드 실행·판정 `scripts/harness/build`** (Execution + Validation)
  - 하는 일
    - generate → `xcodebuild -quiet` → `xcresulttool` 요약 순서로 실행
    - 출력: 성공하면 1줄, 실패하면 첫 에러의 `파일:줄`과 원본 로그 경로
  - 완료 기준: 정상 빌드와 일부러 넣은 컴파일 에러 양쪽의 출력을 확인한다.
- [x] **4. 테스트 실행·판정과 verify** (Execution + Validation)
  - 하는 일
    - `scripts/harness/test` 작성: 실패만 요약
    - `scripts/harness/verify` 작성: 빌드와 변경 모듈 테스트를 명령 하나로 실행
  - 완료 기준: 모듈 하나를 고치면 그 모듈의 테스트가 돌고, 실패가 요약돼 보인다.
- [x] **5. 규칙 재구성** (Context)
  - 하는 일
    - 규칙을 `template/.claude/rules/harness/*.md`로 옮기고 `paths:` 추가
    - `build.md`의 절차는 verify로 대체 (`project-settings.md`로 이름 변경)
    - `git.md`는 경로로 걸 수 없어 꼭 지킬 줄만 AGENTS.md로 옮김 (ADR 0002)
  - 완료 기준: `.swift` 파일을 읽을 때 해당 규칙이 로드된다.
- [x] **6. AGENTS.md 템플릿과 CLAUDE.md** (Context)
  - 하는 일
    - AGENTS.md 템플릿 작성(100줄 이하): 프로젝트 영역, 명령 블록, 꼭 지킬 규칙, Codex용 규칙 인덱스
    - 명령 블록은 생성하지 않고 고정 문장으로 둔다. 스크립트가 설정 파일을 직접 읽기 때문이다 (ADR 0003)
    - CLAUDE.md는 `@AGENTS.md`를 import
    - 프로젝트 고유 규칙 자리 `.claude/rules/project/` 마련
  - 완료 기준: 새 세션에서 빌드·테스트 방법을 물으면 정확한 명령으로 답한다.
- [x] **7. 안전 훅·권한과 플러그인 골격** (Enforcement)
  - 하는 일
    - 플러그인 골격과 로컬 마켓플레이스 작성
    - 자동 생성 파일·`.pbxproj` 편집 차단 훅
    - 서명·시크릿 파일 읽기 deny, 파괴적·외부 공개 git 작업은 ask(사용자 확인)
    - 훅 픽스처 테스트
  - 완료 기준: 위 차단이 MotoTrace에서 실제로 동작한다.
  - 확인: MotoTrace에서 띄운 실제 세션에서 세 가지 차단 모두 동작. 이 과정에서 `git -C` 형식이 규칙을 피해 가는 것을 발견해 보완함 (harness-log, ADR 0004)
- [x] **8. 코드 리뷰 서브에이전트** (추론적 Validation)
  - 하는 일: `ios-reviewer` 작성. 읽기 전용으로 diff를 규칙에 비춰 검토한다.
  - 검토 항목: 동시성 격리, 의존 방향, 접근성, 테스트 약화·설정 완화 같은 편법, 과설계
  - 완료 기준: 일부러 넣은 위반을 잡아낸다.
  - 확인: 시험장에 위반 4종(테스트 약화, @unchecked Sendable, 구현 모듈 import, 설정 완화)을 넣고 맡겼더니 모두 [차단]으로 잡음. 리뷰어가 파일을 열지 않던 문제는 검토 순서로 보완함 (harness-log)
- [x] **9. 시험장에 새로 구성하고 운영하기**
  - 하는 일
    - `scripts/dev-install` 작성
    - MotoTrace의 기존 하네스를 걷어내고 범용 하네스로 새로 구성
    - 1~2주 운영하며 `docs/harness-log.md`에 실패 기록
  - 완료 기준: 실패 기록을 분류해 이후 우선순위를 확정한다.
  - 진행 (2026-10-21)
    - `scripts/dev-install` 작성 (회귀 테스트 26개)
    - MotoTrace `feature/ios-harness` 브랜치에 설치하고 기존 구성 정리. Codex 위임 검증·스탬프·커밋 게이트는 제거하고, mock ride·XcodeBuildMCP·/codex:review는 유지
    - 새 세션이 빌드·테스트·PR 절차를 정확히 답하고, Swift 파일을 열면 규칙이 로드되는 것 확인 (단위 5·6의 실제 프로젝트 확인)
  - 진행 (2026-11-03)
    - 시험장을 ReadSharp로 옮겼다. MotoTrace를 이 컴퓨터에서 쓸 수 없어서다. xcodeproj 단일 앱이라 Tuist 밖 경로 확인도 겸한다
    - 남은 일: ReadSharp에서 1~2주 운영하며 실패 기록, 분류해서 이후 우선순위 확정
    - 이슈 #217을 새 세션에서 처음부터 돌렸다(plan 모드, 3턴 약 49분). verify에서 e2e 실패로 멈췄고, verify 통과는 말로만 알 수 있었다. 그래서 후보 13을 발표대로 켰다(ADR 0012). 나머지 관찰은 harness-log에 있다
  - 완료 (2026-11-04): 문제 14개를 계층별로 분류했다([harness-log.md](harness-log.md) "분류"). 강제 장치 문제는 모두 고쳤고, 남은 미해결 두 개는 E2E다. 운영은 이틀이지만 막힌 문제가 없어 닫는다. 이 분류로 아래 순서를 정했다

## 이후 후보 (단위 9의 분류로 정한 순서)

후보 10~13·19는 발표 기준으로 다시 썼다 (ADR 0005). 다른 문서가 번호를 참조하므로 번호는 바꾸지 않는다.

남은 일의 순서 (2026-11-04):
1. 후보 10의 E2E 정리: 부하에서 온보딩을 못 찾는 문제(공통 시작 흐름의 대기), Maestro 규칙에 클립보드 금지. harness-log의 미해결 두 개다
   - 진행 (2026-11-04): 클립보드 금지 규칙을 넣었다. 검사를 `checks.json` 순서대로 돌게 했다(슬라이드 88). 온보딩은 60초 대기를 넣었고 효과는 실제 작업에서 지켜본다(harness-log #218)
2. 후보 20 (레이어 의존·형식·숨은 import)
   - 진행 (2026-11-05): 끝냈다(ADR 0014·0015). 절차 스킬 두 개는 뺐다
3. 후보 10의 서버 응답 조작 (사용자가 평가보다 먼저 하기로 정했다, 2026-11-05)
4. 후보 17 평가
- 17은 발표에 없다. 평가는 사용자가 맨 마지막으로 정했다(2026-11-05).
- 후보 16(Codex 어댑터)은 뺐다(2026-11-05). 사용자가 정했다. 훅이 stdin JSON만 읽는 원칙은 그대로 둔다.
- 후보 18(래칫·청소 자동화)은 뺐다(2026-11-05). 첫 로드맵에 이름만 있었고, 발표·ai-bouncer에 근거가 없으며 무엇을 하는지 정의된 적이 없다.
- 후보 10의 화면 검증은 미룬다. 시험장 두 곳 모두 Figma 시안이 없어서다. 시안이 있는 프로젝트가 생기면 다시 본다. 다시 볼 때는 `~/Code/hankuk`(한개국어, Expo)의 `figma-parity` 스킬과 `design/audit/`를 먼저 참고한다.

- [ ] 10. 동작·화면 확인
  - [x] Maestro 시나리오와 팀 작성 규칙(ADR 0009): 딥링크로 진입, accessibilityIdentifier로 먼저 찾기, 계정은 환경 변수, 반복 단계는 공통 `runFlow`, 끝까지 통과한 시나리오만 저장. 규칙은 template `rules/harness/maestro.md`, 실행은 `scripts/harness/e2e`
  - [x] `tags: [regression]` 회귀 묶음(`e2e --tag regression`), 수정 전후 영상(`e2e --record`)
  - [ ] 화면 검증: `#Preview` 스냅샷 + Figma MCP 수치 비교. 배치는 AI가, 간격·크기 수치는 스크립트가 보고, 판정은 사람이 한다. 픽셀 비교는 쓰지 않는다(발표에서 차이가 전부 빨갛게 나와 실패). 시험장에 Figma 시안이 없어 미룬다(2026-11-04)
  - [x] 행동 로그 판정(ADR 0010): 시나리오 옆 `<이름>.events.json`에 이벤트·횟수·값을 적으면 흐름이 끝난 뒤 판정하고, 수집 서버 업로드 성공까지 본다. 지금은 Firebase Analytics(`e2e.events: firebase`)만
  - [x] 서버 응답 조작(ADR 0017): 플러그인 MCP `harness-network`가 실제 서버 대신 AI가 건 응답(지연·400·500·빈 응답·본문)을 준다. 앱은 테스트 실행 인자가 있을 때만 요청을 그 서버로 보낸다. `e2e.network.port`를 적은 프로젝트에서만 켜진다
  - 진행 (2026-11-05): ReadSharp에 붙였다. `APIConfig`에서 실행 인자가 있으면 Gemini·Claude 주소를 MCP 서버로 바꾼다. Gemini 500을 건 시나리오에서 분석 실패 화면과 다시 시도 버튼을 확인했고(77초), 회귀 4개는 MCP로 요청 없이 그대로 통과했다. `claude -p` 세션이 `requests`로 주소를 보고 `mock_set`으로 10초 지연·503을 걸었다. IntervalTimer 세션에서는 도구가 보이지 않았다
    - ReadSharp 스킴은 실행도 Release라 "디버그 빌드만"으로 짠 주소 바꾸기가 E2E에서 돌지 않았다. 디버그 조건 대신 `127.0.0.1` 주소만 받게 했다
    - 첫 재시도는 다른 작업의 렌더링으로 load average 114일 때 스플래시에서 60초를 넘겨 실패했다. 부하가 내려간 뒤 통과했다
  - 진행 (2026-11-03): ReadSharp에 회귀 시나리오 2개(프로필 빈 상태, 설정 진입)를 만들어 통과했다. 늦게 뜨는 온보딩과 빌드마다 다른 설정 항목 때문에 두 번 실패했고, 실패 스크린샷으로 고쳤다. 앱에 accessibilityIdentifier가 없어 문구로 찾다가, 같은 날 id를 달아 id로 바꿨다(탭 바는 SwiftUI `Tab`에 id를 달 수 없어 문구)
  - 진행 (2026-11-03): ReadSharp 회귀 시나리오 2개에 행동 로그(온보딩 건너뛰기, 프로필 탭 선택)를 붙여 통과했다. 횟수를 틀리게 적으면 이벤트별로 실패를 보여 주는 것도 확인했다
- [x] 11. 결정적 컨벤션 센서
  - 규칙 목록 `.harness/conventions.json`: AI가 코드에서 초안을 뽑고 사람이 고른다. `lint`가 실행할 때마다 SwiftLint `custom_rules` 설정으로 옮긴다. YAML 대신 JSON을 쓴다(ADR 0006)
  - `scripts/harness/lint`: 100점에서 위반마다 감점하고 `passScore` 이상이면 통과. 결과를 `.harness/out/lint.json`(`passed`, `score`, 위반 목록)으로 남긴다. 검사에는 AI를 쓰지 않는다
  - 첫 대상(ReadSharp): `.sheet(isPresented:)` 금지, `MobileCoreServices` 금지, View에서 `Service.shared`·`AppContainer.shared` 직접 참조 금지
  - 진행 (2026-11-03): ReadSharp 전체 199개 파일 검사에서 주석 속 `.sheet(isPresented:)` 2곳은 잡지 않았고, `SettingsView`의 `AppContainer.shared` 1곳을 찾았다(코드는 따로 고친다). 위반 3개를 넣은 파일은 70점으로 실패. `claude -p`로 시트 화면을 만들게 하자 에이전트가 스스로 `lint`를 돌렸고 처음부터 `.sheet(item:)`으로 작성했다
  - 남은 항목은 후보 20으로 넘겼다. 시험장(xcodeproj 단일 앱)에서 확인할 수 없거나 아직 필요가 관찰되지 않아서다
- [x] 12. 작업 흐름 (ADR 0007)
  - 작업을 시작할 때 사람이 모드(plan: 계획 → 구현 → 검증 → 마무리 / simple: 구현 → 검증 → 마무리)와 검사를 고른다. 플러그인 스킬 `task`가 묻는다
  - 검사 목록 `.harness/checks.json`: 검사마다 `name`, `description`, `prompt`(시킬 일), `run`(했는지 확인하는 명령, 후보 13에서 사용). `project.json`(사실)과 나눈다
  - 단계 상태 파일 `.harness/state/task.json`을 고치면 PostToolUse 훅 `stage-context.sh`가 그 단계의 지시를 `additionalContext`로 넣는다. 훅은 검사 내용을 모르고 설정의 글을 옮길 뿐이다
  - 마무리 단계 지시에 "코드에 남지 않는 정책·결정 정리"를 넣었다 (기록 저장소는 후보 19)
  - 남은 것: git 관례(커밋 구성, 브랜치, PR 본문에 검증 결과 넣기), 워크트리 (ADR 0002에서 넘긴 항목)
  - 진행 (2026-11-03): ReadSharp에서 `claude -p`로 simple 모드·lint 검사를 골라 시트 화면을 만들게 했다. implement → verify → finish → done 네 번 모두 훅 지시가 들어갔고(지시문의 훅 전용 문장을 그대로 인용), verify 단계에서 고른 lint만 돌렸으며, 마무리 보고에 코드에 남지 않는 결정을 따로 정리했다. 16턴
- [x] 13. 검증 강제 (ADR 0012)
  - [x] 검증 단계를 지나 넘어가려 할 때 고른 검사의 `run`을 실행하고, 실패하면 이유를 붙여 막는다(PreToolUse 훅 `check-run.sh`). verify도 결과 파일 `.harness/out/verify.json`을 남긴다
  - 원래 조건("검증을 건너뛰는 일이 관찰될 때만", 원칙 2)은 발표에 없어 걷었다. 사용자가 발표를 그대로 따르라고 정했다(2026-11-03)
  - [x] 끝내려 할 때 Stop 훅 `stop-gate.sh`가 작업 주인 세션을 done 전에 막는다. plan 단계 승인은 Plan 모드로 받는다(발표 슬라이드 17, ai-bouncer)
  - [x] 발표에 없는 세션 구분·도구 없는 반복 방지·10번 연속 시 사용자에게 넘기기·run 시간 제한은 ai-bouncer를 따랐다
  - 결과가 최신인지는 작업 트리 해시 대신 ai-bouncer의 `bouncer passed`처럼 시각으로 본다(`scripts/harness/passed`)
  - 진행 (2026-11-05): `build`도 결과 파일 `build.json`을 남겨 `run`으로 확인한다. 전에는 `build`만 고른 작업에서 빌드했는지 확인하지 않았다
  - 진행 (2026-11-05): 리뷰도 `run`으로 확인한다(ADR 0016). 리뷰어가 연 파일과 보고서의 차단 수를 훅(`review-record.sh`)이 `review.json`으로 남긴다. IntervalTimer에서 실제 리뷰로 통과, 리뷰 뒤 수정 시 실패를 확인했다
  - 진행 (2026-11-03): ReadSharp #217을 이어서 verify → finish → done까지 마쳤다. 넘어갈 때마다 훅이 lint·verify·e2e의 `passed`를 확인했고, 마무리에서 결정 기록(`docs/wiki/translation/draft-across-sentences.md`)을 남겼다. 기록을 쓰다 `build/` 폴더가 git에서 무시돼 빠지는 일이 있어 `wiki check`가 무시되는 기록을 문제로 잡게 했다
- [x] 14. 플러그인 배포와 init/sync/doctor (ADR 0011)
  - 플러그인은 GitHub 마켓플레이스(이 저장소)로 배포한다. init·sync가 프로젝트 `.claude/settings.json`에 마켓플레이스와 플러그인을 등록해, 커밋하면 팀원에게 설치가 권해진다(발표 슬라이드 38 "하네스도 훅도 그대로")
  - `dev-install`을 `scripts/init`(처음 설치)과 `scripts/sync`(갱신)로 나눴다. 개발 중에는 `sync --dev`가 로컬 설정에서만 이 저장소 디렉터리로 덮어쓴다
  - 하네스 버전은 `plugin.json`의 `version` 하나다. sync가 `.harness/harness.json`에 남기고, 프로젝트 안 `scripts/harness/doctor`가 도구·설정·지침 연결·플러그인 버전을 점검한다
  - 진행 (2026-11-03): ReadSharp 시험장을 sync하고, 빈 설정 디렉터리(`CLAUDE_CONFIG_DIR`)로 팀원처럼 GitHub에서 마켓플레이스 추가·플러그인 설치를 했다. GitHub `main`의 플러그인(0.2.0)이 프로젝트 파일(0.3.0)보다 오래됐다고 doctor가 잡았다. `sync --dev`로 되돌린 뒤에는 폴더 버전(0.3.0)으로 통과했다
  - 남은 것: 머지 뒤 GitHub 0.3.0으로 doctor 통과 확인
  - 진행 (2026-11-05): ReadSharp·IntervalTimer에서 `.claude/settings.json`의 git 무시를 풀고 커밋했다(ReadSharp #227, IntervalTimer #24). 두 곳 다 ai-bouncer 설치가 넣은 무시 줄이 원인이었다
- [x] 15. 두 번째 프로젝트 적용: IntervalTimer(`~/Code/IntervalTimer`, Tuist 다중 모듈. xcodeproj 앱은 시험장 ReadSharp로 대신한다)
  - 진행 (2026-11-03): `~/Code/IntervalTimer-harness` 워크트리(`chore/ios-harness`)에 설치했다. 하네스 코드는 detect 한 곳만 고쳤고, 나머지는 프로젝트 설정 파일만 달랐다(발표 슬라이드 38 "같은 훅, 저장소마다 다른 config")
    - detect가 `Project(name: projectName)`처럼 이름이 상수인 manifest에서 앞쪽 `.debug(name: "Debug")`를 이름으로 잡아 `Debug.xcworkspace`를 냈다. `Project(`·`Workspace(` 호출 뒤의 name을 읽고 상수를 풀도록 고쳤다
    - 루트 `Project.swift` 하나에 모듈 타깃이 다 있어 `modules`는 `null`이다. 그래서 어느 파일이 바뀌어도 앱 빌드와 `ServicesTests`를 돌린다. 테스트 타깃이 하나뿐이라 지금은 손해가 없다
    - `verify`: 빌드 통과(276s, generate 포함), 테스트 41개 중 1개 실패. 실패는 하네스와 무관하게 main에 있던 것이다(`WorkoutTimerEngineTests.swift:205`, 기대값 185 / 실제 215)
    - 새 세션이 검증 명령과 `ServicesTests` 스킴을 AGENTS.md·project.json에서 찾아 답했다. ai-bouncer 설정은 이 브랜치에서 뺐다(ADR 0005)
- ~~16. Codex 어댑터~~: 뺐다(2026-11-05). 위 "남은 일의 순서" 참고
- [ ] 17. 평가: fixtures와 `claude plugin eval`로 하네스가 없을 때와 비교
- ~~18. 래칫·청소 자동화~~: 뺐다(2026-11-05). 위 "남은 일의 순서" 참고
- [x] 19. 정책·결정 기록 (발표의 LLM Wiki, ADR 0008)
  - 기술 기록(`kind: fact`): 확인된 동작, 확인 방법, 함의, 안 다룬 것. 결정 기록(`kind: rule`): 규칙, 적용 범위, 근거(기획서·Slack 링크), 예외
  - 프로젝트 안 `docs/wiki/`와 `scripts/harness/wiki`(search·check)로 시작했다. 검색은 `.harness/state/wiki-search.log`에 남긴다
  - 언제 찾고 쓰는지는 프로젝트 `checks.json`의 단계 prompt 한 줄로 둔다. 기록과 반대되는 요청은 근거와 함께 사용자에게 묻는다
  - 진행 (2026-11-03): ReadSharp 임시 워크트리에서 같은 QA 티켓을 기록 유무로 비교했다. 두 쪽 모두 검색 후 고치지 않고 물었고, 기록이 있는 쪽만 결정 날짜와 이유를 근거로 들었다. 코드 주석으로 의도가 보이는 경우라 판단이 갈리지는 않았다
  - 남은 것: 여러 저장소가 함께 쓰는 별도 기록 저장소와 검색 MCP, 열람·반영 측정. 필요해지면 한다
- [x] 20. 컨벤션 센서 확장과 빌드·Tuist 절차 스킬 (후보 11에서 넘김)
  - [x] 레이어 의존 검사(Konsist 대응, ADR 0014): `conventions.json`의 `kind: dependency`. Tuist 프로젝트에서 `tuist graph`의 직접 의존을 본다. 단일 모듈 앱은 `pattern`의 경로 규칙(`included` + 금지 정규식)으로 쓴다
  - [x] 형식 규칙(ktlint 대응, ADR 0014): `kind: format`. Xcode에 들어 있는 swift-format으로 고른 규칙만 본다(SwiftFormat은 설치가 필요해 쓰지 않았다)
  - [x] `tuist inspect` 래퍼(ADR 0015): `tuist inspect implicit-imports`로 의존 목록에 없는 import를 찾아 `dependency` 규칙에 넣었다. ADR 0014의 "선언하지 않은 import는 컴파일러가 막는다"는 전제가 틀려서다
  - ~~`ios-build-fix`, `tuist-change` 스킬~~: 뺐다(2026-11-05). 첫 로드맵에 이름만 있었고, 발표·ai-bouncer에 근거가 없으며, 시험장에서 이 스킬이 없어 생긴 실패가 없다
  - 진행 (2026-11-05): IntervalTimer에 모듈 의존 4개·형식 3개, ReadSharp에 형식 3개를 넣었다. 기존 코드는 통과했고, 일부러 넣은 Feature 사이 의존·`try!`·`String!`·소문자 타입 이름을 모두 잡았다. 의존 위반은 그 모듈을 선언한 `Project.swift` 줄로 나온다

## 만들지 않는 것

발표 팀이 써 본 뒤 걷어낸 것이다. 실패가 관찰되기 전에는 넣지 않는다.

- 구현을 페이지·스텝으로 잘게 나누는 과정: 최신 모델에서는 나눠도 완성도가 같거나 낮았다(웹 큰 작업에서 나눔 93.1%, 안 나눔 94.4%)
- 테스트를 먼저 쓰지 않으면 코드를 못 쓰게 막는 훅
- 모든 작업에 같은 검사를 돌리기
- 계획 여부를 AI가 고르기: 큰 작업을 계획 없이 하면 결함 비율이 78%였고(계획하면 25%), 작업 크기는 AI도 미리 알기 어렵다

## 단위마다 확인하는 방법

- 완료 기준은 시험장 워크트리(`~/Code/EnglishStudy-harness`)에서 실행해 확인한다.
- 스크립트와 훅은 입력 픽스처를 넣는 셸 테스트(`tests/`)로 회귀를 막는다.
- 중요한 결정은 `docs/decisions/`에 ADR로 남긴다.
