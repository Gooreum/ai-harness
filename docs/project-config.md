# 프로젝트 설정 파일 (`.harness/project.json`)

프로젝트마다 다른 사실을 모아두는 JSON 파일이다. 각 프로젝트 루트의 `.harness/project.json`에 두고 git에 커밋한다.
하네스 스크립트와 AGENTS.md의 명령 블록이 이 파일을 읽는다. 그래서 같은 스크립트가 어느 프로젝트에서나 동작한다.

- **사실만 적는다.** "무엇을 언제 검증할지" 같은 정책은 넣지 않는다.
- **필요해질 때 필드를 추가한다.** 이후 단위에서 새 값이 필요하면 그때 필드를 더한다. `schemaVersion`은 기존 필드의 의미가 바뀔 때만 올린다.
- **초안은 `detect`로 만들고, 사람이 확인한 뒤 저장한다.**

## 예시 (Tuist 모듈 프로젝트)

```json
{
  "schemaVersion": 1,
  "generator": "tuist",
  "commands": {
    "install": "tuist install",
    "generate": "make generate"
  },
  "workspace": "MotoTrace.xcworkspace",
  "project": null,
  "app": {
    "scheme": "MotoTrace",
    "path": "MotoTrace",
    "bundleId": "com.woong.MotoTrace",
    "unitTestTargets": ["MotoTraceTests"]
  },
  "destination": {
    "simulator": "iPhone 17 Pro",
    "os": "latest"
  },
  "modules": {
    "manifest": "Project.swift",
    "scheme": "{dir}",
    "testsDir": "Tests"
  }
}
```

## 필드

| 필드 | 값 | 설명 |
|---|---|---|
| `schemaVersion` | `1` | 파일 형식 버전 |
| `generator` | `tuist` · `xcodegen` · `xcodeproj` · `spm` | Xcode 프로젝트를 만드는 방식. `tuist`·`xcodegen`은 프로젝트 파일이 생성물이다 |
| `commands.install` | 문자열 또는 `null` | 외부 의존성을 받는 명령. 새 클론이나 새 워크트리, 의존성이 바뀌었을 때 실행한다 |
| `commands.generate` | 문자열 또는 `null` | Xcode 프로젝트를 (다시) 만드는 명령. 생성기가 없으면 `null`이다 |
| `workspace` | 경로 또는 `null` | 빌드할 `.xcworkspace`. 루트 기준 경로다 |
| `project` | 경로 또는 `null` | 빌드할 `.xcodeproj`. `workspace`와 `project` 중 하나만 값을 가진다 |
| `app.scheme` | 문자열 | 앱을 빌드하는 스킴 |
| `app.path` | 경로 또는 `null` | 앱 manifest가 있는 디렉터리(Tuist). 이 안의 파일은 앱의 변경으로 본다 |
| `app.bundleId` | 문자열 또는 `null` | Debug 구성의 앱 번들 ID. 시뮬레이터에서 앱을 실행할 때 쓴다 |
| `app.unitTestTargets` | 문자열 배열 | 앱이 바뀌었을 때 돌릴 단위 테스트 타깃. UI 테스트는 넣지 않는다 |
| `destination.simulator` | 문자열 | 빌드·테스트에 쓸 시뮬레이터 기기 이름 |
| `destination.os` | `latest` 또는 버전 | 시뮬레이터 OS 버전 |
| `modules` | 객체 또는 `null` | 모듈을 찾는 규칙. 모듈 구조가 없으면 `null`이다 |
| `modules.manifest` | 파일 이름 | 이 파일이 있는 디렉터리를 모듈 하나로 본다 |
| `modules.scheme` | 규칙 문자열 | 모듈 테스트를 돌릴 스킴 이름. `{dir}`은 모듈 디렉터리 이름이다 |
| `modules.testsDir` | 디렉터리 이름 | 생성된 스킴 파일이 없을 때 쓰는 대체 기준. 모듈 안에 이 디렉터리가 있으면 테스트가 있는 모듈로 본다 |

## 구성별 차이

| 구성 | `generator` | `commands` | 빌드 대상 | `modules` |
|---|---|---|---|---|
| Tuist 모듈 프로젝트 | `tuist` | install·generate | `workspace` | 규칙 있음 |
| xcodeproj 단일 앱 | `xcodeproj` | 둘 다 `null` | `project` (CocoaPods 등은 `workspace`) | `null` |
| XcodeGen | `xcodegen` | generate | `project` | `null` |
| SPM 패키지 | `spm` | 둘 다 `null` | 둘 다 `null` | `null` (아직 build·test 미지원) |

## detect

하네스 저장소의 `scripts/detect`가 프로젝트를 훑어서 초안을 만든다. 설치할 때, 또는 프로젝트 구조가 바뀌었을 때 쓰는 도구라 프로젝트에는 복사하지 않는다.

```bash
scripts/detect ~/path/to/app           # 초안을 출력
scripts/detect --write ~/path/to/app   # <프로젝트>/.harness/project.json에 저장 (이미 있으면 --force 필요)
```

- 초안 JSON은 stdout으로, 판단 근거와 경고는 stderr로 출력한다.
- 판단 근거
  - 파일 구조: `Tuist.swift`, `Workspace.swift`, `Project.swift`, `project.yml`, `*.xcodeproj`
  - Makefile 타깃: `make generate`처럼 프로젝트가 감싼 명령을 우선한다
  - pbxproj 내용: `plutil`로 JSON 변환
  - 생성된 워크스페이스가 있으면 `xcodebuild -list`, `-showBuildSettings`로 스킴과 번들 ID를 확인한다
  - `xcrun simctl`: 가장 최신 iOS 런타임의 iPhone을 고른다(Pro 모델 우선)
- Tuist 프로젝트를 아직 생성하지 않았으면 스킴과 번들 ID를 확인할 수 없다. 이 경우 추정값을 쓰거나 `null`로 두고, 경고를 출력한다.
- `HARNESS_OFFLINE=1`을 주면 xcodebuild·simctl을 부르지 않고 파일만 본다(테스트용). 이때 시뮬레이터 이름은 `HARNESS_SIMULATOR`에서 읽는다.
