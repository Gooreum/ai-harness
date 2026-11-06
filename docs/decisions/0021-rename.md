# 0021. 이름에서 iOS를 빼고, sync가 예전 이름의 항목을 지운다

- 상태: 채택 (2026-11-06)
- 관련: ADR 0018(공통 핵심과 묶음), 로드맵 단위 24, `scripts/sync`, `template/scripts/harness/doctor`, `plugin/hooks/review-record.sh`

## 배경

- 하네스가 iOS 밖(RN, 웹, 묶음 없는 저장소)으로 넓어지는데 이름이 모두 iOS다. 발표 슬라이드 21: v2는 "하네스도 훅도 그대로, 저장소마다 config만 다르게" 했다.
- 이미 설치한 프로젝트는 설정에 예전 이름(`ios-harness@ios-ai-harness`)을 들고 있다. 새 이름만 더하면 플러그인 두 개가 같이 켜져 훅이 두 번 돈다.

## 결정

| 항목 | 예전 | 새 이름 |
|---|---|---|
| 저장소 | `Gooreum/ios-ai-harness` | `Gooreum/ai-harness` |
| 마켓플레이스 | `ios-ai-harness` (owner `woong`) | `ai-harness` (owner 그대로) |
| 플러그인 | `ios-harness` | `harness` |
| 리뷰어 | `ios-reviewer` (`ios-harness:ios-reviewer`) | `reviewer` (`harness:reviewer`) |

이름은 사용자가 정했다(2026-11-06).

| 옮기기 | 결정 | 근거 |
|---|---|---|
| 설정 | sync가 `.claude/settings.json`·`settings.local.json`에서 예전 마켓플레이스·플러그인 키를 지우고 새 키를 넣는다. 다른 플러그인은 그대로 둔다 | ai-bouncer `engine/init.sh`가 옛 설치본이 만든 것을 이름으로 찾아 지운다 |
| 검사 목록 | `checks.json`에서 하네스가 추천한 문구(`ios-harness:ios-reviewer`, 설명 `ios-reviewer 코드 리뷰`)만 새 이름으로 바꾼다 | 바꾸지 않으면 리뷰 검사가 없는 에이전트를 부른다. 팀이 쓴 다른 문구는 건드리지 않는다 |
| 설치된 예전 플러그인 | sync는 지우지 않는다. 켜져 있으면 doctor가 문제로 알리고 `claude plugin uninstall`을 안내한다 | 플러그인 설치 기록은 사용자 홈(`~/.claude`)에 있어 프로젝트 도구가 고칠 곳이 아니다 |
| 리뷰 기록 훅 | `agent_type`이 `harness:reviewer`일 때만 기록한다 | 예전에는 `*:ios-reviewer`를 받았다. `reviewer`는 흔한 이름이라 다른 플러그인이나 프로젝트의 리뷰어를 섞지 않게 한다 |
| 그대로 둔 것 | 이 저장소의 로컬 폴더(`~/Code/ios-ai-harness`), 시뮬레이터 잠금 폴더(`ios-harness-simulators`) | 로컬 폴더는 진행 중인 세션과 메모리가 이 경로에 묶여 있다. 잠금 폴더는 iOS 묶음 것이고, 바꾸면 예전 버전과 새 버전이 같은 기기를 동시에 잡는다 |

- 버전은 0.10.0으로 올린다. 플러그인 id가 바뀌어 예전 플러그인에서 이어지는 갱신이 아니다.

## 발표·ai-bouncer와 다른 점

- 발표에는 이름을 바꾸는 이야기가 없다.
- ai-bouncer는 열린 세션이 옛 훅 경로를 계속 부르므로 그 자리에 새 훅으로 넘기는 파일을 둔다. 이 하네스는 예전 플러그인 파일을 지우지 않아(Claude Code 캐시에 남는다) 열린 세션은 예전 플러그인으로 계속 돈다. 넘기는 파일이 필요 없다.

## 결과

- 예전 이름의 항목이 있는 프로젝트를 sync하면 새 이름만 남고, 검사 지시문의 리뷰어가 새 이름이 된다(`tests/sync.test.sh`).
- 예전 플러그인이 켜져 있으면 doctor가 실패한다(`tests/doctor.test.sh`).
