# 로드맵

여러 iOS 프로젝트에서 재사용할 범용 하네스를 작업 단위로 나눠 하나씩 쌓아간다.
단위 하나는 세션 하나 분량이다. 커밋 1~3개로 마무리하고, 끝나면 여기 체크박스를 갱신한다.

## 정해진 것

- 에이전트: Claude Code를 먼저 지원한다. Codex는 후보 16에서 붙인다.
- 스크립트: bash + jq로 작성한다. 둘 다 macOS에 기본으로 들어 있어 따로 설치할 필요가 없다.
- 설계 근거: 레퍼런스에서 도출한 범용 원칙을 따른다. 출처는 OpenAI, Anthropic, Böckeler, HumanLayer, Sentry 등이다.
- 시험장: MotoTrace에서 각 단위를 실제로 돌려본다.
  - MotoTrace에 지금 있는 하네스는 설계 근거로 삼지 않는다.
  - 단위 9에서 기존 하네스를 걷어내고 범용 하네스로 새로 구성한다.

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
4. **각 단위는 MotoTrace에서 실제로 돌려보고 끝낸다.** 단위 9의 운영 기록을 근거로 이후 순서를 다시 정한다.
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
- [ ] **9. MotoTrace에 새로 구성하고 운영하기**
  - 하는 일
    - `scripts/dev-install` 작성
    - MotoTrace의 기존 하네스를 걷어내고 범용 하네스로 새로 구성
    - 1~2주 운영하며 `docs/harness-log.md`에 실패 기록
  - 완료 기준: 실패 기록을 분류해 이후 우선순위를 확정한다.
  - 진행 (2026-10-21)
    - `scripts/dev-install` 작성 (회귀 테스트 26개)
    - MotoTrace `feature/ios-harness` 브랜치에 설치하고 기존 구성 정리. Codex 위임 검증·스탬프·커밋 게이트는 제거하고, mock ride·XcodeBuildMCP·/codex:review는 유지
    - 새 세션이 빌드·테스트·PR 절차를 정확히 답하고, Swift 파일을 열면 규칙이 로드되는 것 확인 (단위 5·6의 실제 프로젝트 확인)
    - 남은 일: 1~2주 운영하며 실패 기록, 분류해서 이후 우선순위 확정

## 이후 후보 (기본 순서이며, 단위 9의 기록으로 조정)

- [ ] 10. UI 확인: 시뮬레이터 실행·접근성 트리·스크린샷 도구, `ios-ui-check` 스킬, 프로젝트 시나리오 스킬 템플릿
- [ ] 11. 빌드·Tuist 절차 스킬과 아키텍처 센서: `ios-build-fix`, `tuist-change`, `tuist inspect` 래퍼
- [ ] 12. 워크플로 스킬: 실행 계획, git 관례(커밋 구성, 브랜치, PR 본문에 검증 결과 넣기), 워크트리 (ADR 0002에서 넘긴 항목 포함)
- [ ] 13. (조건부) 검증 강제: 에이전트가 검증을 건너뛰는 일이 관찰될 때만 추가한다. 가장 단순한 형태부터 시도한다.
- [ ] 14. 플러그인 배포와 init/sync/doctor
- [ ] 15. 두 번째 프로젝트 적용: coinness-ios, 이어서 xcodeproj 앱
- [ ] 16. Codex 어댑터
- [ ] 17. 평가: fixtures와 `claude plugin eval`로 하네스가 없을 때와 비교
- [ ] 18. 래칫·청소 자동화: `harness-retro`, 주기 점검, 지식 큐레이션

## 단위마다 확인하는 방법

- 완료 기준은 MotoTrace의 `MotoTrace-ai-workflow` 슬롯에서 실행해 확인한다.
- 스크립트와 훅은 입력 픽스처를 넣는 셸 테스트(`tests/`)로 회귀를 막는다.
- 중요한 결정은 `docs/decisions/`에 ADR로 남긴다.
