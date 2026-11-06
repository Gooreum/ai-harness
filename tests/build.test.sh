#!/usr/bin/env bash
# build가 쓰는 공용 함수(lib.sh): 시뮬레이터 선택, 이슈 요약, 생성 필요 판단.
# xcodebuild 없이 가짜 입력으로 검사한다. 실제 빌드는 시험장에서 확인한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
. "$here/../template/scripts/harness/lib.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- pick_simulator ----------------------------------------------------------
simctl='{"devices":{
  "com.apple.CoreSimulator.SimRuntime.iOS-26-3":[{"name":"iPhone 17 Pro","udid":"OLD"},{"name":"iPhone 17","udid":"OLD-PLAIN"}],
  "com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{"name":"iPhone 17 Pro","udid":"NEW"}],
  "com.apple.CoreSimulator.SimRuntime.watchOS-11-0":[{"name":"iPhone 17 Pro","udid":"WATCH"}]}}'
assert_eq "simulator: latest는 가장 최신 런타임" "NEW" "$(printf '%s' "$simctl" | pick_simulator "iPhone 17 Pro" latest)"
assert_eq "simulator: OS 버전 지정" "OLD" "$(printf '%s' "$simctl" | pick_simulator "iPhone 17 Pro" 26.3)"
assert_eq "simulator: 주 버전만 지정" "NEW" "$(printf '%s' "$simctl" | pick_simulator "iPhone 17 Pro" 26)"
assert_eq "simulator: 없는 이름은 빈 값" "" "$(printf '%s' "$simctl" | pick_simulator "iPhone 99" latest)"

# --- pick_latest_iphone ----------------------------------------------------------
fb='{"devices":{
  "com.apple.CoreSimulator.SimRuntime.iOS-26-2":[{"name":"iPhone 16 Pro","udid":"OLD"}],
  "com.apple.CoreSimulator.SimRuntime.iOS-26-4":[{"name":"iPhone 17","udid":"P"},{"name":"iPhone 17 Pro Max","udid":"M"},{"name":"iPhone 17 Pro","udid":"PRO"},{"name":"iPad Pro","udid":"IPAD"}]}}'
assert_eq "latest: 최신 런타임의 번호가 가장 큰 Pro" "PRO iPhone 17 Pro" "$(printf '%s' "$fb" | pick_latest_iphone)"
assert_eq "latest: Pro가 없으면 첫 iPhone" "P iPhone 17" "$(printf '%s' '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-4":[{"name":"iPhone 17","udid":"P"}]}}' | pick_latest_iphone)"
assert_eq "latest: iPhone이 없으면 빈 값" "" "$(printf '%s' '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-4":[{"name":"iPad Pro","udid":"I"}]}}' | pick_latest_iphone)"

# --- pick_xcode -----------------------------------------------------------------
cands="/A/Developer 26.2"$'\n'"/B/Developer 26.4"$'\n'"/C/Developer 26.5.1"$'\n'
assert_eq "xcode: 선택된 SDK에 런타임이 있으면 그대로" "" "$(pick_xcode 26.2 "26.2"$'\n'"26.4" "$cands")"
assert_eq "xcode: 없으면 런타임이 있는 Xcode" "/B/Developer" "$(pick_xcode 26.2 26.4 "$cands")"
assert_eq "xcode: 여럿이면 SDK가 높은 쪽" "/C/Developer" "$(pick_xcode 26.2 "26.4"$'\n'"26.5" "$cands")"
assert_eq "xcode: 맞는 후보가 없으면 빈 값" "" "$(pick_xcode 26.2 27.0 "$cands")"

# --- format_issues -----------------------------------------------------------
root_dir="/Users/me/App"
korean_url="$(jq -rn --arg p "$root_dir/한글 폴더/B.swift" '"file://" + ($p | @uri)')"
results="$(jq -n --arg root "$root_dir" --arg korean "$korean_url" '{
  errorCount: 3, warningCount: 0, warnings: [],
  errors: [
    { issueType: "Swift Compiler Error", message: "Cannot find x in scope", targetName: "Feature",
      sourceURL: ("file://" + $root + "/Sources/A.swift#EndingColumnNumber=10&EndingLineNumber=4&StartingColumnNumber=9&StartingLineNumber=4") },
    { issueType: "Link Error", message: "Undefined symbol: _foo", targetName: "App" },
    { issueType: "Swift Compiler Error", message: "Type mismatch", targetName: "Feature",
      sourceURL: ($korean + "#StartingColumnNumber=0&StartingLineNumber=0") }
  ] }')"
