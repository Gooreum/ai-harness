# 레퍼런스

2026-10-01에 조사한 내용이다. 각 항목은 이 하네스의 관점에서 요약했고, 하네스에 반영한 내용을 함께 적었다.

## 하네스 엔지니어링 일반

### OpenAI — Harness engineering: leveraging Codex in an agent-first world (2026-02)

- 사람이 코드를 직접 쓰지 않고 Codex 에이전트만으로 큰 제품을 만든 경험을 다룬다.
- AGENTS.md는 100줄 안팎의 목차로만 쓴다. 실제 지식은 버전 관리되는 `docs/`에 둔다. 설계 문서, 실행 계획, 기술 부채 목록, 참고 자료 같은 것들이다.
- 레이어 간 의존 방향을 커스텀 린터와 구조 테스트로 강제한다. 린트 에러 메시지에 고치는 방법을 적어서 에이전트가 스스로 고치게 한다.
- 워크트리마다 앱을 띄우고, 화면·로그·메트릭을 에이전트가 직접 볼 수 있게 했다.
- 주기적으로 에이전트를 돌려 코드와 문서가 어긋난 부분을 정리한다.
- 반영
  - 목차형 AGENTS.md와 docs 구조
  - 고치는 방법을 담은 에러 메시지
  - 앱 관찰 도구
  - 주기 점검(후보 18이었으나 뺐다, 2026-11-05)

### Birgitta Böckeler — Harness engineering for coding agent users (martinfowler.com)

- 하네스 구성요소를 두 기준으로 나눈다.
  - 시점: 가이드(행동 전에 유도)와 센서(행동 후 검증)
  - 수단: 결정적 수단과 추론적 수단
- 검사는 가능한 한 앞 단계에 둔다. 순서는 편집 중 → 커밋 → CI → 주기 점검이다.
- 프로젝트 구성 유형별로 하네스 템플릿을 만들 수 있다. 다만 템플릿과 각 프로젝트가 점점 어긋나는 문제를 관리해야 한다.
- 반영
  - 계층 구분과 결정적·추론적 Validation
  - 템플릿 갱신 도구 `sync`와 어긋남 점검 `doctor`(후보 14)

### Birgitta Böckeler — Maintainability sensors for coding agents (2026-05)

- 린트, 의존 규칙, 결합도, 뮤테이션 테스트를 센서로 쓴 경험을 다룬다.
- 마크다운 지침만으로는 에이전트가 센서를 꾸준히 실행하지 않았다. pre-commit 훅은 확실히 동작했다.
- 린트 메시지를 고쳐 썼다. 규칙이 왜 있는지와 어떻게 고치는지를 담았다.
- 반영
  - 반복되는 실수는 결정적 수단으로 옮긴다(원칙 4).
  - 에이전트가 읽기 좋은 출력 형식

### Anthropic — Effective harnesses for long-running agents (2025-11)

- 여러 컨텍스트 창에 걸친 긴 작업을 위해 초기화 에이전트와 코딩 에이전트를 나눴다.
- 세션 사이의 상태는 다음으로 남긴다.
  - 기능 목록(JSON)
  - 진행 기록 파일
  - 초기화 스크립트
  - git 커밋
- 에이전트는 한 번에 기능 하나만 다룬다. 실제 UI로 끝까지 확인한 뒤에 완료로 표시한다.
- 관찰한 실패: 테스트 없이 완료로 표시하거나, 일을 너무 일찍 끝났다고 판단했다.
- 반영
  - 실행 계획(후보 12)
  - 검증 강제는 같은 실패가 관찰될 때만 넣는다(후보 13).

### Anthropic — Harness design for long-running application development (2026-03)

- 계획·생성·평가 에이전트를 나눠서, 자기 결과를 후하게 평가하는 편향을 줄였다. 평가 에이전트는 앱을 실제로 조작해서 확인한다.
- 새 모델이 나오면 구성요소를 하나씩 빼면서 결과를 측정했다. 필요 없어진 구성요소는 제거했다.
- 구성요소마다 "모델이 이건 혼자 못 한다"는 가정이 들어 있다. 그 가정이 아직 맞는지 계속 확인해야 한다.
- 반영
  - 원칙 1·10
  - 리뷰 서브에이전트(단위 8)

### Mitchell Hashimoto — My AI Adoption Journey (2026-02)

