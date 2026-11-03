# 플러그인

`plugin/`은 Claude Code 플러그인 `ios-harness`다. 여러 프로젝트에 공통으로 적용할 훅, 서브에이전트, 스킬을 담는다.
이 저장소 루트의 `.claude-plugin/marketplace.json` 덕분에 저장소 자체가 마켓플레이스(`ios-ai-harness`) 역할을 한다.

## 구성

```
.claude-plugin/marketplace.json     마켓플레이스 정의. 플러그인 위치는 ./plugin
plugin/
├── .claude-plugin/plugin.json      플러그인 정보(이름 ios-harness, 버전)
├── agents/
│   └── ios-reviewer.md             읽기 전용 리뷰 서브에이전트 (ios-harness:ios-reviewer)
├── skills/
│   └── task/SKILL.md               작업 시작: 모드·검사를 사용자에게 묻고 상태 파일을 만든다 (ios-harness:task)
└── hooks/
    ├── hooks.json                  훅 등록: 모든 도구 전 tool-count.sh, 편집 전 protect-generated.sh·check-run.sh, 편집 후 stage-context.sh, 끝낼 때 stop-gate.sh
    ├── protect-generated.sh        생성 파일·pbxproj 편집 차단
    ├── check-run.sh                검증 단계를 넘기려 할 때 고른 검사의 run을 돌려, 실패하면 막는다
    ├── stop-gate.sh                작업 주인 세션이 done 전에 끝내지 못하게 막는다
    ├── tool-count.sh               작업 주인 세션의 도구 호출 수를 센다 (stop-gate.sh의 반복 방지용)
    └── stage-context.sh            작업 상태 파일이 바뀌면 그 단계의 지시를 넣는다
```

## 훅: protect-generated.sh

| 프로젝트 생성기 | 막는 파일 | 안내 |
|---|---|---|
| tuist, xcodegen | `*.xcodeproj/` 안, `*.xcworkspace/` 안, `Derived/` 안 | manifest를 고치면 스크립트가 다시 생성한다 |
| 그 외 (xcodeproj 등) | `*.pbxproj` | 직접 고치지 말고 무엇을 바꿔야 하는지 사용자에게 알린다 |

- 파일이 속한 프로젝트는 `.harness/project.json`이 있는 가장 가까운 상위 디렉터리다. 생성기는 그 파일에서 읽는다.
- 판단할 수 없으면 막지 않는다. 설정 파일이 없거나 입력이 깨진 경우다.
- 왜 훅과 권한 규칙을 나눴는지는 [ADR 0004](decisions/0004-enforcement.md)에 있다.

## 훅: stage-context.sh와 스킬: task

작업 흐름(plan/simple 모드, 사람이 고른 검사)을 만든다. 동작과 설정 형식은 [checks.md](checks.md)에 있다.

- PostToolUse(Edit·Write·MultiEdit)에서 고친 파일이 `<프로젝트>/.harness/state/task.json`일 때만 동작한다. 프로젝트는 `.harness/project.json`이 있어야 한다.
- 지금 단계의 지시를 `.harness/checks.json`에서 꺼내 `additionalContext`로 넣고 0으로 끝난다. 막지 않는다.
- `task` 스킬은 모드와 검사를 사용자에게 묻고 상태 파일을 만든다. 모드와 검사를 AI가 대신 고르지 않는다.

## 훅: check-run.sh

검사를 정말 통과했는지 에이전트의 말이 아니라 run의 결과로 판정한다(발표 슬라이드 29·30, [ADR 0012](decisions/0012-run-gate.md)).

- PreToolUse(Edit·Write·MultiEdit)에서 `.harness/state/task.json`을 고치려 할 때만 동작한다. 고친 뒤의 내용을 계산해 `stage`가 verify를 지나 finish·done으로 가는지 본다.
- 그렇다면 고른 검사 중 `run`이 있는 것을 프로젝트 루트에서 실행한다. 하나라도 실패하면 이유를 stderr로 내고 2로 끝나 편집을 막는다.
- 판단할 수 없으면(설정 없음, JSON 오류) 막지 않는다.

## 훅: stop-gate.sh

작업이 끝나기 전에는 멈추지 못하게 한다(발표 슬라이드 14·88, [ADR 0012](decisions/0012-run-gate.md)).

