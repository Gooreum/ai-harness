#!/usr/bin/env bash
# test·verify가 쓰는 공용 함수와 verify의 실행 계획(--plan)을 가짜 입력으로 검사한다.
# xcodebuild는 부르지 않는다. 실제 테스트 실행은 시험장에서 확인한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
. "$here/../template/scripts/harness/lib.sh"
verify="$here/../template/scripts/harness/verify"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- failed_test_messages / format_test_failures --------------------------------
tree='{"testNodes":[{"name":"Plan","nodeType":"Test Plan","result":"Failed","children":[
  {"name":"FooTests","nodeType":"Unit test bundle","result":"Failed","children":[
    {"name":"FooTests","nodeType":"Test Suite","result":"Failed","children":[
      {"name":"test_a()","nodeIdentifier":"FooTests/test_a()","nodeType":"Test Case","result":"Failed","children":[
        {"name":"FooTests.swift:12: XCTAssertEqual failed: (\"1\") is not equal to (\"2\")","nodeType":"Failure Message"}]},
      {"name":"test_b()","nodeIdentifier":"FooTests/test_b()","nodeType":"Test Case","result":"Failed"},
      {"name":"test_c()","nodeIdentifier":"FooTests/test_c()","nodeType":"Test Case","result":"Passed"}]}]}]}]}'
messages="$(printf '%s' "$tree" | failed_test_messages 5)"
assert_eq "failed: 위치가 있는 실패" "FooTests/test_a()	FooTests.swift:12: XCTAssertEqual failed: (\"1\") is not equal to (\"2\")" "$(printf '%s\n' "$messages" | sed -n 1p)"
assert_eq "failed: 메시지가 없는 실패도 테스트 ID는 남긴다" "FooTests/test_b()	" "$(printf '%s\n' "$messages" | sed -n 2p)"
assert_eq "failed: 통과한 테스트는 빼고 실패만" "2" "$(printf '%s\n' "$messages" | wc -l | tr -d ' ')"
assert_eq "failed: 최대 개수 제한" "1" "$(printf '%s' "$tree" | failed_test_messages 1 | wc -l | tr -d ' ')"

summary='{"testFailures":[{"testName":"test_x()","testIdentifierString":"BarTests/test_x()","failureText":"Crash: boom\nstack","targetName":"BarTests","testIdentifier":1}]}'
assert_eq "summary: 위치가 없을 때 대체 출력은 첫 줄만" "  BarTests/test_x(): Crash: boom" "$(printf '%s' "$summary" | format_test_failures 5)"

issue='{"errors":[{"issueType":"Error","message":"Testing cancelled because the build failed."}]}'
assert_eq "issues: 타깃 이름이 없으면 메시지만" "  Testing cancelled because the build failed." "$(printf '%s' "$issue" | format_issues /x errors 5)"

# --- harness_derived_data_path ------------------------------------------------
dd="$(harness_derived_data_path /Users/me/Desktop/App-slot)"
case "$dd" in
  "$HOME/Library/Developer/Xcode/DerivedData/App-slot-harness-"*) ok=yes ;;
  *) ok="$dd" ;;
esac
assert_eq "derivedData: 프로젝트 밖(Xcode DerivedData 폴더)에 워크트리 이름으로 둔다" "yes" "$ok"
assert_eq "derivedData: 워크트리 경로가 다르면 위치도 다르다" "no" \
  "$([ "$dd" = "$(harness_derived_data_path /Users/me/Other/App-slot)" ] && echo yes || echo no)"
assert_eq "derivedData: HARNESS_DERIVED_DATA로 바꿀 수 있다" "/tmp/dd" "$(HARNESS_DERIVED_DATA=/tmp/dd harness_derived_data_path /x)"

# --- module_has_tests ---------------------------------------------------------
root="$work/modules"
mkdir -p "$root/WithScheme/WithScheme.xcodeproj/xcshareddata/xcschemes" \
         "$root/NoTestables/NoTestables.xcodeproj/xcshareddata/xcschemes" "$root/NoTestables/Tests" \
         "$root/FolderOnly/Tests" "$root/Nothing"
echo '<TestAction><Testables><TestableReference skipped="NO"></TestableReference></Testables></TestAction>' \
  > "$root/WithScheme/WithScheme.xcodeproj/xcshareddata/xcschemes/WithScheme.xcscheme"
echo '<TestAction><Testables></Testables></TestAction>' \
  > "$root/NoTestables/NoTestables.xcodeproj/xcshareddata/xcschemes/NoTestables.xcscheme"
has() { if module_has_tests "$1" "$1" Tests; then echo yes; else echo no; fi; }
assert_eq "tests: 스킴에 테스트 대상이 있으면 있음" "yes" "$(has WithScheme)"
assert_eq "tests: Tests 폴더가 있어도 스킴에 테스트 대상이 없으면 없음" "no" "$(has NoTestables)"
assert_eq "tests: 스킴 파일이 없으면 Tests 폴더로 판단" "yes" "$(has FolderOnly)"
assert_eq "tests: 둘 다 없으면 없음" "no" "$(has Nothing)"

