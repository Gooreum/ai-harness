# 템플릿

`template/`의 파일이 각 프로젝트의 어디에 설치되고 어떻게 갱신되는지 정리한다.
설치는 `scripts/init`, 갱신은 `scripts/sync`, 점검은 프로젝트 안의 `scripts/harness/doctor`가 한다(후보 14, [ADR 0011](decisions/0011-plugin-distribution.md)).

## 설치 위치

template 안의 경로가 그대로 프로젝트 루트 기준 경로가 된다.
플랫폼 묶음의 파일은 `.harness/project.json`의 `platforms`에 그 묶음이 있을 때만 설치된다. 어느 파일이 어느 묶음 것인지는 하네스 저장소의 `packs/<묶음>/pack.json`이 적는다([ADR 0019](decisions/0019-pack-install.md)). 목록에 없는 파일은 공통이라 어느 프로젝트에나 설치된다.

| template 경로 | 성격 | 갱신할 때 |
|---|---|---|
| `AGENTS.md` | 위쪽은 프로젝트 영역, 아래쪽은 하네스 관리 블록 | 관리 블록만 바꾼다 |
| `CLAUDE.md` | AGENTS.md를 import하는 연결 파일 | 그대로 둔다 |
| `.claude/rules/harness/*.md` | 공통 상황별 규칙(`wiki.md`) | 통째로 바꾼다 |
| `.claude/rules/harness/ios/*.md` | iOS 묶음 규칙(Swift, 테스트, 프로젝트 설정, Tuist, 컨벤션, Maestro) | 통째로 바꾼다. 묶음을 빼면 지운다 |
| `.claude/rules/project/` | 프로젝트 고유 규칙을 두는 자리 (`.gitkeep`만 있음) | 건드리지 않는다 |
| `.claude/settings.json` | 공통 권한 규칙(`.env` 읽기 deny, 파괴적·외부 공개 git 작업 ask), 고른 묶음의 권한 규칙(`packs/<묶음>/settings.json`, iOS는 인증서 읽기·pbxproj 편집 deny)과 플러그인 등록(GitHub 마켓플레이스) | 프로젝트 설정과 합친다 |
| `scripts/harness/*` | 공통 스크립트(wiki·record·passed·doctor, 공통 함수 lib.sh)와 iOS 묶음 스크립트(build·test·unit-test·lint·e2e, ios.sh, ios-doctor.sh) | 통째로 바꾼다. 묶음을 빼면 그 묶음 것을 지운다 |
| `.harness/.gitignore` | `.harness/`에서 설정 파일과 설치 기록만 커밋되게 함 | 통째로 바꾼다 |

`.harness/harness.json`(설치 기록)은 template에 없다. init·sync가 설치한 하네스 버전(`plugin.json`의 `version`)과 설치한 파일 목록을 `{"version": "0.9.10", "packs": ["ios"], "files": [...]}` 형태로 쓴다. 다음 sync는 이 목록에 있었는데 template에서 사라졌거나 고르지 않은 묶음의 파일만 지운다. 팀이 `scripts/harness/`에 넣은 파일은 남는다. 커밋해서 팀원의 doctor도 같은 값과 비교하게 한다.

`.harness/project.json`은 template에 없다. 설치할 때 하네스 저장소의 `scripts/detect`가 프로젝트를 보고 만들고, 이후에는 `detect --write --force`로만 다시 만든다.

`.harness/conventions.json`(팀 컨벤션 목록)도 template에 없다. 팀이 규칙을 고른 뒤 프로젝트에서 직접 만든다([conventions.md](conventions.md)). 없으면 `lint`는 건너뛴다.

## AGENTS.md의 두 영역

| 영역 | 위치 | 내용 | 누가 고치나 |
|---|---|---|---|
| 프로젝트 영역 | 관리 블록 위 | 앱 소개, 구조, 프로젝트 규칙 | 각 프로젝트. 설치 뒤 채운다 |
| 하네스 관리 블록 | `<!-- harness:begin -->`부터 `<!-- harness:end -->`까지 | 빌드·테스트 명령, 꼭 지킬 규칙, 상황별 규칙 표 | 하네스 저장소. 프로젝트에서 직접 고치지 않는다 |

- 두 영역의 규칙이 다르면 프로젝트 규칙을 따른다. 이 우선순위는 관리 블록 안에 적혀 있다. 그래서 프로젝트는 관리 블록을 고치지 않고도 기본 규칙을 바꿀 수 있다.
- 표시와 안내는 HTML 주석이라 Claude의 컨텍스트에서는 빠진다. 파일을 열어 고칠 때는 보인다.
- 관리 블록의 `<!-- harness:pack commands|notes|rules -->` 줄은 고른 묶음의 `packs/<묶음>/agents-<조각>.md`로 바뀐다. 묶음이 없으면 그 줄만 빠진다.
- 새로 만드는 AGENTS.md의 제목은 프로젝트 폴더 이름이다.
- 명령 블록에는 프로젝트별 값을 채워 넣지 않는다. 스크립트가 `.harness/project.json`을 직접 읽기 때문에 명령이 모든 프로젝트에서 같다.

