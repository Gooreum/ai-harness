# 0023. 묶음 없는 저장소는 공통 핵심만으로 돌고, 다른 플랫폼의 빌드·e2e는 저장소가 정한다

- 상태: 채택 (2026-11-06)
- 관련: ADR 0018(공통 핵심과 묶음), 0019(묶음 구조), 0020(검사 목록은 setup으로), 로드맵 단위 26~30

## 배경

- 로드맵은 범용 하네스로 JS·RN 묶음(27), Android·RN e2e(28), 웹 묶음(29), Linux(30)를 계획했다. 묶음마다 빌드 방식(`xcodebuild`인지 `expo run:ios`인지), 컨벤션 검사 방식, 웹 e2e 도구(Playwright인지 Maestro인지)를 하네스가 정해야 했다.
- 사용자가 되물었다(2026-11-06): "이런 것까지 설정을 해 줘야 해 하네스에서?", "이걸 하네스에서 설정하는 게 맞냐". 지원 OS는 macOS만으로 정했다.
- 발표 슬라이드 38: "하네스도 훅도 그대로, 저장소마다 config만 달라요". 웹 저장소의 검사는 lint·typecheck·unit-test·build, LLM Wiki 저장소는 bats였다. 하네스는 그 저장소의 명령을 모른다. 슬라이드 27: "훅은 검사 내용을 몰라요".
- ai-bouncer에는 플랫폼 묶음이 없다. `bouncer setup`이 저장소에서 명령을 찾아 묻고, `bouncer record <이름> <명령>`이 결과를 남긴다.
- 단위 26에서 이 하네스 저장소 사본에 묶음 없이 설치해 보니 두 가지가 막혔다. setup이 `tests/run.sh`를 찾지 못했고, 리뷰 검사가 iOS 추천 검사에만 있어 묶음이 없으면 리뷰를 고를 수 없었다.

## 결정

| 항목 | 결정 | 근거 |
|---|---|---|
| 묶음 없는 저장소 | 공통 파일(`record`·`passed`·`wiki`·`doctor`·`setup`)과 플러그인만으로 돈다. 리뷰는 공통 추천 검사(`scripts/harness/common-checks.json`)로 옮겨 묶음과 상관없이 setup이 보여 준다 | 발표 슬라이드 38(LLM Wiki 저장소) |
| setup이 찾는 명령 | `tests/run.sh`, `*.bats`(`bats -r .`), `Package.swift`(`swift test`·`swift build`)를 더한다 | ai-bouncer setup이 `tests/run-all.sh`를 찾는 것과 같은 방식 |
| 앱 없는 Swift 패키지 | detect가 iOS 묶음을 고르지 않는다. iOS 묶음 스크립트는 앱 스킴을 전제로 한다. 손으로 고른 경우 doctor가 `spm`에는 앱 스킴을 요구하지 않는다 | 묶음 스크립트가 지원하지 않는 것을 설치하지 않는다 |
| JS·RN·Android·웹 | 묶음을 만들지 않는다. 빌드·테스트·e2e·컨벤션 검사는 저장소의 명령(`npm test`, `npx tsc`, `npx eslint`, `maestro test`, `npx playwright test` 등)을 `checks.json`에 `record`로 적는다. 하네스는 도구를 고르지 않고 설정 파일을 만들지 않는다 | 사용자 결정, 발표 슬라이드 27·38, ai-bouncer |
| 하네스가 계속 맡는 것 | 공통 핵심(단계 훅, run 확인, Stop 게이트, 리뷰, 위키), 생성 파일 보호(`project.json`의 `generated`), 권한(ADR 0022), setup이 명령을 찾아 보여 주기 | 플랫폼과 상관없이 같은 동작 |
| iOS 묶음 | 그대로 둔다 | `xcodebuild` 출력이 커서 요약 스크립트가 필요했다(ADR 0003). 이미 쓰고 있다 |
| 지원 OS | macOS만 지원한다. Linux CI를 두지 않는다 | 사용자 결정. 쓰는 곳이 이 Mac뿐이다 |

## 발표·ai-bouncer와 다른 점

- 발표·ai-bouncer와 같은 방향으로 돌아왔다. iOS 묶음만 하네스가 스크립트를 가진다는 점이 다르고, 이것은 ADR 0018·0019에 있다.

## 결과

- 로드맵 단위 27~29는 묶음을 만들지 않는 것으로 줄이고, 시험장에서 `record`만으로 게이트를 통과하는지 확인한다. 단위 30은 macOS만 지원한다고 적고 닫는다.
- 이 저장소의 사본에서 `task`(simple, 검사 test·review) 작업이 `record test "bash tests/run.sh"` 결과와 리뷰로 done까지 갔다.
