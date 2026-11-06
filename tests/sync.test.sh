#!/usr/bin/env bash
# init·sync: 임시 프로젝트에 설치해 보고, 파일 배치·AGENTS.md 관리 블록·설정 병합·플러그인 등록·반복 실행을 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
init="$here/../scripts/init"
install="$here/../scripts/sync"
template="$here/../template"
packs="$here/../packs"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export HARNESS_OFFLINE=1

# 최소 xcodeproj 프로젝트 (detect가 초안을 만들 수 있게)
new_project() {
  mkdir -p "$1/Sample.xcodeproj"
  cat > "$1/Sample.xcodeproj/project.pbxproj" <<'EOF'
// !$*UTF8*$!
{ archiveVersion = 1; objectVersion = 77; objects = {
  T1 = {isa = PBXNativeTarget; buildConfigurationList = L1; name = Sample; productType = "com.apple.product-type.application"; };
  L1 = {isa = XCConfigurationList; buildConfigurations = (C1, ); };
  C1 = {isa = XCBuildConfiguration; name = Debug; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.example.Sample; }; };
}; rootObject = T1; }
EOF
  (cd "$1" && git init -q -b main && printf '.claude/settings.local.json\n' > .gitignore)
}
same() { if cmp -s "$1" "$2"; then echo yes; else echo no; fi; }

# --- 새 프로젝트에 설치 -----------------------------------------------------------
p="$work/fresh"
new_project "$p"
out="$("$init" "$p")"
assert_eq "fresh: 설정 파일 초안을 만든다" '"xcodeproj"' "$(jq -c .ios.generator "$p/.harness/project.json")"
assert_eq "fresh: iOS 묶음을 고른다" '["ios"]' "$(jq -c .platforms "$p/.harness/project.json")"
assert_eq "fresh: 설치한 묶음을 기록한다" '["ios"]' "$(jq -c .packs "$p/.harness/harness.json")"
assert_eq "fresh: 스크립트를 복사한다" "yes" "$(same "$template/scripts/harness/unit-test" "$p/scripts/harness/unit-test")"
assert_eq "fresh: 스크립트 실행 권한을 유지한다" "yes" "$([ -x "$p/scripts/harness/unit-test" ] && echo yes || echo no)"
assert_eq "fresh: 규칙을 복사한다" "yes" "$(same "$template/.claude/rules/harness/ios/swift.md" "$p/.claude/rules/harness/ios/swift.md")"
assert_eq "fresh: 프로젝트 규칙 자리를 만든다" "yes" "$([ -f "$p/.claude/rules/project/.gitkeep" ] && echo yes || echo no)"
assert_eq "fresh: AGENTS.md 제목을 폴더 이름으로 채운다" "# fresh" "$(head -1 "$p/AGENTS.md")"
assert_eq "fresh: 관리 블록에 iOS 묶음 줄을 넣는다" "1" "$(grep -c 'scripts/harness/unit-test --plan' "$p/AGENTS.md")"
assert_eq "fresh: 묶음 자리 표시는 남기지 않는다" "0" "$(grep -c 'harness:pack' "$p/AGENTS.md" || true)"
assert_eq "fresh: CLAUDE.md를 복사한다" "yes" "$(same "$template/CLAUDE.md" "$p/CLAUDE.md")"
assert_eq "fresh: 공통 권한 규칙을 설치한다" "true" "$(jq -s '(.[1].permissions.deny - .[0].permissions.deny) + (.[1].permissions.ask - .[0].permissions.ask) | length == 0' "$p/.claude/settings.json" "$template/.claude/settings.json")"
assert_eq "fresh: iOS 묶음 권한 규칙을 설치한다" "true" "$(jq -s '(.[1].permissions.deny - .[0].permissions.deny) | length == 0' "$p/.claude/settings.json" "$packs/ios/settings.json")"
case "$out" in *"직접 할 일"*"프로젝트 영역"*) ok=yes ;; *) ok=no ;; esac
assert_eq "fresh: 프로젝트 영역을 채우라고 알린다" "yes" "$ok"

assert_eq "fresh: 검사 목록은 쓰지 않는다 (사용자와 setup으로 정한다)" "no" "$([ -f "$p/.harness/checks.json" ] && echo yes || echo no)"
assert_eq "fresh: 하네스가 넣은 권한 규칙을 기록한다" "true" "$(jq -s '(.[1].permissions.deny - .[0].permissions.deny) | length == 0' "$p/.harness/harness.json" "$packs/ios/settings.json")"
case "$out" in *"scripts/harness/setup 안내대로"*) ok=yes ;; *) ok=no ;; esac
assert_eq "fresh: setup으로 검사를 정하라고 알린다" "yes" "$ok"

