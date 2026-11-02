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
| `scripts/harness/*` | 프로젝트 스크립트(build·test·verify·lint·wiki, lib.sh) | 통째로 바꾼다 |
| `.harness/.gitignore` | `.harness/`에서 설정 파일만 커밋되게 함 | 통째로 바꾼다 |

`.harness/project.json`은 template에 없다. 설치할 때 하네스 저장소의 `scripts/detect`가 프로젝트를 보고 만들고, 이후에는 `detect --write --force`로만 다시 만든다.

`.harness/conventions.json`(팀 컨벤션 목록)도 template에 없다. 팀이 규칙을 고른 뒤 프로젝트에서 직접 만든다([conventions.md](conventions.md)). 없으면 `lint`는 건너뛴다.

## AGENTS.md의 두 영역

| 영역 | 위치 | 내용 | 누가 고치나 |
|---|---|---|---|
| 프로젝트 영역 | 관리 블록 위 | 앱 소개, 구조, 프로젝트 규칙 | 각 프로젝트. 설치 뒤 채운다 |
| 하네스 관리 블록 | `<!-- harness:begin -->`부터 `<!-- harness:end -->`까지 | 빌드·테스트 명령, 꼭 지킬 규칙, 상황별 규칙 표 | 하네스 저장소. 프로젝트에서 직접 고치지 않는다 |

- 두 영역의 규칙이 다르면 프로젝트 규칙을 따른다. 이 우선순위는 관리 블록 안에 적혀 있다. 그래서 프로젝트는 관리 블록을 고치지 않고도 기본 규칙을 바꿀 수 있다.
- 표시와 안내는 HTML 주석이라 Claude의 컨텍스트에서는 빠진다. 파일을 열어 고칠 때는 보인다.
- 명령 블록에는 프로젝트별 값을 채워 넣지 않는다. 스크립트가 `.harness/project.json`을 직접 읽기 때문에 명령이 모든 프로젝트에서 같다.

## 설치: scripts/dev-install

```bash
scripts/dev-install <프로젝트 경로>
```

- 위 표대로 파일을 맞추고, `.harness/project.json`이 없으면 detect로 초안을 만든다.
- 하네스 저장소를 로컬 마켓플레이스로 등록하고 플러그인을 켠다(`.claude/settings.local.json`).
- 여러 번 실행해도 결과가 같다. 바뀐 파일과 사람이 직접 할 일을 출력한다.

## 지침 파일이 이미 있는 프로젝트

MotoTrace에 적용하며 정한 방식이다.

1. dev-install을 실행한다. 기존 AGENTS.md는 그대로 두고 끝에 관리 블록을 붙인다. CLAUDE.md가 import 형태가 아니면 손대지 않고 알린다.
2. 기존 지침(CLAUDE.md, AGENTS.md)의 내용을 셋으로 나눈다.
   - 하네스 관리 블록과 겹치는 것(커밋 승인, 파괴적 명령, 검증 보고 등)은 지운다.
   - 특정 파일 종류에만 해당하는 프로젝트 규칙(아키텍처, 테스트 관례)은 `.claude/rules/project/`에 `paths:`를 달아 옮긴다.
   - 나머지 프로젝트 정보(소개, 구조, 작업 흐름)는 AGENTS.md 프로젝트 영역에 쓴다.
3. CLAUDE.md를 `template/CLAUDE.md` 형태(`@AGENTS.md` import)로 바꾼다. 이 단계 전에는 Claude Code가 AGENTS.md를 읽지 않는다.
4. 하네스가 대신하게 된 기존 장치(별도 검증 스크립트, 커밋 훅 등)는 지우고, 그 장치를 설명하던 문서도 고친다.
5. 프로젝트 고유 스크립트가 빌드 결과를 찾는다면 하네스의 DerivedData를 보게 한다. 경로는 `scripts/harness/lib.sh`의 `harness_derived_data_path`로 얻는다.
6. 프로젝트 `.gitignore`가 `.claude/`를 통째로 무시하면 하네스 규칙이 커밋되지 않는다. `.claude/*`와 `!.claude/rules/` 형태로 바꾼다. `.claude/settings.json`에 개인 값이 들어 있어 무시하는 프로젝트는 권한 규칙을 공유할 방법을 따로 정한다. ReadSharp에 적용하며 발견했다.