- 에이전트가 실수할 때마다 같은 실수를 다시 못 하도록 환경을 고친다.
  - 단순한 실수는 AGENTS.md 한 줄로 해결한다.
  - 복잡한 경우는 스크린샷이나 필터된 테스트 같은 스크립트로 해결한다.
- 에이전트에게 결과를 확인할 수단을 주면 대부분 스스로 고친다.
- 반영: 원칙 3, harness-log

### HumanLayer — Skill issue: harness engineering for coding agents

- 에이전트 실패의 상당수는 모델이 아니라 설정 문제다.
- 지침 파일은 60줄 안팎으로 짧게 둔다. 지침과 도구는 필요할 때만 노출한다.
- MCP 도구를 많이 붙이면 도구 설명이 컨텍스트를 채운다. 그래서 학습 데이터로 익숙한 CLI를 선호한다.
- 검증 출력은 성공하면 조용히 두고, 실패할 때만 자세히 낸다.
- 탐색처럼 긴 작업은 서브에이전트에 맡겨서 중간 과정이 메인 컨텍스트에 쌓이지 않게 한다.
- 반영: 원칙 5·7, 상시 로드 예산

### steipete/agent-scripts

- 여러 저장소가 공유하는 전역 지침과 스킬을 한 저장소에서 관리한다.
- 지침 파일에는 꼭 지킬 규칙만 둔다. 도구 사용법은 스킬에 둔다.
- 반영: AGENTS.md(규칙)와 스킬(절차)의 역할을 나눈다.

## iOS 도구와 생태계

### Sentry — Do you really need an MCP to build your app?

- 3개 모델 × 5개 작업으로 1,350회 실험했다.
- 정확한 빌드 명령을 적어둔 AGENTS.md와 셸 조합이 가장 빠르고 쌌다(회당 약 $0.98).
- XcodeBuildMCP v1은 성공률은 같았지만, 토큰이 약 2배, 비용이 약 2.3배 들었다.
- 안내 없이 셸만 쓴 경우는 49.6%가 출력 잘림에 걸렸다. 빌드 로그 중앙값은 약 1.2MB였고, MCP는 이를 약 2.1KB로 줄였다.
- 반영
  - 명령은 프로젝트 설정 파일로 미리 알려준다(단위 2·6).
  - 빌드 출력은 반드시 요약한다(단위 3).

### MobileBuildMCP (구 XcodeBuildMCP)

- 시뮬레이터 빌드·실행·UI 자동화·로그 수집을 MCP와 CLI로 제공한다. 2026-02에 Sentry가 인수했다.
- 2026-09-23 v2.7.1부터 이름이 MobileBuildMCP로 바뀌었다. npm의 `xcodebuildmcp` 패키지는 2.7.0에서 멈췄다.
- 세션 기본값은 설정 파일에 둔다. CLI 사용법을 알려주는 스킬을 함께 제공한다.
- Sentry 텔레메트리가 기본으로 켜져 있다.
- 반영: UI 확인(후보 10)에서 쓸 때는 버전을 고정하고 래퍼로 감싼다.

### Xcode MCP (Xcode 26.3 이상)

- `xcrun mcpbridge`로 Xcode의 도구 20개를 외부 에이전트에 연다. 빌드, 테스트, 이슈 조회, 프리뷰 렌더링, 문서 검색 등이다.
- Xcode 앱이 실행 중이어야 한다.

### Xcode 27 (WWDC26)

- Anthropic·Google·OpenAI 에이전트를 내장했다. Agent Client Protocol, MCP, 플러그인(커스텀 스킬)을 지원한다.
- Apple이 직접 쓴 스킬 7개를 포함한다.
  - `swiftui-specialist`
  - `swiftui-whats-new-27`
  - `uikit-app-modernization`
  - `test-modernizer`
  - `audit-xcode-security-settings`
  - `c-bounds-safety`
  - `device-interaction`
- 이 스킬들은 Agent Skills 표준 형식이라, 내보내서 다른 에이전트에서도 쓸 수 있다.
- 반영
  - 지식 큐레이션(후보 18이었으나 뺐다, 2026-11-05)
  - Xcode 27 어댑터(백로그)

### Axiom (Claude Code 플러그인)

