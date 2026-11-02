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
    ├── hooks.json                  훅 등록: 편집 전 protect-generated.sh, 편집 후 stage-context.sh
    ├── protect-generated.sh        생성 파일·pbxproj 편집 차단
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

지금은 개발 중이라 로컬 경로를 마켓플레이스로 쓴다. `scripts/dev-install`가 프로젝트의 `.claude/settings.local.json`에 다음을 넣는다.

```json
{
  "extraKnownMarketplaces": {
    "ios-ai-harness": { "source": { "source": "directory", "path": "<이 저장소의 절대 경로>" } }
  },
  "enabledPlugins": { "ios-harness@ios-ai-harness": true }
}
```

- 로컬 디렉터리 마켓플레이스의 플러그인은 복사하지 않고 그 자리에서 불러온다. 그래서 이 저장소에서 고친 내용이 다음 세션부터 바로 반영된다.
- 원격(GitHub) 마켓플레이스로 배포하고 템플릿 설정에 넣는 일은 후보 14에서 한다.

## 검증

```bash
claude plugin validate ./plugin   # 플러그인 정보
claude plugin validate .          # 마켓플레이스
bash tests/run.sh                 # 훅 판단 회귀 테스트 포함
```
