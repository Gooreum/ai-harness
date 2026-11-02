#!/usr/bin/env bash
# lint의 컨벤션 검사·SwiftLint 설정 변환·점수 판정을 가짜 프로젝트로 검사한다.
# swiftlint가 없으면 실제 실행 부분은 건너뛴다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
. "$here/../template/scripts/harness/lib.sh"
lint="$here/../template/scripts/harness/lint"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# 컨벤션 파일의 문제를 출력한다(문제가 없으면 ok).
problem() { (conventions_check "$1" 2>&1 >/dev/null && echo ok) | sed 's/^harness: //' || true; }
conv() { printf '%s' "$2" > "$work/$1.json"; echo "$work/$1.json"; }

# --- conventions_check --------------------------------------------------------
rule='{"id":"swiftui.no_sheet","description":"d","severity":"error","regex":"x"}'
one="$(conv ok '{"schemaVersion":1,"rules":['"$rule"']}')"
two="$(conv d '{"schemaVersion":1,"rules":['"$rule,$rule"']}')"
assert_eq "check: 올바른 파일" "ok" "$(problem "$one")"
assert_eq "check: schemaVersion" ".harness/conventions.json: schemaVersion은 1이어야 합니다" \
  "$(problem "$(conv v '{"rules":[]}')")"
assert_eq "check: severity" ".harness/conventions.json: rules[0]: a: severity는 error·warning·info 중 하나입니다" \
  "$(problem "$(conv s '{"schemaVersion":1,"rules":[{"id":"a","description":"d","severity":"fatal","regex":"x"}]}')")"
assert_eq "check: id 형식" ".harness/conventions.json: rules[0]: id는 영문 소문자·숫자·_·.만 씁니다" \
  "$(problem "$(conv i '{"schemaVersion":1,"rules":[{"id":"No Sheet","description":"d","severity":"info","regex":"x"}]}')")"
assert_eq "check: id 중복" ".harness/conventions.json: id가 겹칩니다: swiftui.no_sheet" \
  "$(problem "$two")"
assert_eq "check: regex 누락" ".harness/conventions.json: rules[0]: a: regex가 필요합니다" \
  "$(problem "$(conv r '{"schemaVersion":1,"rules":[{"id":"a","description":"d","severity":"info"}]}')")"

# --- conventions_to_swiftlint -------------------------------------------------
f="$(conv t '{"schemaVersion":1,"rules":[
  {"id":"a.b","description":"설명","severity":"info","regex":"r","matchKinds":["identifier"],"included":["View\\.swift$"]}]}')"
assert_eq "swiftlint: 컨벤션 규칙만 켠다" '["custom_rules"]' "$(conventions_to_swiftlint "$f" | jq -c .only_rules)"
assert_eq "swiftlint: info는 warning으로, 나머지 필드는 그대로" \
  '{"name":"a.b","regex":"r","message":"설명","severity":"warning","match_kinds":["identifier"],"included":["View\\.swift$"]}' \
  "$(conventions_to_swiftlint "$f" | jq -c '.custom_rules["a.b"]')"

# --- lint_violations ----------------------------------------------------------
f="$(conv p '{"schemaVersion":1,"rules":[
  {"id":"e","description":"에러","severity":"error","regex":"x"},
  {"id":"w","description":"경고","severity":"warning","regex":"x","penalty":3}]}')"
printf '%s' '[{"rule_id":"w","file":"/r/B.swift","line":1,"character":2,"reason":"m"},
  {"rule_id":"e","file":"/r/A.swift","line":9,"character":1,"reason":"m"},
  {"rule_id":"other","file":"/r/A.swift","line":1,"character":1,"reason":"m"}]' > "$work/raw.json"
mkdir -p "$work/r"
sed "s|/r/|$work/r/|g" "$work/raw.json" > "$work/raw2.json"
v="$(lint_violations "$f" "$work/raw2.json" "$work/r")"
assert_eq "violations: 심각한 것부터, 경로는 루트 기준" "e A.swift 10|w B.swift 3" \
  "$(printf '%s' "$v" | jq -r 'map("\(.rule) \(.file) \(.penalty)") | join("|")')"
assert_eq "violations: 메시지는 컨벤션 설명" "에러" "$(printf '%s' "$v" | jq -r '.[0].message')"

# --- lint 실행 ----------------------------------------------------------------
if ! command -v swiftlint >/dev/null 2>&1; then
  echo "  (swiftlint가 없어 lint 실행 검사는 건너뜀)"
  finish
  exit $?
fi

p="$work/app"
mkdir -p "$p/.harness" "$p/App/Views"
jq -n '{schemaVersion:1, generator:"xcodeproj", commands:{install:null, generate:null},
  workspace:null, project:"App.xcodeproj",
  app:{scheme:"App", path:null, bundleId:null, unitTestTargets:[]},
  destination:{simulator:"iPhone 17 Pro", os:"latest"}, modules:null}' > "$p/.harness/project.json"
