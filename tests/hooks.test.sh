#!/usr/bin/env bash
# 플러그인 훅: Claude Code가 넘기는 것과 같은 모양의 stdin JSON을 넣어 결정을 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
hook="$here/../plugin/hooks/protect-generated.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# 훅을 실행하고 결정(deny 또는 allow)을 출력한다. 출력이 없으면 allow다.
decide() { # 파일경로 [cwd]
  local out
  out="$(jq -n --arg f "$1" --arg cwd "${2:-/}" \
    '{session_id: "t", cwd: $cwd, hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: {file_path: $f}}' | "$hook")"
  if [ -z "$out" ]; then echo allow; else printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; fi
}
reason() { # 파일경로
  jq -n --arg f "$1" '{cwd: "/", tool_name: "Write", tool_input: {file_path: $f}}' | "$hook" \
    | jq -r '.hookSpecificOutput.permissionDecisionReason'
}
project() { # 디렉터리 generator
  mkdir -p "$1/.harness"
  jq -n --arg g "$2" '{schemaVersion: 1, generator: $g}' > "$1/.harness/project.json"
}

# --- Tuist 프로젝트 -----------------------------------------------------------
t="$work/tuist"
project "$t" tuist
assert_eq "tuist: 워크스페이스 파일은 막는다" "deny" "$(decide "$t/App.xcworkspace/contents.xcworkspacedata")"
assert_eq "tuist: 모듈 xcodeproj 안의 pbxproj는 막는다" "deny" "$(decide "$t/Modules/A/A.xcodeproj/project.pbxproj")"
assert_eq "tuist: 생성된 스킴도 막는다" "deny" "$(decide "$t/Modules/A/A.xcodeproj/xcshareddata/xcschemes/A.xcscheme")"
assert_eq "tuist: Derived 폴더는 막는다" "deny" "$(decide "$t/Modules/A/Derived/InfoPlists/A-Info.plist")"
assert_eq "tuist: 소스 파일은 허용" "allow" "$(decide "$t/Modules/A/Sources/A.swift")"
assert_eq "tuist: manifest는 허용" "allow" "$(decide "$t/Modules/A/Project.swift")"
assert_eq "tuist: 상대 경로는 cwd 기준으로 판단" "deny" "$(decide "App.xcworkspace/contents.xcworkspacedata" "$t")"
case "$(reason "$t/App.xcworkspace/contents.xcworkspacedata")" in
  *"manifest"*"build·test·unit-test"*) ok=yes ;;
  *) ok=no ;;
esac
assert_eq "tuist: 막는 이유에 고치는 방법(manifest, 스크립트)이 들어 있다" "yes" "$ok"

# --- xcodeproj 프로젝트 --------------------------------------------------------
x="$work/xcodeproj"
project "$x" xcodeproj
assert_eq "xcodeproj: pbxproj는 막는다" "deny" "$(decide "$x/App.xcodeproj/project.pbxproj")"
assert_eq "xcodeproj: 공유 스킴은 생성물이 아니라 허용" "allow" "$(decide "$x/App.xcodeproj/xcshareddata/xcschemes/App.xcscheme")"
assert_eq "xcodeproj: 소스 파일은 허용" "allow" "$(decide "$x/App/ContentView.swift")"

# --- 판단할 수 없으면 막지 않는다 -------------------------------------------------
assert_eq "설정 파일이 없는 프로젝트는 허용" "allow" "$(decide "$work/other/App.xcodeproj/project.pbxproj")"
assert_eq "깨진 JSON 입력은 허용" "" "$(printf 'not json' | "$hook")"
assert_eq "file_path가 없는 입력은 허용" "" "$(printf '{"tool_input":{}}' | "$hook")"

finish
