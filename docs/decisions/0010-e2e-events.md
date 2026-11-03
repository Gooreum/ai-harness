# 0010. E2E 행동 로그 판정

- 상태: 채택 (2026-11-03)
- 관련: ADR 0009(E2E Maestro), 로드맵 후보 10

## 배경

발표 2부 "동작 검증 — Maestro E2E"(슬라이드 85 "활용 1 · 피처 개발")는 화면에 안 보이는 행동 로그를 시나리오와 함께 확인한다.
"어떤 로그가 몇 번, 어떤 값으로 나가야 하는지만 적어 두면, 시나리오가 끝난 뒤 자동으로 판정하고 수집 서버에 쌓였는지까지 확인"한다.
QA에서 가장 손이 많이 가던 확인을 개발 단계로 당기는 것이다.

시험장 ReadSharp는 Firebase Analytics로 이벤트를 보낸다(`AnalyticsService.log`). 확인한 사실은 다음과 같다.

- 앱을 `-FIRAnalyticsDebugEnabled`로 실행하면 이벤트마다 `[I-ACS023072] Event logged. Event name, event params: <이름>, {…}`가 debug 수준 로그로 남는다. 업로드가 성공하면 `[I-ACS023044] Successful upload … 204`가 남는다.
- Maestro `launchApp`의 `arguments: { "-FIRAnalyticsDebugEnabled": true }`로 이 인자가 전달된다.
- Maestro가 흐름마다 남기는 기기 로그(`logs/device-simulator.log`)에는 debug 수준이 빠져 있어 이벤트가 보이지 않는다.
- 흐름별 명령 기록(`commands.json`)에 명령마다 시각(ms)이 있다.

## 결정

- 기대 이벤트는 시나리오 옆 `<이름>.events.json`에 둔다. Maestro YAML에 넣지 않는 것은 Maestro가 모르는 키를 받아 주는지 보장되지 않아서다.
  - 이벤트마다 `name`, `count`(정확한 횟수, 기본 1, 0은 "나가면 안 됨"), `params`(적은 값만 문자열로 비교).
  - `uploaded`(기본 true): 마지막으로 맞은 이벤트 뒤에 업로드 성공이 있어야 한다. 발표의 "수집 서버에 쌓였는지"를 앱 쪽에서 볼 수 있는 가장 가까운 사실이 서버의 204 응답이다.
- `e2e`가 실행 동안 `log stream --level debug --style ndjson`으로 Firebase Analytics 로그를 따로 받는다. 흐름 구간은 그 흐름의 첫 명령 시각부터 다음 흐름의 첫 명령 시각까지로 나눈다. Maestro는 흐름을 차례로 돌린다.
- 로그를 받을 곳은 사실이므로 `.harness/project.json`의 `e2e.events`에 둔다. 지금은 `firebase`만 받는다. 다른 수집기는 그 프로젝트가 생기면 파서를 더한다.
- 판정 결과는 `e2e.json`의 흐름별 `events`에 남기고, 판정이 실패한 흐름은 실패로 센다.

## 결과

- 이벤트 정의를 바꾸는 작업에서 "로그가 나가는지"를 사람이 DebugView로 보지 않고 프로그램으로 판정한다.
- 시험 실행의 이벤트도 실제 Firebase 프로젝트로 올라간다(디버그 표시가 붙어 DebugView에 보인다). 판정을 켜지 않아도 E2E 실행은 원래 이벤트를 보낸다.
- Firebase 로그 형식(`I-ACS023072`)에 기댄다. SDK가 형식을 바꾸면 파서를 고쳐야 한다. 테스트(`tests/e2e.test.sh`)가 지금 형식을 고정한다.
- 서버 응답 조작(발표의 프록시 MCP)은 아직 하지 않는다. 시뮬레이터 트래픽을 가로채려면 Mac 전체 프록시 설정과 인증서 설치가 필요해서, 필요한 작업이 생길 때 따로 정한다.