echo 'import SwiftUI' > "$p/App/Views/HomeView.swift"
echo 'let x = 1' > "$p/App/Model.swift"
(cd "$p" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm init)
run() { (cd "$p" && "$lint" "$@"); }

assert_eq "lint: 컨벤션 파일이 없으면 건너뛴다" "· lint · .harness/conventions.json이 없어 건너뜁니다" "$(run)"

cat > "$p/.harness/conventions.json" <<'JSON'
{
  "schemaVersion": 1,
  "passScore": 90,
  "rules": [
    { "id": "swiftui.no_sheet_is_presented", "description": ".sheet(item:)을 쓴다", "severity": "error",
      "regex": "\\.sheet\\(\\s*isPresented:", "matchKinds": ["identifier", "keyword", "argument"] },
    { "id": "imports.no_mobile_core_services", "description": "UniformTypeIdentifiers를 쓴다", "severity": "warning",
      "regex": "^\\s*import\\s+MobileCoreServices\\b" },
    { "id": "view.no_service_shared", "description": "View에서 Service.shared를 직접 참조하지 않는다", "severity": "info",
      "regex": "\\b\\w*Service\\.shared\\b", "included": ["View\\.swift$"] }
  ]
}
JSON
assert_eq "lint: 바뀐 Swift 파일이 없으면 끝" "✓ lint · 바뀐 Swift 파일 없음" "$(run)"
assert_eq "lint: 변경이 없어도 결과 파일을 남긴다" "true 100" "$(jq -r '"\(.passed) \(.score)"' "$p/.harness/out/lint.json")"

printf 'import MobileCoreServices\nstruct HomeView { func f() { AuthService.shared.load() } }\n' > "$p/App/Views/HomeView.swift"
out="$(run)" && code=0 || code=$?
assert_eq "lint: 감점이 기준 이상이면 통과" "0" "$code"
assert_eq "lint: 점수와 위반 개수" "✓ lint · 94점 (기준 90) · 파일 1개 · 위반 2개" "$(printf '%s\n' "$out" | sed -n 1p)"
assert_eq "lint: 위반은 위치·규칙·감점과 함께, 심각한 것부터" \
  "  App/Views/HomeView.swift:1: [imports.no_mobile_core_services] UniformTypeIdentifiers를 쓴다 (−5)" \
  "$(printf '%s\n' "$out" | sed -n 2p)"

# 주석·문자열 속 패턴은 위반이 아니고, included 밖 파일의 Service.shared도 위반이 아니다.
printf '// .sheet(isPresented: 주석\nlet s = ".sheet(isPresented: 문자열"\nlet a = AuthService.shared\n' > "$p/App/Model.swift"
run >/dev/null || true
assert_eq "lint: 주석·문자열·included 밖은 잡지 않는다" "2" "$(jq '.violations | length' "$p/.harness/out/lint.json")"

printf 'func g() { v.sheet(isPresented: $x) { } }\n' >> "$p/App/Model.swift"
out="$(run)" && code=0 || code=$?
assert_eq "lint: 기준 미달이면 실패(1)" "1" "$code"
assert_eq "lint: 실패 첫 줄" "✗ lint · 84점 (기준 90) · 파일 2개 · 위반 3개" "$(printf '%s\n' "$out" | sed -n 1p)"
assert_eq "lint: error가 맨 앞" "  App/Model.swift:4: [swiftui.no_sheet_is_presented] .sheet(item:)을 쓴다 (−10)" \
  "$(printf '%s\n' "$out" | sed -n 2p)"
assert_eq "lint: 결과 파일" "false 84 90 2" "$(jq -r '"\(.passed) \(.score) \(.passScore) \(.files)"' "$p/.harness/out/lint.json")"

(cd "$p" && git checkout -q -- . && rm -f App/Model.swift)
out="$(run)" && code=0 || code=$?
assert_eq "lint: 지운 파일은 검사하지 않는다" "✓ lint · 바뀐 Swift 파일 없음" "$out"

(cd "$p" && git checkout -q -- . && git checkout -q -b feature \
  && printf 'import MobileCoreServices\n' > App/Model.swift && git -c user.name=t -c user.email=t@t commit -qam change)
assert_eq "lint: 커밋한 변경은 기본으로는 보지 않는다" "✓ lint · 바뀐 Swift 파일 없음" "$(run)"
assert_eq "lint: --base로 브랜치 변경을 본다" "✓ lint · 95점 (기준 90) · 파일 1개 · 위반 1개" "$(run --base main | sed -n 1p)"
assert_eq "lint: --all은 모든 Swift 파일" "✓ lint · 95점 (기준 90) · 파일 2개 · 위반 1개" "$(run --all | sed -n 1p)"

echo '{"schemaVersion":1,"rules":[{"id":"a","severity":"info","regex":"x"}]}' > "$p/.harness/conventions.json"
out="$(run --all 2>&1)" && code=0 || code=$?
assert_eq "lint: 잘못된 컨벤션 파일은 2로 끝난다" "2" "$code"
assert_eq "lint: 문제를 알려 준다" "harness: .harness/conventions.json: rules[0]: a: description이 필요합니다" "$out"

finish
