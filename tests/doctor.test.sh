#!/usr/bin/env bash
# doctor: init으로 설치한 임시 프로젝트를 점검한다. claude CLI는 가짜를 PATH에 넣어 플러그인 목록을 정한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export HARNESS_OFFLINE=1
version="$(jq -r .version "$here/../plugin/.claude-plugin/plugin.json")"

p="$work/app"
mkdir -p "$p/Sample.xcodeproj"
cat > "$p/Sample.xcodeproj/project.pbxproj" <<'PBX'
// !$*UTF8*$!
{ archiveVersion = 1; objectVersion = 77; objects = {
  T1 = {isa = PBXNativeTarget; buildConfigurationList = L1; name = Sample; productType = "com.apple.product-type.application"; };
  L1 = {isa = XCConfigurationList; buildConfigurations = (C1, ); };
  C1 = {isa = XCBuildConfiguration; name = Debug; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = com.example.Sample; }; };
}; rootObject = T1; }
PBX
(cd "$p" && git init -q -b main && printf '.claude/settings.local.json\n' > .gitignore)
"$here/../scripts/init" "$p" > /dev/null
root="$(cd "$p" && pwd -P)"

# 가짜 claude: plugin list --json이 $FAKE_PLUGINS를 출력한다.
mkdir -p "$work/bin"
cat > "$work/bin/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$FAKE_PLUGINS"
FAKE
chmod +x "$work/bin/claude"
export PATH="$work/bin:$PATH"

plugins() { # 버전 [enabled] [projectPath]
  jq -nc --arg v "$1" --argjson e "${2:-true}" --arg p "${3:-$root}" \
    '[{id: "ios-harness@ios-ai-harness", version: $v, scope: "project", enabled: $e, projectPath: $p}]'
}
run_doctor() {
  set +e
  out="$(cd "$p" && HARNESS_ROOT="$root" scripts/harness/doctor 2>&1)"; code=$?
  set -e
}
has() { case "$out" in *"$1"*) echo yes ;; *) echo no ;; esac; }

export FAKE_PLUGINS="$(plugins "$version")"
run_doctor
assert_eq "ok: 문제가 없으면 0으로 끝난다" "0" "$code"
assert_eq "ok: 한 줄로 끝난다" "✓ doctor · 문제 없음 · 하네스 $version" "$out"

export FAKE_PLUGINS="$(plugins 0.0.1)"
run_doctor
assert_eq "old plugin: 실패한다" "1" "$code"
assert_eq "old plugin: 플러그인을 갱신하라고 한다" "yes" "$(has "claude plugin update ios-harness@ios-ai-harness")"

export FAKE_PLUGINS="$(plugins 99.0.0)"
run_doctor
assert_eq "old files: 프로젝트 파일을 sync하라고 한다" "yes" "$(has "프로젝트 파일($version)이 플러그인(99.0.0)보다 오래됐다")"

export FAKE_PLUGINS="$(plugins "$version" true /somewhere/else)"
run_doctor
assert_eq "not installed: 다른 프로젝트에 설치된 것은 세지 않는다" "yes" "$(has "이 프로젝트에 설치되지 않았다")"

export FAKE_PLUGINS="$(plugins "$version" false)"
run_doctor
assert_eq "disabled: 꺼져 있으면 켜라고 한다" "yes" "$(has "claude plugin enable")"

# 디렉터리 마켓플레이스(--dev)는 폴더의 버전을 본다.
export FAKE_PLUGINS="$(jq -nc --arg v "$version" --arg p "$root" '[{id: "ios-harness@ios-ai-harness", version: "0.0.1", folderVersion: $v, enabled: true, projectPath: $p}]')"
run_doctor
assert_eq "dev: 폴더 버전이 맞으면 통과한다" "0" "$code"

export FAKE_PLUGINS="$(plugins "$version")"
printf '# 다른 지침\n' > "$p/CLAUDE.md"
printf '.claude/settings.json\n' >> "$p/.gitignore"
run_doctor
assert_eq "broken: CLAUDE.md import가 없으면 문제다" "yes" "$(has "✕ CLAUDE.md가 AGENTS.md를 불러오지 않는다")"
assert_eq "broken: settings.json이 무시되면 주의를 준다" "yes" "$(has "! .claude/settings.json이 git에서 무시돼")"
assert_eq "broken: 요약 줄에 개수를 쓴다" "✕ doctor · 문제 1 · 주의 1 · 하네스 $version" "$(printf '%s\n' "$out" | head -1)"

# 규칙 폴더가 무시되는지는 어느 프로젝트에나 있는 wiki.md로 본다 (swift.md는 Swift 프로젝트에만 있다)
printf '.claude/*\n' >> "$p/.gitignore"
rm -f "$p/.claude/rules/harness/swift.md"
run_doctor
assert_eq "rules ignored: swift.md가 없어도 규칙 폴더가 무시되면 주의를 준다" "yes" "$(has "! .claude/rules/가 git에서 무시돼")"

finish
