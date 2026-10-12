# 플러그인

`plugin/`은 Claude Code 플러그인 `ios-harness`다. 여러 프로젝트에 공통으로 적용할 훅을 담는다. 이후 단위에서 스킬과 서브에이전트도 추가한다.
이 저장소 루트의 `.claude-plugin/marketplace.json` 덕분에 저장소 자체가 마켓플레이스(`ios-ai-harness`) 역할을 한다.

## 구성

```
.claude-plugin/marketplace.json     마켓플레이스 정의. 플러그인 위치는 ./plugin
plugin/
├── .claude-plugin/plugin.json      플러그인 정보(이름 ios-harness, 버전)
└── hooks/
    ├── hooks.json                  훅 등록: Edit·Write·MultiEdit·NotebookEdit 전에 protect-generated.sh 실행
    └── protect-generated.sh        생성 파일·pbxproj 편집 차단
```

## 훅: protect-generated.sh

| 프로젝트 생성기 | 막는 파일 | 안내 |
|---|---|---|
| tuist, xcodegen | `*.xcodeproj/` 안, `*.xcworkspace/` 안, `Derived/` 안 | manifest를 고치면 스크립트가 다시 생성한다 |
| 그 외 (xcodeproj 등) | `*.pbxproj` | 직접 고치지 말고 무엇을 바꿔야 하는지 사용자에게 알린다 |

- 파일이 속한 프로젝트는 `.harness/project.json`이 있는 가장 가까운 상위 디렉터리다. 생성기는 그 파일에서 읽는다.
- 판단할 수 없으면 막지 않는다. 설정 파일이 없거나 입력이 깨진 경우다.
- 왜 훅과 권한 규칙을 나눴는지는 [ADR 0004](decisions/0004-enforcement.md)에 있다.

## 프로젝트에서 켜기

지금은 개발 중이라 로컬 경로를 마켓플레이스로 쓴다. 프로젝트의 `.claude/settings.local.json`(또는 `.claude/settings.json`)에 다음을 넣는다.

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
