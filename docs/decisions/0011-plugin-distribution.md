# 0011. 플러그인 배포와 init/sync/doctor

- 상태: 채택 (2026-11-03)
- 관련: ADR 0005(발표 기준), 로드맵 후보 14

## 배경

발표는 v2 하네스에서 "하네스와 훅은 하나만 두고 웹, 안드로이드, LLM Wiki 저장소에 똑같이 쓰고, 저장소마다 config만 다르게 적는다"고 했다(슬라이드 21, 38).
v1의 첫 조각도 팀원마다 흩어진 규칙을 하나로 모아 "누가 AI를 쓰든 같은 규칙이 들어가게" 한 것이었다(전사 "v1 하네스" 부분).
발표는 그 하네스를 팀원에게 어떻게 나눠 주는지는 다루지 않는다.

지금까지는 이렇게 동작했다.

- `scripts/dev-install`이 template 파일을 프로젝트에 복사했다.
- 플러그인(훅·스킬·리뷰어)은 `.claude/settings.local.json`에 이 저장소의 절대 경로를 마켓플레이스로 넣어 켰다.
- 그래서 하네스 저장소를 클론한 내 컴퓨터에서만 플러그인이 돌았다. 팀원이 프로젝트를 받아도 스크립트와 규칙만 있고 훅과 `task` 스킬은 없었다.
- 프로젝트 파일과 플러그인이 어느 버전인지 알 방법도 없었다. 시험장에서 확인해 보니 캐시된 플러그인은 0.1.0, 폴더는 0.2.0이었다.

## 결정

- **플러그인은 GitHub 마켓플레이스로 배포한다.** 이 저장소(`Gooreum/ios-ai-harness`)가 마켓플레이스다. init·sync가 프로젝트의 `.claude/settings.json`에 `extraKnownMarketplaces`(github)와 `enabledPlugins`를 넣는다. 커밋된 이 설정을 보고 Claude Code가 팀원에게 설치를 권한다.
- **template은 지금처럼 프로젝트에 복사한다.** 스크립트와 규칙은 사람·CI·다른 에이전트(Codex)도 쓰므로 프로젝트 저장소에 있어야 한다. 플러그인 안으로 옮기지 않는다.
- **도구를 셋으로 나눈다.**
  - `scripts/init`: 처음 설치. 이미 설치된 프로젝트는 거절한다.
  - `scripts/sync`: 갱신. 설치되지 않은 프로젝트는 거절한다. `dev-install`을 이것으로 바꿨다.
  - `scripts/harness/doctor`: 프로젝트 안의 읽기 전용 점검. 팀원은 하네스 저장소가 없어도 돌릴 수 있어야 하므로 template에 둔다.
- **버전은 하나다.** `plugin.json`의 `version`이 하네스 버전이다. template과 plugin은 같은 설정 형식(`checks.json` 등)을 읽어서 함께 바뀐다. sync가 `.harness/harness.json`에 이 버전을 남기고, doctor가 설치된 플러그인 버전과 비교한다.
- **개발 중에는 `sync --dev`를 쓴다.** 같은 이름의 디렉터리 마켓플레이스를 `.claude/settings.local.json`에 넣어 내 컴퓨터에서만 덮어쓴다. 공유 설정(`settings.json`)은 늘 GitHub를 가리킨다.

## 고르지 않은 것

- 마켓플레이스 소스에 git ref(태그)를 고정하는 것: 버전이 어긋나는 일을 아예 막을 수 있지만, 릴리스마다 태그를 만들고 프로젝트마다 ref를 올려야 한다. 지금은 doctor가 어긋남을 알려 주는 것으로 충분한지 먼저 본다.
- template을 플러그인 안에 넣고 스킬로 init·sync를 돌리는 것: 팀원이 하네스 저장소 없이 설치할 수 있지만, 설치는 하네스를 관리하는 사람 한 명이 하고 결과를 커밋하면 된다. 구조를 크게 바꿀 이유가 아직 없다.
- doctor가 직접 고치기: 점검과 수정을 나눈다. 고치는 일은 sync나 사람이 한다.

## 결과

- 팀원은 프로젝트를 받아 Claude Code에서 열기만 하면 같은 훅·스킬·리뷰어를 쓴다. 시험장에서 빈 설정 디렉터리(`CLAUDE_CONFIG_DIR`)로 GitHub에서 마켓플레이스를 추가하고 플러그인을 설치했다.
- 프로젝트가 `.claude/settings.json`을 git에서 무시하면 이 공유가 일어나지 않는다. ReadSharp와 IntervalTimer가 그렇다. sync와 doctor가 이를 알린다. 개인 값을 `settings.local.json`으로 옮기는 일은 각 프로젝트에서 한다.
- template이나 plugin을 바꿔 머지할 때 버전을 올려야 한다. 잊으면 팀원의 Claude Code가 갱신을 알아채지 못한다. 이 규칙은 docs/plugin.md에 있다.
