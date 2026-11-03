# 0013. 백그라운드 서브에이전트를 기다리는 동안 Stop 게이트가 막지 않는다

- 상태: 채택 (2026-11-04)
- 관련: ADR 0012(검증 강제), `docs/harness-log.md` 2026-11-04 IntervalTimer #8, `docs/problem-notes.md` 2번

## 배경

- IntervalTimer #8의 verify 단계에서 일이 이렇게 흘렀다.
  - 에이전트가 리뷰어 서브에이전트를 백그라운드로 띄우고, 기다리려고 턴을 끝냈다.
  - Stop 게이트가 1분 사이 4번 막았다. 서브에이전트가 돌아온 뒤에야 끝났다.
  - ReadSharp #218에서도 같은 모양이 한 번 있었다.
- 원인(시각으로 추정): 서브에이전트의 도구 호출이 메인과 같은 session_id로 `tool-count.sh`에 세어졌다.
  - 그래서 "도구 없이 재진입하면 끝내게 둔다"(ADR 0012, ai-bouncer `guarded_block`)가 걸리지 않았다.
- ai-bouncer도 구조가 같다(코드를 읽어 확인했고, 돌려 보지는 않았다).
  - `hooks/pre-tool.sh`는 세션의 모든 도구 호출을 `.tool_seq`로 센다.
  - `hooks/stop.sh`는 `background_tasks`를 보지 않는다.
  - 커밋 6c6c90d의 주석에는 "백그라운드 작업이 끝나면 그 알림으로 턴이 다시 열리고, 그때 다시 판정한다"고 적혀 있다.
  - 그런데 테스트(`21-no-ask-and-bg-wait.sh`)는 기다리는 동안 도구 호출이 없는 경우만 확인한다.
- 발표는 이 경우를 다루지 않는다(슬라이드 14: 완료가 아니면 못 멈추게 한다).

## 결정

- Stop 입력의 `background_tasks`에 `type`이 `"subagent"`인 항목이 있으면 `stop-gate.sh`는 막지 않고 0으로 끝난다.
  - 차단 기록(`stop-gate.json`)도 건드리지 않는다.
  - stage가 비었거나 `done`인 경우, 주인이 아닌 세션인 경우는 이 검사보다 먼저 처리한다.
- `tool-count.sh`는 그대로 둔다. 서브에이전트의 도구도 계속 센다.
- 셸(`shell`)·모니터(`monitor`) 같은 다른 백그라운드 작업은 넣지 않는다.
  - 개발 서버처럼 끝나지 않는 작업이 있으면, 에이전트가 끝나지 않은 작업을 두고 멈추는 길이 된다.
  - 관찰된 것은 서브에이전트뿐이다.

### 입력 필드 근거

- 설치된 Claude Code 2.1.317 실행 파일의 Stop 입력 스키마에서 확인했다.
  - `background_tasks`: "In-flight background work (running/pending + backgrounded)… Lets hooks distinguish 'session is done' from 'session is paused waiting for background work to wake it'. Empty array when nothing is in flight."
  - 항목: `id`, `type`('shell'·'subagent'·'monitor'·'workflow'), `status`, `description`, `agent_type`(subagent만)
- 배열에는 진행 중인 작업만 들어오므로 `status`는 보지 않는다.
- 실제 Stop 입력에 들어오는지는 시험장에서 확인한다.

## 생각했지만 하지 않은 것

| 방법 | 하지 않은 이유 |
|---|---|
| 서브에이전트의 도구는 `tool-count.sh`에서 세지 않기(`agent_id`로 구분) | `agent_id`를 잘못 가리면 메인의 도구도 빠진다. 그러면 일이 남았는데 끝내게 둔다. 판단에 필요한 정보(기다리는 중인가)를 직접 보는 쪽이 낫다 |
| 모든 백그라운드 작업이 있을 때 막지 않기 | 위의 셸·모니터 이유 |

## 발표·ai-bouncer와 다른 점 (사용자에게 보고, 2026-11-04 승인)

- ai-bouncer `hooks/stop.sh`에는 이 예외가 없다. 이 저장소는 백그라운드 서브에이전트가 있으면 막지 않는다.
- 이유: ai-bouncer의 의도("알림으로 턴이 다시 열리면 다시 판정")는 같다. 그런데 서브에이전트가 도구를 쓰는 동안에는 그 의도대로 돌지 않는 것을 시험장 두 곳에서 관찰했다.

## 남겨 둔 것

- 서브에이전트를 중간에 취소하면 어떻게 되는지는 확인하지 않았다. 문제가 생기면 다룬다.
- 추정: 취소되면 배열에서 빠지므로 다음 Stop에서 다시 막는다. 일을 끝내지 않고 빠져나가는 길은 없다.