## 설치와 갱신: scripts/init, scripts/sync

```bash
scripts/init <프로젝트 경로>          # 처음 설치. 이미 설치됐으면(harness.json이 있으면) 거절한다
scripts/sync <프로젝트 경로>          # 갱신. 설치되지 않았으면(project.json이 없으면) 거절한다
scripts/sync --dev <프로젝트 경로>    # 갱신하되 플러그인을 이 저장소 디렉터리에서 읽게 한다
```

- 위 표대로 파일을 맞추고, `.harness/project.json`이 없으면 detect로 초안을 만든다. 옛 형식(`schemaVersion` 1)이면 iOS 값을 `ios` 아래로 옮긴다.
- `.claude/settings.json`에 GitHub 마켓플레이스와 플러그인을 등록한다. 이 파일을 커밋하면 팀원이 프로젝트를 열 때 Claude Code가 설치를 권한다.
- `--dev`는 `.claude/settings.local.json`에 같은 이름의 디렉터리 마켓플레이스를 넣는다. 로컬 설정이 우선하므로 공유 설정은 그대로 두고 내 컴퓨터에서만 개발 중인 플러그인을 쓴다. `--dev` 없이 다시 실행하면 이 항목을 지운다.
- 여러 번 실행해도 결과가 같다. 바뀐 파일과 사람이 직접 할 일을 출력한다.

## 점검: scripts/harness/doctor

프로젝트 안에서 누구나 돌린다. 파일은 고치지 않고, 문제마다 고치는 방법을 한 줄 붙인다.

| 보는 것 | ✕ 문제 | ! 주의 |
|---|---|---|
| 묶음 | 설정이 옛 형식이다, 고른 묶음의 점검 스크립트(`<묶음>-doctor.sh`)가 없다 | |
| iOS 도구 | xcodebuild, 생성기(tuist·xcodegen)가 없다 | `.maestro/`가 있는데 maestro가 없다 |
| 설정 파일 | ios 설정·ios.app.scheme이 없다, 프로젝트·워크스페이스 파일이 없다(생성기 없는 프로젝트만), checks·conventions JSON이 깨졌다 | 설정에 적은 시뮬레이터가 없다(최신 iPhone을 대신 쓴다) |
| 설치된 파일 | AGENTS.md 관리 블록, CLAUDE.md의 `@AGENTS.md`, `.claude/rules/harness/`가 없다 | 설치 기록이 없다, 규칙이나 `settings.json`이 git에서 무시된다 |
| 플러그인 | 켜져 있지 않다, 이 프로젝트에 설치되지 않았다, 꺼져 있다, 버전이 설치 기록과 다르다 | claude CLI가 없어 버전을 못 봤다 |

- 플러그인 버전은 `claude plugin list --json`에서 이 프로젝트(`projectPath`)나 사용자 전체에 설치된 항목을 본다. `--dev`로 디렉터리에서 읽는 플러그인은 폴더의 버전(`folderVersion`)을 본다.
- 버전이 다르면 어느 쪽이 오래됐는지에 따라 플러그인 갱신(`claude plugin update`) 또는 `sync`를 안내한다.

## 지침 파일이 이미 있는 프로젝트

MotoTrace에 적용하며 정한 방식이다.

1. init을 실행한다. 기존 AGENTS.md는 그대로 두고 끝에 관리 블록을 붙인다. CLAUDE.md가 import 형태가 아니면 손대지 않고 알린다.
2. 기존 지침(CLAUDE.md, AGENTS.md)의 내용을 셋으로 나눈다.
   - 하네스 관리 블록과 겹치는 것(커밋 승인, 파괴적 명령, 검증 보고 등)은 지운다.
   - 특정 파일 종류에만 해당하는 프로젝트 규칙(아키텍처, 테스트 관례)은 `.claude/rules/project/`에 `paths:`를 달아 옮긴다.
   - 나머지 프로젝트 정보(소개, 구조, 작업 흐름)는 AGENTS.md 프로젝트 영역에 쓴다.
3. CLAUDE.md를 `template/CLAUDE.md` 형태(`@AGENTS.md` import)로 바꾼다. 이 단계 전에는 Claude Code가 AGENTS.md를 읽지 않는다.
4. 하네스가 대신하게 된 기존 장치(별도 검증 스크립트, 커밋 훅 등)는 지우고, 그 장치를 설명하던 문서도 고친다.
5. 프로젝트 고유 스크립트가 빌드 결과를 찾는다면 하네스의 DerivedData를 보게 한다. 경로는 `scripts/harness/ios.sh`의 `harness_derived_data_path`로 얻는다.
6. 프로젝트 `.gitignore`가 `.claude/`를 통째로 무시하면 하네스 규칙이 커밋되지 않는다. `.claude/*`와 `!.claude/rules/` 형태로 바꾼다. `.claude/settings.json`에 개인 값이 들어 있어 무시하는 프로젝트는 권한 규칙을 공유할 방법을 따로 정한다. ReadSharp에 적용하며 발견했다.
