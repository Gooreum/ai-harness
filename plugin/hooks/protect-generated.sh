#!/usr/bin/env bash
# PreToolUse 훅: 자동 생성 파일(Tuist·XcodeGen 결과, project.json의 generated)과 project.pbxproj를 에이전트가 직접 고치지 못하게 막는다.
#
# - 입력은 stdin JSON만 읽는다 (tool_input.file_path 또는 notebook_path, cwd). Codex에서도 재사용하기 위해서다.
# - 막을 때는 이유와 고치는 방법을 담아 deny 결정을 출력한다.
# - 판단할 수 없으면(.harness/project.json 없음, JSON 오류 등) 막지 않는다.
#   실수를 막는 장치이지 보안 경계가 아니라서, 고장 난 훅이 정상 작업을 막으면 안 된다.
set -uo pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)" || exit 0
[ -n "$file" ] || exit 0
case "$file" in
  /*) ;;
  *)
    cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
    [ -n "$cwd" ] || exit 0
    file="$cwd/$file"
    ;;
esac

# 파일이 속한 프로젝트 루트: .harness/project.json이 있는 가장 가까운 상위 디렉터리
root=""
dir="$(dirname "$file")"
while [ -n "$dir" ] && [ "$dir" != "/" ]; do
  if [ -f "$dir/.harness/project.json" ]; then
    root="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done
[ -n "$root" ] || exit 0

# 새 형식은 ios.generator, sync 전의 옛 형식(schemaVersion 1)은 generator에 있다.
generator="$(jq -r '.ios.generator // .generator // empty' "$root/.harness/project.json" 2>/dev/null)"
rel="${file#"$root"/}"

reason=""
case "$generator" in
  tuist | xcodegen)
    case "/$rel" in
      */*.xcodeproj/* | */*.xcworkspace/* | */Derived/*)
        reason="자동 생성 파일이라 직접 고쳐도 다시 생성하면 사라집니다: $rel. manifest(Tuist는 Project.swift·Tuist/, XcodeGen은 project.yml)를 고치세요. scripts/harness의 build·test·unit-test가 필요할 때 다시 생성합니다."
        ;;
    esac
    ;;
esac
# 프로젝트가 정한 생성 파일(project.json의 generated, 글롭). 예: Expo prebuild의 "ios/*", codegen 결과.
if [ -z "$reason" ]; then
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    # shellcheck disable=SC2254 # 글롭으로 맞춘다
    case "$rel" in
      $g)
        reason="자동 생성 파일이라 직접 고쳐도 다시 생성하면 사라집니다: $rel (.harness/project.json의 generated: $g). 생성하는 쪽(설정·스키마·원본)을 고치고 다시 생성하세요."
        break
        ;;
    esac
  done < <(jq -r '.generated // [] | .[] | strings' "$root/.harness/project.json" 2>/dev/null)
fi
if [ -z "$reason" ]; then
  case "$rel" in
    *.pbxproj)
      reason="project.pbxproj는 직접 편집하지 않습니다: $rel. 파일 추가나 설정 변경에 pbxproj 수정이 필요하면, 직접 고치지 말고 무엇을 바꿔야 하는지 사용자에게 알리세요."
      ;;
  esac
fi
[ -n "$reason" ] || exit 0

jq -n --arg reason "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
