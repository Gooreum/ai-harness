# 프로젝트 설정 파일 (`.harness/project.json`)

프로젝트마다 다른 사실을 모아두는 JSON 파일이다. 각 프로젝트 루트의 `.harness/project.json`에 두고 git에 커밋한다.
하네스의 훅과 스크립트는 이 파일이 있는 가장 가까운 상위 디렉터리를 프로젝트 루트로 본다. 그래서 내용이 비어 있어도 파일은 있어야 한다.

- **사실만 적는다.** "무엇을 언제 검증할지" 같은 정책은 `checks.json`에 둔다([checks.md](checks.md)).
- **하네스는 플랫폼을 모른다.** 스킴·시뮬레이터·생성기 같은 플랫폼 값은 하네스가 읽지 않는다([ADR 0024](decisions/0024-no-platform.md)). 프로젝트가 가진 스크립트가 쓰는 값이면 이 파일에 둬도 된다. 하네스는 건드리지 않는다.
- **처음 설치하면 `{ "schemaVersion": 2 }`만 있다.** `scripts/init`이 쓴다. 나머지는 Claude 세션에서 `scripts/harness/setup` 안내대로 사용자와 정해 더한다.
- **필요해질 때 필드를 추가한다.** `schemaVersion`은 기존 필드의 의미가 바뀔 때만 올린다.

## 예시 (Expo 앱, 가짜 응답 서버 사용)

```json
{
  "schemaVersion": 2,
  "generated": ["ios/*", "android/*", "src/gql/*.generated.ts"],
  "e2e": { "network": { "port": 18787 } }
}
```

## 필드

| 필드 | 값 | 설명 |
|---|---|---|
| `schemaVersion` | `2` | 파일 형식 버전 |
| `generated` | 글롭 배열, 선택 | 직접 고치면 안 되는 생성 파일(루트 기준, `*`는 `/`도 넘는다). 예: Expo prebuild의 `["ios/*", "android/*"]`, Tuist·XcodeGen의 `["*.xcodeproj/*", "*.xcworkspace/*", "Derived/*", "*/Derived/*"]`, codegen 결과 `["src/gql/*.generated.ts"]`. 훅 `protect-generated.sh`가 편집을 막고, 리뷰어가 열지 않아도 된다. setup이 사용자에게 물어 정한다 |
| `e2e.network.port` | 포트 번호 또는 없음 | 가짜 응답 서버(플러그인 MCP `harness-network`)가 쓸 포트. 있을 때만 MCP 도구가 보인다. 프로젝트마다 다른 번호를 쓴다. 같은 프로젝트의 다른 워크트리가 이미 쓰고 있으면 서버가 빈 포트로 띄우고 `.harness/state/network.port`에 남긴다([plugin.md](plugin.md#mcp-harness-network-가짜-응답-서버)) |

- 생성물은 아니지만 손으로 고치면 깨지는 파일(예: `project.pbxproj`)은 여기에 적지 않고 `.claude/settings.json`의 deny에 `Edit(<글롭>)`으로 넣는다. setup이 함께 묻는다.

## 예전 iOS 값

0.11.x까지는 iOS 묶음이 이 파일의 `platforms`와 `ios` 값(`generator`, `workspace`, `app.scheme`, `modules` 등), `e2e.events`를 읽었다. 그 스펙은 git 기록(0.11.2의 `docs/project-config.md`)에 있다.

- 묶음을 쓰던 프로젝트를 sync하면 iOS 스크립트가 `scripts/ios/`로 넘어간다. 넘어간 스크립트는 지금도 `ios` 값을 읽으므로 sync는 이 값을 지우지 않는다.
- `ios.generator`가 `tuist`·`xcodegen`이면 sync가 프로젝트 파일 글롭을 `generated`에 더한다. 예전에는 훅이 generator를 보고 막았다.
- `platforms`는 이제 아무도 읽지 않는다. 남아 있어도 된다.
- sync는 더 이상 `schemaVersion` 1(iOS 값이 최상위에 있던 형식)을 옮기지 않는다.