assert_eq "fresh: 두 번째 실행은 바뀐 것이 없다" "✓ sync · 바뀐 것 없음 · $p" "$("$install" "$p" | sed -n 1p)"

# --- 관리 블록이 있는 AGENTS.md: 프로젝트 영역은 지키고 블록만 바꾼다 --------------------------
printf '%s\n' '# Sample' '' '우리 프로젝트 소개' '<!-- harness:begin 옛날 -->' '옛 블록' '<!-- harness:end -->' '' '블록 뒤 프로젝트 메모' > "$p/AGENTS.md"
"$install" "$p" > /dev/null
assert_eq "agents: 블록 앞 프로젝트 영역을 지킨다" "우리 프로젝트 소개" "$(sed -n 3p "$p/AGENTS.md")"
assert_eq "agents: 옛 블록은 사라진다" "0" "$(grep -c '옛 블록' "$p/AGENTS.md" || true)"
assert_eq "agents: 새 블록이 들어간다" "1" "$(grep -c '## 빌드·테스트' "$p/AGENTS.md")"
assert_eq "agents: 블록 뒤 내용도 지킨다" "블록 뒤 프로젝트 메모" "$(tail -1 "$p/AGENTS.md")"

# --- 이미 지침과 설정이 있는 프로젝트 ----------------------------------------------------
q="$work/existing"
new_project "$q"
printf '# 기존 지침\n\n- 기존 규칙\n' > "$q/AGENTS.md"
printf '# 기존 Claude 지침\n' > "$q/CLAUDE.md"
mkdir -p "$q/.claude"
jq -n '{permissions: {allow: ["Bash(make generate)"], deny: ["Read(**/*.p12)"]}, hooks: {PreToolUse: []}}' > "$q/.claude/settings.json"
out="$("$init" "$q")"
assert_eq "existing: 기존 AGENTS.md 내용을 지킨다" "- 기존 규칙" "$(sed -n 3p "$q/AGENTS.md")"
assert_eq "existing: 관리 블록을 끝에 덧붙인다" "1" "$(grep -c '<!-- harness:begin' "$q/AGENTS.md")"
assert_eq "existing: 기존 CLAUDE.md는 건드리지 않는다" "# 기존 Claude 지침" "$(cat "$q/CLAUDE.md")"
case "$out" in *"CLAUDE.md에 @AGENTS.md import가 없다"*) ok=yes ;; *) ok=no ;; esac
assert_eq "existing: CLAUDE.md를 정리하라고 알린다" "yes" "$ok"
assert_eq "existing: 기존 allow 규칙을 지킨다" '["Bash(make generate)"]' "$(jq -c .permissions.allow "$q/.claude/settings.json")"
assert_eq "existing: 기존 훅 설정을 지킨다" '{"PreToolUse":[]}' "$(jq -c .hooks "$q/.claude/settings.json")"
assert_eq "existing: deny 규칙은 중복 없이 합친다" "1" "$(jq '[.permissions.deny[] | select(. == "Read(**/*.p12)")] | length' "$q/.claude/settings.json")"
assert_eq "existing: template의 deny 규칙이 모두 들어간다" "true" \
  "$(jq -s '(.[1].permissions.deny - .[0].permissions.deny) | length == 0' "$q/.claude/settings.json" "$template/.claude/settings.json")"
assert_eq "existing: 묶음의 deny 규칙도 들어간다" "true" \
  "$(jq -s '(.[1].permissions.deny - .[0].permissions.deny) | length == 0' "$q/.claude/settings.json" "$packs/ios/settings.json")"
assert_eq "existing: 두 번째 실행은 바뀐 것이 없다" "✓ sync · 바뀐 것 없음 · $q" "$("$install" "$q" | sed -n 1p)"

# --- template에서 사라진 하네스 규칙은 지운다 -----------------------------------------------
assert_eq "record: 설치한 파일 목록을 남긴다" "true" "$(jq '.files | index("scripts/harness/passed") != null' "$p/.harness/harness.json")"
echo '# old' > "$p/.claude/rules/harness/old-rule.md"
echo '# mine' > "$p/.claude/rules/project/mine.md"
printf '#!/usr/bin/env bash\n' > "$p/scripts/harness/verify"
printf '#!/usr/bin/env bash\n' > "$p/scripts/harness/team-tool"
# verify와 old-rule.md는 지난번에 하네스가 설치했던 파일이라고 적는다(이름이 바뀐 경우)
jq '.files += ["scripts/harness/verify", ".claude/rules/harness/old-rule.md", "../outside"]' "$p/.harness/harness.json" > "$work/h.json" && mv "$work/h.json" "$p/.harness/harness.json"
"$install" "$p" > /dev/null
assert_eq "scripts: 지난번에 설치했는데 template에서 사라진 스크립트는 지운다" "no" "$([ -f "$p/scripts/harness/verify" ] && echo yes || echo no)"
assert_eq "rules: template에서 사라진 하네스 규칙은 지운다" "no" "$([ -f "$p/.claude/rules/harness/old-rule.md" ] && echo yes || echo no)"
assert_eq "scripts: 팀이 넣은 스크립트는 지우지 않는다" "yes" "$([ -f "$p/scripts/harness/team-tool" ] && echo yes || echo no)"
assert_eq "rules: 프로젝트 규칙은 지우지 않는다" "yes" "$([ -f "$p/.claude/rules/project/mine.md" ] && echo yes || echo no)"
jq 'del(.files)' "$p/.harness/harness.json" > "$work/h.json" && mv "$work/h.json" "$p/.harness/harness.json"
printf '#!/usr/bin/env bash\n' > "$p/scripts/harness/verify"
"$install" "$p" > /dev/null
assert_eq "scripts: 목록이 없는 첫 갱신에서는 지우지 않는다" "yes" "$([ -f "$p/scripts/harness/verify" ] && echo yes || echo no)"
rm -f "$p/scripts/harness/verify" "$p/scripts/harness/team-tool"

# --- 플러그인 등록과 설치 기록 -----------------------------------------------------------
version="$(jq -r .version "$here/../plugin/.claude-plugin/plugin.json")"
assert_eq "plugin: 공유 설정에 GitHub 마켓플레이스를 넣는다" '{"source":"github","repo":"Gooreum/ios-ai-harness"}' \
  "$(jq -c '.extraKnownMarketplaces["ios-ai-harness"].source' "$p/.claude/settings.json")"
assert_eq "plugin: 공유 설정에서 플러그인을 켠다" "true" "$(jq '.enabledPlugins["ios-harness@ios-ai-harness"]' "$p/.claude/settings.json")"
assert_eq "plugin: 기본 설치는 로컬 설정을 만들지 않는다" "no" "$([ -f "$p/.claude/settings.local.json" ] && echo yes || echo no)"
assert_eq "plugin: 기존 설정에도 플러그인을 등록한다" "true" "$(jq '.enabledPlugins["ios-harness@ios-ai-harness"]' "$q/.claude/settings.json")"
assert_eq "record: 설치한 하네스 버전을 남긴다" "$version" "$(jq -r .version "$p/.harness/harness.json")"

# --- init과 sync의 구분 ----------------------------------------------------------------
set +e
"$init" "$p" > /dev/null 2> "$work/err"; code=$?
set -e
assert_eq "init: 이미 설치된 프로젝트는 거절한다" "2" "$code"
case "$(cat "$work/err")" in *"scripts/sync"*) ok=yes ;; *) ok=no ;; esac
assert_eq "init: 거절할 때 sync를 안내한다" "yes" "$ok"
mkdir -p "$work/bare"
set +e
"$install" "$work/bare" > /dev/null 2> "$work/err"; code=$?
set -e
assert_eq "sync: 설치되지 않은 프로젝트는 거절한다" "2" "$code"
assert_eq "sync: 거절할 때 아무 파일도 만들지 않는다" "" "$(ls -A "$work/bare")"

# --- --dev: 로컬 디렉터리 마켓플레이스 ------------------------------------------------------
echo '{"permissions":{"deny":["Skill(x)"]}}' > "$p/.claude/settings.local.json"
"$install" --dev "$p" > /dev/null
assert_eq "dev: 로컬 설정에 이 저장소를 디렉터리 마켓플레이스로 넣는다" "directory" \
  "$(jq -r '.extraKnownMarketplaces["ios-ai-harness"].source.source' "$p/.claude/settings.local.json")"
assert_eq "dev: 공유 설정은 GitHub 그대로 둔다" "github" \
  "$(jq -r '.extraKnownMarketplaces["ios-ai-harness"].source.source' "$p/.claude/settings.json")"
"$install" "$p" > /dev/null
assert_eq "dev 해제: --dev 없이 실행하면 디렉터리 마켓플레이스를 지운다" "null" \
  "$(jq -c '.extraKnownMarketplaces' "$p/.claude/settings.local.json")"
assert_eq "dev 해제: 로컬 설정의 다른 값은 지킨다" '["Skill(x)"]' "$(jq -c .permissions.deny "$p/.claude/settings.local.json")"

# --- 공유 설정이 git에서 무시되는 프로젝트 ---------------------------------------------------
printf '.claude/settings.json\n' >> "$q/.gitignore"
out="$("$install" "$q")"
case "$out" in *"settings.json이 git에서 무시된다"*) ok=yes ;; *) ok=no ;; esac
assert_eq "ignored: settings.json이 공유되지 않는다고 알린다" "yes" "$ok"

# --- 옛 형식 설정(schemaVersion 1)을 옮긴다 ---------------------------------------------
m="$work/migrate"
new_project "$m"
"$init" "$m" > /dev/null
jq -n '{schemaVersion: 1, generator: "xcodeproj", commands: {install: null, generate: null}, workspace: null,
  project: "Sample.xcodeproj", app: {scheme: "Sample", bundleId: "com.example.Sample"},
  destination: {simulator: "iPhone 17 Pro", os: "latest"}, modules: null, e2e: {network: {port: 18787}}}' > "$m/.harness/project.json"
out="$("$install" "$m")"
assert_eq "migrate: 새 형식으로 옮긴다" "2" "$(jq .schemaVersion "$m/.harness/project.json")"
assert_eq "migrate: iOS 묶음을 고른다" '["ios"]' "$(jq -c .platforms "$m/.harness/project.json")"
assert_eq "migrate: iOS 설정은 ios 아래로" '"Sample"|"iPhone 17 Pro"' \
  "$(jq -c '.ios.app.scheme' "$m/.harness/project.json")|$(jq -c '.ios.destination.simulator' "$m/.harness/project.json")"
assert_eq "migrate: e2e는 위에 남긴다" "18787" "$(jq .e2e.network.port "$m/.harness/project.json")"
assert_eq "migrate: 위에 iOS 키가 남지 않는다" "null" "$(jq -c .generator "$m/.harness/project.json")"
case "$out" in *"새 형식으로 옮김"*) ok=yes ;; *) ok=no ;; esac
assert_eq "migrate: 옮겼다고 알린다" "yes" "$ok"
assert_eq "migrate: 두 번째 실행은 바뀐 것이 없다" "✓ sync · 바뀐 것 없음 · $m" "$("$install" "$m" | sed -n 1p)"

# 파일 목록이 없는 옛 설치에서도 묶음 폴더로 옮긴 규칙의 옛 자리는 지운다
echo '# old swift' > "$m/.claude/rules/harness/swift.md"
jq 'del(.files)' "$m/.harness/harness.json" > "$work/h.json" && mv "$work/h.json" "$m/.harness/harness.json"
"$install" "$m" > /dev/null
assert_eq "moved: 묶음 폴더로 옮긴 규칙의 옛 자리를 지운다" "no" "$([ -f "$m/.claude/rules/harness/swift.md" ] && echo yes || echo no)"
assert_eq "moved: 공통 규칙은 남는다" "yes" "$([ -f "$m/.claude/rules/harness/wiki.md" ] && echo yes || echo no)"

# --- 권한 규칙: 하네스가 넣었다가 빠진 규칙만 지운다 ------------------------------------------
jq '.permissions.deny += ["Bash(old-harness-rule)", "Bash(team-rule)"]' "$m/.claude/settings.json" > "$work/s" && mv "$work/s" "$m/.claude/settings.json"
jq '.permissions.deny += ["Bash(old-harness-rule)"]' "$m/.harness/harness.json" > "$work/h" && mv "$work/h" "$m/.harness/harness.json"
"$install" "$m" > /dev/null
assert_eq "perm: 하네스가 넣었는데 이제 없는 규칙을 지운다" "0" "$(jq '[.permissions.deny[] | select(. == "Bash(old-harness-rule)")] | length' "$m/.claude/settings.json")"
assert_eq "perm: 팀이 넣은 규칙은 남긴다" "1" "$(jq '[.permissions.deny[] | select(. == "Bash(team-rule)")] | length' "$m/.claude/settings.json")"
assert_eq "perm: 지금 넣는 규칙은 남는다" "1" "$(jq '[.permissions.deny[] | select(. == "Edit(**/*.pbxproj)")] | length' "$m/.claude/settings.json")"
jq 'del(.permissions)' "$m/.harness/harness.json" > "$work/h" && mv "$work/h" "$m/.harness/harness.json"
jq '.permissions.deny += ["Bash(unknown-rule)"]' "$m/.claude/settings.json" > "$work/s" && mv "$work/s" "$m/.claude/settings.json"
"$install" "$m" > /dev/null
assert_eq "perm: 기록이 없으면(옛 설치) 지우지 않는다" "1" "$(jq '[.permissions.deny[] | select(. == "Bash(unknown-rule)")] | length' "$m/.claude/settings.json")"

