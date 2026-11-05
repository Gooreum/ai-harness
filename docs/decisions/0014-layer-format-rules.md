# 0014. 모듈 의존은 tuist graph로, 형식은 swift-format으로 검사한다

- 상태: 채택 (2026-11-05). 구조 검사의 전제는 ADR 0015에서 고쳤다
- 관련: ADR 0006(컨벤션 목록과 SwiftLint), 로드맵 후보 20, `docs/conventions.md`

## 배경

- 발표의 andcon은 규칙 목록 하나를 성격에 따라 세 도구에 나눠 맡긴다(슬라이드 63~66).
  - Konsist: 구조. 예: "presentation 레이어는 data 구현체를 import하지 않는다"
  - detekt: 쓰면 안 되는 것. 예: `android.util.Log` 금지
  - ktlint: 형식. 예: "파일명은 최상위 클래스명과 같게"
- 후보 11에서 detekt에 해당하는 금지 패턴만 SwiftLint로 만들었다(ADR 0006). Konsist와 ktlint에 해당하는 검사가 비어 있었다.
- 시험장 두 곳은 구조가 다르다.
  - ReadSharp: xcodeproj 단일 모듈. 레이어가 폴더로만 나뉜다.
  - IntervalTimer: Tuist 다중 모듈(App → Feature* → Services·Models·DesignSystem). 의존 방향은 `checks.json`의 plan 지시에 문장으로만 있었다.
- ai-bouncer에는 컨벤션 검사가 없다. `engine/setup.sh`가 프로젝트에 이미 있는 lint 명령을 찾아 등록할 뿐이다.

## 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 규칙 종류 | `conventions.json`의 규칙에 `kind`(`pattern`·`format`·`dependency`)를 둔다. 기본은 `pattern` | 발표처럼 목록은 하나로 두고 도구만 나눈다. 기존 파일은 그대로 읽힌다 |
| 구조 검사 (Konsist 대응) | `dependency`: `tuist graph -f dot`의 직접 의존에 `from`·`forbid` 모듈 이름 패턴을 대어 본다 | iOS 모듈은 컴파일 단위라, 선언하지 않은 모듈의 import는 컴파일러가 막는다. 남는 위험은 금지된 의존을 manifest에 선언하는 것이라 모듈 그래프를 본다. 발표와 다르다. **틀린 전제였다: 다른 모듈 때문에 먼저 빌드된 모듈은 선언 없이 import해도 빌드된다. import도 보게 고쳤다(ADR 0015)** |
| 구조 검사를 돌리는 때 | manifest(`Project.swift`·`Workspace.swift`·`Package.swift`·`Tuist/`)가 바뀌었거나 `--all`일 때만 | 그래프는 manifest가 바뀔 때만 바뀐다. 뽑는 데 시간이 든다(IntervalTimer 6~22초) |
| 단일 모듈 앱 | `dependency`를 쓰면 2로 끝나고 `pattern`의 `included`와 금지 정규식을 쓰라고 알린다 | 모듈이 하나면 모듈 그래프로 레이어를 나눌 수 없다. 폴더 경로 규칙은 이미 `pattern`으로 쓸 수 있다 |
| 형식 검사 (ktlint 대응) | `format`: Xcode 16 이상에 들어 있는 swift-format으로 고른 규칙만 켠다 | 설계 원칙대로 따로 설치하지 않는다(SwiftFormat은 brew 설치가 필요하다). 발표와 도구가 다르다 |
| 고르지 않은 형식 지적 | swift-format은 들여쓰기·줄 길이 같은 지적을 설정으로 끌 수 없어, 결과에서 고른 규칙 이름만 남긴다 | 컨벤션 규칙만 판정에 넣는다(ADR 0006의 `only_rules`와 같다). IntervalTimer 전체에서 고르지 않은 들여쓰기 지적이 7,556개 나왔다 |
| 위반 위치 | `dependency`는 `from` 모듈을 선언한 `Project.swift` 줄 | 고칠 곳이 그 모듈의 의존 목록이다 |
| 규칙의 자리 | 하네스는 종류별 변환·판정만 갖고, 무엇을 금지할지는 프로젝트의 `conventions.json`에 둔다 | 프로젝트마다 모듈 구성과 형식이 다르다(발표 슬라이드 38 "같은 훅, 저장소마다 다른 config") |

## 결과

- IntervalTimer에 모듈 의존 규칙 4개와 형식 규칙 3개를 넣었다. 전체 59개 파일이 100점으로 통과했다.
  - `FeatureTimer`에 `FeatureHistory` 의존을 넣으면 `Project.swift:216`(FeatureTimer 선언 줄)에서 −10으로 잡혔다.
  - `try!`를 넣으면 그 줄에서 −5로 잡혔다.
- ReadSharp에 형식 규칙 3개를 넣었다. 기존 코드에는 이 규칙의 위반이 없다. 넣은 `String!`과 소문자 타입 이름은 각각 −5, −1로 잡혔다.
- 형식 규칙은 기존 코드가 이미 지키는 것만 넣는다(`rules/harness/conventions.md`). 두 시험장 모두 줄 길이·들여쓰기는 넣지 않았다. 지금 코드와 달라 손대는 파일마다 감점되기 때문이다.
- 발표의 "파일명은 최상위 클래스명과 같게"는 swift-format에 없는 규칙이라 다루지 않는다. 필요해지면 `lint`에 직접 넣는다.
- `dependency`는 직접 의존만 본다. 이어지는 의존(A → B → C)은 보지 않는다.
- Tuist가 아닌 다중 모듈(SPM 로컬 패키지, xcodeproj 여러 타깃)의 모듈 그래프는 아직 읽지 못한다. 그런 프로젝트가 생기면 그래프를 뽑는 방법만 더한다.
