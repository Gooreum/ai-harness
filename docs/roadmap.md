# 로드맵

여러 프로젝트에서 재사용할 하네스를 작업 단위로 나눠 하나씩 쌓아간다. 단위 1~20은 iOS용으로 만들었고, 단위 21부터는 어떤 플랫폼에서든 쓰는 범용 하네스로 넓힌다.
단위 하나는 세션 하나 분량이다. 커밋 1~3개로 마무리하고, 끝나면 여기 체크박스를 갱신한다.

지금: 23

(위 줄은 로드맵 패널이 읽는다. 작업 단위를 바꾸면 함께 고친다.)

## 정해진 것

- 에이전트: Claude Code만 지원한다. Codex 어댑터(후보 16)는 뺐다(2026-11-05).
- 스크립트: bash + jq로 작성한다. 둘 다 macOS에 기본으로 들어 있어 따로 설치할 필요가 없다. macOS만 지원한다(ADR 0023).
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
3. 후보 10의 서버 응답 조작
   - 진행 (2026-11-05): 끝냈다(ADR 0017)
- 후보 17(평가)은 뺐다(2026-11-05). 사용자가 정했다. 발표에 없다.
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
  - 진행 (2026-11-05): 응답을 걸지 않아도 실패 화면이 떠 헛통과하는 것을 막았다. 시나리오 옆 `<이름>.network.json`의 기대 응답이 그 흐름 동안 서버 기록에 있어야 통과한다. ReadSharp에서 응답 없이 돌리면 "500 응답이 없었다(받은 요청 … 404)"로 실패, 500을 걸면 통과, 회귀 4개는 그대로 통과했다
  - 진행 (2026-11-05): 사용자가 원할 때만 쓰게 했다. 지시는 "사용자가 요청했을 때만"으로, 그런 시나리오는 `tags: [network]`로 두고 인자 없는 실행·회귀 묶음에서 뺀다
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
- ~~17. 평가~~: 뺐다(2026-11-05). 위 "남은 일의 순서" 참고
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

## 범용 하네스 (2026-11-06~)

어떤 플랫폼(iOS, React Native, Android, 웹, 서버, 앱이 아닌 저장소)이든 이 하네스로 개발하게 넓힌다.

- 근거: 발표 슬라이드 19·21·38. v1이 다른 플랫폼에서 못 쓴다는 피드백을 받았고, v2는 "하네스도 훅도 그대로, 저장소마다 config만 다르게" 했다. 웹 저장소는 lint·typecheck·unit-test·build, LLM Wiki 저장소는 bats를 검사로 썼다.
- 구조: **공통 핵심 + 플랫폼 묶음**이다. → 2026-11-06에 플랫폼 묶음을 없앴다(단위 31, ADR 0024).
  - 공통 핵심: 단계 훅, Stop 게이트, `task` 스킬, `checks.json`, `passed`, `wiki`, 리뷰 절차.
  - 플랫폼 묶음: 빌드·테스트·e2e 스크립트, 규칙, 권한, 생성 파일 목록, 리뷰 확인 항목, doctor 항목.
  - 한 프로젝트가 묶음을 여러 개 쓸 수 있다. React Native는 JS, iOS, Android를 함께 쓴다.
- 검증 방식은 플랫폼마다 다르다. 특히 e2e가 그렇다.
  - 공통 규칙: 기능 시나리오와 영향 시나리오를 나누고, 조건은 시나리오 안에서 만들고, 증거를 남기고, 배포 전에 회귀 묶음을 돌린다.
  - 도구: 모바일(iOS, Android, RN, Flutter)은 Maestro를 함께 쓰고 앱 설치만 simctl·adb로 나눈다. 웹은 Playwright, 서버는 HTTP 시나리오를 쓴다.
- RN 시험장: PetCycle(`~/Code/PetCycle`). 사용자가 정했다(2026-11-06). iOS와 Android를 둘 다 확인한다.
  - Expo이고, `ios/`·`android/`는 git이 무시하는 prebuild 생성물이다(CNG). 검사 명령은 `npm test`(jest)와 `npm run typecheck`가 있고, `.maestro/`는 아직 없다
  - 원본에서 사용자가 작업 중이라 별도 워크트리(`~/Code/PetCycle-harness`)에서 한다. ai-bouncer 설정은 그 브랜치에서 뺀다(ADR 0005, IntervalTimer와 같다)
  - `server/`와 웹(`expo start --web`, `invite-site/`)도 있어, 웹·서버 묶음(29)을 할 때도 시험장이 될 수 있다