# --- verify --plan (Tuist 모듈 프로젝트) -----------------------------------------
p="$work/tuist"
mkdir -p "$p/.harness" "$p/App/Sources" "$p/Tuist" \
         "$p/Modules/FeatureA/Sources" "$p/Modules/FeatureA/Tests" \
         "$p/Modules/CoreB/Sources" "$p/Modules/CoreB/Tests"
for f in App/Project.swift Modules/FeatureA/Project.swift Modules/CoreB/Project.swift Workspace.swift Tuist/Helpers.swift; do
  echo '// manifest' > "$p/$f"
done
# Tests 폴더에도 파일을 둔다. 빈 폴더는 git이 추적하지 않아 reset 때 지워진다.
for f in App/Sources/App.swift Modules/FeatureA/Sources/A.swift Modules/FeatureA/Tests/ATests.swift \
         Modules/CoreB/Sources/B.swift Modules/CoreB/Tests/Keep.swift README.md; do
  echo '// source' > "$p/$f"
done
# CoreB는 Tests 폴더만 있고 테스트 타깃이 없는 모듈이다.
mkdir -p "$p/Modules/CoreB/CoreB.xcodeproj/xcshareddata/xcschemes"
echo '<TestAction><Testables></Testables></TestAction>' > "$p/Modules/CoreB/CoreB.xcodeproj/xcshareddata/xcschemes/CoreB.xcscheme"
jq -n '{
  schemaVersion: 1, generator: "tuist", commands: { install: null, generate: null },
  workspace: "App.xcworkspace", project: null,
  app: { scheme: "App", path: "App", bundleId: null, unitTestTargets: ["AppTests"] },
  destination: { simulator: "iPhone 17 Pro", os: "latest" },
  modules: { manifest: "Project.swift", scheme: "{dir}", testsDir: "Tests" } }' > "$p/.harness/project.json"
(cd "$p" && git init -q -b main && printf '*.xcodeproj\n' > .gitignore && git add -A && git -c user.name=t -c user.email=t@t commit -qm init)

plan() { (cd "$p" && "$verify" --plan "$@"); }
reset() { (cd "$p" && git checkout -q -- . && git clean -qfd -e .harness); }

assert_eq "plan: 바뀐 파일이 없으면 끝" "✓ verify · 바뀐 파일 없음" "$(plan)"

echo '// changed' >> "$p/Modules/FeatureA/Sources/A.swift"
assert_eq "plan: 모듈 소스가 바뀌면 그 모듈만 테스트" "$(printf '· verify 계획 · 바뀐 파일 1개\n  build App\n  test FeatureA (FeatureA)')" "$(plan)"
reset

echo '// new' > "$p/Modules/FeatureA/Sources/New.swift"
assert_eq "plan: 새 파일도 바뀐 파일로 본다" "  test FeatureA (FeatureA)" "$(plan | sed -n 3p)"
reset

echo '// changed' >> "$p/App/Sources/App.swift"
assert_eq "plan: 앱이 바뀌면 앱 단위 테스트" "  test 앱 (App: AppTests)" "$(plan | sed -n 3p)"
reset

echo '// changed' >> "$p/Modules/CoreB/Sources/B.swift"
assert_eq "plan: 테스트 타깃이 없는 모듈은 건너뛴다" "  건너뜀 (테스트 없음): CoreB" "$(plan | sed -n 3p)"
reset

echo '// changed' >> "$p/README.md"
assert_eq "plan: 모듈 밖 파일만 바뀌면 빌드만" "2" "$(plan | wc -l | tr -d ' ')"
reset

echo '// changed' >> "$p/Tuist/Helpers.swift"
assert_eq "plan: 생성 설정이 바뀌면 전체" "$(printf '  test 앱 (App: AppTests)\n  test FeatureA (FeatureA)\n  건너뜀 (테스트 없음): CoreB')" "$(plan | sed -n '3,5p')"
reset

assert_eq "plan: --all은 변경과 상관없이 전체" "· verify 계획 · 전체" "$(plan --all | sed -n 1p)"

(cd "$p" && git checkout -q -b feature && echo '// committed' >> Modules/FeatureA/Sources/A.swift && git -c user.name=t -c user.email=t@t commit -qam change)
assert_eq "plan: 커밋한 변경은 기본으로는 보지 않는다" "✓ verify · 바뀐 파일 없음" "$(plan)"
assert_eq "plan: --base로 브랜치의 모든 변경을 본다" "  test FeatureA (FeatureA)" "$(plan --base main | sed -n 3p)"

# --- verify --plan (모듈 구조가 없는 xcodeproj 앱) --------------------------------
p="$work/xcodeproj"
mkdir -p "$p/.harness" "$p/App"
echo '// source' > "$p/App/App.swift"
jq -n '{
  schemaVersion: 1, generator: "xcodeproj", commands: { install: null, generate: null },
  workspace: null, project: "App.xcodeproj",
  app: { scheme: "App", path: null, bundleId: null, unitTestTargets: ["AppTests"] },
  destination: { simulator: "iPhone 17 Pro", os: "latest" }, modules: null }' > "$p/.harness/project.json"
(cd "$p" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm init)
echo '// changed' >> "$p/App/App.swift"
assert_eq "plan: 모듈 구조가 없으면 모든 변경을 앱 변경으로 본다" "  test 앱 (App: AppTests)" "$(plan | sed -n 3p)"

finish
