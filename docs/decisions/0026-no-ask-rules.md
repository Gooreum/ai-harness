# 0026. 권한 규칙의 ask 목록을 두지 않는다

- 상태: 채택 (2026-11-07)
- 관련: ADR 0004(강제 장치) 표의 "파괴적 git 명령, 외부 공개 작업" 줄을 대신한다, `template/.claude/settings.json`, `scripts/sync`

## 배경

- 하네스는 `git push`, `gh pr create`·`merge`, `git reset --hard`·`clean`·`restore`·`rebase`·`branch -D`, 배포 명령(`fastlane`, `eas update`·`submit`, `firebase deploy`, `npm publish` 등)을 `ask`에 넣어 설치했다.
- Claude Code 문서: 명령 내용에 맞는 `ask` 규칙은 auto 모드에서도 분류기보다 먼저 걸려 항상 묻는다. 더 구체적인 `allow`가 있어도 `ask`가 이긴다. 그래서 "다시 묻지 않기"로도 끌 수 없다.
- PetCycle은 ai-bouncer에서 이 하네스로 바꾼 뒤 push·PR·배포마다 확인 창이 떴다. 배포 작업은 이 명령이 이어져 확인이 잦았다. 사용자: "그냥 안물어봤으면 좋겠다."
- 발표에는 권한 확인 목록이 없다. ai-bouncer도 `ask` 권한 규칙을 설치하지 않는다(`engine/bouncer.sh`의 "ask"는 모드 선택 방식이다).

## 결정

- `template/.claude/settings.json`의 `ask`를 비운다. `deny`(비밀 파일 읽기 금지)는 그대로 둔다.
- sync는 설치 기록(`.harness/harness.json`의 `permissions.ask`)에 있던 규칙만 지운다. 팀이 직접 넣은 `ask`는 남는다.
- 커밋·push·PR·파괴적 git 명령은 지침(AGENTS.md "꼭 지킬 규칙": 사용자가 요청하거나 승인한 뒤에 한다)과 auto 모드 분류기에 맡긴다.

## 결과

- 좋아지는 점: 사용자가 시킨 push·PR·배포가 확인 창 없이 이어진다.
- 비용: 에이전트가 지침을 어기고 push·배포를 하면 권한 규칙으로는 막히지 않는다. 분류기가 막지 않는 경우가 관찰되면 그 명령만 `ask`나 훅으로 다시 넣는다.
- 확인 방법: sync 회귀 테스트, 시험장 sync 뒤 `.claude/settings.json`에 하네스가 넣은 `ask`가 남지 않았는지 본다.