- 순서: 지금 있는 문제(21) → 공통 핵심(22) → 묶음 구조(23) → 이름 변경(24) → 리뷰어·권한(25) → 묶음 없는 저장소(26) → RN(27·28).
  - 웹(29)과 Linux(30)는 필요해지면 한다. → 2026-11-06에 27~30을 묶음 없이 `record`로 하는 것으로 다시 정했다(ADR 0023).
  - 각 묶음은 실제 시험장에서 막히는 것을 보고 만든다. 미리 다 대비하지 않는다(진행 원칙 1).
- 점검 기록: 2026-11-06에 코드를 읽어 특이점 100개를 찾았다. 아래 단위의 할 일이 그 목록이다. "관찰되면 한다"에 둔 것은 시험장에서 실제로 막힐 때 한다.
- 정할 것 (해당 단위를 시작할 때 묻는다)
  - 새 이름(저장소·플러그인·마켓플레이스): 단위 24
  - RN iOS 빌드 방식, 컨벤션 검사 방식, 웹 e2e 도구: 하네스가 정하지 않고 저장소가 `checks.json`에 적는다(2026-11-06, ADR 0023)
  - 지원 OS: macOS만(2026-11-06)
  - detect가 알아볼 범위(Flutter, KMP, nx·turborepo 모노레포), 한 저장소에 앱이 여럿일 때 쓸 설정: 단위 23

