# 로드맵

여러 iOS 프로젝트에서 재사용할 범용 하네스를 작업 단위로 나눠 하나씩 쌓아간다.
단위 하나는 세션 하나 분량이다. 커밋 1~3개로 마무리하고, 끝나면 여기 체크박스를 갱신한다.

## 정해진 것

- 에이전트: Claude Code를 먼저 지원한다. Codex는 후보 16에서 붙인다.
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
- [ ] **9. 시험장에 새로 구성하고 운영하기**
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

## 이후 후보 (기본 순서이며, 단위 9의 기록으로 조정)

후보 10~13·19는 발표 기준으로 다시 썼다 (ADR 0005). 다른 문서가 번호를 참조하므로 번호는 바꾸지 않는다.

- [ ] 10. 동작·화면 확인
  - Maestro 시나리오와 팀 작성 규칙: 딥링크로 진입, accessibilityIdentifier로 먼저 찾기, 계정은 환경 변수, 반복 단계는 공통 `runFlow`, 끝까지 통과한 시나리오만 저장
  - `tags: [regression]`이 붙은 시나리오를 회귀 묶음으로 모아 배포 전·리팩터링 후에 돌린다. PR에 수정 전후 영상을 붙인다
  - 그다음 화면 검증: `#Preview` 스냅샷 + Figma MCP 수치 비교. 배치는 AI가, 간격·크기 수치는 스크립트가 보고, 판정은 사람이 한다. 픽셀 비교는 쓰지 않는다(발표에서 차이가 전부 빨갛게 나와 실패)
  - 나중에: 서버 응답 조작(500·느린 네트워크·빈 응답), 행동 로그 판정
- [x] 11. 결정적 컨벤션 센서
  - 규칙 목록 `.harness/conventions.json`: AI가 코드에서 초안을 뽑고 사람이 고른다. `lint`가 실행할 때마다 SwiftLint `custom_rules` 설정으로 옮긴다. YAML 대신 JSON을 쓴다(ADR 0006)
  - `scripts/harness/lint`: 100점에서 위반마다 감점하고 `passScore` 이상이면 통과. 결과를 `.harness/out/lint.json`(`passed`, `score`, 위반 목록)으로 남긴다. 검사에는 AI를 쓰지 않는다
  - 첫 대상(ReadSharp): `.sheet(isPresented:)` 금지, `MobileCoreServices` 금지, View에서 `Service.shared`·`AppContainer.shared` 직접 참조 금지
  - 진행 (2026-11-03): ReadSharp 전체 199개 파일 검사에서 주석 속 `.sheet(isPresented:)` 2곳은 잡지 않았고, `SettingsView`의 `AppContainer.shared` 1곳을 찾았다(코드는 따로 고친다). 위반 3개를 넣은 파일은 70점으로 실패. `claude -p`로 시트 화면을 만들게 하자 에이전트가 스스로 `lint`를 돌렸고 처음부터 `.sheet(item:)`으로 작성했다
  - 남은 항목은 후보 20으로 넘겼다. 시험장(xcodeproj 단일 앱)에서 확인할 수 없거나 아직 필요가 관찰되지 않아서다
- [ ] 12. 작업 흐름과 워크플로 스킬
  - 작업을 시작할 때 사람이 모드(plan: 계획 → 구현 → 검증 → 마무리 / simple: 구현 → 검증 → 마무리)와 검사를 고른다
  - 검사 목록 `.harness/checks.json`: 검사마다 `name`, `prompt`(시킬 일), `run`(했는지 확인하는 스크립트). `project.json`(사실)과 나눈다
  - 단계 상태 파일을 고치면 PostToolUse 훅이 그 단계의 prompt를 `additionalContext`로 넣는다. 훅은 검사 내용을 모르고 설정의 글을 옮길 뿐이다
  - 마무리 단계 prompt에 "이번에 정한 정책 정리"를 넣는다 (후보 19)
  - git 관례(커밋 구성, 브랜치, PR 본문에 검증 결과 넣기), 워크트리 (ADR 0002에서 넘긴 항목 포함)
- [ ] 13. (조건부) 검증 강제
  - 다음 단계로 넘어가거나 끝내려 할 때 고른 검사의 `run`을 실행한다. run은 결과 파일(`passed`와 작업 트리 해시)만 확인한다
  - 실패하면 이유를 붙여 막고, 같은 실패가 반복되면 사람에게 넘긴다
  - 에이전트가 검증을 건너뛰는 일이 관찰될 때만 켠다 (원칙 2)
- [ ] 14. 플러그인 배포와 init/sync/doctor
- [ ] 15. 두 번째 프로젝트 적용: coinness-ios (xcodeproj 앱은 시험장 ReadSharp로 대신한다)
- [ ] 16. Codex 어댑터
- [ ] 17. 평가: fixtures와 `claude plugin eval`로 하네스가 없을 때와 비교
- [ ] 18. 래칫·청소 자동화: `harness-retro`, 주기 점검, 지식 큐레이션
- [ ] 19. 정책·결정 기록 (발표의 LLM Wiki)
  - 기술 기록(`kind: fact`): 라이브러리·플랫폼의 실제 동작. 항목은 확인된 동작, 확인 방법, 함의, 안 다룬 것
  - 결정 기록(`kind: rule`): 이 서비스·팀이 정한 규칙. 항목은 규칙, 적용 범위, 근거(기획서·Slack 링크), 예외
  - 마무리 때 쓰고(비슷한 문서가 있으면 고친다), 작업을 시작할 때 관련 기록부터 찾아 읽는다
  - 처음에는 프로젝트 안의 `docs/wiki/`와 grep으로 시작한다. 별도 저장소와 검색 MCP는 필요해지면 만든다

- [ ] 20. 컨벤션 센서 확장과 빌드·Tuist 절차 스킬 (후보 11에서 넘김)
  - 레이어 의존 검사(Konsist 대응). 단일 모듈 앱은 지금 `lint`의 경로 규칙(`included` + import 금지 정규식)으로 표현할 수 있다. 모듈 프로젝트는 Harmonize, `tuist inspect`를 조사한다
  - 형식 규칙(ktlint 대응): SwiftFormat 설정 생성. 프로젝트가 SwiftFormat을 쓰기 시작할 때
  - `ios-build-fix`, `tuist-change` 스킬, `tuist inspect` 래퍼. Tuist 시험장이 필요하다

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
