# 팀 컨벤션 목록 (`.harness/conventions.json`)

`scripts/harness/lint`가 검사하는 팀 규칙 목록이다. 프로젝트마다 다르다. 각 프로젝트의 `.harness/conventions.json`에 두고 git에 커밋한다.
`project.json`이 프로젝트의 사실을 담는다면, 이 파일은 팀이 정한 정책을 담는다. 그래서 두 파일을 나눈다([ADR 0005](decisions/0005-talk-criteria.md)).

## 만드는 방법

발표의 andcon과 같이 세 단계로 나눈다([ADR 0006](decisions/0006-convention-lint.md)).

| 단계 | 누가 | 언제 |
|---|---|---|
| 1. 규칙 뽑기: 코드에서 팀이 쓰는 방식을 규칙 후보로 만든다 | 에이전트가 초안, 사람이 고름 | 가끔 |
| 2. 도구가 읽게 옮기기: 목록을 규칙 종류별 도구 설정(SwiftLint·swift-format)으로 바꾼다 | `lint`가 정해진 틀대로 | 실행할 때마다 |
| 3. 검사: 바뀐 파일과 모듈 구성을 점수로 판정한다 | 도구와 `lint` | 코드를 바꿀 때마다 |

규칙을 넣는 절차는 프로젝트에 설치되는 `.claude/rules/harness/ios/conventions.md`에 있다. 이 파일을 열면 자동으로 함께 읽힌다.

## 예시 (ReadSharp)

```json
{
  "schemaVersion": 1,
  "passScore": 95,
  "rules": [
    {
      "id": "swiftui.no_sheet_is_presented",
      "description": ".sheet(isPresented:) 대신 .sheet(item:)을 쓴다 (빈 시트가 뜨는 버그)",
      "severity": "error",
      "regex": "\\.sheet\\(\\s*isPresented:",
      "matchKinds": ["identifier", "keyword", "argument"]
    },
    {
      "id": "mvi.no_service_shared_in_view",
      "description": "View에서 Service.shared를 직접 참조하지 않는다. Processor(@Environment)를 거친다",
      "severity": "error",
      "regex": "\\b[A-Za-z]*Service\\.shared\\b",
      "matchKinds": ["identifier"],
      "included": ["/View/", "View\\.swift$"]
    }
  ]
}
```

## 규칙 종류

발표의 andcon이 규칙 성격에 따라 detekt·ktlint·Konsist에 나눠 맡기듯, `kind`마다 맡는 도구가 다르다([ADR 0014](decisions/0014-layer-format-rules.md)).

| kind | 발표의 도구 | 잡는 것 | 도구 | 쓸 수 있는 프로젝트 |
|---|---|---|---|---|
| `pattern` (기본) | detekt | 쓰면 안 되는 코드 | SwiftLint `custom_rules` | 모두 |
| `format` | ktlint | 이름·줄 길이·들여쓰기 같은 모양 | swift-format (Xcode 16 이상에 포함) | 모두 |
| `dependency` | Konsist | 모듈 사이의 금지된 의존, 의존 목록에 없는 import | `tuist graph`·`tuist inspect implicit-imports` | Tuist 프로젝트 |

규칙은 프로젝트마다 다르다. 하네스는 종류별 변환과 판정만 갖고, 무엇을 금지할지는 각 프로젝트의 이 파일에 있다.
모듈이 하나뿐인 앱은 `dependency`를 쓸 수 없다. 레이어 규칙은 `pattern`의 `included`와 금지 정규식으로 적는다(예: `/Domain/` 아래에서 `import SwiftUI` 금지).

### 예시 (IntervalTimer, Tuist 다중 모듈)

```json
{
  "id": "modules.no_feature_to_feature",
  "kind": "dependency",
  "description": "Feature 모듈끼리 직접 의존하지 않는다. 공통 코드는 Services·Models로 옮긴다",
  "severity": "error",
  "from": "Feature*",
  "forbid": ["Feature*"]
}
```

이름 패턴으로 적으면 새 모듈도 이름 규칙(`Feature…`)만 따르면 저절로 들어간다.

의존 목록에 적지 않은 모듈을 import해도, 그 모듈이 다른 모듈 때문에 먼저 빌드되면 빌드가 통과한다(숨은 의존). 이것까지 막으려면 `undeclared` 규칙을 둔다.