- [x] **21. 지금 있는 문제 먼저 고치기** (iOS 시험장에서 확인)
  - 무엇을 하나: 범용으로 넓히기 전에, 지금 iOS에서도 틀리게 동작하는 것을 먼저 고친다. 구조를 옮기면서 고치면 무엇 때문에 깨졌는지 구분하기 어렵다.
  - 각 항목은 "문제 → 고치는 방법"이다. 근거가 발표·ai-bouncer에 있으면 적었다. 둘 다 없는 것은 시험장에서 겪은 문제이거나 코드를 읽어 찾은 것이다.
  - [x] 작업 시작 기록: 작업을 시작한 커밋을 남기지 않고, 새 작업인지 "제목+모드"로 구분해 같은 제목으로 다시 시작하면 지난 결과가 통과한다
    - → 새 작업이 시작될 때 HEAD를 `.harness/state/task.base`에 적는다(ai-bouncer `start`의 `base_sha`)
    - → `stage-context.sh`가 지난번에 본 단계를 적어 두고, 그 단계가 없거나 `done`이었다가 다른 단계가 되면 새 작업으로 본다. 그때 `task.started`의 시각과 `task.base`를 새로 적는다(ai-bouncer `.started`)
    - `passed`·리뷰·unit-test가 이 기록을 같이 쓴다
  - [x] passed 기준 커밋: 바뀐 파일을 HEAD 기준으로 봐서, 작업 중에 커밋하면 옛 결과가 통과한다
    - → `task.base` 이후 바뀐 파일과 추적 안 된 파일을 본다(ai-bouncer `result_fresh`)
  - [x] passed 안내 문구: 결과가 없을 때 `scripts/harness/<이름>`을 실행하라고 안내해, review 같은 검사에는 틀린 안내다
    - → "`.harness/checks.json`에 적힌 이 검사의 prompt대로 실행한다"로 바꾼다
  - [x] unit-test 기준 커밋: 작업 중에 커밋하면 "바뀐 파일 없음"으로 통과한다
    - → 작업 중이면(`task.json`의 stage가 `done`이 아님) `task.base` 기준으로 본다. `--base`를 주면 지금처럼 그 브랜치 기준이다
  - [x] unit-test 쓰는 모듈: 바뀐 모듈만 테스트하고 그 모듈을 쓰는 모듈은 테스트하지 않는다
    - → 다른 모듈의 manifest에 바뀐 모듈 이름이 나오면 그 모듈도 넣고, 더 늘지 않을 때까지 반복한다. 많이 넣는 쪽으로 틀린다(빠뜨리는 것보다 낫다)
    - 시험장 둘 다 모듈 구조가 없어 회귀 테스트로만 확인한다
  - [x] unit-test 코드 아닌 파일: 문서만 바꿔도 앱 전체를 빌드·테스트한다
    - → 코드가 아닌 파일(`*.md`, `docs/`, `.maestro/`, `.claude/`, `.agents/`)은 거른다. 이미지는 앱 리소스일 수 있어 거르지 않는다. 남는 파일이 없으면 "코드 변경 없음"으로 통과한다
  - [x] unit-test 테스트 0개 표시: 테스트가 하나도 돌지 않아도 다른 통과와 똑같이 보인다
    - → 결과에 돌린 테스트 수를 남기고, 0이면 요약 첫머리에 "테스트 0개"를 적는다. 통과 여부는 바꾸지 않는다(테스트가 없는 프로젝트도 있다)
  - [x] e2e 오래된 앱: `--no-build`는 예전에 빌드한 앱으로 통과할 수 있다
    - → 앱 번들의 시각이 바뀐 코드 파일보다 오래됐으면 멈추고 다시 빌드하라고 알린다
  - [x] e2e 시뮬레이터 잠금: 워크트리 두 곳이 같은 시뮬레이터를 골라 동시에 돌리면 서로 덮어쓴다
    - → 고른 기기에 잠금을 건다(사용자 임시 폴더, 워크트리 경로와 프로세스 번호). 다른 워크트리가 쓰는 중이면 같은 런타임의 다른 iPhone을 고르고, 남은 기기가 없으면 어느 워크트리가 쓰는지 알리고 멈춘다. 프로세스가 끝난 잠금은 무시한다
  - [x] e2e 가짜 응답 포트: 포트가 커밋되는 `project.json`에 있어 같은 프로젝트의 워크트리끼리 겹친다(ReadSharp 원본과 harness 워크트리가 둘 다 18787)
    - → 적힌 포트가 이미 쓰이면 MCP 서버가 빈 포트를 골라 띄우고, 실제 포트를 `.harness/state/network.port`에 적는다. `e2e`는 이 파일을 먼저 읽는다
  - [x] install 따로 실행: `commands.install`은 `generate`가 있을 때만 돈다. CocoaPods를 쓰는 xcodeproj 프로젝트는 `pod install`이 돌지 않는다
    - → install을 generate와 따로 판단한다
  - [x] 설치 지문 Podfile: 설치 지문이 Tuist 파일만 본다
    - → `Podfile`과 `Podfile.lock`도 본다
  - [x] 리뷰 대상: 작업 전부터 있던 추적 안 된 파일이 섞인다
    - → `task.base` 이후 바뀐 파일과, 추적 안 된 파일 중 작업 시작 뒤에 고친 것만 넣는다
  - [x] 단계 순서 한 곳: 단계 순서(plan/simple)가 `stage-context.sh`와 `check-run.sh` 두 곳에 따로 있다
    - → `plugin/hooks/flows.json` 한 곳에 두고 둘이 읽는다
  - [x] doctor 규칙 폴더 확인: 규칙 폴더 git 무시 여부를 `swift.md`로 확인해 Swift가 아닌 프로젝트에서 틀린다
    - → 어느 프로젝트에나 있는 `wiki.md`로 확인한다
  - [x] sync 지우는 범위: `scripts/harness/`·`.claude/rules/harness/`에서 template에 없는 파일을 지워, 팀이 넣은 스크립트도 지워진다
    - → 설치한 파일 목록을 `.harness/harness.json`에 적고, 그 목록에 있었는데 template에서 사라진 것만 지운다. 목록이 없는 첫 갱신에서는 지우지 않는다
  - [x] testing.md 예외: "프로덕션 코드에 테스트 전용 분기를 넣지 않는다"가 `maestro.md`의 테스트용 실행 인자(`-HarnessNetworkBaseURL`)와 충돌한다
    - → `testing.md`에 예외를 적는다: e2e 실행 인자를 읽는 코드는 `#if DEBUG` 안에 두고 `maestro.md`를 따른다
  - [x] 응답 서버 버전: 가짜 응답 서버의 `VERSION`이 0.9.2에 머물러 있다
    - → 손으로 맞추지 않고 `plugin.json`의 버전을 읽는다
  - 완료 기준: 고친 것마다 회귀 테스트가 있고, ReadSharp·IntervalTimer에서 기존 작업 흐름이 그대로 통과한다
  - 진행 (2026-11-06): 18개 모두 고치고 회귀 테스트를 붙였다(0.9.8). ReadSharp 확인용 워크트리에서 확인했다
    - 문서만 바꾸면 "코드 변경 없음", 작업 중 커밋한 코드도 바뀐 파일로 잡고 빌드·테스트 221개 통과
    - 결과 뒤에 고치고 커밋하면 `passed`가 막는다
    - 다른 워크트리가 기기를 잡고 있으면 다른 iPhone을 쓰고, `--no-build`로 옛 앱이면 멈춘다
    - 회귀 e2e 4개 통과(행동 로그 4)
    - IntervalTimer 확인용 워크트리(0.9.4 → 0.9.8): 문서만 바꾸면 건너뜀, 작업 중 커밋한 코드로 generate·빌드·테스트 130개 통과, `passed` 통과, 회귀 e2e 3개 통과
    - 두 시험장(`EnglishStudy-harness`, `IntervalTimer-harness`)은 열린 세션이 끝나면 0.9.8로 올린다
