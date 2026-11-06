# 0019. 묶음을 pack.json 목록으로 정하고, 설정 파일의 플랫폼 값을 묶음 이름 아래로 옮긴다

- 상태: 채택 (2026-11-06)
- 관련: ADR 0018(공통 핵심과 묶음), ADR 0003(AGENTS.md 두 영역), 로드맵 단위 23, `packs/`, `scripts/sync`·`detect`

## 배경

- 발표 슬라이드 19: v1은 "웹 작업인데 안드로이드 검증 스킬을 불러와요". 플랫폼마다 다른 것이 모든 저장소에 들어갔다.
- 발표 슬라이드 38: "하네스도 훅도 그대로, 저장소마다 config만 달라요". 저장소마다 다른 것은 설정에 둔다.
- ai-bouncer는 묶음이 없다. 저장소마다 `workflow.yaml`의 검사만 다르고, 검사 스크립트는 저장소가 가진다.
- ADR 0018에서 iOS 함수를 `ios.sh`로 뗐지만, sync는 아직 모든 프로젝트에 iOS 스크립트·규칙·권한을 설치한다. `project.json`의 iOS 값(`app.scheme`, `generator` …)도 최상위에 있어, 묶음이 늘면 어느 플랫폼 값인지 알 수 없다.

## 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 묶음 정의 | `packs/<묶음>/pack.json`의 `files`가 template 안의 어느 파일이 그 묶음 것인지 적는다(`/`로 끝나면 폴더). 파일은 `template/`에 그대로 둔다 | 스크립트가 서로를 같은 폴더에서 불러온다(`ios.sh` → `lib.sh`). 폴더를 나누면 설치된 모습과 저장소 모습이 달라져 테스트가 설치를 흉내 내야 한다 |
| 묶음의 나머지 | 권한은 `packs/<묶음>/settings.json`, AGENTS.md 관리 블록 조각은 `agents-commands.md`·`agents-notes.md`·`agents-rules.md`, doctor 항목은 `scripts/harness/<묶음>-doctor.sh`의 `doctor_<묶음>` | 공통 template에는 묶음과 상관없는 것만 남긴다 |
| 규칙 폴더 | 묶음 규칙은 `.claude/rules/harness/<묶음>/`에 둔다. 공통 규칙(`wiki.md`)만 바로 아래 | Claude Code는 규칙 폴더를 하위 폴더까지 읽는다. 묶음 하나를 지울 때 폴더째 지울 수 있다 |
| 고르는 곳 | `project.json`의 `platforms`. 설치 기록(`harness.json`)의 `packs`는 기록일 뿐이다 | 설정은 사람이 확인하고 커밋하는 파일이다. 묶음을 빼면 다음 sync가 그 묶음 파일을 지운다(설치 기록의 `files`에 있던 것만) |
| 설정 모양 | `schemaVersion` 2. iOS 값은 `ios` 아래에 둔다. `e2e`(행동 기록, 가짜 응답 포트)는 위에 남긴다 | 사용자가 정했다(2026-11-06). 묶음이 여러 개여도 키가 섞이지 않는다. 가짜 응답 서버는 Android·RN에서도 쓴다(단위 28) |
| 옛 설정 | sync가 `schemaVersion` 1을 2로 옮긴다(`platforms: ["ios"]`). 생성 파일 보호 훅은 sync 전 옛 형식도 읽는다. doctor는 옛 형식을 문제로 친다 | 플러그인이 sync보다 먼저 갱신될 수 있다. 훅이 설정을 못 읽으면 막을 것을 못 막는다 |
| detect | Xcode 프로젝트가 있으면 `ios`를 고른다. `package.json`·`gradlew`·`pyproject.toml`·`Cargo.toml`·`go.mod`는 묶음이 없다고 알리기만 한다. 묶음이 없어도 초안을 만든다 | 공통 파일(`record`·`passed`·`wiki`)만으로도 검사 게이트가 돈다(ADR 0018) |
| AGENTS.md 제목 | 새로 만들 때 폴더 이름 | 앱 스킴은 iOS 묶음에만 있다 |

## 발표·ai-bouncer와 다른 점

- 발표와 ai-bouncer에는 묶음이 없다. 검사는 설정에, 검사 스크립트는 각 저장소에 있다. 이 하네스는 여러 프로젝트에 같은 빌드·테스트 스크립트를 설치하려고 묶음을 둔다(로드맵 단위 22·23에서 정했다). 훅과 작업 흐름은 묶음과 상관없이 같다.

## 결과

- 묶음이 없는 저장소에 init하면 `record`·`passed`·`wiki`·`doctor`와 `wiki.md` 규칙만 설치되고, 관리 블록에 iOS 줄이 없다(`tests/sync.test.sh`).
- iOS 프로젝트는 sync하면 설정이 새 형식으로 바뀌고 규칙이 `rules/harness/ios/`로 옮겨진다. 옛 위치의 규칙은 설치 기록에 있어 지워진다.
- 프로젝트의 `checks.json`이 옛 규칙 경로(`rules/harness/maestro.md`)를 적어 두었으면 사람이 고친다. sync는 `checks.json`을 고치지 않는다.
