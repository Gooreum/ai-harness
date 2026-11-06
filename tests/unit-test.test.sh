#!/usr/bin/env bash
# test·unit-test가 쓰는 공용 함수와 unit-test의 실행 계획(--plan)을 가짜 입력으로 검사한다.
# xcodebuild는 부르지 않는다. 실제 테스트 실행은 시험장에서 확인한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
. "$here/../template/scripts/harness/ios.sh"
unit_test="$here/../template/scripts/harness/unit-test"
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

# --- unit-test --plan (Tuist 모듈 프로젝트) -----------------------------------------
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

plan() { (cd "$p" && "$unit_test" --plan "$@"); }
reset() { (cd "$p" && git checkout -q -- . && git clean -qfd -e .harness); }

assert_eq "plan: 바뀐 파일이 없으면 끝" "✓ unit-test · 바뀐 파일 없음" "$(plan)"

echo '// changed' >> "$p/Modules/FeatureA/Sources/A.swift"
assert_eq "plan: 모듈 소스가 바뀌면 그 모듈만 테스트" "$(printf '· unit-test 계획 · 바뀐 파일 1개\n  build App\n  test FeatureA (FeatureA)')" "$(plan)"
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

echo 'x' > "$p/Scripts.sh"
assert_eq "plan: 모듈 밖 파일만 바뀌면 빌드만" "2" "$(plan | wc -l | tr -d ' ')"
reset

echo '// changed' >> "$p/README.md"
mkdir -p "$p/docs" "$p/.maestro" && echo x > "$p/docs/a.md" && echo x > "$p/.maestro/a.yaml"
assert_eq "plan: 문서·시나리오만 바뀌면 빌드·테스트하지 않는다" "✓ unit-test · 코드 변경 없음 (문서·시나리오·지침만 바뀜)" "$(plan)"
echo '// changed' >> "$p/Modules/FeatureA/Sources/A.swift"
assert_eq "plan: 코드와 문서가 같이 바뀌면 코드만 센다" "· unit-test 계획 · 바뀐 파일 1개" "$(plan | sed -n 1p)"
reset

# 바뀐 모듈을 쓰는 모듈(manifest에 이름이 나오는 모듈)도 테스트한다
echo 'let deps = [.project(target: "CoreB", path: "../CoreB")]' >> "$p/Modules/FeatureA/Project.swift"
(cd "$p" && git -c user.name=t -c user.email=t@t commit -qam deps)
echo '// changed' >> "$p/Modules/CoreB/Sources/B.swift"
assert_eq "plan: 바뀐 모듈을 쓰는 모듈도 테스트" "$(printf '  test FeatureA (FeatureA)\n  건너뜀 (테스트 없음): CoreB')" "$(plan | sed -n '3,4p')"
reset
echo 'let deps = [.project(target: "FeatureA", path: "../Modules/FeatureA")]' >> "$p/App/Project.swift"
(cd "$p" && git -c user.name=t -c user.email=t@t commit -qam appdeps)
echo '// changed' >> "$p/Modules/CoreB/Sources/B.swift"
assert_eq "plan: 거꾸로 따라가 앱까지 넓힌다 (CoreB → FeatureA → 앱)" "  test 앱 (App: AppTests)" "$(plan | sed -n 3p)"
reset
echo '// manifest' > "$p/App/Project.swift"; echo '// manifest' > "$p/Modules/FeatureA/Project.swift"
(cd "$p" && git -c user.name=t -c user.email=t@t commit -qam undeps)

echo '// changed' >> "$p/Tuist/Helpers.swift"
assert_eq "plan: 생성 설정이 바뀌면 전체" "$(printf '  test 앱 (App: AppTests)\n  test FeatureA (FeatureA)\n  건너뜀 (테스트 없음): CoreB')" "$(plan | sed -n '3,5p')"
reset

assert_eq "plan: --all은 변경과 상관없이 전체" "· unit-test 계획 · 전체" "$(plan --all | sed -n 1p)"