- [x] **22. 공통 핵심 떼어 내기와 `record`**
  - `lib.sh`를 공통과 iOS로 나눈다. `harness_init`이 Xcode를 고르고 `simctl`을 부르지 않게 한다. 지금은 `passed`·`wiki`도 이 과정을 거친다
  - `scripts/harness/record <이름> <명령>`: 어떤 명령이든 실행하고 `.harness/out/<이름>.json`을 남긴다(ai-bouncer `bouncer record`)
    - 결과 형식은 JSON(`passed`, `summary`, 종료 코드)으로 둔다. ai-bouncer는 로그 끝에 `exit: N`을 쓴다. 이 차이는 ADR에 남긴다
    - 전체 로그는 `.harness/out/<이름>.log`에 두고, 화면에는 끝부분만 보여 준다(성공은 짧게, 실패는 첫 에러부터). ai-bouncer는 전부 보여 준다. 이 차이도 ADR에 남긴다
    - `CI=1`을 넣어 감시 모드(watch)로 떠서 끝나지 않는 일을 막는다
    - 검사 이름은 영문·숫자·`-`·`_`만 허용한다(ai-bouncer와 같다)
    - 10분 넘게 걸리는 명령(Gradle, e2e)은 백그라운드로 돌리고 결과 파일을 보라고 안내한다
  - 파일을 고치는 검사(`--fix`, 포매터, 설치)는 다른 검사보다 먼저 돌리라고 규칙에 적는다. 나중에 돌리면 앞 결과가 낡은 것이 된다
  - jq가 없으면 모든 훅이 조용히 꺼진다. doctor와 단계 지시에서 알린다
  - ADR: 공통 핵심 + 플랫폼 묶음 구조
  - 완료 기준: iOS 스크립트 없이 `record`와 `passed`만으로 `checks.json`의 검사가 게이트를 통과·실패한다
  - 결과(2026-11-06): `tests/record.test.sh`에서 결과 없음·실패는 막고, 통과는 넘기고, 고친 뒤 낡은 결과는 다시 막았다. IntervalTimer 임시 워크트리(0.9.9)에서 `record`·`passed`·`wiki`가 `xcrun`을 부르지 않았고, unit-test(테스트 130)·`passed`·lint가 그대로 통과했다. ADR 0018
- [x] **23. 플랫폼 묶음과 설치**
  - [x] 묶음 구조: `packs/<묶음>/pack.json`이 template 안의 묶음 파일(스크립트, 규칙 `rules/harness/<묶음>/`)을 적고, 권한(`settings.json`), AGENTS.md 관리 블록 조각(`agents-*.md`), doctor 항목(`<묶음>-doctor.sh`)을 둔다(ADR 0019). 생성 파일 목록은 단위 25에서 묶음으로 옮긴다
  - [x] 한 프로젝트가 묶음을 여러 개 고를 수 있다. 고른 묶음을 설치 기록(`harness.json`의 `packs`)에 남기고, 고르지 않은 묶음의 파일은 설치 기록의 `files`로 지운다
  - [x] `project.json`: `platforms`를 두고 iOS 키를 `ios` 아래로 옮겼다. `schemaVersion` 2. 옛 설정은 sync가 옮기고, 생성 파일 보호 훅은 옛 형식도 읽는다
  - [x] detect가 Xcode 프로젝트를 보고 `ios`를 고른다. `package.json`·`gradlew`·`pyproject.toml`·`Cargo.toml`·`go.mod`는 묶음이 없다고 알리고 공통 파일만 설치한다
  - [x] 검사 목록: 저장소에서 찾은 명령과 묶음 추천 검사를 `scripts/harness/setup`이 보여 주고, 에이전트가 사용자에게 물어 `checks.json`을 쓴다(ai-bouncer `setup.sh`)
  - [x] sync가 권한 규칙을 더하기만 하고 지우지 않는다. 하네스가 넣은 항목은 지울 수 있게 한다
  - [x] 하위 폴더 프로젝트(모노레포)
    - 스크립트는 git 최상위를 루트로, 훅은 가장 가까운 `.harness/project.json`을 루트로 쓴다. 맞춘다
    - `git diff --name-only`가 저장소 루트 기준 경로를 내서 리뷰가 "바뀐 파일 0개"로 통과한다. `--relative`를 쓴다
  - [x] AGENTS.md 제목을 `app.scheme`이 아니라 폴더 이름으로 한다
  - [x] doctor가 `checks.json`의 run 명령과 결과 이름이 실제로 있는지 확인한다
  - 완료 기준: iOS 묶음으로 ReadSharp·IntervalTimer를 sync했을 때 지금과 같게 돈다
  - 결과(23-1, 0.9.10): 묶음 구조·설정 새 형식·detect. 시험장 두 곳의 HEAD로 만든 임시 워크트리에 sync하니 설정이 옮겨지고 규칙이 `rules/harness/ios/`로 옮겨졌다(옛 자리는 지움). 파일 목록이 없는 옛 설치 기록이라 옮긴 규칙의 옛 자리를 이름으로 지우게 했다
  - 결과(23-2, 0.9.11): `checks.json`은 init이 쓰지 않고 `scripts/harness/setup` 안내로 사용자에게 물어 정한다(ai-bouncer `setup`, 처음엔 초안을 쓰게 했다가 사용자가 원하지 않아 바꿨다). sync가 지난번에 넣은 권한 규칙 중 빠진 것만 지우고, 스크립트가 가장 가까운 `.harness/project.json`을 루트로 쓴다. 시험장 두 곳의 HEAD로 만든 임시 워크트리에서 unit-test(221·130)와 `passed`가 그대로 통과했다(ADR 0020)