- iOS 개발용 스킬 276개, 에이전트 42개, 명령 17개를 제공한다.
- 상위 스킬이 하위 스킬로 안내하는 방식이라, 필요한 스킬만 불러온다.
- 소스 하나에서 Claude Code·Codex·Cursor·MCP용 결과물을 빌드한다.
- 훅 스크립트 하나가 stdin JSON을 읽어서 Claude Code(Edit/Write)와 Codex(apply_patch)를 모두 처리한다.
- 항상 로드되는 분량을 스크립트로 측정한다.
- 반영
  - 훅은 stdin JSON만 읽는다.
  - 규모는 따라 하지 않는다.

### Swift·SwiftUI 지식 스킬

- 큐레이션 목록: twostraws/Swift-Agent-Skills
- 주요 제작자
  - Paul Hudson: SwiftUI, SwiftData, Concurrency, Testing
  - Antoine van der Lee: SwiftUI, Concurrency, Swift Testing, Xcode 빌드 최적화
  - Thomas Ricouard: SwiftUI 패턴, iOS 디버깅
- Paul Hudson이 제시한 선택 기준
  - 모델이 모르는 것(새 API, 최근 deprecation, 함정)을 가르치는 스킬만 쓴다.
  - 설치하기 전에 내용을 직접 읽는다.
- 반영: 지식은 직접 쓰지 않고, 검증된 스킬을 골라 쓴다(후보 18이었으나 뺐다, 2026-11-05).

### 결정적 검증 도구

- `xcresulttool get build-results --compact`, `get test-results summary|tests`
  - Xcode 기본 도구로 빌드·테스트 결과를 JSON으로 얻는다(단위 3·4).
- xcsift
  - xcodebuild 출력을 JSON, 또는 토큰을 줄인 TOON 형식으로 바꾼다.
  - 대안으로 둔다.
- `tuist inspect implicit-imports|redundant-imports`
  - 선언하지 않은 import와 불필요한 의존을 찾는다(후보 11).
- Harmonize
  - 아키텍처 규칙을 단위 테스트로 작성한다.
  - 필요할 때 쓴다.
- Claude Code `swift-lsp` 플러그인
  - 편집 직후 sourcekit-lsp의 진단을 받는다.
  - Xcode 프로젝트는 빌드 서버 설정이 필요할 수 있다(백로그).

## 팀 적용 사례

### 여기어때 안드로이드 팀 — Workflow AX 적용기: 자동 정책 정리부터 E2E까지 (DroidKnights 2026, 2026-11-02)

발표 슬라이드의 발표자 노트를 기준으로 정리했다(2026-11-03). 반영 내용은 [ADR 0005](decisions/0005-talk-criteria.md)에 있다.

- 출발점은 문제 네 가지였다.
  - 사람마다 방식이 제각각이다.
  - 에이전트가 끝까지 하지 않는다(TODO를 남기고, 커밋을 빠뜨린다).
  - 중간 확인이 없다.
  - 팀 정책을 모른다.
- v1 하네스
  - 팀 공통 규칙을 스킬 하나에 모았다.
  - Stop 훅이 `state.json`의 단계를 보고, 완료 전에는 끝내지 못하게 막는다.
  - Phase·Step으로 나누고 테스트를 먼저 쓰게 강제했다.
- v1 피드백은 "너무 오래 걸린다"와 "다른 플랫폼에서 못 쓴다" 두 가지였다. "iOS에도 도입할 수 있나요?"라는 질문도 나왔다.
- v2 하네스
  - `.dev-workflow/config.yaml`의 `verifications:`에 검사마다 `name`·`prompt`·`run`을 적는다.
  - 단계가 바뀌면 PostToolUse 훅이 prompt를 `additionalContext`로 넣는다(exit 0).
  - 다음 단계로 넘어가려 하면 훅이 run을 직접 돌린다. 실패하면 이유를 붙여 막는다.
  - 스킬은 `dev-workflow-plan`과 `dev-workflow-simple` 둘이고, 어느 쪽을 쓸지와 어떤 검사를 돌릴지는 사람이 고른다.
  - 같은 훅을 웹·안드로이드·위키 저장소에 쓰고, config만 다르다.
- 수치
  - 작은 작업: plan 평균 19.1분, simple 평균 9.3분(결함 없음)
  - 큰 작업 결함 비율: plan 25%(4번 중 1번), simple 78%(9번 중 7번)
  - Phase 분할: 안드로이드 작은 작업 100% = 100%, 웹 큰 작업 나눔 93.1% < 안 나눔 94.4%(조건마다 3번)
