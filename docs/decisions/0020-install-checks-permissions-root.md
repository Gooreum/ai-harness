# 0020. 검사 목록은 setup 안내로 사용자와 정하고, sync가 넣었던 권한 규칙을 지우고, 스크립트가 가장 가까운 설정을 루트로 쓴다

- 상태: 채택 (2026-11-06)
- 관련: ADR 0019(묶음 설치), ADR 0012(run 확인), 로드맵 단위 23, `scripts/sync`, `template/scripts/harness/lib.sh`·`doctor`, `plugin/hooks/review-record.sh`

## 배경

- 발표 슬라이드 29·30·88: 검사는 설정(config)의 prompt·run에 있고, 사람이 고른 검사를 차례로 돈다. 검사 목록이 없으면 고를 검사가 없다.
- 지금은 아무도 `checks.json`을 만들지 않는다. 시험장 두 곳은 손으로 썼다.
- sync는 권한 규칙을 더하기만 해서, template이나 묶음에서 뺀 규칙(묶음을 빼는 경우 포함)이 프로젝트에 남는다.
- 스크립트는 git 최상위를, 훅은 가장 가까운 `.harness/project.json`을 루트로 썼다. 모노레포 하위 폴더에 설치하면 스크립트가 설정을 못 찾는다. `git diff --name-only`는 저장소 기준 경로를 내서, 리뷰 기록 훅이 바뀐 파일을 0개로 보고 통과시켰다.

## 결정

| 항목 | 결정 | 근거 |
|---|---|---|
| 검사 목록 | init·sync는 `checks.json`을 쓰지 않는다. 없으면 "Claude 세션에서 `scripts/harness/setup` 안내대로 검사를 정한다"를 할 일로 남긴다 | ai-bouncer `init`이 빈 설정만 만들고 `bouncer setup`으로 넘기는 것과 같다. 검사는 팀이 정하는 정책이다(ADR 0005) |
| setup | `scripts/harness/setup`(공통)은 아무것도 쓰지 않고 안내만 낸다: 저장소에서 찾은 명령, 고른 묶음의 추천 검사(`scripts/harness/<묶음>-checks.json`), 묻는 순서. 에이전트가 AskUserQuestion으로 사용자에게 묻고 답대로 `checks.json`을 쓴다. 이미 있으면 바꿀 부분만 묻는다 | ai-bouncer `engine/setup.sh`를 따른다. 명령을 찾는 규칙(package.json scripts, Makefile, pytest·ruff, go, cargo, gradlew)도 같다 |
| 권한 규칙 | sync가 넣은 규칙을 `harness.json`의 `permissions`에 적는다. 다음 sync는 그 기록에 있는데 이번에 넣을 규칙에 없는 것만 지운다. 기록이 없으면(옛 설치) 지우지 않는다 | 설치 파일 목록(`files`)과 같은 방식. ai-bouncer `init.sh`도 자기가 넣은 훅만 골라 지운다 |
| 루트 | `HARNESS_ROOT`가 없으면 현재 디렉터리에서 git 최상위까지 올라가며 가장 가까운 `.harness/project.json`을 찾는다. 없으면 git 최상위 | ai-bouncer `bouncer_project_root`·`init.sh`와 같다. 훅도 이미 이렇게 찾는다 |
| 바뀐 파일 | `git diff --name-only --relative`로 루트 기준 경로를 받는다(`lib.sh`, 리뷰 기록 훅). 루트 밖 변경은 보지 않는다 | `git ls-files -o`는 원래 현재 폴더 기준이다. 둘을 맞춘다 |
| doctor | `checks.json`의 run 명령이 프로젝트 안 실행 파일이거나 PATH에 있는지, `passed <이름>`이면 그 결과를 만드는 것(`scripts/harness/<이름>`, prompt의 `record <이름>`, review)이 있는지 본다 | run이 돌 수 없으면 verify 단계를 넘지 못한다 |

## 발표·ai-bouncer와 다른 점

- 묶음 추천 검사는 ai-bouncer에 없다. ai-bouncer 기본 항목 `test`·`review` 자리에 iOS 묶음의 스크립트(lint·unit-test·review)를 추천한다. 고르는 것은 그대로 사용자다.
- 처음에는 init이 초안 파일을 바로 쓰게 했으나, 사용자가 원하지 않아 ai-bouncer처럼 묻고 쓰는 방식으로 바꿨다(2026-11-06).

## 결과

- init하면 `checks.json` 없이 setup 안내가 할 일로 나온다. setup은 찾은 명령(`pnpm test` 등)과 묶음 추천 검사를 보여 주고 파일을 쓰지 않는다(`tests/sync.test.sh`, `tests/setup.test.sh`).
- 하네스가 넣었다가 뺀 권한 규칙은 다음 sync에서 사라지고, 팀이 넣은 규칙은 남는다.
- `apps/ios/`에 설치한 프로젝트에서 `passed`와 리뷰 기록이 그 폴더 기준으로 돈다(`tests/passed.test.sh`, `tests/review-record.test.sh`).