- [x] **24. 이름 바꾸기와 이전**
  - 저장소, 플러그인(`ios-harness`), 마켓플레이스(`ios-ai-harness`, owner `woong`), 리뷰어(`ios-reviewer`) 이름
  - 이미 설치한 곳이 깨지지 않게 한다: `enabledPlugins` 키, doctor에 박힌 id, 리뷰 기록 훅의 이름 비교, 시험장 `checks.json` 지시문의 `ios-harness:ios-reviewer`. sync가 옛 항목을 지우고 새 항목을 넣는다. 둘이 같이 켜지면 훅이 두 번 돈다
  - README, `docs/*`, AGENTS.md·CLAUDE.md, `plugin.json`·`marketplace.json`의 설명
  - 완료 기준: 시험장 두 곳이 sync 한 번으로 새 이름의 플러그인을 쓰고, 옛 플러그인이 꺼져 있다
  - 결과(2026-11-06, 0.10.0): 저장소 `Gooreum/ai-harness`, 마켓플레이스 `ai-harness`(owner `woong` 그대로), 플러그인 `harness`, 리뷰어 `reviewer`(사용자가 정했다). sync가 설정에서 예전 마켓플레이스·플러그인 키를 지우고 `checks.json`의 `ios-harness:ios-reviewer`를 새 이름으로 바꾼다. 예전 플러그인이 켜져 있으면 doctor가 알린다(ADR 0021). 시험장 두 곳의 HEAD로 만든 임시 워크트리에서 `sync --dev` 한 번으로 설정에 새 이름만 남았고, 새 플러그인을 설치하니 doctor가 문제 없음이었다. 이 Mac의 사용자 설정에 폴더 마켓플레이스가 예전 이름으로 등록돼 있어 새 이름으로 다시 등록했다
