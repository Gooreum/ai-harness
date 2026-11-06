# 0022. 리뷰어는 공통 절차만 두고, 플랫폼 항목·생성 파일·권한은 묶음과 설정에서 받는다

- 상태: 채택 (2026-11-06)
- 관련: ADR 0004(강제 장치), 0016(리뷰 기록), 0019(묶음 구조), 로드맵 단위 25, `plugin/agents/reviewer.md`, `plugin/hooks/review-record.sh`, `plugin/hooks/protect-generated.sh`

## 배경

- 리뷰어 설명과 중점 항목이 iOS(동시성, Tuist manifest, 접근성 식별자)를 말한다. RN에서 JS만 고칠 때도 iOS 지시가 섞인다. 발표 슬라이드 19: "웹 작업인데 안드로이드 검증 스킬을 불러와요".
- 생성 파일 보호 훅은 Tuist·XcodeGen·pbxproj만 안다. Expo prebuild의 `ios/`·`android/`, codegen 결과는 막지 못한다.
- 리뷰 기록 훅은 바뀐 파일을 다 열어야 통과로 친다. lock 파일이나 생성 코드도 열어야 해서, 큰 lock 파일 하나로 리뷰가 길어진다.
- 공통 권한은 git만 다룬다. 패키지·앱 배포처럼 되돌릴 수 없는 명령과 Android·npm 비밀 파일이 빠져 있다.

## 결정

| 항목 | 결정 | 근거 |
|---|---|---|
| 리뷰어 | 공통 절차(바뀐 파일 열기, 참조처로 기존 영향 찾기, 보고 형식)와 공통 중점 항목만 둔다. 플랫폼 확인 항목·편법은 `.claude/rules/harness/<묶음>/review.md`(iOS: `ios/review.md`)에 두고, 리뷰어가 Glob으로 찾아 연다 | 발표 슬라이드 27·38: 하네스는 내용을 모르고 저장소에 적힌 것을 옮긴다. 규칙 파일은 `paths`로 바뀐 파일을 열 때 함께 들어온다 |
| 공통 편법 목록 | 여러 언어의 예(`@ts-ignore`, `eslint-disable`, `# noqa`, `@Suppress`, 스냅샷 `-u`)를 공통에 둔다 | 묶음이 없는 저장소(JS, Python)도 같은 편법을 쓴다. 묶음을 만들지 않고도 잡는다 |
| 생성 파일 | `.harness/project.json`의 `generated`(글롭 배열)를 보호 훅과 리뷰 기록 훅이 함께 읽는다 | 생성 파일은 프로젝트마다 다른 사실이라 설정 파일에 둔다(설계 원칙). 고치면 안 되는 파일은 리뷰할 필요도 없다 |
| 리뷰어가 열지 않아도 되는 파일 | 바이너리 확장자를 넓히고(`webp`·`woff2`·`ico`·`jar`·`aar`·`so`·`wasm` 등), 흔한 lock 파일 이름을 뺀다 | 열어도 판단할 것이 없다. 묶음별로 나누지 않고 공통 목록 하나로 둔다(어느 저장소에나 같은 이름) |
| 묻는 명령(ask) | 공통에 배포·공개 명령을 더한다: `npm`·`yarn`·`pnpm publish`, `eas submit`·`eas update`, `fastlane`, gradle publish, `firebase deploy`, `vercel`. `npm --prefix`, `yarn --cwd`, `pnpm -C`, `gradlew -p` 형식도 | 되돌릴 수 없는 행동이라 처음부터 막는 대상이다(ADR 0004). 묶음이 없는 저장소도 쓰므로 공통에 둔다 |
| 비밀 파일(deny) | 공통에 `*.jks`, `*.keystore`, `keystore.properties`, `.npmrc`, `credentials.json` 읽기를 더한다. `.env`는 Bash 명령 인자로 쓰는 것(`cat .env`)도 막는다(`Bash(* .env)` 등) | 같은 이유. Bash 규칙은 명령 글자만 보므로 보안 경계가 아니라 흔한 실수를 막는 장치다(Claude Code 권한 문서) |
| 자동 실행 | `checks.json`의 run이 묻지 않고 실행된다는 것을 `docs/checks.md`에 적고, doctor가 `scripts/harness/passed`가 아닌 run을 "참고"로 보여 준다 | 남의 저장소를 내려받으면 그 저장소가 적은 명령이 돈다. 막지는 않는다(발표의 run은 저장소가 정한다) |

## 발표·ai-bouncer와 다른 점

- 발표에는 리뷰 서브에이전트가 없다. ai-bouncer의 `review` 검사는 "git diff를 읽고 버그·누락·불필요한 변경을 찾는다" 한 줄이다. 이 하네스는 ADR 0016대로 리뷰어를 두고, 이번에는 그 리뷰어를 플랫폼과 떼어 놓기만 했다.
- `local.properties`는 deny에 넣지 않았다. 보통 `sdk.dir`만 있고 Android 빌드 문제를 볼 때 읽어야 한다. 서명 값이 들어 있는 프로젝트가 생기면 그때 넣는다.

## 결과

- 리뷰어 지시문에 iOS 이름이 없다. iOS 프로젝트는 Swift 파일을 열 때 `ios/review.md`가 함께 들어와 이전과 같은 항목을 본다.
- `generated`에 적은 파일은 편집이 막히고 리뷰 대상에서 빠진다(`tests/hooks.test.sh`, `tests/review-record.test.sh`).
- doctor가 자동 실행되는 run을 알린다(`tests/doctor.test.sh`).
