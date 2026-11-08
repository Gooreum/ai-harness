# ai-harness

여러 프로젝트에서 재사용하는 AI 코딩 에이전트 하네스를 만드는 저장소다. 하네스는 플랫폼을 모른다(ADR 0024).
이 파일은 **이 저장소를 개발할 때** 따르는 지침이다. 각 프로젝트에 설치되는 지침은 `template/`에 따로 있다.

## 구조

- `README.md`: 처음 보는 사람을 위한 개요. 하네스의 동작 흐름과 파일별 역할. 구조나 동작이 바뀌면 함께 고친다
- `template/`: 각 프로젝트에 설치되는 파일의 원본(에이전트 지침, 규칙, 스크립트)
  - 대상 프로젝트의 루트를 기준으로 쓴다.
  - 이 저장소를 개발하기 위한 내용은 넣지 않는다.
  - `template/AGENTS.md`, `template/CLAUDE.md`: 프로젝트에 설치될 지침. AGENTS.md는 프로젝트 영역과 하네스 관리 블록으로 나뉜다
  - `template/.claude/rules/harness/`: 공통 상황별 규칙(`wiki.md`). `paths:`로 해당 파일을 읽을 때만 로드된다. 프로젝트 고유 규칙 자리는 `rules/project/`
  - `template/scripts/harness/`: 프로젝트 안에서 쓰는 스크립트(record·passed·wiki·doctor·setup), 추천 검사 `common-checks.json`, 공통 함수 `lib.sh`. 설치되면 `scripts/harness/`가 된다. 빌드·테스트 스크립트는 넣지 않는다. 그것은 각 프로젝트가 갖는다.
  - `template/.harness/.gitignore`: 프로젝트의 `.harness/`에서 설정 파일만 커밋하게 한다.
  - `template/.claude/settings.json`: 공통 권한 규칙(비밀 파일 읽기 deny. ask는 두지 않는다, ADR 0026)
- `plugin/`: Claude Code 플러그인 `harness`. 훅(생성 파일 편집 차단, 단계 지시, run 확인, Stop 게이트, 리뷰 기록), 작업 시작 스킬(`task`), 리뷰 서브에이전트(`reviewer`), 가짜 응답 MCP(`harness-network`)를 담는다. 루트의 `.claude-plugin/marketplace.json`이 이 저장소를 마켓플레이스로 만든다
- `scripts/`: 하네스를 설치·관리하는 도구. 대상 프로젝트 경로를 인자로 받는다.
  - `scripts/init <프로젝트 경로>`: 하네스를 처음 설치
  - `scripts/sync [--dev] <프로젝트 경로>`: 설치된 하네스를 갱신. 예전 iOS 묶음은 프로젝트 코드로 넘긴다. `--dev`는 플러그인을 이 저장소 디렉터리에서 읽게 한다
- `tests/`: 스크립트 회귀 테스트. `bash tests/run.sh`로 전부 실행한다.
- `docs/roadmap.md`: 작업 단위와 순서, 진행 상황
- `docs/project-config.md`: 프로젝트 설정 파일(`.harness/project.json`) 스펙
- `docs/conventions.md`: 팀 컨벤션 목록(`.harness/conventions.json`). 예전 iOS lint가 읽던 파일이라 하네스 밖으로 옮겼다는 안내만 남았다
- `docs/checks.md`: 작업 흐름(plan/simple)과 검사 목록(`.harness/checks.json`) 스펙
- `docs/wiki.md`: 정책·결정 기록(`docs/wiki/`) 형식과 쓰는 때
- `docs/scripts.md`: 프로젝트에 설치되는 하네스 스크립트의 동작 방식(출력 형식, 산출물 위치)
- `docs/template.md`: template 파일이 프로젝트의 어디에 설치되고 어떻게 갱신되는지
- `docs/plugin.md`: 플러그인 구성, 훅이 막는 것, 프로젝트에서 켜는 방법
- `docs/principles.md`: 하네스 계층, 설계 원칙, 실수를 어느 층에서 고칠지 정한 기준표, 용어
- `docs/references.md`: 레퍼런스 조사 요약, 플랫폼 제약, 로컬 환경, 출처
- `docs/decisions/`: 설계 결정 기록(ADR)
- `docs/harness-log.md`: 시험장에서 관찰한 에이전트 실패 기록
- `docs/problem-notes.md`: 시험장에서 만난 문제의 기술 설명(문제·원인·해결·결과)과 비유, 하네스를 만들며 물은 질문과 답
- `docs/talk/`: 설계 기준인 발표의 전사·슬라이드 노트 로컬 사본. git에 올리지 않는다(CLAUDE.md 참고)

## 작업 방식

- `docs/roadmap.md`의 단위 순서대로 진행한다.
  - 단위 하나가 세션 하나 분량이다.
  - 시작하기 전에 해당 단위의 할 일과 완료 기준을 확인한다.
- 단위마다 작업 브랜치 `feature/unit-<번호>-<주제>`를 만든다.
- 작업을 마치면 커밋·push·PR·머지까지 묻지 않고 하고, 머지한 브랜치는 지운다.
  - 커밋 메시지는 한글로 쓴다.
  - prefix는 `feat:` `fix:` `docs:` `chore:` `test:` 중 하나를 쓴다.
- 단위를 마치면 roadmap의 체크박스를 갱신한다. 설계 결정은 `docs/decisions/`에 ADR로 남긴다.
- 완료 기준은 시험장 프로젝트에서 실제로 실행해 확인한다.
  - 시험장은 ReadSharp(`~/Code/EnglishStudy`)의 `~/Code/EnglishStudy-harness` 워크트리다. 단위 1~9의 기록은 MotoTrace에서 했다.
  - 시험장에 이미 있는 하네스 구성은 설계 근거로 쓰지 않는다.

## 설계 원칙 (자세한 내용은 docs/principles.md)

- 최소 구성부터 만든다. 구성요소마다 어떤 실패나 위험을 막는지 설명할 수 있어야 한다.
- 강제 장치(훅·권한)는 처음에는 위험하거나 되돌리기 어려운 행동을 막는 것만 넣는다. 나머지는 실패가 관찰된 뒤에 넣는다.
- 하네스는 플랫폼을 모른다. 플랫폼·도구에 따라 다른 것(빌드·테스트 명령, 생성 파일, 막을 파일)은 하네스 코드에 넣지 않고, 프로젝트의 설정(`.harness/project.json`, `.harness/checks.json`, `.claude/settings.json`)과 AGENTS.md 프로젝트 영역에 둔다. setup이 사용자에게 물어 정한다(ADR 0024).
- 스크립트는 macOS 기본 도구인 bash와 jq로 쓴다.
  - 예외: 가짜 응답 MCP 서버(`plugin/mcp/network.py`)는 HTTP 서버라 python3로 쓴다(ADR 0017).
  - 성공하면 출력을 짧게 한다.
  - 실패하면 첫 에러의 위치부터 구체적으로 보여준다.
  - 사람이나 에이전트가 직접 실행하는 명령(`init`, `sync`, `wiki`·`doctor`·`passed`·`record`·`setup`)은 확장자를 붙이지 않는다. `source`로 불러 쓰는 파일(`lib.sh`)과 테스트·훅 스크립트에는 `.sh`를 붙인다.
- 훅 스크립트는 stdin으로 받은 JSON만 읽는다. 그래야 Codex에서도 재사용할 수 있다.
- 문서는 한국어로 쓰고, 새 용어는 처음 나올 때 정의한다.
