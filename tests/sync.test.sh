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

export HARNESS_OFFLINE=1

new_project() {
  mkdir -p "$1"
  (cd "$1" && git init -q -b main && printf '.claude/settings.local.json\n' > .gitignore)
}
same() { if cmp -s "$1" "$2"; then echo yes; else echo no; fi; }

# --- 새 프로젝트에 설치 -----------------------------------------------------------
p="$work/fresh"
new_project "$p"
out="$("$init" "$p")"
assert_eq "fresh: 빈 설정 파일을 만든다 (플랫폼은 묻지 않는다)" '{"schemaVersion":2}' "$(jq -c . "$p/.harness/project.json")"
assert_eq "fresh: 스크립트를 복사한다" "yes" "$(same "$template/scripts/harness/passed" "$p/scripts/harness/passed")"
assert_eq "fresh: 스크립트 실행 권한을 유지한다" "yes" "$([ -x "$p/scripts/harness/passed" ] && echo yes || echo no)"
assert_eq "fresh: 플랫폼 스크립트는 없다" "no" "$([ -e "$p/scripts/harness/unit-test" ] || [ -e "$p/scripts/harness/ios.sh" ] && echo yes || echo no)"
assert_eq "fresh: 규칙을 복사한다" "yes" "$(same "$template/.claude/rules/harness/wiki.md" "$p/.claude/rules/harness/wiki.md")"
assert_eq "fresh: 프로젝트 규칙 자리를 만든다" "yes" "$([ -f "$p/.claude/rules/project/.gitkeep" ] && echo yes || echo no)"
assert_eq "fresh: AGENTS.md 제목을 폴더 이름으로 채운다" "# fresh" "$(head -1 "$p/AGENTS.md")"
assert_eq "fresh: 프로젝트 영역에 빌드·테스트 칸을 둔다" "1" "$(awk '/harness:begin/ { exit } /^## 빌드·테스트$/' "$p/AGENTS.md" | wc -l | tr -d ' ')"
assert_eq "fresh: CLAUDE.md를 복사한다" "yes" "$(same "$template/CLAUDE.md" "$p/CLAUDE.md")"
assert_eq "fresh: 공통 권한 규칙을 설치한다" "true" "$(jq -s '(.[1].permissions.deny - .[0].permissions.deny) + (.[1].permissions.ask - .[0].permissions.ask) | length == 0' "$p/.claude/settings.json" "$template/.claude/settings.json")"
case "$out" in *"직접 할 일"*"프로젝트 영역"*) ok=yes ;; *) ok=no ;; esac
assert_eq "fresh: 프로젝트 영역을 채우라고 알린다" "yes" "$ok"

assert_eq "fresh: 검사 목록은 쓰지 않는다 (사용자와 setup으로 정한다)" "no" "$([ -f "$p/.harness/checks.json" ] && echo yes || echo no)"
assert_eq "fresh: 하네스가 넣은 권한 규칙을 기록한다" "true" "$(jq -s '.[0].permissions == .[1].permissions' "$p/.harness/harness.json" "$template/.claude/settings.json")"
case "$out" in *"scripts/harness/setup 안내대로"*) ok=yes ;; *) ok=no ;; esac
assert_eq "fresh: setup으로 검사를 정하라고 알린다" "yes" "$ok"

assert_eq "fresh: 두 번째 실행은 바뀐 것이 없다" "✓ sync · 바뀐 것 없음 · $p" "$("$install" "$p" | sed -n 1p)"

# --- 관리 블록이 있는 AGENTS.md: 프로젝트 영역은 지키고 블록만 바꾼다 --------------------------
printf '%s\n' '# Sample' '' '우리 프로젝트 소개' '<!-- harness:begin 옛날 -->' '옛 블록' '<!-- harness:pack rules -->' '<!-- harness:end -->' '' '블록 뒤 프로젝트 메모' > "$p/AGENTS.md"
"$install" "$p" > /dev/null
assert_eq "agents: 블록 앞 프로젝트 영역을 지킨다" "우리 프로젝트 소개" "$(sed -n 3p "$p/AGENTS.md")"
assert_eq "agents: 옛 블록은 사라진다" "0" "$(grep -c '옛 블록' "$p/AGENTS.md" || true)"
assert_eq "agents: 새 블록이 들어간다" "1" "$(grep -c '## 하네스 명령' "$p/AGENTS.md")"
assert_eq "agents: 예전 묶음 자리 표시는 남기지 않는다" "0" "$(grep -c 'harness:pack' "$p/AGENTS.md" || true)"
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
assert_eq "plugin: 공유 설정에 GitHub 마켓플레이스를 넣는다" '{"source":"github","repo":"Gooreum/ai-harness"}' \
  "$(jq -c '.extraKnownMarketplaces["ai-harness"].source' "$p/.claude/settings.json")"