```json
{
  "id": "modules.declare_imports",
  "kind": "dependency",
  "description": "import하는 내부 모듈은 Project.swift 의존 목록에 적는다",
  "severity": "error",
  "from": "*",
  "undeclared": true
}
```

### 예시 (형식)

```json
{
  "id": "naming.lower_camel_case",
  "kind": "format",
  "description": "함수·변수 이름은 lowerCamelCase로 쓴다",
  "severity": "warning",
  "formatRule": "AlwaysUseLowerCamelCase"
}
```

## 필드

| 필드 | 값 | 설명 |
|---|---|---|
| `schemaVersion` | `1` | 파일 형식 버전 |
| `passScore` | 0~100, 기본 95 | 이 점수 이상이면 통과 |
| `rules[].id` | 영문 소문자·숫자·`_`·`.` | 규칙 이름. `영역.내용` 형식을 권한다. 겹치면 안 된다 |
| `rules[].kind` | `pattern` · `format` · `dependency`, 기본 `pattern` | 검사할 도구 |
| `rules[].description` | 문장 | 위반 메시지로 그대로 나온다. 대신 무엇을 쓰는지 적는다 |
| `rules[].severity` | `error` · `warning` · `info` | 기본 감점 10 · 5 · 1 |
| `rules[].penalty` | 0 이상 숫자, 선택 | 기본 감점 대신 쓸 값 |
| `rules[].regex` | 정규식 (`pattern`) | 금지 패턴. SwiftLint `custom_rules`의 `regex` |
| `rules[].matchKinds` | 문자열 배열, 선택 | 이 구문 종류에 걸린 것만 위반으로 본다(SwiftLint `match_kinds`). `identifier`·`keyword`·`argument` 등을 주면 주석과 문자열 속 글자는 잡지 않는다 |
| `rules[].included` | 정규식 배열, 선택 | 파일 경로가 하나라도 맞으면 검사한다 |
| `rules[].excluded` | 정규식 배열, 선택 | 파일 경로가 맞으면 검사하지 않는다 (`pattern`) |
| `rules[].formatRule` | 문자열 (`format`) | swift-format 규칙 이름(`xcrun swift-format dump-configuration`의 `rules`) 또는 늘 나오는 형식 지적 `Indentation`·`LineLength`·`Spacing`·`TrailingComma`·`TrailingWhitespace`·`RemoveLine`·`AddLines`·`EndOfLineComment`. 규칙마다 하나, 겹치면 안 된다 |
| `rules[].formatOptions` | 객체, 선택 (`format`) | swift-format 설정 위에 덮을 값. 예: `{"lineLength": 120}`, `{"indentation": {"spaces": 4}}` |
| `rules[].from` | 모듈 이름 패턴 (`dependency`) | 이 모듈들의 직접 의존을 본다. 와일드카드는 `*`뿐 |
| `rules[].forbid` | 모듈 이름 패턴 배열 (`dependency`) | 의존하면 안 되는 모듈. 외부 패키지 이름도 된다(예: `Firebase*`). 의존 목록에 적은 것과 import만 한 것을 모두 본다 |
| `rules[].undeclared` | `true`, 선택 (`dependency`) | `forbid` 대신 쓴다. `from` 모듈이 의존 목록에 없는 모듈을 import하면 위반이다. 같은 의존이 `forbid` 규칙에 걸리면 그쪽으로만 센다 |

- 잘못된 파일이면 `lint`가 첫 문제를 알려 주고 2로 끝난다.
- `pattern`·`format` 위반의 위치는 그 파일·줄이다. `dependency` 위반의 위치는 `from` 모듈을 선언한 `Project.swift` 줄이다.
- `dependency`는 직접 의존만 본다. A → B → C에서 A가 C를 금지해도 위반이 아니다.
- 어느 `dependency` 규칙의 `from`·`forbid` 패턴에도 맞지 않는 내부 모듈은 감점 없이 "의존 규칙에 없는 모듈"로 알린다. 테스트 타깃(`…Tests`)과 패턴 `*`는 셈에 넣지 않는다. 새 모듈을 규칙에 넣을지는 사람이 정한다.
