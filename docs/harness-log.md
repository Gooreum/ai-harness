# 하네스 실패 기록

에이전트가 하네스를 쓰면서 실수하거나 막힌 일을 기록한다. 이 기록은 다음에 무엇을 만들지 정하는 근거다.
기록할 때마다 [principles.md](principles.md)의 "실수 → 고칠 층" 기준표로 분류한다.

## 기록 방법

새 항목은 맨 위에 추가한다. 형식은 다음과 같다.

```markdown
### YYYY-MM-DD — 한 줄 요약
- 프로젝트·작업:
- 무슨 일이 있었나: 에이전트가 한 행동과 그 결과. 가능하면 명령과 메시지를 그대로 적는다.
- 원인: 부족했던 계층 (Context / Execution / Validation / Enforcement / State)
- 조치: 어느 층에 무엇을 추가하거나 고칠지. 고치지 않기로 했으면 "보류"와 이유를 적는다.
- 상태: 미해결 | 반영됨 (커밋 또는 단위 번호) | 보류
```

## 기록

### 2026-10-02 — Tests 폴더가 있다고 테스트 타깃이 있는 것은 아니다
- 프로젝트·작업: MotoTrace 시험장, 단위 4 `verify --all` 확인
- 무슨 일이 있었나
  - AppDI·Shared 모듈 테스트가 `Unable to start testing`으로 실패했다.
  - 두 모듈에는 `Tests/Sources` 폴더가 있지만, manifest(`makeSingleModule`)가 테스트 타깃을 만들지 않아서 스킴의 테스트 액션이 비어 있었다.
- 원인: Execution — "Tests 폴더가 있으면 테스트가 있다"는 판단 규칙이 틀렸다.
- 조치
  - 생성된 스킴 파일의 테스트 액션에 테스트 대상이 있는지로 판단하도록 바꿨다.
  - 스킴 파일이 없을 때만 Tests 폴더로 판단한다(verify, detect).
- 상태: 반영됨 (단위 4)

### 2026-10-02 — DerivedData를 ~/Desktop 아래에 두면 테스트 번들을 읽지 못한다
- 프로젝트·작업: MotoTrace 시험장(`~/Desktop/MotoTrace/...`), 단위 4 test 스크립트 개발
- 무슨 일이 있었나
  - 프로젝트 안의 `.harness/DerivedData`를 쓰면 `xcodebuild test`가 `Failed to create a bundle instance representing '…/CoreTrackingTests.xctest'. Check that the bundle exists on disk.`로 실패했다. 번들은 실제로 있었다.
  - 같은 스킴(CoreTracking, 테스트 20개)을 Desktop 밖 DerivedData로 돌리면 20개 모두 통과했다.
- 원인: Execution — 시뮬레이터 쪽 테스트 프로세스가 macOS 보호 폴더(~/Desktop) 아래의 번들을 읽지 못하는 것으로 추정한다. 빌드는 터미널 권한으로 되기 때문에 테스트 단계에서만 드러난다.
- 조치
  - DerivedData 기본 위치를 `~/Library/Developer/Xcode/DerivedData/<워크트리 이름>-harness-<경로 해시>`로 바꿨다.
  - 워크트리마다 분리하는 것은 유지한다. `HARNESS_DERIVED_DATA`로 위치를 바꿀 수 있다.
- 상태: 반영됨 (단위 4)
