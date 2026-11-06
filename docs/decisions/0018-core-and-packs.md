# 0018. 하네스를 공통 핵심과 플랫폼 묶음으로 나누고, 아무 명령의 결과는 record로 남긴다

- 상태: 대체됨 (2026-11-06, ADR 0024 — 하네스는 플랫폼을 모른다)
- 관련: ADR 0005(발표 기준), ADR 0012(run 확인), 로드맵 단위 22·23, `template/scripts/harness/lib.sh`·`ios.sh`·`record`

## 배경

- 발표 슬라이드 19·21·38: v1은 다른 플랫폼에서 쓸 수 없었다. v2는 "하네스도 훅도 그대로, 저장소마다 config만 다르게" 만들었다. 웹 저장소는 lint·typecheck·unit-test·build를, LLM Wiki 저장소는 bats를 검사로 썼다.
- 발표 슬라이드 29·30: prompt는 시키고, run은 확인한다. run은 가장 최근 실행이 통과했는지 본다.
- 지금 하네스는 iOS 전용이다.
  - 공용 함수 `lib.sh`의 `harness_init`이 Xcode를 고르고 `simctl`을 부른다. Xcode와 상관없는 `passed`·`wiki`도 이 과정을 거친다.
  - 결과 파일(`.harness/out/<검사>.json`)을 쓰는 것이 iOS 스크립트(build·unit-test·lint·e2e)와 리뷰 훅뿐이다. `npm run typecheck` 같은 명령은 run으로 확인할 방법이 없다.
- ai-bouncer는 `bouncer record <이름> <명령>`으로 아무 명령이나 돌려 로그를 남기고, `bouncer passed <이름>`이 로그 끝 `exit: N`과 최신 여부를 본다.

## 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 구조 | 공통 핵심(단계 훅, Stop 게이트, `task`, `checks.json`, `passed`, `record`, `wiki`, 리뷰 절차)과 플랫폼 묶음(빌드·테스트·e2e 스크립트, 규칙, 권한, 생성 파일, doctor 항목)으로 나눈다. 한 프로젝트가 묶음을 여러 개 쓸 수 있다 | 발표처럼 훅과 흐름은 그대로 두고 저장소마다 검사만 다르게 한다. React Native는 JS·iOS·Android 묶음을 함께 쓴다 |
| 스크립트 공용 함수 | `lib.sh`에는 공통(루트·설정, 바뀐 파일, 작업 시작 커밋, `cfg`, 위키)만 둔다. Xcode·시뮬레이터 함수는 `ios.sh`로 옮기고, iOS 스크립트는 `ios.sh`를 불러 `harness_init_ios`를 쓴다 | `passed`·`record`·`wiki`가 Xcode 없이 돈다. 묶음 설치 구조는 단위 23에서 만든다 |
| `record` | `scripts/harness/record <이름> <명령>`이 명령을 프로젝트 루트에서 돌리고 `.harness/out/<이름>.json`을 남긴다. run은 지금처럼 `passed <이름>` | ai-bouncer `bouncer record`와 같은 짝이다. 어느 명령이든 run으로 확인할 수 있다 |
| 결과 형식 (ai-bouncer와 다름) | 로그 끝 `exit: N` 대신 JSON(`passed`, `summary`, `exit`, `command`, `seconds`) | build·unit-test·lint·e2e·review 결과가 이미 JSON이다. `passed`가 한 가지 형식만 읽게 한다 |
| 화면 출력 (ai-bouncer와 다름) | 전체 출력은 `.harness/out/<이름>.log`에 두고, 성공하면 한 줄, 실패하면 끝 30줄(`HARNESS_RECORD_TAIL`)과 로그 경로만 보여 준다 | 성공은 짧게, 실패는 구체적으로(설계 원칙). 아무 명령이나 받으니 "첫 에러"를 찾을 수 없어 끝부분을 보여 준다. ai-bouncer는 `tee`로 전부 보여 주고, `passed`가 실패하면 끝 20줄을 보여 준다 |
| 실행 환경 | `CI=1`을 넣고 입력을 `/dev/null`로 둔다 | jest·vitest 같은 도구가 감시 모드(watch)나 질문으로 멈추지 않게 한다 |
| 검사 이름 | 영문·숫자·`-`·`_`만 | ai-bouncer `result_name`과 같다. 이름이 파일 이름이 된다 |
| 시작할 때 결과 지우기 | 실행 전에 이전 `<이름>.json`을 지운다 | 실행이 중간에 끊겨도 옛 통과가 남지 않는다(unit-test와 같다) |
| 검사 순서 | 파일을 고치는 검사(포매터, `--fix`, 설치)는 먼저 돌린다고 verify 단계 지시에 적는다 | 나중에 돌리면 앞 검사 결과가 고친 파일보다 오래돼 `passed`가 막는다 |
| 오래 걸리는 검사 | 10분이 넘는 검사는 백그라운드로 돌리고 결과 파일을 보라고 verify 단계 지시에 적는다 | Gradle·e2e는 도구 호출 시간 제한을 넘는다 |
| jq가 없을 때 | 단계 지시 훅이 jq 없이 고정 문구로 "훅이 모두 꺼져 있다"고 알리고, doctor가 jq를 문제로 친다 | 지금은 jq가 없으면 모든 훅이 아무 말 없이 꺼진다. 막아야 할 것을 막지 못해도 알 수 없다 |

## 결과

- iOS 스크립트 없이 `record`·`passed`만으로 `checks.json`의 검사가 게이트를 통과·실패한다(`tests/record.test.sh`).
- iOS 프로젝트는 sync하면 `ios.sh`가 함께 설치된다. 동작은 같다.
- 묶음을 고르고 설치하는 구조, `project.json`의 `platforms`는 단위 23에서 한다.