- LLM Wiki
  - 별도 저장소(`yeogi-library`)에 두고 MCP `library_search`로 찾는다.
  - 마무리 단계에서 쓴다(config 한 줄). 비슷한 문서가 있으면 고친다.
  - 기록은 두 종류다.
    - 기술 기록 `kind: fact`: 확인된 동작, 확인 방법, 함의, 안 다룬 것
    - 결정 기록 `kind: rule`: 규칙, 적용 범위, 근거 링크, 예외
  - 같은 티켓을 줬을 때 위키가 없는 AI는 정책을 뒤집었고, 위키가 있는 AI는 티켓을 반려했다.
  - 한 달 사용량: 검색 2,322회, 열람 540회, 반영 504회(93%)
- andcon (컨벤션)
  - AI에게 확인을 맡겼더니 "모두 지켰다"고 했지만 실제로는 어겼다.
  - 그래서 AI는 규칙만 뽑아 `conventions.yml`에 초안을 쓰고, 팀이 고른다.
  - 그 규칙을 Konsist(구조)·detekt(금지 API)·ktlint(형식) 설정으로 옮긴다.
  - 검사는 AI 없이 한다. 100점에서 깎는 점수와 기준선으로 판정하고, 결과는 `.andcon/last-check.json`에 남는다.
- 화면 검증
  - Roborazzi가 기존 `@Preview`를 기기 없이 그린다.
  - 픽셀 비교는 전부 빨갛게 나와 실패했다.
  - 그래서 AI가 큰 배치를 보고, 파이썬 스크립트가 Figma MCP 수치와 코드 값을 1:1로 비교한다(dp 차이 리포트). 판정은 사람이 한다.
- 동작 검증
  - Appium 대신 Maestro를 골랐다. 작성·검토가 쉽고, 알아서 기다리고, MCP와 CLI를 다 쓸 수 있어서다.
  - 팀 작성 규칙
    - 딥링크로 진입한다.
    - 요소는 id로 먼저 찾는다.
    - 계정은 환경 변수로 넣는다.
    - 반복 단계는 공통 `runFlow`로 쓴다.
    - 끝까지 통과한 시나리오만 저장한다.
  - 프록시 MCP로 서버 응답을 바꾼다(500·느린 네트워크·빈 응답).
  - 행동 로그를 판정한다.
  - `tags: [regression]` 회귀 묶음을 만들고, MR에 수정 전후 영상을 붙인다.

## 에이전트 플랫폼 제약

### Claude Code

- AGENTS.md 지원
  - v2.1.277부터 AGENTS.md를 직접 읽는다.
  - 단, CLAUDE.md가 있으면 CLAUDE.md만 읽는다. 그래서 CLAUDE.md에서 `@AGENTS.md`로 import한다.
  - 로컬 CLI는 2.1.209라 import가 필요하다.
- 경로 규칙
  - `.claude/rules/*.md`에 `paths:`를 달면, 해당 경로의 파일을 읽을 때만 로드된다.
  - 프로젝트 밖으로 symlink한 규칙은 승인을 받은 뒤에도 `paths`가 없는 것만 로드된다. 그래서 경로 규칙은 프로젝트 안에 복사해야 한다.
- 플러그인
  - 스킬, 서브에이전트, 훅, MCP, LSP, `bin/`(PATH에 추가)을 담을 수 있다.
  - 플러그인 안의 CLAUDE.md는 로드되지 않는다. 그래서 항상 적용될 지침은 플러그인으로 배포할 수 없다.
  - 프로젝트 `.claude/settings.json`의 `enabledPlugins`, `extraKnownMarketplaces`로 팀원에게 플러그인을 배포할 수 있다. 폴더를 신뢰한 뒤에 적용된다.
- 기타 도구
  - `/doctor prompt-audit`(v2.1.283 이상): 지침 파일 사이의 충돌과 낡은 내용을 점검한다.
  - `claude plugin eval`: 플러그인을 시나리오로 평가하고, 플러그인이 없을 때와 비교한다.

### Codex

- AGENTS.md를 저장소 루트부터 현재 디렉터리까지 합쳐서 읽는다. 기본 상한은 32KiB다.
- 스킬 경로는 `.agents/skills`다. Claude Code는 `.claude/skills`라서 다르다.
- 플러그인(`.codex-plugin/plugin.json`)과 훅(PreToolUse, PostToolUse, Stop 등)을 지원한다.
- read-only 샌드박스에서는 셸로 실행한 작업 일부가 막힌다.
  - 막히는 것: `xcodebuild`(DerivedData 쓰기), 시뮬레이터 제어(CoreSimulatorService)
  - MCP 서버는 샌드박스 밖에서 실행되므로 동작한다.

