#!/usr/bin/env bash
# detect: 임시 디렉터리에 가짜 프로젝트를 만들고, 오프라인 모드로 초안을 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
detect="$here/../scripts/detect"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export HARNESS_OFFLINE=1

run_detect() { "$detect" "$@" 2>/dev/null; }
field() { printf '%s' "$1" | jq -c ".ios | $2"; }

# 최소 pbxproj: 앱·단위 테스트·UI 테스트 타깃. $2는 앱의 번들 ID 값(따옴표 포함 가능).
write_pbxproj() {
  mkdir -p "$1"
  cat > "$1/project.pbxproj" <<EOF
// !\$*UTF8*\$!
{
	archiveVersion = 1;
	objectVersion = 77;
	objects = {
		T1 = {isa = PBXNativeTarget; buildConfigurationList = L1; name = Sample; productType = "com.apple.product-type.application"; };
		T2 = {isa = PBXNativeTarget; buildConfigurationList = L2; name = SampleTests; productType = "com.apple.product-type.bundle.unit-test"; };
		T3 = {isa = PBXNativeTarget; buildConfigurationList = L3; name = SampleUITests; productType = "com.apple.product-type.bundle.ui-testing"; };
		L1 = {isa = XCConfigurationList; buildConfigurations = (C1, ); };
		L2 = {isa = XCConfigurationList; buildConfigurations = (C2, ); };
		L3 = {isa = XCConfigurationList; buildConfigurations = (C3, ); };
		C1 = {isa = XCBuildConfiguration; name = Debug; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = $2; }; };
		C2 = {isa = XCBuildConfiguration; name = Debug; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.example.SampleTests; }; };
		C3 = {isa = XCBuildConfiguration; name = Debug; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.example.SampleUITests; }; };
	};
	rootObject = T1;
}
EOF
}

# --- Tuist 모듈 프로젝트 (생성 전) ---------------------------------------------
p="$work/tuist"
mkdir -p "$p/Tuist" "$p/App" "$p/Modules/Feature/FeatureA/Tests" "$p/Modules/Core/CoreB"
echo 'let tuist = Tuist(project: .tuist())' > "$p/Tuist.swift"
printf 'let workspace = Workspace(\n    name: "Sample",\n    projects: ["App"]\n)\n' > "$p/Workspace.swift"
echo '// dependencies' > "$p/Tuist/Package.swift"
printf 'generate:\n\ttuist generate\n' > "$p/Makefile"
echo 'let project = Project(name: "Sample", targets: [.target(name: "Sample", product: .app)])' > "$p/App/Project.swift"
echo 'let project = Project.makeFeature(name: "FeatureA")' > "$p/Modules/Feature/FeatureA/Project.swift"
echo 'let project = Project.makeModule(name: "CoreB")' > "$p/Modules/Core/CoreB/Project.swift"

out="$(run_detect "$p")"
assert_eq "tuist: generator" '"tuist"' "$(field "$out" .generator)"
assert_eq "tuist: Makefile의 generate 타깃을 쓴다" '"make generate"' "$(field "$out" .commands.generate)"
assert_eq "tuist: Makefile에 install이 없으면 tuist install" '"tuist install"' "$(field "$out" .commands.install)"
assert_eq "tuist: Workspace.swift의 이름" '"Sample.xcworkspace"' "$(field "$out" .workspace)"
assert_eq "tuist: project는 null" 'null' "$(field "$out" .project)"
assert_eq "tuist: 앱 경로" '"App"' "$(field "$out" .app.path)"
assert_eq "tuist: 생성 전에는 앱 디렉터리 이름으로 스킴 추정" '"App"' "$(field "$out" .app.scheme)"
assert_eq "tuist: 생성 전에는 번들 ID 없음" 'null' "$(field "$out" .app.bundleId)"
assert_eq "tuist: 모듈 규칙" '{"manifest":"Project.swift","scheme":"{dir}","testsDir":"Tests"}' "$(field "$out" .modules)"
assert_eq "tuist: 시뮬레이터는 적지 않는다" 'null' "$(field "$out" .destination)"

