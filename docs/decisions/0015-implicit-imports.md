# 0015. 의존 목록에 없는 import도 모듈 의존 검사에 넣는다

- 상태: 채택 (2026-11-05)
- 관련: ADR 0014(모듈 의존 검사), 로드맵 후보 20, `docs/conventions.md`

## 배경

- ADR 0014는 "선언하지 않은 모듈의 import는 컴파일러가 막는다"고 보고 `Project.swift`의 의존 목록(tuist graph)만 검사했다. 이 전제가 틀렸다.
  - IntervalTimer에서 `tuist inspect implicit-imports`를 돌리자 앱 타깃이 의존 목록에 없는 `DesignSystem`·`Models`·`Services`를 import하고 있었다(`App/Sources/` 5개 파일). 빌드는 통과했다.
  - Feature 모듈이 그 모듈들에 의존해 먼저 빌드되므로, 앱이 목록에 적지 않아도 우연히 찾아진다.
- 그래서 Feature가 다른 Feature를 목록에 적지 않고 import만 하면, 빌드도 ADR 0014의 검사도 통과한다.
- 발표의 Konsist 예시도 의존 목록이 아니라 소스의 import 줄을 본다(슬라이드 64, "UI 레이어는 data 구현체 import 금지"). import를 보는 쪽이 발표에 더 가깝다.
- ai-bouncer에는 컨벤션 검사가 없다(ADR 0014).
- 사용자가 새 모듈을 추가했을 때 규칙이 어떻게 되는지 물었다. 규칙은 이름 패턴(`Feature*`)이라 이름 규칙을 따르는 새 Feature는 자동으로 들어가지만, 이름 규칙을 안 따르거나 새 종류의 모듈(`Network` 등)은 빠진다.

## 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 숨은 의존 찾기 | `tuist inspect implicit-imports`의 결과를 의존으로 더한다 | Tuist가 import와 의존 목록을 비교해 준다. 따로 import를 파싱하지 않는다 |
| `forbid` 규칙 | 목록에 적은 의존과 import만 한 의존을 모두 본다 | 금지된 의존은 어느 쪽으로 생겨도 같은 위반이다 |
| `undeclared: true` 규칙 | `from` 모듈이 목록에 없는 모듈을 import하면 위반. 같은 의존이 `forbid`에 걸리면 그쪽으로만 센다 | 금지 여부와 별개로 "목록에 적고 쓴다"를 팀이 고를 수 있게 한다. 발표의 "같은 위반을 두 번 잡지 않는다"(슬라이드 63) |
| 돌리는 때 | manifest가 바뀌었거나 `--all`, 또는 바뀐 Swift 파일의 `import` 줄이 늘거나 줄었을 때 | 숨은 의존은 import나 목록이 바뀔 때만 생긴다. 26초가 걸려 매번 돌리지 않는다 |
| 규칙에 없는 모듈 | 그래프를 뽑았을 때 어느 규칙의 `from`·`forbid` 패턴에도 맞지 않는 내부 모듈을 알린다. 감점하지 않는다 | 새 모듈을 규칙에 넣을지는 사람이 정한다(원칙 11). 감점하면 모듈을 추가하는 작업마다 실패한다 |
| 위반 위치 | `from` 모듈을 선언한 `Project.swift` 줄. 이름 상수(`name: projectName`)를 풀고 스킴·프로젝트 이름 줄은 건너뛴다 | IntervalTimer 앱 타깃 이름이 상수라 첫 구현은 스킴 줄(276)을 가리켰다 |

## 결과

- IntervalTimer에 `undeclared` 규칙(`modules.declare_imports`)을 넣었다. `lint --all`이 앱의 숨은 의존 3개를 `Project.swift:117`(앱 타깃 선언)에서 잡았다. 앱 의존 목록에 세 모듈을 적어 100점으로 통과했다.
- 앱 의존 목록을 바꾼 뒤 앱 빌드가 통과했다(452초, generate 포함).
- `FeatureTimer`의 파일에 `import FeatureHistory`만 넣고 목록은 그대로 두자 `modules.no_feature_to_feature`로 한 번만 잡혔다(`undeclared`로 또 세지 않았다). ADR 0014의 검사로는 통과하던 경우다.
- 시간: `tuist inspect implicit-imports` 16~26초, `tuist graph` 19초. manifest와 import가 함께 바뀐 작업의 `lint`는 60초였다. import 줄이 바뀌지 않는 작업에는 시간이 늘지 않는다.
- 위반 위치는 import한 파일이 아니라 manifest 줄이다. `tuist inspect`가 파일을 알려 주지 않아서다. 메시지에 "import만 있고 의존 목록에 없음"을 붙여 구분한다.
- 내부 모듈은 manifest에서 선언한 이름으로 가린다. 이름을 함수 인자로 넘겨 만드는 manifest는 일부가 빠질 수 있다.
