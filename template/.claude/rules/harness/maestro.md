---
paths:
  - ".maestro/**"
---

# E2E 시나리오 (Maestro)

`.maestro/`의 시나리오는 `scripts/harness/e2e`가 돌린다. 한 번 시키고 끝나는 대화가 아니라, 누가 받아도 다시 돌릴 수 있는 파일로 남긴다.

## 작성 규칙

- **앱 ID는 변수로**: 첫 줄은 `appId: ${APP_ID}`. 스크립트가 `.harness/project.json`의 번들 ID를 넣는다.
- **요소는 id로 먼저 찾는다**: `tapOn: { id: "..." }`. 화면 문구는 바뀌면 시나리오가 깨진다. id가 없으면 문구로 쓰되, 보고에 "accessibilityIdentifier를 달면 좋을 요소"를 적는다.
- **원하는 화면으로 바로 들어간다**: 딥링크(`openLink`)가 있으면 앞 화면을 거치지 않는다.
- **계정·비밀 값은 환경 변수로**: `${MAESTRO_TEST_EMAIL}`처럼 쓴다. 실제 값을 파일에 적지 않는다.
- **반복 단계는 공통 흐름으로**: 앱 시작·로그인 같은 단계는 `.maestro/common/`에 두고 `runFlow: common/<이름>.yaml`로 부른다. `common/` 아래는 혼자 돌리지 않는다.
- **결과를 확인한다**: 화면이 뜬 것만으로 성공으로 보지 않는다. 바뀌어야 할 값(`assertVisible`, `assertNotVisible`)을 확인하는 단계로 끝낸다.
- **개인 경로를 쓰지 않는다**: 파일 경로는 저장소 기준 상대 경로로 쓴다.
- **끝까지 통과한 것만 남긴다**: `scripts/harness/e2e <파일>`로 처음부터 끝까지 통과한 뒤에 저장한다. 통과하지 못한 시나리오는 지우거나 사용자에게 알린다.

## 태그

- 앞으로도 계속 확인할 시나리오에는 `tags: [regression]`을 붙인다. 배포 전과 리팩터링 뒤에 `scripts/harness/e2e --tag regression`으로 묶어 돌린다.

## 수정 전후 영상

- QA 티켓을 고칠 때는 고치기 전과 후에 `scripts/harness/e2e --record <파일>`로 돌려 `.harness/out/e2e.mp4`를 남긴다. PR에 두 영상을 붙인다.
