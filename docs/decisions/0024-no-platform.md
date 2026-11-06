# 0024. 하네스는 플랫폼을 모른다. 플랫폼 도구는 저장소가 갖고, setup이 함께 정한다

- 상태: 채택 (2026-11-06)
- 관련: ADR 0018·0019(공통 핵심과 묶음, 이 결정으로 대체), 0020(setup), 0023(묶음 없는 저장소), 로드맵 단위 31
- 대체: ADR 0018의 "플랫폼 묶음"과 ADR 0019 전체, ADR 0023의 "iOS 묶음은 그대로 둔다"

## 배경

- 단위 25~30 동안 사용자가 여러 번 되물었다(2026-11-06): "이런 것까지 설정을 해 줘야 해 하네스에서?", "이 하네스가 구체적인 플랫폼을 알아야 하는 이유가 뭐야?".
- 사용자의 뜻: 플랫폼마다 무엇을 어떻게 쓰는지는 사용자마다 다르다(누구는 Tuist를 쓰고 누구는 안 쓴다). 하네스가 설정을 미리 만들어 두지 말고, 사용자가 자기 설정을 만들도록 돕는 데까지만 한다.
- 발표 슬라이드 27: "훅은 검사 내용을 몰라요. config에 적힌 글을 옮겨 줄 뿐이에요". 슬라이드 38: "하네스도 훅도 그대로, 저장소마다 config만 달라요". andcon·gc-e2e는 하네스가 아니라 팀이 만든 도구이고, config가 부른다(슬라이드 29·61).
- ai-bouncer에는 플랫폼 코드가 없다. `bouncer setup`이 저장소에서 명령을 찾아 보여 주고, 사용자에게 물어 yaml을 쓴다(`engine/setup.sh`).
- 그런데 이 하네스에는 iOS 묶음이 있었다. 빌드·테스트·린트·e2e 스크립트(`ios.sh` 700줄), Swift 규칙 10개, iOS 권한, detect의 iOS 판단, 훅의 Tuist·XcodeGen·pbxproj 처리. 시험장이 iOS였고, 거기서 막힌 문제(긴 빌드 로그, 시뮬레이터 충돌)를 하네스 안에서 풀다가 들어왔다.

## 결정

| 항목 | 결정 | 근거 |
|---|---|---|
| 하네스가 갖는 것 | 단계 훅, run 확인, Stop 게이트, `task`, `checks.json`, `record`·`passed`, 리뷰어와 리뷰 기록, 위키, 가짜 응답 MCP, 공통 권한, `setup`·`doctor` | 발표의 하네스, ai-bouncer |
| 하네스가 갖지 않는 것 | 플랫폼 묶음(`packs/`), iOS 스크립트(`build`·`test`·`unit-test`·`lint`·`e2e`·`ios.sh`·`ios-doctor.sh`·`ios-checks.json`), iOS 규칙(`rules/harness/ios/`), `scripts/detect` | 사용자 결정. 발표 슬라이드 27·38 |
| 설정 만들기 | `setup`이 저장소에서 찾은 명령과 단서(Tuist manifest, `project.yml`, xcodeproj, Expo가 무시하는 `ios/`, codegen 설정)를 보여 주고, 묻는 것: 고를 검사, 자동 생성 파일, 직접 고치면 안 되는 파일, 출력이 긴 명령을 감쌀 스크립트. 답을 `checks.json`, `project.json`의 `generated`, `.claude/settings.json`의 `Edit(...)` deny, `AGENTS.md` 프로젝트 영역, 저장소의 `scripts/`에 쓴다 | ai-bouncer `setup.sh`. 단서는 보여 주기만 하고 정하는 것은 사용자의 답이다 |
| 생성 파일 보호 | 훅은 `generated` 글롭만 본다. generator·pbxproj를 따로 알지 않는다 | 플랫폼 지식을 훅에서 뺀다. pbxproj처럼 생성물은 아니지만 막을 파일은 권한 규칙(`Edit(**/*.pbxproj)`)으로 막는다 |
| 처음 설치 | `init`이 `{ "schemaVersion": 2 }`만 쓰고 setup으로 정하라고 알린다 | 플랫폼을 묻지 않는다 |
| 이미 iOS 묶음을 쓰는 프로젝트 | `sync`가 지우지 않고 프로젝트 코드로 넘긴다. 스크립트는 `scripts/ios/`로(쓰던 `lib.sh` 사본과 함께), 규칙은 `.claude/rules/project/ios/`로 옮기고, `checks.json`과 옮긴 파일의 경로를 바꾼다. Tuist·XcodeGen이면 생성물 글롭을 `generated`에 적고, 묶음이 넣은 권한은 프로젝트 규칙으로 남긴다. `project.json`의 iOS 값은 옮긴 스크립트가 읽는 그대로 둔다 | 시험장 두 곳(ReadSharp, IntervalTimer)이 쓰고 있다. 지우면 검사가 깨진다 |
| 리뷰 항목 | 리뷰어는 `.claude/rules/project/**/*.md`에서 바뀐 파일에 맞는 규칙을 연다 | 플랫폼 리뷰 항목도 프로젝트 규칙이다 |

## 발표·ai-bouncer와 다른 점

- 같은 방향으로 맞췄다. 발표·ai-bouncer와 다른 점이 줄었다.
- `setup`이 생성 파일·보호할 파일까지 묻는 것은 ai-bouncer에 없다. 이 하네스에는 생성 파일 훅이 있어 그 설정도 함께 정한다.

## 결과

- 지운 것: `packs/`, `scripts/detect`, iOS 스크립트·규칙, 그 테스트(build·unit-test·lint·lint-kinds·e2e·detect).
- 이미 설치한 프로젝트를 sync하면 iOS 파일이 프로젝트 쪽으로 옮겨지고 두 번째 실행은 바뀐 것이 없다(`tests/sync.test.sh`).
- iOS 도구는 git 기록(0.11.2)에 남아 있다. 새 iOS 저장소가 원하면 setup이 그 저장소에 맞게 새로 만들거나, 사용자가 가져다 쓴다.