assert_eq "plugin: 공유 설정에서 플러그인을 켠다" "true" "$(jq '.enabledPlugins["harness@ai-harness"]' "$p/.claude/settings.json")"
assert_eq "plugin: 기본 설치는 로컬 설정을 만들지 않는다" "no" "$([ -f "$p/.claude/settings.local.json" ] && echo yes || echo no)"
assert_eq "plugin: 기존 설정에도 플러그인을 등록한다" "true" "$(jq '.enabledPlugins["harness@ai-harness"]' "$q/.claude/settings.json")"
assert_eq "record: 설치한 하네스 버전을 남긴다" "$version" "$(jq -r .version "$p/.harness/harness.json")"

# --- 예전 이름(ios-harness@ios-ai-harness) 정리 ------------------------------------------------
jq '.extraKnownMarketplaces["ios-ai-harness"] = {source: {source: "github", repo: "Gooreum/ios-ai-harness"}}
    | .enabledPlugins["ios-harness@ios-ai-harness"] = true | .enabledPlugins["other@x"] = true' \
  "$p/.claude/settings.json" > "$work/s.json" && mv "$work/s.json" "$p/.claude/settings.json"
echo '{"extraKnownMarketplaces":{"ios-ai-harness":{"source":{"source":"directory","path":"/x"}}},"enabledPlugins":{"ios-harness@ios-ai-harness":true},"env":{"A":"1"}}' \
  > "$p/.claude/settings.local.json"
cat > "$p/.harness/checks.json" <<'JSON'
{ "schemaVersion": 1, "checks": [
  { "name": "review", "description": "ios-reviewer 코드 리뷰", "prompt": "ios-harness:ios-reviewer 서브에이전트에 변경 검토를 맡긴다", "run": "scripts/harness/passed review" },
  { "name": "mine", "description": "팀 검사", "prompt": "scripts/harness/record mine \"make t\"", "run": "scripts/harness/passed mine" } ] }
JSON
"$install" "$p" > /dev/null
assert_eq "old name: 공유 설정에서 예전 마켓플레이스를 지운다" "null" "$(jq -c '.extraKnownMarketplaces["ios-ai-harness"]' "$p/.claude/settings.json")"
assert_eq "old name: 공유 설정에서 예전 플러그인을 지운다" "null" "$(jq -c '.enabledPlugins["ios-harness@ios-ai-harness"]' "$p/.claude/settings.json")"
assert_eq "old name: 다른 플러그인은 남긴다" "true" "$(jq -c '.enabledPlugins["other@x"]' "$p/.claude/settings.json")"
assert_eq "old name: 로컬 설정에서도 지우고 다른 값은 남긴다" '{"env":{"A":"1"}}' "$(jq -c . "$p/.claude/settings.local.json")"
assert_eq "old name: 검사 지시문의 리뷰어를 새 이름으로 바꾼다" "harness:reviewer 서브에이전트에 변경 검토를 맡긴다|reviewer 코드 리뷰" \
  "$(jq -r '.checks[0] | "\(.prompt)|\(.description)"' "$p/.harness/checks.json")"
assert_eq "old name: 다른 검사는 그대로 둔다" 'scripts/harness/record mine "make t"' "$(jq -r '.checks[1].prompt' "$p/.harness/checks.json")"
rm -f "$p/.claude/settings.local.json" "$p/.harness/checks.json"
jq 'del(.enabledPlugins["other@x"])' "$p/.claude/settings.json" > "$work/s.json" && mv "$work/s.json" "$p/.claude/settings.json"

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
  "$(jq -r '.extraKnownMarketplaces["ai-harness"].source.source' "$p/.claude/settings.local.json")"
assert_eq "dev: 공유 설정은 GitHub 그대로 둔다" "github" \
  "$(jq -r '.extraKnownMarketplaces["ai-harness"].source.source' "$p/.claude/settings.json")"
