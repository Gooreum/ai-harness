#!/usr/bin/env bash
# lint의 규칙 종류 format(swift-format)·dependency(tuist graph)를 가짜 프로젝트로 검사한다.
# swift-format이 없으면 format 실행 부분은 건너뛴다. tuist는 가짜 명령으로 바꿔 쓴다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
. "$here/../template/scripts/harness/lib.sh"
lint="$here/../template/scripts/harness/lint"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

problem() { (conventions_check "$1" 2>&1 >/dev/null && echo ok) | sed 's/^harness: //' || true; }
conv() { printf '%s' "$2" > "$work/$1.json"; echo "$work/$1.json"; }

# --- conventions_check --------------------------------------------------------
assert_eq "check: dependency 규칙" "ok" "$(problem "$(conv d1 '{"schemaVersion":1,"rules":[
  {"id":"dep.a","kind":"dependency","description":"d","severity":"error","from":"Feature*","forbid":["Feature*"]}]}')")"
assert_eq "check: format 규칙" "ok" "$(problem "$(conv f1 '{"schemaVersion":1,"rules":[
  {"id":"fmt.a","kind":"format","description":"d","severity":"info","formatRule":"LineLength","formatOptions":{"lineLength":120}}]}')")"
assert_eq "check: 모르는 kind" ".harness/conventions.json: rules[0]: a: kind는 pattern·dependency·format 중 하나입니다" \
  "$(problem "$(conv k '{"schemaVersion":1,"rules":[{"id":"a","kind":"layer","description":"d","severity":"info"}]}')")"
assert_eq "check: dependency는 from이 필요" ".harness/conventions.json: rules[0]: a: from(모듈 이름 패턴)이 필요합니다" \
  "$(problem "$(conv d2 '{"schemaVersion":1,"rules":[{"id":"a","kind":"dependency","description":"d","severity":"info","forbid":["X"]}]}')")"
assert_eq "check: dependency는 forbid 배열이 필요" ".harness/conventions.json: rules[0]: a: forbid(금지할 모듈 이름 패턴 배열)가 필요합니다" \
  "$(problem "$(conv d3 '{"schemaVersion":1,"rules":[{"id":"a","kind":"dependency","description":"d","severity":"info","from":"A","forbid":"B"}]}')")"
assert_eq "check: format은 formatRule이 필요" ".harness/conventions.json: rules[0]: a: formatRule(swift-format 규칙 이름)이 필요합니다" \
  "$(problem "$(conv f2 '{"schemaVersion":1,"rules":[{"id":"a","kind":"format","description":"d","severity":"info"}]}')")"
assert_eq "check: 같은 formatRule 두 번" ".harness/conventions.json: formatRule이 겹칩니다: LineLength" \
  "$(problem "$(conv f3 '{"schemaVersion":1,"rules":[
    {"id":"a","kind":"format","description":"d","severity":"info","formatRule":"LineLength"},
    {"id":"b","kind":"format","description":"d","severity":"info","formatRule":"LineLength"}]}')")"

# --- 종류별 변환 ----------------------------------------------------------------
mixed="$(conv m '{"schemaVersion":1,"rules":[
  {"id":"p","description":"패턴","severity":"error","regex":"x"},
  {"id":"f","kind":"format","description":"이름은 lowerCamelCase","severity":"warning","formatRule":"AlwaysUseLowerCamelCase"},
  {"id":"l","kind":"format","description":"줄은 120자까지","severity":"info","formatRule":"LineLength","formatOptions":{"lineLength":120}},
  {"id":"dep","kind":"dependency","description":"Feature끼리 의존하지 않는다","severity":"error","from":"Feature*","forbid":["Feature*","Firebase*"]}]}')"
assert_eq "swiftlint: pattern 규칙만 옮긴다" '["p"]' "$(conventions_to_swiftlint "$mixed" | jq -c '.custom_rules | keys')"
assert_eq "has_kind: 있는 종류" "yes" "$(conventions_has_kind "$mixed" dependency && echo yes)"
assert_eq "has_kind: 없는 종류" "no" "$(conventions_has_kind "$(conv po '{"schemaVersion":1,"rules":[{"id":"p","description":"d","severity":"info","regex":"x"}]}')" format && echo yes || echo no)"

