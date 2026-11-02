# 0006. 팀 컨벤션은 JSON 목록으로 두고 SwiftLint와 점수로 판정한다

- 상태: 채택
- 날짜: 2026-11-03

## 배경

- 발표(ADR 0005)의 andcon은 컨벤션 검사를 세 단계로 나눈다.
  - 규칙 뽑기: AI가 코드에서 초안을 뽑고, 팀이 고른 것만 `conventions.yml`에 넣는다.
  - 도구가 읽게 옮기기: 규칙 목록을 detekt·ktlint·Konsist 설정으로 정해진 틀대로 옮긴다.
  - 검사: AI 없이 도구가 돌리고, 100점에서 감점해 기준 점수로 통과를 정한다. 결과는 `last-check.json`에 남는다.
- 발표 팀이 처음 시도한 방법은 컨벤션을 md 파일로 주고 AI에게 지켰는지 묻는 것이었다. AI는 "3/3 지킴"이라고 했지만 실제로는 한 곳에서 `Log`를 썼다(슬라이드 59).
- ReadSharp에는 문장으로만 있는 규칙이 있다(`.claude/rules/project/architecture.md`). 지금은 에이전트가 읽고 지키기를 기대할 뿐이다.

## 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 목록 형식 | `.harness/conventions.json` (발표는 YAML) | 스크립트는 bash와 jq만 쓴다(설계 원칙). macOS에는 YAML 파서가 기본으로 없다 |
| 검사 도구 | SwiftLint `custom_rules` | 금지 패턴(detekt 대응)을 정규식으로 잡는다. `match_kinds`로 주석·문자열 속 글자를 거른다. 실험에서 확인했다 |
| 설정 옮기기 | `lint`가 실행할 때마다 `.harness/out/swiftlint.yml`을 만든다 | 목록과 설정이 어긋날 수 없다. JSON은 YAML이기도 해서 SwiftLint가 그대로 읽는다 |
| 켜는 규칙 | 컨벤션 규칙만(`only_rules: [custom_rules]`) | 프로젝트의 기존 `.swiftlint.yml`과 기본 규칙 경고가 판정에 섞이지 않게 한다 |
| 판정 | 100점에서 감점(error 10, warning 5, info 1), `passScore` 기본 95 | 발표와 같다. error 하나는 실패, warning 하나는 통과, info는 여러 개까지 허용한다 |
| 검사 범위 | 기본은 바뀐 Swift 파일(verify와 같은 기준), `--all`은 전체 | 기존 코드의 위반 때문에 새 작업이 막히지 않게 한다 |
| 결과 | `.harness/out/lint.json`(`passed`, `score`, 위반) | 후보 13이 결과 파일만 보고 판정할 수 있게 한다 |
| 규칙 뽑기 | 스킬이나 스크립트를 만들지 않고 template 규칙(`rules/harness/conventions.md`)에 절차만 둔다 | 규칙 뽑기는 가끔 하는 일이다. 사람이 고르는 단계가 핵심이라 자동화할 부분이 적다 |
| verify와의 관계 | verify에 넣지 않고 따로 돌린다. AGENTS.md 명령 표에 함께 돌리라고 적는다 | 어떤 검사를 돌릴지는 작업마다 사람이 고른다(원칙 11, 후보 12) |

## 결과

- 발표의 Konsist(레이어 의존)와 ktlint(형식)에 해당하는 검사는 아직 없다. 후보 11에 남긴다.
- SwiftLint가 설치되어 있어야 한다. 없으면 `lint`가 설치 방법을 알려 주고 2로 끝난다.
- 정규식이라 같은 이름의 다른 타입도 잡을 수 있다. 오탐이 나오면 `included`·`matchKinds`로 좁히고, 그래도 안 되면 그 규칙은 문장 규칙으로 되돌린다.