- [x] **25. 공통 리뷰어와 권한**
  - 리뷰어는 공통 절차(바뀐 파일 열기, 기존 영향 찾기, 보고 형식)만 두고, 확인 항목과 편법 목록은 묶음 규칙에서 읽는다
    - 편법 예: 스냅샷 갱신(`-u`), `@ts-ignore`, `eslint-disable`, `any`, tsconfig strict 끄기, `@Suppress`
    - 리뷰어 설명과 관리 블록이 늘 iOS를 말하면 RN에서 JS만 고칠 때도 iOS 지시가 섞인다(발표 슬라이드 19 "웹 작업인데 안드로이드 검증 스킬을 불러와요")
  - 리뷰어가 열지 않아도 되는 파일(lock 파일, 스냅샷, 생성 코드, `webp`·`woff2`·`ico`·`jar`·`aar`·`so`·`wasm`)을 묶음이 정한다
  - 생성 파일 보호(`protect-generated.sh`)도 목록을 묶음과 설정에서 받는다. 예: Expo prebuild의 `ios/`·`android/`, GraphQL·OpenAPI codegen, Prisma client, lock 파일
  - 묻는 명령(ask)을 묶음이 더한다: `npm publish`, `eas submit`·`eas update`, `fastlane`, gradle publish, `firebase deploy`, `vercel`. `git -C`처럼 `npm --prefix`, `yarn --cwd`, `gradle -p` 변형도 넣는다
  - 비밀 파일 막기(deny)를 묶음이 더한다: `*.jks`, `*.keystore`, `keystore.properties`, `local.properties`, `.npmrc`, Expo `credentials.json`. `.env`는 Read뿐 아니라 Bash로 읽는 것도 막는다
  - 내려받은 저장소의 `checks.json` run이 자동으로 실행된다는 점을 문서와 doctor에 적는다
  - 관찰되면 한다: 바뀐 파일이 수백 개(codemod, 이름 바꾸기)일 때의 리뷰 규칙
  - 완료 기준: iOS 시험장에서 지금과 같은 리뷰 결과가 나오고, 묶음 규칙을 바꾸면 리뷰 항목이 따라 바뀐다
  - 결과(2026-11-06, 0.11.0): 리뷰어 지시문에서 iOS를 빼고, iOS 항목은 `rules/harness/ios/review.md`로 옮겼다. 생성 파일은 `project.json`의 `generated` 글롭으로 받아 편집을 막고 리뷰 대상에서 뺀다. 공통 권한에 배포 명령 ask와 Android·npm 비밀 파일 deny, `.env`를 Bash로 읽기 deny를 더했다. doctor가 `passed`가 아닌 run을 알린다(ADR 0022). ReadSharp HEAD로 만든 임시 워크트리에서 `claude -p --plugin-dir`로 `harness:reviewer`를 불러 `@unchecked Sendable`을 `ios/review.md` 근거로 차단했고, `review.md`에 `print(` 항목을 더하니 그 항목으로 차단했다(둘 다 review.json 기록). 바뀐 파일이 수백 개일 때의 규칙은 관찰되면 한다
- [x] **26. 묶음 없는 저장소**
  - 빌드·e2e가 없는 저장소에서 `record`, `passed`, `wiki`, 리뷰만으로 돈다(발표의 LLM Wiki 저장소)
  - 시험장: 이 하네스 저장소 자체(`bash tests/run.sh`)
  - 앱이 없는 iOS 저장소(SPM 라이브러리)도 doctor가 문제로 치지 않게 한다
  - 완료 기준: 이 저장소에서 `task`로 시작한 작업이 `record`로 남긴 테스트 결과로 게이트를 통과한다
  - 결과(2026-11-06, 0.11.1): 이 저장소의 사본에 묶음 없이 설치하니 setup이 `tests/run.sh`를 못 찾고, 리뷰가 iOS 추천 검사에만 있었다. setup이 `tests/run.sh`·`*.bats`·`Package.swift`를 찾고, 리뷰를 공통 추천 검사(`common-checks.json`)로 옮겼다. 앱 없는 Swift 패키지는 detect가 iOS 묶음을 고르지 않는다. 사본에서 `claude -p --plugin-dir`로 `task`(simple, test·review)를 돌려 `record test "bash tests/run.sh"`(92초 통과)와 리뷰로 done까지 갔다. 그때 리뷰 보고서 앞에 다른 문장이 있으면 "발견 없음"을 못 읽는 문제를 찾아 고쳤다(ADR 0023)