# --- 검사 목록이 있으면 알리지 않는다 ---------------------------------------------------------
c="$work/haschecks"
new_project "$c"
mkdir -p "$c/.harness" && echo '{"schemaVersion":1,"checks":[{"name":"mine"}]}' > "$c/.harness/checks.json"
out="$("$init" "$c")"
assert_eq "checks: 이미 있는 검사 목록은 그대로 둔다" '["mine"]' "$(jq -c '[.checks[].name]' "$c/.harness/checks.json")"
case "$out" in *"setup 안내대로"*) ok=no ;; *) ok=yes ;; esac
assert_eq "checks: 있으면 setup을 안내하지 않는다" "yes" "$ok"

# --- 묶음이 없는 프로젝트: 공통 파일만 ------------------------------------------------------
n="$work/nopack"
mkdir -p "$n" && (cd "$n" && git init -q -b main) && echo '{"scripts":{"test":"jest","lint":"eslint ."}}' > "$n/package.json"
touch "$n/yarn.lock"
"$init" "$n" > /dev/null
assert_eq "nopack: 묶음 없음" '[]' "$(jq -c .platforms "$n/.harness/project.json")"
assert_eq "nopack: 공통 스크립트는 설치한다" "yes" "$([ -x "$n/scripts/harness/record" ] && [ -x "$n/scripts/harness/passed" ] && echo yes || echo no)"
assert_eq "nopack: iOS 스크립트는 설치하지 않는다" "no" "$([ -e "$n/scripts/harness/unit-test" ] || [ -e "$n/scripts/harness/ios.sh" ] && echo yes || echo no)"
assert_eq "nopack: iOS 규칙은 설치하지 않는다" "no" "$([ -d "$n/.claude/rules/harness/ios" ] && echo yes || echo no)"
assert_eq "nopack: 공통 규칙은 설치한다" "yes" "$([ -f "$n/.claude/rules/harness/wiki.md" ] && echo yes || echo no)"
assert_eq "nopack: 관리 블록에 iOS 줄이 없다" "0" "$(grep -c 'unit-test\|swift.md' "$n/AGENTS.md" || true)"
assert_eq "nopack: iOS 권한 규칙은 넣지 않는다" "0" "$(jq '[.permissions.deny[] | select(. == "Edit(**/*.pbxproj)")] | length' "$n/.claude/settings.json")"

assert_eq "nopack: setup은 공통 스크립트라 설치한다" "yes" "$([ -x "$n/scripts/harness/setup" ] && echo yes || echo no)"
assert_eq "nopack: iOS 추천 검사는 설치하지 않는다" "no" "$([ -e "$n/scripts/harness/ios-checks.json" ] && echo yes || echo no)"

# 고른 묶음을 빼면 그 묶음 파일을 지운다
jq '.platforms = []' "$m/.harness/project.json" > "$work/pj" && mv "$work/pj" "$m/.harness/project.json"
"$install" "$m" > /dev/null
assert_eq "unpick: 뺀 묶음의 스크립트를 지운다" "no" "$([ -e "$m/scripts/harness/unit-test" ] && echo yes || echo no)"
assert_eq "unpick: 뺀 묶음의 규칙을 지운다" "no" "$([ -e "$m/.claude/rules/harness/ios/swift.md" ] && echo yes || echo no)"
assert_eq "unpick: 뺀 묶음의 권한 규칙을 지운다" "0" "$(jq '[.permissions.deny[] | select(. == "Edit(**/*.pbxproj)")] | length' "$m/.claude/settings.json")"
assert_eq "unpick: 공통 스크립트는 남는다" "yes" "$([ -e "$m/scripts/harness/passed" ] && echo yes || echo no)"
jq '.platforms = ["android"]' "$m/.harness/project.json" > "$work/pj" && mv "$work/pj" "$m/.harness/project.json"
out="$("$install" "$m")"
case "$out" in *"'android' 묶음이 하네스에 없다"*) ok=yes ;; *) ok=no ;; esac
assert_eq "unknown: 없는 묶음을 알린다" "yes" "$ok"

finish
