| 코드를 바꾼 뒤 검증 (앱 빌드 + 바뀐 모듈 테스트) | `scripts/harness/unit-test` |
| 무엇을 돌릴지 미리 보기 | `scripts/harness/unit-test --plan` |
| PR 전에 브랜치 전체 변경 검증 | `scripts/harness/unit-test --base <기본 브랜치>` |
| 빌드만 | `scripts/harness/build` |
| 앱 단위 테스트 / 특정 스킴 테스트 | `scripts/harness/test` / `scripts/harness/test --scheme <스킴>` |
| 팀 컨벤션 검사 (바뀐 Swift 파일) | `scripts/harness/lint` |
| E2E 시나리오 / 회귀 묶음(배포 전·리팩터링 뒤) / 영상 | `scripts/harness/e2e <파일>` / `scripts/harness/e2e --tag regression` / `--record` |