- Stop에서 cwd의 프로젝트(`.harness/project.json`)를 찾고 `.harness/state/task.json`의 stage를 본다.
- 작업 주인 세션(`.harness/state/task.owner`, `stage-context.sh`가 적는다)만 막는다. done 전이면 이유를 stderr로 내고 2로 끝난다.
- plan 단계도 막는다. 승인은 Plan 모드(ExitPlanMode)로 턴 안에서 받는다.
- 반복 방지는 ai-bouncer를 따른다: 도구 없이 같은 이유로 재진입하면 끝내게 두고(`tool-count.sh`가 도구 수를 센다), 같은 단계에서 10번 연속이면 사용자에게 넘기게 한다. 상태는 `.harness/state/stop-gate.json`.
- 상태 파일이 없거나 깨졌을 때, 주인이 아닌 세션은 막지 않는다.

## 서브에이전트: ios-reviewer

변경을 하네스 규칙에 비춰 검토하는 읽기 전용 리뷰어다(추론적 Validation). 플러그인 안에서는 `ios-harness:ios-reviewer`로 부른다.

- 쓸 수 있는 도구는 Read·Grep·Glob·Bash뿐이다. Bash는 git의 읽기 명령에만 쓰도록 지시한다. 플러그인 서브에이전트에서는 `permissionMode`가 무시되기 때문에 도구 목록으로 제한한다.
- 검토 범위: 기본은 커밋하지 않은 변경이다. 요청하면 브랜치 전체(`git diff <기본 브랜치>...HEAD`)를 본다.
- 검토 순서: 바뀐 파일 찾기(`git diff HEAD`, `git status --porcelain`) → 바뀐 파일을 Read로 열기 → 의심되는 부분 확인 → 출력.
  바뀐 파일을 열면 그 파일에 맞는 `.claude/rules/harness/` 규칙이 자동으로 함께 들어온다. 그래서 규칙 파일을 따로 읽으라고 시키지 않는다.
- 중점 항목: 동시성 격리, 의존 방향, 접근성, 테스트 약화·설정 완화 같은 편법, 과설계
- 출력
  - 발견이 없으면 한 줄만 쓴다.
  - 발견이 있으면 `[차단|권장|참고] 경로:줄 — 문제`, 근거, 제안을 세 줄로 쓰고 마지막에 요약 줄을 붙인다.
  - 마지막에 "열어 본 파일·규칙"을 적는다. 검토 순서를 지켰는지 확인하기 위해서다.
- 언제 쓰나: PR을 만들기 전, 또는 사용자가 리뷰를 요청할 때. 프로젝트 AGENTS.md의 관리 블록에 안내가 있다.

## 프로젝트에서 켜기

이 저장소가 GitHub 마켓플레이스다. `scripts/init`·`sync`가 프로젝트의 `.claude/settings.json`에 다음을 넣는다.

```json
{
  "extraKnownMarketplaces": {
    "ios-ai-harness": { "source": { "source": "github", "repo": "Gooreum/ios-ai-harness" } }
  },
  "enabledPlugins": { "ios-harness@ios-ai-harness": true }
}
```

- 이 파일을 커밋하면 팀원이 프로젝트를 열고 폴더를 신뢰할 때 Claude Code가 마켓플레이스 추가와 플러그인 설치를 권한다. 직접 하려면 `claude plugin marketplace add Gooreum/ios-ai-harness` 후 `claude plugin install ios-harness@ios-ai-harness --scope project`.
- 저장소 이름은 `plugin.json`의 `repository`에서 읽는다. 다른 포크로 배포하려면 그 값을 고치거나 `HARNESS_MARKETPLACE_REPO=<owner>/<repo>`를 준다.
- 하네스를 고치는 중에는 `scripts/sync --dev <프로젝트>`로 같은 이름의 마켓플레이스를 이 저장소 디렉터리로 덮어쓴다(`.claude/settings.local.json`). 디렉터리 마켓플레이스는 복사하지 않고 그 자리에서 읽어서, 고친 내용이 다음 세션부터 반영된다.

## 버전

- `plugin.json`의 `version` 하나가 하네스 버전이다. template(프로젝트 파일)과 plugin(훅·스킬)이 같은 설정 형식을 읽으므로 따로 세지 않는다.
- template이나 plugin을 바꿔 `main`에 머지할 때 버전을 올린다. 올리지 않으면 Claude Code가 플러그인 갱신을 알아채지 못한다.
- 프로젝트에는 sync가 설치한 버전을 `.harness/harness.json`에 남긴다. `scripts/harness/doctor`가 설치된 플러그인 버전과 비교한다.
- 팀원 쪽 갱신: `claude plugin marketplace update ios-ai-harness && claude plugin update ios-harness@ios-ai-harness`

## 검증

```bash
claude plugin validate ./plugin   # 플러그인 정보
claude plugin validate .          # 마켓플레이스
bash tests/run.sh                 # 훅 판단 회귀 테스트 포함
```