## 로컬 환경 (2026-10-01 확인)

- Xcode 26.6 (17F113), Swift 6.3.3, Tuist 4.81.1, Claude Code CLI 2.1.209
- 기본 도구: `/usr/bin/jq` 1.7.1, python3 3.9.6
- Xcode 툴체인에 포함된 것
  - `swift format` 6.3: `NeverForceUnwrap`, `NeverUseForceTry` 규칙이 있다. 기본으로 꺼져 있다.
  - `sourcekit-lsp`
  - `xcrun mcpbridge run-agent skills export`
- Xcode 번들에 들어 있는 에이전트용 Apple 문서 20개
  - 위치: `/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation/`
- 설치되지 않은 것: SwiftLint, xcbeautify, xcsift, MobileBuildMCP CLI

## 출처

- [OpenAI — Harness engineering](https://openai.com/index/harness-engineering/)
- [Böckeler — Harness engineering for coding agent users](https://martinfowler.com/articles/exploring-gen-ai/harness-engineering.html)
- [Böckeler — Maintainability sensors for coding agents](https://martinfowler.com/articles/sensors-for-coding-agents.html)
- [Anthropic — Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Anthropic — Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- [Mitchell Hashimoto — My AI Adoption Journey](https://mitchellh.com/writing/my-ai-adoption-journey)
- [HumanLayer — Skill issue](https://www.humanlayer.dev/blog/skill-issue-harness-engineering-for-coding-agents)
- [steipete/agent-scripts](https://github.com/steipete/agent-scripts)
- [Sentry — Do you really need an MCP to build your app?](https://blog.sentry.io/do-you-really-need-an-mcp-to-build-your-app)
- [getsentry/MobileBuildMCP](https://github.com/getsentry/MobileBuildMCP)
- [Xcode 26.3 MCP 도구 정리 (DEV)](https://dev.to/arshtechpro/xcode-263-use-ai-agents-from-cursor-claude-code-beyond-4dmi)
- [Apple Newsroom — WWDC26 개발 도구 발표](https://www.apple.com/newsroom/2026/06/apple-aids-app-development-with-new-intelligence-frameworks-and-advanced-tools/)
- [Xcode 27 Apple 스킬 정리 (DEV)](https://dev.to/arshtechpro/wwdc-2026-xcode-27-ships-with-apples-own-agent-skills-what-they-are-and-how-to-use-them-3g2)
- [CharlesWiltgen/Axiom](https://github.com/CharlesWiltgen/Axiom)
- [twostraws/Swift-Agent-Skills](https://github.com/twostraws/swift-agent-skills)
- [Hacking with Swift — Agent skills in Xcode](https://www.hackingwithswift.com/articles/283/how-to-install-and-use-ai-agent-skills-in-xcode)
- [Dimillian/Skills](https://github.com/Dimillian/Skills)
- [ldomaradzki/xcsift](https://github.com/ldomaradzki/xcsift)
- [perrystreetsoftware/Harmonize](https://github.com/perrystreetsoftware/Harmonize)
- [Claude Code — Memory](https://code.claude.com/docs/en/memory)
- [Claude Code — Skills](https://code.claude.com/docs/en/skills)
- [Claude Code — Plugins reference](https://code.claude.com/docs/en/plugins-reference)
- [Claude Code — Hooks](https://code.claude.com/docs/en/hooks)
- [Claude Code — Plugin evals](https://code.claude.com/docs/en/plugin-evals)
- [Claude Code — Code intelligence](https://code.claude.com/docs/en/plugins/code-intelligence)
- [Codex — AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Codex — Skills](https://learn.chatgpt.com/docs/build-skills)
- [Codex — Plugins](https://developers.openai.com/codex/plugins/build)
- [Codex hooks 정리 (Blake Crosley)](https://blakecrosley.com/blog/codex-hooks-make-the-harness-real)
- [여기어때 — Workflow AX 적용기 슬라이드 (DroidKnights 2026)](https://claude.ai/artifact/KBRFrrtvkB8RUB2TJFVGaP)
- [여기어때 — Workflow AX 적용기 발표 요약·전사](https://claude.ai/artifact/SK8EowGXyMV4x2hSCMNi8t)
