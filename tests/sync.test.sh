#!/usr/bin/env bash
# init·sync: 임시 프로젝트에 설치해 보고, 파일 배치·AGENTS.md 관리 블록·설정 병합·플러그인 등록·반복 실행을 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
init="$here/../scripts/init"
install="$here/../scripts/sync"
template="$here/../template"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export HARNESS_OFFLINE=1 HARNESS_SIMULATOR="iPhone Test"

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
assert_eq "fresh: 설정 파일 초안을 만든다" '"xcodeproj"' "$(jq -c .generator "$p/.harness/project.json")"
assert_eq "fresh: 스크립트를 복사한다" "yes" "$(same "$template/scripts/harness/unit-test" "$p/scripts/harness/unit-test")"
assert_eq "fresh: 스크립트 실행 권한을 유지한다" "yes" "$([ -x "$p/scripts/harness/unit-test" ] && echo yes || echo no)"
assert_eq "fresh: 규칙을 복사한다" "yes" "$(same "$template/.claude/rules/harness/swift.md" "$p/.claude/rules/harness/swift.md")"
assert_eq "fresh: 프로젝트 규칙 자리를 만든다" "yes" "$([ -f "$p/.claude/rules/project/.gitkeep" ] && echo yes || echo no)"
assert_eq "fresh: AGENTS.md 제목을 앱 스킴으로 채운다" "# Sample" "$(head -1 "$p/AGENTS.md")"
assert_eq "fresh: CLAUDE.md를 복사한다" "yes" "$(same "$template/CLAUDE.md" "$p/CLAUDE.md")"
assert_eq "fresh: 권한 규칙을 설치한다" "true" "$(jq -s '.[1].permissions == .[0].permissions' "$p/.claude/settings.json" "$template/.claude/settings.json")"
case "$out" in *"직접 할 일"*"프로젝트 영역"*) ok=yes ;; *) ok=no ;; esac
assert_eq "fresh: 프로젝트 영역을 채우라고 알린다" "yes" "$ok"

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
assert_eq "existing: 두 번째 실행은 바뀐 것이 없다" "✓ sync · 바뀐 것 없음 · $q" "$("$install" "$q" | sed -n 1p)"

# --- template에서 사라진 하네스 규칙은 지운다 -----------------------------------------------
echo '# old' > "$p/.claude/rules/harness/old-rule.md"
echo '# mine' > "$p/.claude/rules/project/mine.md"
printf '#!/usr/bin/env bash\n' > "$p/scripts/harness/verify"
"$install" "$p" > /dev/null
assert_eq "scripts: template에 없는(이름이 바뀐) 스크립트는 지운다" "no" "$([ -f "$p/scripts/harness/verify" ] && echo yes || echo no)"
assert_eq "rules: template에 없는 하네스 규칙은 지운다" "no" "$([ -f "$p/.claude/rules/harness/old-rule.md" ] && echo yes || echo no)"
assert_eq "rules: 프로젝트 규칙은 지키지 않는다" "yes" "$([ -f "$p/.claude/rules/project/mine.md" ] && echo yes || echo no)"

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

finish
