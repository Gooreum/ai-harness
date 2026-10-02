# 프로젝트 스크립트

각 iOS 프로젝트에 설치되는 스크립트(`template/scripts/harness/`)의 동작 방식이다.
에이전트·사람·CI가 같은 스크립트를 쓴다. 모든 스크립트는 `.harness/project.json`을 읽는다([project-config.md](project-config.md)).

## 공통

- **출력**: 성공하면 한 줄, 실패하면 원인을 찾는 데 필요한 만큼만 출력한다. 전체 로그와 결과 번들은 파일로 남기고 경로만 알려준다.
- **산출물 위치**: 모두 프로젝트의 `.harness/` 아래에 둔다. `.harness/.gitignore`가 설정 파일만 남기고 나머지를 무시한다.

  | 경로 | 내용 |
  |---|---|
  | `.harness/out/` | 마지막 실행의 로그(`*.log`)와 결과 번들(`*.xcresult`). 실행할 때마다 덮어쓴다 |
  | `.harness/state/` | 다음 실행이 참고하는 로컬 상태(생성 입력 지문 등) |
  | `.harness/DerivedData/` | 이 워크트리 전용 DerivedData. 워크트리끼리 빌드 캐시가 섞이지 않는다 |

- **프로젝트 생성(Tuist·XcodeGen)**: 빌드 전에 생성이 필요한지 스스로 판단한다.
  - 생성 입력의 지문이 지난번과 다르면 install·generate를 다시 실행한다. 지문은 git이 보는 파일 목록과 manifest 내용으로 만든다.
  - 그래서 파일을 추가·삭제·이동하거나 manifest를 바꾸면 자동으로 다시 생성된다. 소스 내용만 바뀌었을 때는 건너뛴다.
  - 생성된 프로젝트 파일이 없으면 항상 생성한다. `--generate`를 주면 무조건 다시 생성한다.
  - Tuist가 생성 뒤 Xcode를 여는 동작은 `TUIST_GENERATE_OPEN=false`로 끈다.
- **시뮬레이터**: 설정의 기기 이름과 OS로 UDID를 찾는다. 없으면 설치된 iPhone 목록을 보여주고 멈춘다.

## build

```bash
scripts/harness/build                    # 앱 스킴 빌드
scripts/harness/build --scheme FeatureA  # 다른 스킴 빌드
scripts/harness/build --generate         # 프로젝트를 다시 생성한 뒤 빌드
```

- 순서: 필요하면 install·generate → `xcodebuild build -quiet` → `xcresulttool get build-results`로 요약
- 성공: `✓ build MotoTrace · iPhone 17 Pro · 4s · 경고 0`
- 실패: 첫 에러부터 최대 5개(`HARNESS_MAX_ERRORS`로 변경)를 `경로:줄:열: 메시지`로 보여주고, 로그와 결과 번들 경로를 붙인다.
  - 결과 번들에 에러가 없는 실패(인자 오류, 스크립트 단계 실패)는 로그의 에러 줄을 보여준다.
- 종료 코드: 성공 0, 빌드 실패는 xcodebuild의 코드(보통 65), 설정·인자 오류 2
