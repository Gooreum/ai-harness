# 템플릿

`template/`의 파일이 각 프로젝트의 어디에 설치되고 어떻게 갱신되는지 정리한다.
설치는 `scripts/init`, 갱신은 `scripts/sync`, 점검은 프로젝트 안의 `scripts/harness/doctor`가 한다(후보 14, [ADR 0011](decisions/0011-plugin-distribution.md)).

## 설치 위치

template 안의 경로가 그대로 프로젝트 루트 기준 경로가 된다. 모든 파일이 어느 프로젝트에나 똑같이 설치된다. 하네스는 플랫폼별 파일을 갖지 않는다([ADR 0024](decisions/0024-no-platform.md)).

| template 경로 | 성격 | 갱신할 때 |
|---|---|---|
| `AGENTS.md` | 위쪽은 프로젝트 영역, 아래쪽은 하네스 관리 블록 | 관리 블록만 바꾼다 |
| `CLAUDE.md` | AGENTS.md를 import하는 연결 파일 | 그대로 둔다 |
| `.claude/rules/harness/*.md` | 공통 상황별 규칙(`wiki.md`) | 통째로 바꾼다 |
| `.claude/rules/project/` | 프로젝트 고유 규칙을 두는 자리 (`.gitkeep`만 있음). 플랫폼 규칙·리뷰 항목도 여기 둔다 | 건드리지 않는다 |
| `.claude/settings.json` | 공통 권한 규칙(`.env`·서명 키 등 비밀 파일 읽기 deny. ask는 두지 않는다, ADR 0026)과 플러그인 등록(GitHub 마켓플레이스) | 프로젝트 설정과 합친다. 지난번에 하네스가 넣었는데 이제 없는 규칙만 지운다(설치 기록의 `permissions`). setup으로 팀이 넣은 `Edit(...)` 같은 규칙은 남는다 |
| `scripts/harness/*` | 하네스 스크립트(record·passed·wiki·doctor·setup), 추천 검사 `common-checks.json`, 공통 함수 `lib.sh` | 통째로 바꾼다. template에서 사라진 것만 지운다 |
| `.harness/.gitignore` | `.harness/`에서 설정 파일과 설치 기록만 커밋되게 함 | 통째로 바꾼다 |

`.harness/harness.json`(설치 기록)은 template에 없다. init·sync가 설치한 하네스 버전(`plugin.json`의 `version`)과 설치한 파일 목록을 `{"version": "0.12.0", "files": [...], "permissions": {"deny": [...], "ask": [...]}}` 형태로 쓴다. 다음 sync는 이 목록에 있었는데 template에서 사라진 파일만 지운다. 팀이 `scripts/harness/`에 넣은 파일은 남는다. 커밋해서 팀원의 doctor도 같은 값과 비교하게 한다.

`.harness/project.json`은 template에 없다. 없으면 init·sync가 `{ "schemaVersion": 2 }`만 쓴다. 이후에는 하네스가 고치지 않는다(예전 iOS 묶음을 넘길 때 `generated`를 더하는 것만 예외). `generated` 같은 값은 setup에서 사용자와 정한다([project-config.md](project-config.md)).