formatted="$(printf '%s' "$results" | format_issues "$root_dir" errors 5)"
assert_eq "issues: 상대 경로와 1부터 시작하는 줄·열" "  Sources/A.swift:5:10: Cannot find x in scope" "$(printf '%s\n' "$formatted" | sed -n 1p)"
assert_eq "issues: 위치가 없으면 타깃 이름" "  App: Undefined symbol: _foo" "$(printf '%s\n' "$formatted" | sed -n 2p)"
assert_eq "issues: 인코딩된 한글·공백 경로를 푼다" "  한글 폴더/B.swift:1:1: Type mismatch" "$(printf '%s\n' "$formatted" | sed -n 3p)"
assert_eq "issues: 최대 개수 제한" "1" "$(printf '%s' "$results" | format_issues "$root_dir" errors 1 | wc -l | tr -d ' ')"

# --- harness_ensure_generated --------------------------------------------------
# generate·install 명령은 호출 횟수만 기록하는 가짜 명령으로 바꾼다.
p="$work/project"
mkdir -p "$p/.harness" "$p/Sources"
(cd "$p" && git init -q && echo 'let a = 1' > Sources/A.swift && echo 'let project = Project()' > Project.swift)
jq -n '{
  schemaVersion: 1, generator: "tuist",
  commands: { install: "echo i >> install-calls", generate: "mkdir -p App.xcworkspace && echo g >> generate-calls" },
  workspace: "App.xcworkspace", project: null,
  app: { scheme: "App" }, destination: { simulator: "iPhone 17 Pro", os: "latest" }, modules: null }' > "$p/.harness/project.json"
calls() { if [ -f "$p/$1" ]; then wc -l < "$p/$1" | tr -d ' '; else echo 0; fi; }

HARNESS_ROOT="$p"
harness_init
harness_ensure_generated
assert_eq "generate: 처음에는 실행" "1" "$(calls generate-calls)"
assert_eq "install: 처음에는 실행" "1" "$(calls install-calls)"
harness_ensure_generated
assert_eq "generate: 변화가 없으면 건너뛴다" "1" "$(calls generate-calls)"
assert_eq "generate: 건너뛰면 generated_now=0" "0" "$generated_now"

echo 'let a = 2' > "$p/Sources/A.swift"
harness_ensure_generated
assert_eq "generate: 소스 내용만 바뀌면 건너뛴다" "1" "$(calls generate-calls)"

echo 'let b = 1' > "$p/Sources/B.swift"
harness_ensure_generated
assert_eq "generate: 파일이 추가되면 다시 실행" "2" "$(calls generate-calls)"
assert_eq "generate: 실행하면 generated_now=1" "1" "$generated_now"

rm "$p/Sources/B.swift"
harness_ensure_generated
assert_eq "generate: 파일이 삭제되면 다시 실행" "3" "$(calls generate-calls)"

echo 'let project = Project(name: "Changed")' > "$p/Project.swift"
harness_ensure_generated
assert_eq "generate: manifest가 바뀌면 다시 실행" "4" "$(calls generate-calls)"
assert_eq "install: 의존성 선언이 그대로면 다시 실행하지 않는다" "1" "$(calls install-calls)"

harness_ensure_generated force
assert_eq "generate: force면 항상 실행" "5" "$(calls generate-calls)"

rm -rf "$p/App.xcworkspace"
harness_ensure_generated
assert_eq "generate: 생성물이 없으면 다시 실행" "6" "$(calls generate-calls)"

jq '.commands.generate = "echo boom; exit 3"' "$p/.harness/project.json" > "$work/c.json" && mv "$work/c.json" "$p/.harness/project.json"
if out="$(harness_ensure_generated force)"; then code=0; else code=$?; fi
assert_eq "generate: 실패하면 1을 반환" "1" "$code"
assert_eq "generate: 실패 요약 첫 줄" "✗ generate 실패 (echo boom; exit 3)" "$(printf '%s\n' "$out" | sed -n 1p)"

# --- install만 있는 프로젝트 (CocoaPods를 쓰는 xcodeproj) ----------------------------
p="$work/pods"
mkdir -p "$p/.harness"
(cd "$p" && git init -q && echo "pod 'A'" > Podfile)
jq -n '{ schemaVersion: 1, generator: "xcodeproj",
  commands: { install: "mkdir -p Pods && echo i >> install-calls", generate: null },
  workspace: "App.xcworkspace", project: "App.xcodeproj", app: { scheme: "App" }, modules: null }' > "$p/.harness/project.json"
HARNESS_ROOT="$p"
harness_init
harness_ensure_generated
assert_eq "install: generate가 없어도 실행" "1" "$(calls install-calls)"
harness_ensure_generated
assert_eq "install: 그대로면 건너뛴다" "1" "$(calls install-calls)"
echo "A (1.0)" > "$p/Podfile.lock"
harness_ensure_generated
assert_eq "install: Podfile.lock이 바뀌면 다시 실행" "2" "$(calls install-calls)"
rm -rf "$p/Pods"
harness_ensure_generated
assert_eq "install: Pods/가 없으면 다시 실행" "3" "$(calls install-calls)"

finish
