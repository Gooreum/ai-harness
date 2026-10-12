# 템플릿

`template/`의 파일이 각 프로젝트의 어디에 설치되고 어떻게 갱신되는지 정리한다.
설치 도구는 단위 9(dev-install), 갱신 도구는 후보 14(init/sync/doctor)에서 만든다.

## 설치 위치

template 안의 경로가 그대로 프로젝트 루트 기준 경로가 된다.

| template 경로 | 성격 | 갱신할 때 |
|---|---|---|
| `AGENTS.md` | 위쪽은 프로젝트 영역, 아래쪽은 하네스 관리 블록 | 관리 블록만 바꾼다 |
| `CLAUDE.md` | AGENTS.md를 import하는 연결 파일 | 그대로 둔다 |
| `.claude/rules/harness/*.md` | 하네스가 관리하는 상황별 규칙 | 통째로 바꾼다 |
| `.claude/rules/project/` | 프로젝트 고유 규칙을 두는 자리 (`.gitkeep`만 있음) | 건드리지 않는다 |
| `.claude/settings.json` | 권한 규칙: 시크릿 읽기 deny, pbxproj 편집 deny, 파괴적·외부 공개 git 작업 ask | 프로젝트 설정과 합친다 (단위 9) |
| `scripts/harness/*` | 프로젝트 스크립트(build·test·verify, lib.sh) | 통째로 바꾼다 |
| `.harness/.gitignore` | `.harness/`에서 설정 파일만 커밋되게 함 | 통째로 바꾼다 |

`.harness/project.json`은 template에 없다. 설치할 때 하네스 저장소의 `scripts/detect`가 프로젝트를 보고 만들고, 이후에는 `detect --write --force`로만 다시 만든다.

## AGENTS.md의 두 영역

| 영역 | 위치 | 내용 | 누가 고치나 |
|---|---|---|---|
| 프로젝트 영역 | 관리 블록 위 | 앱 소개, 구조, 프로젝트 규칙 | 각 프로젝트. 설치 뒤 채운다 |
| 하네스 관리 블록 | `<!-- harness:begin -->`부터 `<!-- harness:end -->`까지 | 빌드·테스트 명령, 꼭 지킬 규칙, 상황별 규칙 표 | 하네스 저장소. 프로젝트에서 직접 고치지 않는다 |

- 두 영역의 규칙이 다르면 프로젝트 규칙을 따른다. 이 우선순위는 관리 블록 안에 적혀 있다. 그래서 프로젝트는 관리 블록을 고치지 않고도 기본 규칙을 바꿀 수 있다.
- 표시와 안내는 HTML 주석이라 Claude의 컨텍스트에서는 빠진다. 파일을 열어 고칠 때는 보인다.
- 명령 블록에는 프로젝트별 값을 채워 넣지 않는다. 스크립트가 `.harness/project.json`을 직접 읽기 때문에 명령이 모든 프로젝트에서 같다.

## 지침 파일이 이미 있는 프로젝트

- CLAUDE.md만 있으면 그 내용을 AGENTS.md 프로젝트 영역으로 옮기고, CLAUDE.md는 import 파일로 바꾼다.
- AGENTS.md가 있으면 기존 내용을 프로젝트 영역으로 두고 관리 블록을 덧붙인다.
- 단위 9에서 MotoTrace에 적용하면서 구체화한다.
