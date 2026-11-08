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
mkdir -p "$p"
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
    '[{id: "harness@ai-harness", version: $v, scope: "project", enabled: $e, projectPath: $p}]'
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
assert_eq "old plugin: 플러그인을 갱신하라고 한다" "yes" "$(has "claude plugin update harness@ai-harness")"

export FAKE_PLUGINS="$(plugins 99.0.0)"
run_doctor
assert_eq "old files: 프로젝트 파일을 sync하라고 한다" "yes" "$(has "프로젝트 파일($version)이 플러그인(99.0.0)보다 오래됐다")"

export FAKE_PLUGINS="$(plugins "$version" true /somewhere/else)"
run_doctor
assert_eq "not installed: 다른 프로젝트에 설치된 것은 세지 않는다" "yes" "$(has "이 프로젝트에 설치되지 않았다")"

export FAKE_PLUGINS="$(plugins "$version" false)"
run_doctor
assert_eq "disabled: 꺼져 있으면 켜라고 한다" "yes" "$(has "claude plugin enable")"

# 예전 이름의 플러그인이 같이 켜져 있으면 훅이 두 번 돈다.
export FAKE_PLUGINS="$(jq -nc --arg v "$version" --arg p "$root" '[{id: "harness@ai-harness", version: $v, scope: "project", enabled: true, projectPath: $p},
  {id: "ios-harness@ios-ai-harness", version: "0.9.11", scope: "project", enabled: true, projectPath: $p}]')"
run_doctor
assert_eq "old name: 실패한다" "1" "$code"
assert_eq "old name: 지우라고 한다" "yes" "$(has "claude plugin uninstall ios-harness@ios-ai-harness")"
export FAKE_PLUGINS="$(jq -nc --arg v "$version" --arg p "$root" '[{id: "harness@ai-harness", version: $v, scope: "project", enabled: true, projectPath: $p},
  {id: "ios-harness@ios-ai-harness", version: "0.9.11", scope: "project", enabled: false, projectPath: $p}]')"
run_doctor
assert_eq "old name: 꺼져 있으면 통과한다" "0" "$code"

# 디렉터리 마켓플레이스(--dev)는 폴더의 버전을 본다.
export FAKE_PLUGINS="$(jq -nc --arg v "$version" --arg p "$root" '[{id: "harness@ai-harness", version: "0.0.1", folderVersion: $v, enabled: true, projectPath: $p}]')"
run_doctor
assert_eq "dev: 폴더 버전이 맞으면 통과한다" "0" "$code"

export FAKE_PLUGINS="$(plugins "$version")"
printf '# 다른 지침\n' > "$p/CLAUDE.md"
printf '.claude/settings.json\n' >> "$p/.gitignore"
run_doctor
assert_eq "broken: CLAUDE.md import가 없으면 문제다" "yes" "$(has "✕ CLAUDE.md가 AGENTS.md를 불러오지 않는다")"
assert_eq "broken: settings.json이 무시되면 주의를 준다" "yes" "$(has "! .claude/settings.json이 git에서 무시돼")"
assert_eq "broken: 요약 줄에 개수를 쓴다" "✕ doctor · 문제 1 · 주의 1 · 하네스 $version" "$(printf '%s\n' "$out" | head -1)"

# 규칙 폴더가 무시되는지는 어느 프로젝트에나 있는 wiki.md로 본다
printf '.claude/*\n' >> "$p/.gitignore"
run_doctor
assert_eq "rules ignored: 규칙 폴더가 무시되면 주의를 준다" "yes" "$(has "! .claude/rules/가 git에서 무시돼")"

printf '# 지침\n@AGENTS.md\n' > "$p/CLAUDE.md"

# --- 검사 목록(checks.json)의 run과 결과 ---------------------------------------------------
# setup 안내대로 추천 검사를 옮기고, 결과를 직접 남기는 저장소 도구(scripts/ios/unit-test)를 부르는 목록
mkdir -p "$p/scripts/ios" && printf '#!/bin/sh\n' > "$p/scripts/ios/unit-test" && chmod +x "$p/scripts/ios/unit-test"
jq '{schemaVersion: 1, checks: ([{name: "unit-test", prompt: "`scripts/ios/unit-test`를 실행하고 통과할 때까지 고친다", run: "scripts/harness/passed unit-test"}] + .checks)}' \
  "$p/scripts/harness/common-checks.json" > "$work/checks.bak"
jq '.checks += [
  {name: "typecheck", prompt: "scripts/harness/record typecheck \"npm run typecheck\"를 실행한다", run: "scripts/harness/passed typecheck"},
  {name: "ghost", prompt: "알아서 돌린다", run: "scripts/harness/passed ghost"},
  {name: "missing", prompt: "x", run: "scripts/harness/nothing-here"},
  {name: "nocmd", prompt: "x", run: "no-such-command-xyz --flag"}]' "$work/checks.bak" > "$p/.harness/checks.json"
run_doctor
assert_eq "checks: record로 만드는 결과는 통과한다" "no" "$(has "'typecheck'")"
assert_eq "checks: 결과를 직접 남기는 도구와 리뷰는 통과한다" "nono" "$(has "'unit-test'")$(has "'review'")"
assert_eq "checks: 결과를 만드는 곳이 없으면 문제다" "yes" "$(has "'ghost'이 결과 'ghost'를 확인하지만 만드는 곳이 없다")"
assert_eq "checks: 프로젝트 안 run 명령이 없으면 문제다" "yes" "$(has "'missing' run 명령이 없다: scripts/harness/nothing-here")"
assert_eq "checks: PATH에 없는 run 명령은 문제다" "yes" "$(has "'nocmd' run 명령을 찾지 못했다: no-such-command-xyz")"
assert_eq "checks: passed가 아닌 run은 자동 실행된다고 알린다" "yes" "$(has "묻지 않고 실행한다 — missing: scripts/harness/nothing-here; nocmd: no-such-command-xyz --flag")"
cp "$work/checks.bak" "$p/.harness/checks.json"
run_doctor
assert_eq "checks: run이 모두 passed면 자동 실행 참고를 띄우지 않는다" "no" "$(has "묻지 않고 실행한다")"
assert_eq "wiki: 단계 지시에 위키가 없으면 주의를 준다" "yes|0" "$(has "! checks.json의 단계 지시(stages)에 위키가 없어")|$code"
jq '. + {stages: {finish: {prompt: "x"}}}' "$work/checks.bak" > "$p/.harness/checks.json"
run_doctor
assert_eq "wiki: 위키가 아닌 단계 지시만 있어도 주의를 준다" "yes" "$(has "위키가 없어")"
jq --slurpfile c "$p/scripts/harness/common-checks.json" '. + {stages: $c[0].stages}' "$work/checks.bak" > "$p/.harness/checks.json"
run_doctor
assert_eq "wiki: 추천 위키 지시를 옮기면 주의가 없다" "no" "$(has "위키가 없어")"
jq '. + {wiki: false}' "$work/checks.bak" > "$p/.harness/checks.json"
run_doctor
assert_eq "wiki: \"wiki\": false면 묻지 않는다" "no" "$(has "위키가 없어")"
rm -f "$p/.harness/checks.json"

rc=0; out="$(cd "$p" && env PATH="$(nojq_path "$work")" /bin/bash scripts/harness/doctor)" || rc=$?
assert_eq "jq가 없으면 문제로 알린다" "1" "$rc"
case "$out" in *'jq가 없다'*) ok=yes ;; *) ok="$out" ;; esac
assert_eq "  jq가 없으면 훅이 꺼진다고 알린다" "yes" "$ok"

finish
