#!/usr/bin/env bash
# SessionStart 훅: 하네스를 켠 프로젝트에서 세션을 열 때(시작·재개·/clear·압축 뒤) 작업 시작 방법이나 진행 중인 작업을 알려 준다.
#
# ai-bouncer hooks/session-start.sh를 따른다: 작업이 없으면 "개발 작업은 /dev-bounce로 시작한다"를, 있으면 그 단계를 넣는다.
# 편집을 막지는 않는다. 작업 밖에서 고치지 않게 하는 것은 이 안내와 task 스킬 설명이 맡는다(ai-bouncer도 같다).
#
# - 입력은 stdin JSON만 읽는다 (cwd). stdout이 그대로 모델 컨텍스트에 들어간다.
# - 판단할 수 없으면(프로젝트가 아님, jq 없음) 아무것도 내지 않는다.
set -uo pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

dir="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$dir" ] || exit 0
while [ "$dir" != "/" ] && [ ! -f "$dir/.harness/project.json" ]; do dir="$(dirname "$dir")"; done
[ -f "$dir/.harness/project.json" ] || exit 0
state="$dir/.harness/state/task.json"

stage="" title="" mode=""
if [ -f "$state" ]; then
  stage="$(jq -r '.stage // ""' "$state" 2>/dev/null)" || stage=""
  title="$(jq -r '.title // ""' "$state" 2>/dev/null)" || title=""
  mode="$(jq -r '.mode // ""' "$state" 2>/dev/null)" || mode=""
fi

if [ -n "$stage" ] && [ "$stage" != done ]; then
  cat <<MSG
[하네스] 진행 중인 작업이 있다: "$title" · $mode 모드 · $stage 단계
이어서 하려면 .harness/state/task.json을 같은 내용으로 다시 저장해 이 단계의 지시를 받는다.
이 작업과 다른 수정을 하려면 사용자에게 먼저 묻는다.
MSG
else
  cat <<'MSG'
[하네스] 코드를 고치는 작업은 파일을 고치기 전에 task 스킬(/harness:task)로 시작한다.
작업을 done으로 닫은 뒤 이어서 고치는 것(리뷰 지적 반영, 추가 요청)도 새 작업이다.
MSG
fi
exit 0