# --- Tuist (Tuist/Config.swift + Makefile install) ----------------------------
p="$work/tuist-config"
mkdir -p "$p/Tuist" "$p/Projects/App"
echo 'let config = Config()' > "$p/Tuist/Config.swift"
printf 'let workspace = Workspace(\n    name: "BigWorkspace",\n    projects: []\n)\n' > "$p/Workspace.swift"
printf 'install:\n\ttuist install\n\ngenerate:\n\tTUIST_ROOT_DIR=${PWD} tuist generate\n' > "$p/Makefile"
echo 'let project = Project.make(name: env.name) { Target.make(name: env.name, product: .app) }' > "$p/Projects/App/Project.swift"

out="$(run_detect "$p")"
assert_eq "tuist-config: generator" '"tuist"' "$(field "$out" .generator)"
assert_eq "tuist-config: Makefile의 install 타깃을 쓴다" '"make install"' "$(field "$out" .commands.install)"
assert_eq "tuist-config: 워크스페이스" '"BigWorkspace.xcworkspace"' "$(field "$out" .workspace)"
assert_eq "tuist-config: 모듈이 없으면 null" 'null' "$(field "$out" .modules)"

# --- xcodeproj 단일 앱 --------------------------------------------------------
p="$work/xcodeproj"
write_pbxproj "$p/Sample.xcodeproj" "com.example.Sample"

out="$(run_detect "$p")"
assert_eq "xcodeproj: generator" '"xcodeproj"' "$(field "$out" .generator)"
assert_eq "xcodeproj: commands 없음" '{"install":null,"generate":null}' "$(field "$out" .commands)"
assert_eq "xcodeproj: project" '"Sample.xcodeproj"' "$(field "$out" .project)"
assert_eq "xcodeproj: 앱 스킴은 앱 타깃 이름" '"Sample"' "$(field "$out" .app.scheme)"
assert_eq "xcodeproj: 번들 ID" '"com.example.Sample"' "$(field "$out" .app.bundleId)"
assert_eq "xcodeproj: UI 테스트는 빼고 단위 테스트만" '["SampleTests"]' "$(field "$out" .app.unitTestTargets)"
assert_eq "xcodeproj: 모듈 없음" 'null' "$(field "$out" .modules)"
assert_eq "xcodeproj: 스킴 파일이 없으면 테스트 스킴 없음" 'null' "$(field "$out" .app.testScheme)"
echo "pod 'A'" > "$p/Podfile"
assert_eq "xcodeproj: Podfile이 있으면 pod install" '"pod install"' "$(field "$(run_detect "$p")" .commands.install)"
rm "$p/Podfile"

# --- 앱 테스트 스킴 ---------------------------------------------------------------
# 공유 스킴 파일. $1: 프로젝트, $2: 스킴 이름, $3: 테스트 액션 구성, $4: 테스트 액션에 넣을 타깃
write_scheme() {
  local dir="$1/Sample.xcodeproj/xcshareddata/xcschemes"
  mkdir -p "$dir"
  cat > "$dir/$2.xcscheme" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Scheme>
   <BuildAction>
      <BuildActionEntries>
         <BuildableReference BlueprintName = "Sample"/>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "$3">
      <Testables>
         <TestableReference>
            <BuildableReference
               BlueprintName = "$4"/>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "$3">
   </LaunchAction>
</Scheme>
EOF
}

p="$work/test-scheme-debug"
write_pbxproj "$p/Sample.xcodeproj" "com.example.Sample"
write_scheme "$p" "Sample" "Debug" "SampleTests"
out="$(run_detect "$p")"
assert_eq "test-scheme: 앱 스킴 테스트가 Debug면 따로 두지 않는다" 'null' "$(field "$out" .app.testScheme)"

p="$work/test-scheme-release"
write_pbxproj "$p/Sample.xcodeproj" "com.example.Sample"
write_scheme "$p" "Sample" "Release" "SampleTests"
write_scheme "$p" "Sample Dev" "Debug" "SampleTests"
write_scheme "$p" "SampleTests" "Debug" "SampleTests"
out="$(run_detect "$p")"
assert_eq "test-scheme: Release면 테스트 타깃 이름의 Debug 스킴을 먼저 고른다" '"SampleTests"' "$(field "$out" .app.testScheme)"