- [x] **27. JS·React Native 저장소** (시험장: PetCycle)
  - 다시 정함(2026-11-06, ADR 0023): 묶음을 만들지 않는다. 빌드·테스트·컨벤션 검사는 저장소의 명령을 `checks.json`에 `record`로 적는다. 아래 원래 할 일 중 하네스가 도구를 고르거나 설정을 만드는 것은 하지 않는다. 남는 것: detect가 Expo prebuild 생성물을 `generated`로 제안, setup이 찾는 명령 확인, PetCycle에서 게이트 통과 확인
  - 바뀐 것만 테스트: `jest --findRelatedTests`, `vitest related`
  - 의존성: 설치 지문에 `package-lock.json`·`yarn.lock`·`pnpm-lock.yaml`을 넣고 `node_modules`를 설치한다. 패키지 매니저는 lock 파일로 고른다(ai-bouncer `setup.sh`)
  - Expo prebuild는 `generate` 자리에 둔다
  - RN iOS: CocoaPods, `ios/.xcode.env`의 node 경로
  - doctor: node 버전(`.nvmrc`·volta), 비대화형 셸에서 nvm이 불러와지는지, CocoaPods
  - 규칙: `testing.md`의 경로(`__tests__`, `*.test.ts`)와 내용을 공통·묶음으로 나눈다. 컨벤션 검사 방식은 위 "정할 것"대로
  - 완료 기준: PetCycle에서 `task` 작업 하나가 lint·typecheck·unit-test·review를 고르고 게이트를 통과한다
  - 결과(2026-11-06, 0.11.2): detect가 Expo의 git 무시 `ios/`·`android/`를 `generated`로 넣고 묶음은 고르지 않는다. setup이 `npm run test`·`npm run typecheck`와 jest의 `--findRelatedTests`를 찾는다. PetCycle HEAD로 만든 임시 워크트리에서 `claude -p --plugin-dir`로 setup(test·typecheck·review)을 쓰고 `task`를 돌렸다. HEAD에 이미 있는 typecheck 에러(`app.config.ts:72`)와 jest 실패 2건 때문에 verify에서 막혔고, 에이전트는 검사를 빼지 않고 사용자에게 물었다. 관련 테스트만 도는 `test-related`(`npx jest --findRelatedTests`)와 review로 다시 돌리니 done까지 갔다. 리뷰어가 `git -C`를 써서 권한 규칙에 안 맞던 것을 고쳤다. PetCycle에 eslint가 없어 lint는 고르지 않았다
- [x] **28. 모바일 e2e를 Android·RN으로**
  - 다시 정함(2026-11-06, ADR 0023): 하네스가 Android·RN e2e 스크립트를 만들지 않는다. 저장소가 `maestro test` 등을 `record`로 적는다. 아래 원래 할 일은 하지 않고, 가짜 응답 서버를 Android에서 쓰는 방법만 문서에 남긴다
  - 결과(2026-11-06): `docs/checks.md`에 `record`로 적는 Android·웹 e2e 예시를, `docs/plugin.md`에 가짜 응답 서버를 Android에서 쓰는 방법(`10.0.2.2`·`adb reverse`, 디버그 평문 허용)을 적었다. 코드는 바꾸지 않았다. Android 에뮬레이터에서는 돌려 보지 않았다
  - 앱 id가 플랫폼마다 다르다(bundleId, applicationId). `--platform`과 앱 id 두 개를 둔다. 결과는 `e2e-ios`·`e2e-android`로 나눈다
  - Android
    - 빌드 변형(debug/release, flavor)이 iOS 스킴에 해당한다. debug의 `applicationIdSuffix` 때문에 앱 id가 달라지니 빌드 결과에서 읽는다
    - 기기를 고를 때 버전을 고정하지 않는다. 켜진 에뮬레이터를 먼저 쓰고, 없으면 최신 AVD를 띄운다
    - doctor: JAVA_HOME, ANDROID_HOME, adb
  - RN 디버그 빌드는 Metro가 떠 있어야 한다. 워크트리마다 포트를 나눈다(DerivedData를 워크트리별로 나눈 것과 같다)
  - 가짜 응답 서버
    - Android 에뮬레이터에서는 Mac이 `10.0.2.2`로 보인다(또는 `adb reverse`)
    - Android 9 이상은 `http://` 평문을 막는다. 디버그 `network_security_config`를 안내한다
    - 앱 쪽 약속을 묶음별로 둔다: iOS 실행 인자, Android intent extra, RN JS 설정
  - Maestro 규칙의 요소 id 표현을 묶음별로 쓴다(RN `testID`, Android `testTag`·`resource-id`). 클립보드 규칙은 iOS 묶음으로 옮긴다
  - 관찰되면 한다: 행동 로그(logcat), 녹화(`adb screenrecord`는 3분 제한), 계측 테스트(`connectedAndroidTest`), 에뮬레이터 부하로 생기는 흔들림과 재시도 규칙
  - 완료 기준: PetCycle에서 같은 시나리오가 iOS 시뮬레이터와 Android 에뮬레이터에서 통과한다
- [x] **29. 웹 묶음** (웹 시험장이 생기면)
  - 다시 정함(2026-11-06, ADR 0023): 웹 묶음을 만들지 않는다. e2e 도구(Playwright 등)는 저장소가 고르고 `record`로 적는다. 아래 원래 할 일은 웹 시험장에서 막히면 그때 본다
  - 결과(2026-11-06): `docs/checks.md` 예시에 Playwright를 `record`로 적는 방법을 넣었다. 가짜 응답 서버의 CORS는 웹에서 막히면 넣는다. 코드는 바꾸지 않았다
  - e2e는 위 "정할 것"대로(Playwright 또는 Maestro)
  - dev 서버를 띄우고, 워크트리마다 포트를 나눈다
  - 가짜 응답 서버: CORS를 응답한다(지금은 OPTIONS에도 404). Playwright `page.route`로 충분하면 MCP를 쓰지 않는다
  - 위키 경로를 설정으로 받는다. Docusaurus·VitePress 같은 문서 사이트는 `docs/` 아래를 그대로 공개한다
  - 관찰되면 한다: 서버 e2e(DB·docker), 화면 검증(후보 10)
