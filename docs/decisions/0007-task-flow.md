# 0007. 작업 흐름은 사람이 고른 모드·검사와 단계 지시 훅으로 만든다

- 상태: 채택
- 날짜: 2026-11-03

## 배경

- 발표 V2(ADR 0005, 슬라이드 20~39)는 사람이 처음에 두 가지만 정한다: 계획할지(plan/simple)와 무엇을 검증할지.
  - 검사 목록은 저장소마다 config에 둔다. 검사마다 `prompt`(시킬 일)와 `run`(했는지 확인)이 있다.
  - AI가 상태 파일의 단계를 고치면 PostToolUse 훅이 config에서 그 단계의 지시를 꺼내 `additionalContext`로 넣는다. 훅은 검사 내용을 모른다.
  - 넘어가려는 순간 훅이 `run`을 돌려 통과해야 넘어간다.
- 이 저장소는 강제 장치를 실패가 관찰된 뒤에 넣는다(원칙 2). 로드맵은 지시 주입을 후보 12, `run` 확인과 Stop 차단을 조건부 후보 13으로 나눴다.
- 상태 파일 대신 스크립트 출력으로 지시를 주는 방법(훅 없음)도 검토했다. 사용자가 발표 방식 그대로를 골랐다(2026-11-03).

## 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 모드 | plan(plan → implement → verify → finish), simple(implement → verify → finish) | 발표와 같다. 페이지·스텝 분할은 넣지 않는다 |
| 고르는 사람 | 사용자. `task` 스킬이 AskUserQuestion으로 묻는다 | AI가 작업 크기를 미리 알기 어렵다(결함 78% / 25%) |
| 상태 | `.harness/state/task.json`, 에이전트가 `stage`를 고친다 | 발표의 state.json. 기존 `.harness/.gitignore`가 무시한다 |
| 지시 주입 | 플러그인 PostToolUse 훅 `stage-context.sh`. 상태 파일이 바뀔 때만 동작하고 막지 않는다 | 발표 슬라이드 27. stdin JSON만 읽어 Codex에서도 쓸 수 있다 |
| 검사 목록 | `.harness/checks.json`(`stages.<단계>.prompt`, `checks[]`의 `name`·`description`·`prompt`·`run`) | 발표의 config. 형식은 bash·jq로 읽는 JSON(ADR 0006과 같은 이유) |
| `run` | 필드는 지금 정의하되 실행하지 않는다 | 단계를 넘길 때 막는 것은 강제 장치다. 검증을 건너뛰는 일이 관찰되면 후보 13에서 켠다 |
| 마무리 | 코드에 남지 않는 정책·결정을 보고에 정리하게 한다 | 원칙 12. 기록 저장소는 후보 19 |

## 결과

- 지금은 에이전트가 검증 단계를 건너뛰거나 `stage`를 바로 `done`으로 바꿔도 막지 않는다. 이런 일이 시험장에서 관찰되면 harness-log에 기록하고 후보 13을 켠다.
- ai-bouncer를 쓰지 않기로 한 이유(ADR 0005)는 흐름을 맡는 장치가 둘이면 서로 다른 상태를 본다는 것이었다. 이 흐름을 쓰는 프로젝트에서는 다른 워크플로 엔진을 끈다(ReadSharp는 `Skill(dev-bounce)` deny).