rm "$p/Sample.xcodeproj/xcshareddata/xcschemes/SampleTests.xcscheme"
out="$(run_detect "$p")"
assert_eq "test-scheme: 이름이 다른 Debug 스킴도 테스트 타깃을 담으면 고른다(공백 이름)" '"Sample Dev"' "$(field "$out" .app.testScheme)"

write_scheme "$p" "Sample Dev" "Debug" "OtherTests"
out="$(run_detect "$p")"
assert_eq "test-scheme: 단위 테스트 타깃이 없는 스킴은 고르지 않는다" 'null' "$(field "$out" .app.testScheme)"
"$detect" "$p" > /dev/null 2> "$work/err"
if grep -q "app.testScheme을 직접 채우세요" "$work/err"; then warned=1; else warned=0; fi
assert_eq "test-scheme: 찾지 못하면 경고한다" "1" "$warned"

# --- 번들 ID가 빌드 설정 변수일 때 (오프라인에서는 확인 불가 → null) ------------
p="$work/xcodeproj-var"
write_pbxproj "$p/Sample.xcodeproj" '"$(APP_BUNDLE_ID)"'

out="$(run_detect "$p")"
assert_eq "xcodeproj-var: 변수 번들 ID는 null" 'null' "$(field "$out" .app.bundleId)"

# --- XcodeGen ---------------------------------------------------------------
p="$work/xcodegen"
mkdir -p "$p"
printf 'name: Sample\ntargets:\n  Sample:\n    type: application\n' > "$p/project.yml"

out="$(run_detect "$p")"
assert_eq "xcodegen: generator" '"xcodegen"' "$(field "$out" .generator)"
assert_eq "xcodegen: generate" '"xcodegen generate"' "$(field "$out" .commands.generate)"
assert_eq "xcodegen: project" '"Sample.xcodeproj"' "$(field "$out" .project)"

# --- Tuist: 이름은 name: 인자에서만 읽는다 -----------------------------------------
p="$work/tuist-name"
mkdir -p "$p/Tuist"
echo 'let tuist = Tuist(project: .tuist())' > "$p/Tuist.swift"
printf 'let workspace = Workspace(\n    ㅁname: "Wrong1",\n    my_name: "Wrong2",\n    name: "Right",\n    projects: []\n)\n' > "$p/Workspace.swift"

out="$(run_detect "$p")"
assert_eq "tuist-name: ㅁname·my_name은 건너뛰고 name: 값을 쓴다" '"Right.xcworkspace"' "$(field "$out" .workspace)"

# --- Tuist: 루트 Project.swift 하나에 앱이 있고 이름이 상수인 경우 (IntervalTimer) ------
# Project( 앞의 .debug(name: "Debug")를 이름으로 잡으면 안 된다.
p="$work/tuist-root-app"
mkdir -p "$p/Tuist"
echo 'let config = Config()' > "$p/Tuist.swift"
cat > "$p/Project.swift" <<'EOF'
let projectName = "Timer"
let configs: [Configuration] = [.debug(name: "Debug"), .release(name: "Release")]
let project = Project(
    name: projectName,
    settings: .settings(configurations: [.debug(name: "Debug")]),
    targets: [
        .target(name: projectName, destinations: .iOS, product: .app, bundleId: "com.example.timer")
    ]
)
EOF

out="$(run_detect "$p")"
assert_eq "tuist-root-app: Project( 호출의 name 상수를 풀어 쓴다" '"Timer.xcworkspace"' "$(field "$out" .workspace)"
assert_eq "tuist-root-app: 앱 경로는 루트" '"."' "$(field "$out" .app.path)"
assert_eq "tuist-root-app: 생성 전 스킴은 프로젝트 이름으로 추정" '"Timer"' "$(field "$out" .app.scheme)"

