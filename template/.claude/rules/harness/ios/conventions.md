---
paths:
  - ".harness/conventions.json"
---

# 팀 컨벤션 목록

`.harness/conventions.json`은 `scripts/harness/lint`가 검사하는 팀 규칙 목록이다. 검사는 도구가 하고, AI는 규칙 초안만 만든다.

## 규칙 종류

규칙마다 `kind`로 검사할 도구를 정한다. 이 프로젝트에서 쓸 수 있는 종류만 제안한다.

| kind | 잡는 것 | 도구 | 쓸 수 있는 프로젝트 |
|---|---|---|---|
| `pattern` (기본) | 쓰면 안 되는 코드(API, import, 호출) | SwiftLint | 모두 |
| `format` | 이름·줄 길이·들여쓰기 같은 모양 | swift-format (Xcode 포함) | 모두 |
| `dependency` | 모듈 사이의 금지된 의존, 의존 목록에 없는 import(`undeclared: true`) | tuist graph·inspect | `.harness/project.json`의 `ios.generator`가 `tuist`일 때만 |

- 모듈이 하나뿐인 앱(xcodeproj 단일 타깃 등)의 레이어 규칙은 `dependency`로 쓸 수 없다. `pattern`의 `included`로 폴더를 좁히고 금지할 타입·import를 정규식으로 적는다.
- `format`의 `formatRule`은 `xcrun swift-format dump-configuration`의 `rules` 이름이나 `Indentation`·`LineLength`·`Spacing`·`TrailingComma`·`TrailingWhitespace`·`RemoveLine`·`AddLines`·`EndOfLineComment` 중 하나다. 줄 길이·들여쓰기 폭은 `formatOptions`로 정한다(예: `{"lineLength": 120}`).
- `dependency`는 `Project.swift` 등 manifest나 Swift 파일의 import 줄이 바뀐 작업, `--all`에서 검사된다. 모듈 이름 패턴의 와일드카드는 `*`뿐이다. 모듈 이름을 하나씩 적지 말고 이름 규칙에 맞춘 패턴(`Feature*`)으로 적는다.
- `lint`가 "의존 규칙에 없는 모듈"을 알리면, 그 모듈을 어느 규칙에 넣을지 사용자에게 묻는다. 스스로 규칙을 고치지 않는다.

## 규칙 추가

1. 코드에서 팀이 이미 지키는 방식을 찾아 규칙 후보를 만든다. 모듈 구성은 manifest(`Project.swift`)의 의존 목록에서, 형식은 기존 코드에서 찾는다. 후보마다 근거 파일 2~3개와 지금 어기는 곳의 개수(`scripts/harness/lint --all`로 확인)를 함께 보여 준다.
2. 사용자가 고른 규칙만 파일에 넣는다. 고르지 않은 후보는 넣지 않는다.
3. 넣은 뒤 `scripts/harness/lint --all`을 돌려 의도한 곳만 잡히는지 확인한다. 주석·문자열까지 잡히면 `matchKinds`로 좁힌다. `format` 규칙은 기존 코드가 이미 거의 지키는 것만 넣는다. 안 그러면 손대는 파일마다 감점된다.

## 지킬 것

- lint를 통과시키려고 규칙을 지우거나 `passScore`·`penalty`를 낮추거나 `excluded`를 늘리지 않는다. 바꿔야 하면 이유를 들어 사용자에게 먼저 묻는다.
- 규칙 하나는 금지 패턴·형식 규칙·의존 금지 하나만 잡는다. `description`은 위반 메시지로 그대로 나오므로 "무엇을 대신 쓰는지"를 적는다.
- 형식과 필드는 하네스 저장소의 `docs/conventions.md`에 있다.