(cd "$p" && git checkout -q -b feature && echo '// committed' >> Modules/FeatureA/Sources/A.swift && git -c user.name=t -c user.email=t@t commit -qam change)
assert_eq "plan: 커밋한 변경은 기본으로는 보지 않는다" "✓ unit-test · 바뀐 파일 없음" "$(plan)"
assert_eq "plan: --base로 브랜치의 모든 변경을 본다" "  test FeatureA (FeatureA)" "$(plan --base main | sed -n 3p)"

# 작업 중이면(task.json의 stage가 done이 아님) 작업을 시작한 커밋부터 본다
mkdir -p "$p/.harness/state"
git -C "$p" rev-parse main > "$p/.harness/state/task.base"
echo '{"stage":"verify"}' > "$p/.harness/state/task.json"
assert_eq "plan: 작업 중이면 작업 중에 커밋한 변경도 본다" "  test FeatureA (FeatureA)" "$(plan | sed -n 3p)"
echo '// old' > "$p/Modules/CoreB/Sources/Old.swift"; touch -t 202601010000 "$p/Modules/CoreB/Sources/Old.swift"
touch "$p/.harness/state/task.started"
assert_eq "plan: 작업 전부터 있던 추적 안 된 파일은 빼고 본다" "· unit-test 계획 · 바뀐 파일 1개" "$(plan | sed -n 1p)"
echo '{"stage":"done"}' > "$p/.harness/state/task.json"
assert_eq "plan: 작업이 끝났으면 커밋하지 않은 변경만 본다" "  건너뜀 (테스트 없음): CoreB" "$(plan | sed -n 3p)"
rm -rf "$p/.harness/state" "$p/Modules/CoreB/Sources/Old.swift"

# --- unit-test --plan (모듈 구조가 없는 xcodeproj 앱) --------------------------------
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

# 앱 테스트 스킴이 따로 있으면 빌드는 앱 스킴, 테스트는 테스트 스킴으로 돈다.
jq '.app.testScheme = "AppTests"' "$p/.harness/project.json" > "$p/.harness/tmp.json" \
  && mv "$p/.harness/tmp.json" "$p/.harness/project.json"
assert_eq "plan: app.testScheme이 있으면 빌드는 앱 스킴" "  build App" "$(plan | sed -n 2p)"
assert_eq "plan: app.testScheme이 있으면 앱 테스트는 그 스킴" "  test 앱 (AppTests: AppTests)" "$(plan | sed -n 3p)"

# --- 결과 파일 .harness/out/unit-test.json (checks.json의 run이 읽는다) ----------------
rm -f "$p/.harness/out/unit-test.json"
plan > /dev/null
assert_eq "result: --plan은 결과 파일을 남기지 않는다" "no" "$([ -f "$p/.harness/out/unit-test.json" ] && echo yes || echo no)"
(cd "$p" && git checkout -q -- App/App.swift)
assert_eq "result: 바뀐 파일이 없으면 통과로 남긴다" "true|바뀐 파일 없음" \
  "$( (cd "$p" && "$unit_test" > /dev/null) && jq -r '"\(.passed)|\(.summary)"' "$p/.harness/out/unit-test.json")"

# --- 돌린 테스트 수 (build·test는 가짜로 바꾼다) ------------------------------------
fake="$work/fake"
mkdir -p "$fake"
cp "$here/../template/scripts/harness/unit-test" "$here/../template/scripts/harness/lib.sh" "$here/../template/scripts/harness/ios.sh" "$fake/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fake/build"
printf '#!/usr/bin/env bash\necho "{\\"ran\\": $FAKE_RAN}" > "$HARNESS_ROOT/.harness/out/test.json"\n' > "$fake/test"
chmod +x "$fake/build" "$fake/test"
echo '// changed' >> "$p/App/App.swift"
run_fake() { (cd "$p" && FAKE_RAN="$1" "$fake/unit-test" > /dev/null) || true; jq -r "$2" "$p/.harness/out/unit-test.json"; }
assert_eq "tests: 테스트가 0개 돌면 요약 첫머리에 적는다" "true|테스트 0개 · 통과: 앱|0" "$(run_fake 0 '"\(.passed)|\(.summary)|\(.tests)"')"
assert_eq "tests: 돌린 수를 남긴다" "true|통과: 앱|7" "$(run_fake 7 '"\(.passed)|\(.summary)|\(.tests)"')"

finish