# --- xcodebuild -list의 스킴 목록 (가짜 xcodebuild로 온라인 경로 확인) ----------------
# 가짜 xcodebuild는 -list에만 FAKE_SCHEMES를 스킴 목록으로 돌려주고, 나머지 호출은 실패한다.
bin="$work/bin"
mkdir -p "$bin"
cat > "$bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *" -list "*) printf '{"project":{"name":"Sample","schemes":%s}}\n' "${FAKE_SCHEMES:-[]}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$bin/xcodebuild"

p="$work/xcodeproj-online"
write_pbxproj "$p/Sample.xcodeproj" "com.example.Sample"

out="$(FAKE_SCHEMES='[]' PATH="$bin:$PATH" HARNESS_OFFLINE=0 "$detect" "$p" 2> "$work/err")"
assert_eq "schemes-empty: 빈 목록은 확인 못 한 것으로 보고 앱 타깃 이름으로 추정" '"Sample"' "$(field "$out" .app.scheme)"
if grep -q "스킴을 하나도 돌려주지 않았습니다" "$work/err"; then warned=1; else warned=0; fi
assert_eq "schemes-empty: 빈 목록을 경고한다" "1" "$warned"

out="$(FAKE_SCHEMES='["Other"]' PATH="$bin:$PATH" HARNESS_OFFLINE=0 "$detect" "$p" 2> /dev/null)"
assert_eq "schemes-other: 목록에 앱 스킴 후보가 없으면 null" 'null' "$(field "$out" .app.scheme)"

# 생성된 Tuist 프로젝트: 스킴이 없는 모듈이 여럿이면 모두 구분해서 알린다.
p="$work/tuist"
mkdir -p "$p/Sample.xcworkspace"
FAKE_SCHEMES='["App"]' PATH="$bin:$PATH" HARNESS_OFFLINE=0 "$detect" "$p" > /dev/null 2> "$work/err"
assert_eq "modules-no-scheme: 스킴 없는 모듈을 \", \"로 나열" \
  "detect: 경고: 디렉터리 이름과 같은 스킴이 없는 모듈: Modules/Core/CoreB, Modules/Feature/FeatureA — modules.scheme 규칙을 확인하세요" \
  "$(grep '스킴이 없는 모듈' "$work/err")"

# --- 묶음 ---------------------------------------------------------------------
p="$work/empty"
mkdir -p "$p"
echo '{}' > "$p/package.json"
if out="$("$detect" "$p" 2> "$work/err")"; then code=0; else code=$?; fi
assert_eq "empty: Xcode 프로젝트가 없어도 초안을 만든다" "0" "$code"
assert_eq "empty: 묶음 없음" '{"schemaVersion":2,"platforms":[]}' "$(printf '%s' "$out" | jq -c .)"
assert_eq "empty: 묶음이 없는 플랫폼을 알린다" "1" "$(grep -c 'package.json 파일이 있지만' "$work/err")"
p="$work/xcodeproj"
assert_eq "platforms: Xcode 프로젝트면 ios" '["ios"]' "$(run_detect "$p" 2> /dev/null | jq -c .platforms)"

p="$work/spmlib"
mkdir -p "$p/Sources/Lib" && echo '// swift-tools-version:5.9' > "$p/Package.swift"
assert_eq "spm: 앱 없는 Swift 패키지는 묶음 없이 공통 파일만" '{"schemaVersion":2,"platforms":[]}' "$("$detect" "$p" 2> "$work/err" | jq -c .)"
assert_eq "spm: setup에서 swift test로 정하라고 알린다" "1" "$(grep -c 'swift test' "$work/err")"

# --- --write / --force --------------------------------------------------------
p="$work/xcodeproj"
run_detect --write "$p" >/dev/null
assert_eq "write: 파일 생성" '"xcodeproj"' "$(jq -c .ios.generator "$p/.harness/project.json")"
if run_detect --write "$p" >/dev/null; then code=0; else code=$?; fi
assert_eq "write: 이미 있으면 --force 없이 실패" "1" "$code"
if run_detect --write --force "$p" >/dev/null; then code=0; else code=$?; fi
assert_eq "write: --force면 덮어쓴다" "0" "$code"

finish