echo '{"lineLength":100,"indentation":{"spaces":2},"rules":{"AlwaysUseLowerCamelCase":true,"NeverForceUnwrap":true,"OrderedImports":true}}' > "$work/base.json"
sf="$(conventions_to_swiftformat "$mixed" "$work/base.json")"
assert_eq "swift-format: 고른 규칙만 켠다" '{"AlwaysUseLowerCamelCase":true,"NeverForceUnwrap":false,"OrderedImports":false}' \
  "$(printf '%s' "$sf" | jq -c .rules)"
assert_eq "swift-format: formatOptions를 덮는다" "120 2" "$(printf '%s' "$sf" | jq -r '"\(.lineLength) \(.indentation.spaces)"')"
bad="$(conv fb '{"schemaVersion":1,"rules":[{"id":"a","kind":"format","description":"d","severity":"info","formatRule":"NoSuchRule"}]}')"
assert_eq "swift-format: 없는 규칙 이름은 실패하고 이름을 알린다" "NoSuchRule 1" \
  "$( (conventions_to_swiftformat "$bad" "$work/base.json" 2>&1 >/dev/null; echo $?) | tr '\n' ' ' | sed 's/ $//')"

mkdir -p "$work/r"
cat > "$work/sf.txt" <<EOF
$work/r/A.swift:3:1: warning: [Indentation] unindent by 4 spaces
$work/r/A.swift:4:10: warning: [AlwaysUseLowerCamelCase] rename the function 'foo_bar' using lowerCamelCase
$work/r/B.swift:1:121: warning: [LineLength] line is too long
EOF
v="$(swiftformat_violations "$mixed" "$work/sf.txt" "$work/r")"
assert_eq "swift-format 위반: 고른 규칙만, 경로는 루트 기준" "f A.swift 4 5|l B.swift 1 1" \
  "$(printf '%s' "$v" | jq -r 'map("\(.rule) \(.file) \(.line) \(.penalty)") | join("|")')"
assert_eq "swift-format 위반: 설명 뒤에 도구 메시지" "이름은 lowerCamelCase (rename the function 'foo_bar' using lowerCamelCase)" \
  "$(printf '%s' "$v" | jq -r '.[0].message')"

cat > "$work/graph.dot" <<'EOF'
digraph {
  FeatureTimer [fillcolor=darkgoldenrod1 shape=cylinder style=filled]
  FeatureTimer -> Services
  FeatureTimer -> FeatureHistory
  FeatureHistory -> "Firebase-Core"
  Services -> FirebaseAnalytics
  IntervalTimer -> FeatureTimer
}
EOF
printf 'let p = Project(targets: [\n  .target(name: "App", dependencies: [.target(name: "FeatureTimer")]),\n  .target(name: "Dep", dependencies: [\n    .target(name: "FeatureTimer")]),\n  .target(\n    name: "FeatureTimer",\n  ),\n])\n' > "$work/r/Project.swift"
v="$(dependency_violations "$mixed" "$work/graph.dot" "$work/r")"
assert_eq "dependency: from 패턴의 직접 의존만, 금지 패턴에 맞는 것" "FeatureTimer → FeatureHistory|FeatureHistory → Firebase-Core" \
  "$(printf '%s' "$v" | jq -r 'map(.message | capture("\\((?<e>.*)\\)$").e) | join("|")')"
assert_eq "dependency: 위치는 from 모듈을 선언한 manifest 줄(의존 목록 줄은 건너뜀)" "Project.swift:6 Project.swift:1" \
  "$(printf '%s' "$v" | jq -r 'map("\(.file):\(.line)") | join(" ")')"

assert_eq "manifest: Project.swift" "yes" "$(lint_touches_manifest $'App/A.swift\nModules/X/Project.swift' && echo yes)"
assert_eq "manifest: Tuist 폴더" "yes" "$(lint_touches_manifest 'Tuist/ProjectDescriptionHelpers/H.swift' && echo yes)"
assert_eq "manifest: 일반 파일" "no" "$(lint_touches_manifest 'App/ProjectView.swift' && echo yes || echo no)"

# --- lint 실행: dependency (가짜 tuist) ------------------------------------------
p="$work/app"
mkdir -p "$p/.harness" "$p/App" "$work/bin"
jq -n '{schemaVersion:1, generator:"tuist", commands:{install:null, generate:null},
  workspace:"App.xcworkspace", project:null,
  app:{scheme:"App", path:null, bundleId:null, unitTestTargets:[]},
  destination:{simulator:"iPhone 17 Pro", os:"latest"}, modules:null}' > "$p/.harness/project.json"
