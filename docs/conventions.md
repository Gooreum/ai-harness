# 팀 컨벤션 목록 (`.harness/conventions.json`)

`scripts/harness/lint`가 검사하는 팀 규칙 목록이다. 각 프로젝트의 `.harness/conventions.json`에 두고 git에 커밋한다.
`project.json`이 프로젝트의 사실을 담는다면, 이 파일은 팀이 정한 정책을 담는다. 그래서 두 파일을 나눈다([ADR 0005](decisions/0005-talk-criteria.md)).

## 만드는 방법

발표의 andcon과 같이 세 단계로 나눈다([ADR 0006](decisions/0006-convention-lint.md)).

| 단계 | 누가 | 언제 |
|---|---|---|
| 1. 규칙 뽑기: 코드에서 팀이 쓰는 방식을 규칙 후보로 만든다 | 에이전트가 초안, 사람이 고름 | 가끔 |
| 2. 도구가 읽게 옮기기: 목록을 SwiftLint 설정으로 바꾼다 | `lint`가 정해진 틀대로 | 실행할 때마다 |
| 3. 검사: 바뀐 파일을 점수로 판정한다 | SwiftLint와 `lint` | 코드를 바꿀 때마다 |

규칙을 넣는 절차는 프로젝트에 설치되는 `.claude/rules/harness/conventions.md`에 있다. 이 파일을 열면 자동으로 함께 읽힌다.

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

## 필드

| 필드 | 값 | 설명 |
|---|---|---|
| `schemaVersion` | `1` | 파일 형식 버전 |
| `passScore` | 0~100, 기본 95 | 이 점수 이상이면 통과 |
| `rules[].id` | 영문 소문자·숫자·`_`·`.` | 규칙 이름. `영역.내용` 형식을 권한다. 겹치면 안 된다 |
| `rules[].description` | 문장 | 위반 메시지로 그대로 나온다. 대신 무엇을 쓰는지 적는다 |
| `rules[].severity` | `error` · `warning` · `info` | 기본 감점 10 · 5 · 1 |
| `rules[].penalty` | 0 이상 숫자, 선택 | 기본 감점 대신 쓸 값 |
| `rules[].regex` | 정규식 | 금지 패턴. SwiftLint `custom_rules`의 `regex` |
| `rules[].matchKinds` | 문자열 배열, 선택 | 이 구문 종류에 걸린 것만 위반으로 본다(SwiftLint `match_kinds`). `identifier`·`keyword`·`argument` 등을 주면 주석과 문자열 속 글자는 잡지 않는다 |
| `rules[].included` | 정규식 배열, 선택 | 파일 경로가 하나라도 맞으면 검사한다 |
| `rules[].excluded` | 정규식 배열, 선택 | 파일 경로가 맞으면 검사하지 않는다 |

- 잘못된 파일이면 `lint`가 첫 문제를 알려 주고 2로 끝난다.
- 아직 정규식 하나로 잡는 금지 패턴만 다룬다. 레이어 의존(Konsist 대응)과 형식(ktlint·SwiftFormat 대응)은 로드맵 후보 11의 남은 항목이다.
