# 0016. 리뷰를 했는지 리뷰어의 말이 아니라 훅 기록으로 확인한다

- 상태: 채택 (2026-11-05)
- 관련: ADR 0012(run 확인), ADR 0013(서브에이전트 입력), `plugin/agents/ios-reviewer.md`, `docs/plugin.md`

## 배경

- `checks.json`의 `review` 검사에는 `run`이 없었다. 리뷰어를 부르지 않아도 검증 단계를 넘어갔다.
- 리뷰어 보고서의 "열어 본 파일·규칙" 줄은 리뷰어가 스스로 적는다. 발표가 말한 "다 지켰다는 AI의 말"과 같은 종류라 증거가 못 된다(발표 전사 85줄, 슬라이드 68).
- ai-bouncer의 `review` 항목도 `run`이 없다(`engine/default.yaml`). 일을 한 에이전트가 자기 diff를 다시 읽으라는 지시뿐이다.
- 리뷰어를 서브에이전트로 둔 이유(자기 결과를 후하게 보는 편향, 메인 컨텍스트)는 Anthropic의 harness design 글과 HumanLayer 글이다(`docs/references.md`). ai-bouncer와 다른 점인데 ADR이 없었다.
- 리뷰를 건너뛴 일은 시험장에서 아직 관찰되지 않았다. 사용자가 강제하기로 정했다(2026-11-05).
- Claude Code 2.1.318 실행 파일의 훅 입력 스키마에서 확인한 것:
  - 서브에이전트 안에서 불린 훅 입력에는 `agent_id`와 `agent_type`이 있다. 메인 세션에는 `agent_id`가 없다.
  - SubagentStop 입력에는 `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`가 있다.

## 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 리뷰어 | 서브에이전트 `ios-reviewer`를 유지한다 | 메인과 대화를 나눠 자기 변경을 후하게 보는 것을 줄이고, 리뷰하며 연 파일이 메인 컨텍스트에 쌓이지 않는다. ai-bouncer(메인이 직접 리뷰)와 다르다 |
| 기록 | 플러그인 훅 `review-record.sh`가 PostToolUse(Read)에서 리뷰어가 연 파일을 적고, SubagentStop에서 `.harness/out/review.json`을 쓴다 | 리뷰어가 아니라 훅이 적어서 꾸밀 수 없다. 입력은 stdin JSON만 읽는다(원칙: Codex 재사용) |
| 통과 조건 | 바뀐 파일(지운 파일·바이너리 제외)을 모두 Read로 열었고, 보고서의 `요약 · 차단 N`이 0이거나 `발견 없음` | 열지 않은 파일은 리뷰하지 않은 것이다. 차단은 고치라는 지시가 있었는데 확인하지 않았다 |
| 확인 | `review`에 `"run": "scripts/harness/passed review"` | 다른 검사와 같은 결과 파일·최신 판정을 쓴다(ADR 0012, ai-bouncer `bouncer passed`). 리뷰 뒤에 파일을 고치면 다시 맡겨야 한다 |
| 리뷰어 구분 | `agent_type`이 `ios-reviewer` 또는 `…:ios-reviewer` | 플러그인 에이전트 이름에는 플러그인 이름이 붙는다(시험장에서 `ios-harness:ios-reviewer`로 확인) |
| 보고서 | SubagentStop의 `last_assistant_message`에서 읽고, 요약 줄이 없으면 리뷰어가 `SubagentHandback` 도구로 넘긴 `message`(PostToolUse에서 적어 둔 것)를 쓴다 | 백그라운드로 돈 리뷰어는 보고서를 이 도구로 넘겨, 마지막 메시지에 보고서가 없었다 |

## 결과

- 증명되는 것은 "리뷰어를 불렀고, 바뀐 파일을 열었고, 차단이 0이라고 보고했다"까지다. 리뷰를 잘했는지는 증명되지 않는다. 일부러 넣은 위반을 몇 개 잡는지는 평가(로드맵 후보 17)에서 잰다.
- 차단 수는 리뷰어 보고서에서 읽는다. 보고서 형식이 틀리면 통과하지 않는다.
- grep이나 `git diff`로만 본 파일은 연 것으로 치지 않는다. 리뷰어 지시에 Read로 열라고 적었다.
- 차단을 고치면 리뷰를 다시 맡겨야 한다. 리뷰 시간이 늘 수 있다.
- 시험장(IntervalTimer, 2026-11-05): 메인 세션에 Swift 파일 한 줄을 바꾸고 리뷰를 맡겼다.
  - 첫 실행: 훅이 리뷰어를 알아보고 연 파일 3개를 적었다. 그런데 리뷰어가 백그라운드로 돌아 보고서를 `SubagentHandback`으로 넘겨서, 요약 줄을 못 찾고 실패로 남겼다.
  - 그 보고서도 적게 고친 뒤 두 번째 실행: `passed: true`, 차단 0, 안 연 파일 없음. `scripts/harness/passed review`가 0으로 끝났다.
  - 리뷰 뒤에 그 파일을 한 줄 더 고치자 `passed review`가 "결과가 오래됐다"로 2를 냈다.