"$install" "$p" > /dev/null
assert_eq "dev 해제: --dev 없이 실행하면 디렉터리 마켓플레이스를 지운다" "null" \
  "$(jq -c '.extraKnownMarketplaces' "$p/.claude/settings.local.json")"
assert_eq "dev 해제: 로컬 설정의 다른 값은 지킨다" '["Skill(x)"]' "$(jq -c .permissions.deny "$p/.claude/settings.local.json")"

# --- 공유 설정이 git에서 무시되는 프로젝트 ---------------------------------------------------
printf '.claude/settings.json\n' >> "$q/.gitignore"
out="$("$install" "$q")"
case "$out" in *"settings.json이 git에서 무시된다"*) ok=yes ;; *) ok=no ;; esac
assert_eq "ignored: settings.json이 공유되지 않는다고 알린다" "yes" "$ok"

m="$work/perm"
new_project "$m"
"$init" "$m" > /dev/null

# --- 권한 규칙: 하네스가 넣었다가 빠진 규칙만 지운다 ------------------------------------------
jq '.permissions.deny += ["Bash(old-harness-rule)", "Bash(team-rule)"]' "$m/.claude/settings.json" > "$work/s" && mv "$work/s" "$m/.claude/settings.json"
jq '.permissions.deny += ["Bash(old-harness-rule)"]' "$m/.harness/harness.json" > "$work/h" && mv "$work/h" "$m/.harness/harness.json"
"$install" "$m" > /dev/null
assert_eq "perm: 하네스가 넣었는데 이제 없는 규칙을 지운다" "0" "$(jq '[.permissions.deny[] | select(. == "Bash(old-harness-rule)")] | length' "$m/.claude/settings.json")"
assert_eq "perm: 팀이 넣은 규칙은 남긴다" "1" "$(jq '[.permissions.deny[] | select(. == "Bash(team-rule)")] | length' "$m/.claude/settings.json")"
assert_eq "perm: 지금 넣는 규칙은 남는다" "1" "$(jq --arg r "$(jq -r '.permissions.deny[0]' "$template/.claude/settings.json")" '[.permissions.deny[] | select(. == $r)] | length' "$m/.claude/settings.json")"
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

# --- 예전 iOS 묶음을 프로젝트 코드로 넘긴다 (ADR 0024) -------------------------------------------
# 0.9.x 설치를 흉내 낸다: 옛 형식 설정, 파일 목록 없는 설치 기록, 묶음 폴더 전의 규칙 자리
h="$work/handover"
new_project "$h"
"$init" "$h" > /dev/null
printf '#!/usr/bin/env bash\n. "$(dirname "$0")/ios.sh"\necho "scripts/harness/unit-test --plan, scripts/harness/test-related"\n' > "$h/scripts/harness/unit-test"
chmod +x "$h/scripts/harness/unit-test"
printf '# ios\n' > "$h/scripts/harness/ios.sh"
printf '{}\n' > "$h/scripts/harness/ios-checks.json"
printf '# doctor\n' > "$h/scripts/harness/ios-doctor.sh"
printf -- '---\npaths: ["**/*.swift"]\n---\nscripts/harness/build를 쓴다\n' > "$h/.claude/rules/harness/swift.md"
mkdir -p "$h/.claude/rules/harness/ios" && printf '# review\n' > "$h/.claude/rules/harness/ios/review.md"
echo '{"schemaVersion":1,"generator":"tuist","app":{"scheme":"App"}}' > "$h/.harness/project.json"
jq 'del(.files) | .permissions.deny += ["Edit(**/*.pbxproj)"]' "$h/.harness/harness.json" > "$work/h" && mv "$work/h" "$h/.harness/harness.json"
jq '.permissions.deny += ["Edit(**/*.pbxproj)"]' "$h/.claude/settings.json" > "$work/s" && mv "$work/s" "$h/.claude/settings.json"
cat > "$h/.harness/checks.json" <<'JSON'
{ "schemaVersion": 1, "checks": [
  { "name": "unit-test", "prompt": "scripts/harness/unit-test를 실행하고 통과할 때까지 고친다", "run": "scripts/harness/passed unit-test" },
  { "name": "e2e", "prompt": ".claude/rules/harness/maestro.md를 따른다", "run": "scripts/harness/passed e2e" } ] }
