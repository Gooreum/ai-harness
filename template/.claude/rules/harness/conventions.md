---
paths:
  - ".harness/conventions.json"
---

# 팀 컨벤션 목록

`.harness/conventions.json`은 `scripts/harness/lint`가 검사하는 팀 규칙 목록이다. 검사는 SwiftLint가 하고, AI는 규칙 초안만 만든다.

## 규칙 추가

1. 코드에서 팀이 이미 지키는 방식을 찾아 규칙 후보를 만든다. 후보마다 근거 파일 2~3개와 지금 어기는 곳의 개수(`scripts/harness/lint --all`로 확인)를 함께 보여 준다.
2. 사용자가 고른 규칙만 파일에 넣는다. 고르지 않은 후보는 넣지 않는다.
3. 넣은 뒤 `scripts/harness/lint --all`을 돌려 의도한 곳만 잡히는지 확인한다. 주석·문자열까지 잡히면 `matchKinds`로 좁힌다.

## 지킬 것

- lint를 통과시키려고 규칙을 지우거나 `passScore`·`penalty`를 낮추거나 `excluded`를 늘리지 않는다. 바꿔야 하면 이유를 들어 사용자에게 먼저 묻는다.
- 규칙 하나는 금지 패턴 하나만 잡는다. `description`은 위반 메시지로 그대로 나오므로 "무엇을 대신 쓰는지"를 적는다.
- 형식과 필드는 하네스 저장소의 `docs/conventions.md`에 있다.