`.harness/checks.json`(검사 목록)도 template에 없다. init·sync는 쓰지 않고, 없으면 Claude 세션에서 `scripts/harness/setup` 안내대로 사용자와 정하라고 알린다. setup은 저장소에서 찾은 명령과 추천 검사(`scripts/harness/common-checks.json`)를 보여 준다([checks.md](checks.md), [scripts.md](scripts.md#setup), [ADR 0020](decisions/0020-install-checks-permissions-root.md)).

`.harness/conventions.json`(팀 컨벤션 목록)도 template에 없다. 예전 iOS `lint`가 읽던 파일이라 하네스는 읽지 않는다. `.harness/.gitignore`는 넘겨받은 프로젝트를 위해 이 파일을 계속 커밋 대상으로 둔다([conventions.md](conventions.md)).

## AGENTS.md의 두 영역

| 영역 | 위치 | 내용 | 누가 고치나 |
|---|---|---|---|
| 프로젝트 영역 | 관리 블록 위 | 앱 소개, 구조, 빌드·테스트 명령, 프로젝트 규칙 | 각 프로젝트. 설치 뒤 채운다. 빌드·테스트는 setup이 채운다 |
| 하네스 관리 블록 | `<!-- harness:begin -->`부터 `<!-- harness:end -->`까지 | 하네스 명령 표(record·wiki·doctor·setup), 꼭 지킬 규칙, 상황별 규칙 표 | 하네스 저장소. 프로젝트에서 직접 고치지 않는다 |

- 두 영역의 규칙이 다르면 프로젝트 규칙을 따른다. 이 우선순위는 관리 블록 안에 적혀 있다. 그래서 프로젝트는 관리 블록을 고치지 않고도 기본 규칙을 바꿀 수 있다.
- 표시와 안내는 HTML 주석이라 Claude의 컨텍스트에서는 빠진다. 파일을 열어 고칠 때는 보인다.
- 예전 관리 블록에 있던 묶음 자리 표시(`<!-- harness:pack … -->` 줄)는 sync가 지운다.
- 새로 만드는 AGENTS.md의 제목은 프로젝트 폴더 이름이다.
- 관리 블록에는 프로젝트별 값을 채워 넣지 않는다. 하네스 명령은 모든 프로젝트에서 같다. 프로젝트의 빌드·테스트 명령은 프로젝트 영역에 쓴다.

## 설치와 갱신: scripts/init, scripts/sync

```bash
scripts/init <프로젝트 경로>          # 처음 설치. 이미 설치됐으면(harness.json이 있으면) 거절한다
scripts/sync <프로젝트 경로>          # 갱신. 설치되지 않았으면(project.json이 없으면) 거절한다
scripts/sync --dev <프로젝트 경로>    # 갱신하되 플러그인을 이 저장소 디렉터리에서 읽게 한다
```

- 위 표대로 파일을 맞추고, `.harness/project.json`이 없으면 `{ "schemaVersion": 2 }`만 쓴다. 플랫폼은 묻지 않는다.
- `.harness/checks.json`이 없으면 "직접 할 일"로 Claude 세션에서 setup 안내대로 정하라고 알린다.
- 예전 iOS 묶음을 설치한 프로젝트면 그 파일을 프로젝트 코드로 넘긴다(아래).
- `.claude/settings.json`에 GitHub 마켓플레이스와 플러그인을 등록한다. 이 파일을 커밋하면 팀원이 프로젝트를 열 때 Claude Code가 설치를 권한다.
- `--dev`는 `.claude/settings.local.json`에 같은 이름의 디렉터리 마켓플레이스를 넣는다. 로컬 설정이 우선하므로 공유 설정은 그대로 두고 내 컴퓨터에서만 개발 중인 플러그인을 쓴다. `--dev` 없이 다시 실행하면 이 항목을 지운다.
- 여러 번 실행해도 결과가 같다. 바뀐 파일과 사람이 직접 할 일을 출력한다.

## 점검: scripts/harness/doctor

프로젝트 안에서 누구나 돌린다. 파일은 고치지 않고, 문제마다 고치는 방법을 한 줄 붙인다.

| 보는 것 | ✕ 문제 | ! 주의 |
|---|---|---|
| 도구 | jq가 없다(스크립트와 훅이 모두 꺼진다) | `e2e.network.port`가 있는데 python3가 없다 |
| 설정 파일 | checks·conventions JSON이 깨졌다, checks.json의 run 명령이 없다, `passed <이름>`이 확인하는 결과를 만드는 곳이 없다 | checks.json의 단계 지시(`stages`)에 위키가 없다(`"wiki": false`면 보지 않는다) |
| 설치된 파일 | AGENTS.md 관리 블록, CLAUDE.md의 `@AGENTS.md`, `.claude/rules/harness/`가 없다 | 설치 기록이 없다, 규칙이나 `settings.json`이 git에서 무시된다 |
| 플러그인 | 켜져 있지 않다, 이 프로젝트에 설치되지 않았다, 꺼져 있다, 버전이 설치 기록과 다르다 | claude CLI가 없어 버전을 못 봤다 |

- 플러그인 버전은 `claude plugin list --json`에서 이 프로젝트(`projectPath`)나 사용자 전체에 설치된 항목을 본다. `--dev`로 디렉터리에서 읽는 플러그인은 폴더의 버전(`folderVersion`)을 본다.
- 버전이 다르면 어느 쪽이 오래됐는지에 따라 플러그인 갱신(`claude plugin update`) 또는 `sync`를 안내한다.
- `passed <이름>`의 결과를 만드는 곳: prompt의 `record <이름>`, prompt가 부르는 실행 파일 중 이름이 `<이름>`인 것(예: `scripts/ios/unit-test`), 또는 리뷰(`review`). 셋 다 없으면 검증 단계를 영영 넘지 못하므로 문제로 친다.
- 예전 이름의 플러그인(`ios-harness@ios-ai-harness`)이 켜져 있으면 문제로 친다. 훅이 두 번 돈다.
- 위키 단계 지시는 `stages`의 prompt 중 하나라도 `wiki`를 담고 있으면 있는 것으로 본다. 없으면 작업을 시작할 때 기록을 찾지 않고 마무리할 때 남기지 않으므로 주의를 준다([ADR 0008](decisions/0008-wiki.md)).
- 플랫폼 도구(Xcode, Node 등)는 보지 않는다.

## 예전 iOS 묶음을 쓰던 프로젝트

0.11.x까지는 iOS 묶음(`packs/ios`)이 빌드·테스트·린트·e2e 스크립트, Swift 규칙, iOS 권한을 설치했다. 단위 31에서 하네스가 이것을 갖지 않게 됐다([ADR 0024](decisions/0024-no-platform.md)). 그 묶음을 설치한 프로젝트를 sync하면 지우지 않고 프로젝트 코드로 넘긴다. 시험장 두 곳(ReadSharp, IntervalTimer)이 쓰고 있어, 지우면 검사가 깨지기 때문이다.

| 예전 자리 | 새 자리 |
|---|---|
| `scripts/harness/build`·`test`·`unit-test`·`lint`·`e2e`·`ios.sh` | `scripts/ios/` (그때 쓰던 `scripts/harness/lib.sh` 사본을 `scripts/ios/lib.sh`로 함께 둔다) |
| `.claude/rules/harness/ios/*.md`, 그 전 자리 `.claude/rules/harness/<swift 등>.md` | `.claude/rules/project/ios/` |
| `scripts/harness/ios-doctor.sh`, `ios-checks.json` | 지운다 |

- 스크립트는 지난번에 하네스가 설치한 것(설치 기록의 `files`. 기록이 없으면 하네스 것으로 본다)만 옮긴다. 스크립트를 하나라도 옮겼을 때만 규칙 옮기기, `ios-doctor.sh`·`ios-checks.json` 지우기, 아래 경로 바꾸기를 한다.
- 새 자리에 같은 이름이 이미 있으면 그 파일은 옮기지 않는다.
- 옮긴 파일과 `.harness/checks.json` 안의 경로(`scripts/harness/unit-test` 등, 규칙 경로)를 새 자리로 바꾼다.
- `project.json`의 `ios.generator`가 `tuist`·`xcodegen`이면 `generated`에 `*.xcodeproj/*`, `*.xcworkspace/*`, `Derived/*`, `*/Derived/*`를 더한다. 예전에는 훅이 generator를 보고 막았다.
- 묶음이 넣은 권한(pbxproj 편집 deny, 인증서 읽기 deny 등)은 지우지 않고 프로젝트 규칙으로 남긴다.
- `project.json`의 `ios` 값은 옮긴 스크립트가 읽으므로 그대로 둔다.
- "직접 할 일"로 AGENTS.md 프로젝트 영역에 빌드·테스트 명령(`scripts/ios/unit-test` 등)을 적으라고 알린다.
- 옮긴 뒤로는 하네스가 갱신하지 않는다. 두 번째 sync는 바뀐 것이 없다.

## 지침 파일이 이미 있는 프로젝트

MotoTrace에 적용하며 정한 방식이다.

1. init을 실행한다. 기존 AGENTS.md는 그대로 두고 끝에 관리 블록을 붙인다. CLAUDE.md가 import 형태가 아니면 손대지 않고 알린다.
2. 기존 지침(CLAUDE.md, AGENTS.md)의 내용을 셋으로 나눈다.
   - 하네스 관리 블록과 겹치는 것(커밋 승인, 파괴적 명령, 검증 보고 등)은 지운다.
   - 특정 파일 종류에만 해당하는 프로젝트 규칙(아키텍처, 테스트 관례)은 `.claude/rules/project/`에 `paths:`를 달아 옮긴다.
   - 나머지 프로젝트 정보(소개, 구조, 작업 흐름)는 AGENTS.md 프로젝트 영역에 쓴다.
3. CLAUDE.md를 `template/CLAUDE.md` 형태(`@AGENTS.md` import)로 바꾼다. 이 단계 전에는 Claude Code가 AGENTS.md를 읽지 않는다.
4. 하네스가 대신하게 된 기존 장치(별도 검증 스크립트, 커밋 훅 등)는 지우고, 그 장치를 설명하던 문서도 고친다.
5. 프로젝트 `.gitignore`가 `.claude/`를 통째로 무시하면 하네스 규칙이 커밋되지 않는다. `.claude/*`와 `!.claude/rules/` 형태로 바꾼다. `.claude/settings.json`에 개인 값이 들어 있어 무시하는 프로젝트는 권한 규칙을 공유할 방법을 따로 정한다. ReadSharp에 적용하며 발견했다.