- [x] **30. Linux 지원** (정하면)
  - 다시 정함(2026-11-06): macOS만 지원한다(사용자 결정, ADR 0023). 아래 원래 할 일은 하지 않는다
  - 결과(2026-11-06): README에 지원 OS를 적었다
  - jq가 기본으로 없고, `shasum`·`nc`·BSD `sed` 문법을 쓴다. `passed`의 `stat -f %m`이 GNU stat에서 깨질 것으로 보인다(확인 필요, ai-bouncer도 같은 코드)
  - 가짜 응답 서버의 `python3` 이름
  - Linux CI를 둔다. 지금은 CI가 없고 테스트가 이 Mac에서만 돈다
- [x] **31. 하네스에서 플랫폼 빼기** (ADR 0024)
  - 정함(2026-11-06): 하네스는 플랫폼을 모른다. 플랫폼마다 무엇을 어떻게 쓰는지는 사용자가 정하고, 하네스는 setup으로 그 설정을 함께 만드는 데까지 한다(사용자 결정)
  - 할 일: `packs/`·iOS 스크립트·규칙·`detect`를 지운다. 훅은 `generated` 글롭만 본다. setup이 검사·생성 파일·보호할 파일·감쌀 스크립트를 묻는다. sync가 예전 iOS 파일을 `scripts/ios/`·`.claude/rules/project/ios/`로 넘긴다
  - 완료 기준: `bash tests/run.sh` 통과. 시험장 사본(ReadSharp)을 sync하면 iOS 스크립트가 `scripts/ios/`로 옮겨지고, 옮긴 스크립트로 검사가 통과한다
  - 결과(2026-11-06): ReadSharp 사본(0.9.7)을 sync하니 스크립트 5개와 규칙 9개가 프로젝트 쪽으로 옮겨지고 checks.json 경로가 바뀌었다. `scripts/ios/build`·`unit-test`(통과 221)·`lint`(100점)와 `passed unit-test`가 통과했다. 시험장 두 곳 실제 sync는 열린 세션이 끝나면 한다
- 범용 하네스에서 관찰되면 할 것
  - 가짜 응답 서버: 스트리밍 응답(SSE), 요청 본문 기록
  - 위키 폴더가 `dist/`·`out/`·`build/` 무시 규칙에 걸리는지 `wiki check`에서 본다(11-03에 한 번 겪었다)
  - 검사가 많아져 질문이 길어질 때 묶음별 기본 선택
  - 진행 중인 작업을 새 세션에 알리는 세션 시작 훅(ai-bouncer `session-start.sh`)
  - `passed e2e`가 어떤 시나리오를 돌렸는지 보지 않는 문제
  - 묶음마다 다른 하네스 버전
  - macOS·iPad·watch 앱, Flutter·KMP 묶음
  - Codex 지원은 단위 16에서 뺀 그대로 둔다

## 만들지 않는 것

발표 팀이 써 본 뒤 걷어낸 것이다. 실패가 관찰되기 전에는 넣지 않는다.

- 구현을 페이지·스텝으로 잘게 나누는 과정: 최신 모델에서는 나눠도 완성도가 같거나 낮았다(웹 큰 작업에서 나눔 93.1%, 안 나눔 94.4%)
- 테스트를 먼저 쓰지 않으면 코드를 못 쓰게 막는 훅
- 모든 작업에 같은 검사를 돌리기
- 계획 여부를 AI가 고르기: 큰 작업을 계획 없이 하면 결함 비율이 78%였고(계획하면 25%), 작업 크기는 AI도 미리 알기 어렵다

## 단위마다 확인하는 방법

- 완료 기준은 시험장 워크트리(`~/Code/EnglishStudy-harness`)에서 실행해 확인한다. 범용 하네스 단위는 그 단위에 적은 시험장(이 저장소, PetCycle 등)에서 확인한다.
- 스크립트와 훅은 입력 픽스처를 넣는 셸 테스트(`tests/`)로 회귀를 막는다.
- 중요한 결정은 `docs/decisions/`에 ADR로 남긴다.