printf 'let p = Project(targets: [\n  .target(name: "FeatureTimer", sources: "F"),\n])\n' > "$p/Project.swift"
echo 'let x = 1' > "$p/App/A.swift"
cat > "$work/bin/tuist" <<EOF
#!/usr/bin/env bash
# 가짜 tuist graph: -o 경로에 고정된 그래프를 쓴다.
echo "\$*" >> "$work/tuist.log"
while [ \$# -gt 0 ]; do [ "\$1" = -o ] && { [ -d "\$2" ] && cp "$work/graph.dot" "\$2/graph.dot"; }; shift; done
EOF
chmod +x "$work/bin/tuist"
(cd "$p" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm init)
echo '{"schemaVersion":1,"rules":[{"id":"dep.feature","kind":"dependency","description":"Feature끼리 의존하지 않는다","severity":"error","from":"Feature*","forbid":["Feature*"]}]}' \
  > "$p/.harness/conventions.json"
run() { (cd "$p" && PATH="$work/bin:$PATH" "$lint" "$@"); }

echo 'let y = 2' >> "$p/App/A.swift"
out="$(run)" && code=0 || code=$?
assert_eq "dependency: manifest가 안 바뀌면 그래프를 뽑지 않는다" "0 no" "$code $([ -f "$work/tuist.log" ] && echo yes || echo no)"
(cd "$p" && git checkout -q -- .)

printf '// 모듈 추가\n' >> "$p/Project.swift"
out="$(run)" && code=0 || code=$?
assert_eq "dependency: manifest가 바뀌면 그래프로 판정한다" "1" "$code"
assert_eq "dependency: 첫 줄" "✗ lint · 90점 (기준 95) · 파일 1개 · 모듈 의존 포함 · 위반 1개" "$(printf '%s\n' "$out" | sed -n 1p)"
assert_eq "dependency: 위반 줄" "  Project.swift:2: [dep.feature] Feature끼리 의존하지 않는다 (FeatureTimer → FeatureHistory) (−10)" \
  "$(printf '%s\n' "$out" | sed -n 2p)"
(cd "$p" && git checkout -q -- .)
assert_eq "dependency: --all이면 manifest 변경이 없어도 본다" "✗ lint · 90점 (기준 95) · 파일 2개 · 모듈 의존 포함 · 위반 1개" "$(run --all | sed -n 1p)"

jq '.generator = "xcodeproj"' "$p/.harness/project.json" > "$work/pj" && cp "$work/pj" "$p/.harness/project.json"
out="$(run --all 2>&1)" && code=0 || code=$?
assert_eq "dependency: Tuist가 아니면 2로 끝나고 대신 쓸 방법을 알린다" "2 yes" "$code $(printf '%s' "$out" | grep -q 'pattern 규칙의 included' && echo yes)"
(cd "$p" && git checkout -q -- .)

# --- lint 실행: format (실제 swift-format) ---------------------------------------
if ! xcrun --find swift-format >/dev/null 2>&1; then
  echo "  (swift-format이 없어 format 실행 검사는 건너뜀)"
  finish
  exit $?
fi
echo '{"schemaVersion":1,"passScore":95,"rules":[
  {"id":"naming.lower_camel","kind":"format","description":"함수·변수 이름은 lowerCamelCase","severity":"warning","formatRule":"AlwaysUseLowerCamelCase"}]}' \
  > "$p/.harness/conventions.json"
printf 'struct A {\n      func foo_bar() {}\n}\n' > "$p/App/A.swift"
out="$(run)" && code=0 || code=$?
assert_eq "format: 고른 규칙만 감점(들여쓰기 지적은 거른다)" "0" "$code"
assert_eq "format: 첫 줄" "✓ lint · 95점 (기준 95) · 파일 1개 · 위반 1개" "$(printf '%s\n' "$out" | sed -n 1p)"
assert_eq "format: 위반 위치" "App/A.swift:2 naming.lower_camel" "$(jq -r '.violations[0] | "\(.file):\(.line) \(.rule)"' "$p/.harness/out/lint.json")"

echo '{"schemaVersion":1,"rules":[{"id":"a","kind":"format","description":"d","severity":"info","formatRule":"NoSuchRule"}]}' > "$p/.harness/conventions.json"
out="$(run 2>&1)" && code=0 || code=$?
assert_eq "format: 없는 규칙 이름은 2" "2 yes" "$code $(printf '%s' "$out" | grep -q 'NoSuchRule' && echo yes)"

finish
