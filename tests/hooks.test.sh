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
# --- project.json의 generated (글롭) -------------------------------------------
g="$work/gen"
mkdir -p "$g/.harness"
echo '{"schemaVersion":2,"generated":["ios/*","android/*","src/gql/*.generated.ts"]}' > "$g/.harness/project.json"
assert_eq "generated: Expo prebuild의 ios/는 막는다" "deny" "$(decide "$g/ios/App/AppDelegate.swift")"
assert_eq "generated: 하위 폴더까지 막는다" "deny" "$(decide "$g/android/app/src/main/AndroidManifest.xml")"
assert_eq "generated: codegen 결과는 막는다" "deny" "$(decide "$g/src/gql/user.generated.ts")"
assert_eq "generated: 원본은 허용" "allow" "$(decide "$g/src/gql/user.graphql")"
assert_eq "generated: 목록에 없는 파일은 허용" "allow" "$(decide "$g/app/index.tsx")"
case "$(reason "$g/ios/App/AppDelegate.swift")" in
  *"generated: ios/*"*) ok=yes ;;
  *) ok=no ;;
esac
assert_eq "generated: 막는 이유에 걸린 글롭이 들어 있다" "yes" "$ok"

# Tuist처럼 저장소 안 여러 곳에 생기는 생성물. *는 /도 넘으므로 하위 모듈까지 막는다.
t="$work/tuist"
mkdir -p "$t/.harness"
echo '{"schemaVersion":2,"generated":["*.xcodeproj/*","*.xcworkspace/*","Derived/*","*/Derived/*"]}' > "$t/.harness/project.json"
assert_eq "generated: 모듈 xcodeproj 안의 pbxproj는 막는다" "deny" "$(decide "$t/Modules/A/A.xcodeproj/project.pbxproj")"
assert_eq "generated: Derived 폴더는 막는다" "deny" "$(decide "$t/Modules/A/Derived/InfoPlists/A-Info.plist")"
assert_eq "generated: 상대 경로는 cwd 기준으로 판단" "deny" "$(decide "App.xcworkspace/contents.xcworkspacedata" "$t")"
assert_eq "generated: manifest는 허용" "allow" "$(decide "$t/Modules/A/Project.swift")"

# 하네스는 플랫폼을 모른다. 예전 설정의 generator나 pbxproj만으로는 막지 않는다(ADR 0024).
x="$work/xcodeproj"
mkdir -p "$x/.harness"
echo '{"schemaVersion":2,"platforms":["ios"],"ios":{"generator":"tuist"}}' > "$x/.harness/project.json"
assert_eq "generator만 있으면 막지 않는다" "allow" "$(decide "$x/App.xcworkspace/contents.xcworkspacedata")"
assert_eq "pbxproj도 generated에 없으면 막지 않는다" "allow" "$(decide "$x/App.xcodeproj/project.pbxproj")"

# --- 판단할 수 없으면 막지 않는다 -------------------------------------------------
assert_eq "설정 파일이 없는 프로젝트는 허용" "allow" "$(decide "$work/other/App.xcodeproj/project.pbxproj")"
assert_eq "깨진 JSON 입력은 허용" "" "$(printf 'not json' | "$hook")"
assert_eq "file_path가 없는 입력은 허용" "" "$(printf '{"tool_input":{}}' | "$hook")"

finish