JSON
out="$("$install" "$h")"
assert_eq "handover: 스크립트를 scripts/ios/로 옮긴다" "yes|yes|no" \
  "$([ -x "$h/scripts/ios/unit-test" ] && echo yes || echo no)|$([ -f "$h/scripts/ios/ios.sh" ] && echo yes || echo no)|$([ -e "$h/scripts/harness/unit-test" ] && echo yes || echo no)"
assert_eq "handover: 옮긴 스크립트가 쓰던 lib.sh를 함께 둔다" "yes" "$(same "$template/scripts/harness/lib.sh" "$h/scripts/ios/lib.sh")"
assert_eq "handover: 규칙을 프로젝트 규칙으로 옮긴다" "yes|yes|no|no" \
  "$([ -f "$h/.claude/rules/project/ios/swift.md" ] && echo yes || echo no)|$([ -f "$h/.claude/rules/project/ios/review.md" ] && echo yes || echo no)|$([ -e "$h/.claude/rules/harness/swift.md" ] && echo yes || echo no)|$([ -e "$h/.claude/rules/harness/ios" ] && echo yes || echo no)"
assert_eq "handover: 하네스 것(doctor 조각, 추천 검사)은 지운다" "no|no" \
  "$([ -e "$h/scripts/harness/ios-doctor.sh" ] && echo yes || echo no)|$([ -e "$h/scripts/harness/ios-checks.json" ] && echo yes || echo no)"
assert_eq "handover: 검사 목록의 경로를 바꾸고 passed는 그대로 둔다" "scripts/ios/unit-test를 실행하고 통과할 때까지 고친다|scripts/harness/passed unit-test" \
  "$(jq -r '.checks[0] | "\(.prompt)|\(.run)"' "$h/.harness/checks.json")"
assert_eq "handover: 옮긴 규칙을 가리키는 경로도 바꾼다" ".claude/rules/project/ios/maestro.md를 따른다" "$(jq -r '.checks[1].prompt' "$h/.harness/checks.json")"
assert_eq "handover: 옮긴 파일 안의 경로도 바꾼다 (이름이 겹치는 다른 경로는 그대로)" 'echo "scripts/ios/unit-test --plan, scripts/harness/test-related"' "$(sed -n 3p "$h/scripts/ios/unit-test")"
assert_eq "handover: 규칙 안의 경로도 바꾼다" "scripts/ios/build를 쓴다" "$(tail -1 "$h/.claude/rules/project/ios/swift.md")"
assert_eq "handover: 설정 형식은 옮긴 스크립트가 읽던 그대로 둔다" "1|App" "$(jq -r '"\(.schemaVersion)|\(.app.scheme)"' "$h/.harness/project.json")"
assert_eq "handover: Tuist 생성물을 generated로 적는다" "true" "$(jq '.generated | index("*.xcodeproj/*") != null' "$h/.harness/project.json")"
assert_eq "handover: 묶음이 넣은 권한은 프로젝트 규칙으로 남긴다" "1" "$(jq '[.permissions.deny[] | select(. == "Edit(**/*.pbxproj)")] | length' "$h/.claude/settings.json")"
case "$out" in *"직접 할 일"*"scripts/ios/"*"AGENTS.md"*) ok=yes ;; *) ok=no ;; esac
assert_eq "handover: 넘긴 것과 AGENTS.md에 적을 것을 알린다" "yes" "$ok"
assert_eq "handover: 두 번째 실행은 바뀐 것이 없다" "✓ sync · 바뀐 것 없음 · $h" "$("$install" "$h" | sed -n 1p)"
assert_eq "handover: 다음 갱신에서도 권한은 남는다" "1" "$(jq '[.permissions.deny[] | select(. == "Edit(**/*.pbxproj)")] | length' "$h/.claude/settings.json")"

# 하네스가 설치하지 않은(설치 기록에 없는) 같은 이름의 팀 스크립트는 옮기지 않는다
printf '#!/usr/bin/env bash\n' > "$p/scripts/harness/build"
"$install" "$p" > /dev/null
assert_eq "handover: 팀이 둔 scripts/harness/build는 그대로 둔다" "yes|no" "$([ -f "$p/scripts/harness/build" ] && echo yes || echo no)|$([ -e "$p/scripts/ios" ] && echo yes || echo no)"
rm -f "$p/scripts/harness/build"

finish
