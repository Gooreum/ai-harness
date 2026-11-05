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
- **클립보드를 쓰지 않는다**: `setClipboard`·`pasteText`는 시뮬레이터 클립보드를 바꾸지 못해, Mac 클립보드 내용이 앱에 붙고 스크린샷에 남는다. 글은 `inputText`로 넣고, 글자가 빠지면 딥링크로 값을 넘긴다.
- **개인 경로를 쓰지 않는다**: 파일 경로는 저장소 기준 상대 경로로 쓴다.
- **끝까지 통과한 것만 남긴다**: `scripts/harness/e2e <파일>`로 처음부터 끝까지 통과한 뒤에 저장한다. 통과하지 못한 시나리오는 지우거나 사용자에게 알린다.

## 태그

- 앞으로도 계속 확인할 시나리오에는 `tags: [regression]`을 붙인다. 배포 전과 리팩터링 뒤에 `scripts/harness/e2e --tag regression`으로 묶어 돌린다.

## 행동 로그

- 화면에 안 보이는 이벤트도 확인해야 하면 시나리오 옆에 `<이름>.events.json`을 둔다. 어떤 이벤트가 몇 번, 어떤 값으로 나가야 하는지만 적는다.
  ```json
  { "events": [ { "name": "tab_select", "count": 1, "params": { "tab": "profile" } }, { "name": "banner_click", "count": 0 } ] }
  ```
- `.harness/project.json`의 `e2e.events`가 `firebase`여야 판정한다. 앱 실행에 `arguments: { "-FIRAnalyticsDebugEnabled": true }`를 넣는다. 공통 흐름의 `launchApp`에 두면 된다.
- 이벤트 이름과 값은 앱 코드의 로깅 정의에서 가져온다. 기대 값을 지어내지 않는다.

## 서버 응답 바꾸기

- 500·400 에러, 느린 응답, 빈 응답처럼 실제 서버로 만들기 어려운 상황은 가짜 응답 서버(MCP `harness-network`)로 만든다. `.harness/project.json`에 `e2e.network.port`가 있을 때만 도구가 보인다.
- 가짜 응답은 MCP 도구 `mock_set`으로 건다. **프로젝트 코드나 `.maestro/`에 목 데이터 파일을 만들지 않는다.**
  - `match`는 `[메서드] 호스트/경로` 앞부분이다. 주소를 추측하지 말고, 앱을 한 번 돌린 뒤 `requests`로 앱이 보낸 주소를 보고 고른다.
  - 끝나면 `mock_clear`로 지운다. 걸어 둔 응답은 `.harness/state/network.json`에 남는다.
- 시나리오는 앱 실행에 서버 주소를 넘긴다: `launchApp`의 `arguments: { "-HarnessNetworkBaseURL": "${NETWORK_BASE_URL}" }`. 값은 `e2e`가 넣는다.
- 앱은 이 인자가 있고 값이 `http://127.0.0.1:`로 시작할 때만 `https://<호스트>/<경로>` 요청을 `<인자 주소>/<호스트>/<경로>`로 보내야 한다. 이 코드가 없으면 사용자에게 어디에 넣을지 알린다.
- 화면에서 결과를 확인한다: 에러 문구, 다시 시도 버튼, 로딩 표시를 `assertVisible`로 본다.
- 시나리오 옆에 `<이름>.network.json`으로 받아야 할 응답을 적는다. `match`는 `mock_set`에 쓴 그대로다.
  ```json
  { "expect": [ { "match": "POST api.example.com/v1/items", "status": 500 } ] }
  ```
  응답을 걸지 않았거나 서버가 꺼져 있어도 앱의 실패 화면은 똑같이 뜬다. `e2e`는 서버 기록에 이 응답이 그 흐름 동안 한 번 이상 있어야 통과시킨다.
- 응답 조건은 MCP 세션 동안만 있다. 회귀 묶음(`tags: [regression]`)에는 넣지 않는다.

## 수정 전후 영상

- QA 티켓을 고칠 때는 고치기 전과 후에 `scripts/harness/e2e --record <파일>`로 돌려 `.harness/out/e2e.mp4`를 남긴다. PR에 두 영상을 붙인다.
