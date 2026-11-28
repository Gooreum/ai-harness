#!/usr/bin/env bash
# wiki-use.sh와 wiki stats: 세션별 위키 검색·열람을 남기고, 결과가 있었는데 열지 않은 검색을 세는지 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
hook="$here/../plugin/hooks/wiki-use.sh"
wiki="$here/../template/scripts/harness/wiki"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/.harness" "$p/docs/wiki/home" "$p/docs/wiki/기술" "$p/App"
echo '{"schemaVersion":1,"generator":"xcodeproj"}' > "$p/.harness/project.json"
(cd "$p" && git init -q -b main)
log="$p/.harness/state/wiki-use.jsonl"
lines() { [ -f "$log" ] && grep -c . "$log" || echo 0; }

search() { # 세션 명령 출력 [응답 형식: object|string]
  jq -n --arg s "$1" --arg c "$2" --arg o "$3" --arg k "${4:-object}" --arg cwd "$p" \
    '{hook_event_name: "PostToolUse", session_id: $s, cwd: $cwd, tool_name: "Bash", tool_input: {command: $c},
      tool_response: (if $k == "string" then $o else {stdout: $o, stderr: "", interrupted: false} end)}' | "$hook"
}
readf() { # 세션 파일 [cwd]
  jq -n --arg s "$1" --arg f "$2" --arg cwd "${3:-$p}" \
    '{hook_event_name: "PostToolUse", session_id: $s, cwd: $cwd, tool_name: "Read", tool_input: {file_path: $f}}' | "$hook"
}
stats() { (cd "$p" && "$wiki" stats); }

# 기록이 없을 때
assert_eq "stats: 기록이 없으면 알리고 0" "0|yes" \
  "$(stats > "$work/o" 2>&1; echo $?)|$(grep -q '검색·열람 기록 없음' "$work/o" && echo yes || echo no)"

# 위키와 상관없는 Bash·Read는 남기지 않는다
search s1 "git status" ""
readf s1 "$p/App/A.swift"
readf s1 "$p/docs/wiki/home/notes.txt"
assert_eq "위키와 상관없는 도구 호출은 남기지 않는다" "0" "$(lines)"

# 검색: 출력의 경로를 걸린 기록으로 남긴다
out1="$(printf 'rule\tdocs/wiki/home/curation-max.md\t홈 추천은 20개까지\nfact\tdocs/wiki/기술/store-platform-facts.md\t업로드가 막히는 경우를 모았다\n')"
search s1 "scripts/harness/wiki search 홈 추천 | head -5" "$out1"
assert_eq "검색: 검색어와 걸린 기록" '홈 추천|docs/wiki/home/curation-max.md,docs/wiki/기술/store-platform-facts.md' \
  "$(tail -1 "$log" | jq -r '"\(.query)|\(.hits | join(","))"')"

# 열람: 절대·상대 경로 모두 프로젝트 루트 기준으로 남긴다
readf s1 "$p/docs/wiki/home/curation-max.md"
readf s1 "curation-max.md" "$p/docs/wiki/home"
assert_eq "열람: 루트 기준 경로" "docs/wiki/home/curation-max.md" "$(tail -1 "$log" | jq -r .path)"

# 결과 없는 검색, 글자로 온 응답
search s2 "scripts/harness/wiki search 없는말" "· wiki · \"없는말\"에 맞는 기록 없음"
assert_eq "결과 없는 검색도 남긴다" "0" "$(tail -1 "$log" | jq '.hits | length')"
search s2 "./scripts/harness/wiki search 업로드" "$(printf 'fact\tdocs/wiki/기술/store-platform-facts.md\t업로드\n')" string
assert_eq "응답이 글자여도 걸린 기록을 읽는다" "docs/wiki/기술/store-platform-facts.md" "$(tail -1 "$log" | jq -r '.hits[0]')"

# s3: 걸렸는데 다른 기록만 열었다. 검색 전에 연 것은 검색 뒤 열람으로 세지 않는다
readf s3 "$p/docs/wiki/home/curation-max.md"
search s3 "scripts/harness/wiki search 업로드" "$(printf 'fact\tdocs/wiki/기술/store-platform-facts.md\t업로드\n')"

# 프로젝트 밖이면 남기지 않는다
n="$(lines)"
readf s9 "/tmp/x.md" "/tmp"
assert_eq "프로젝트 밖에서는 남기지 않는다" "$n" "$(lines)"

stats > "$work/o"
assert_eq "stats: 요약 줄" "wiki · 세션 3개 · 검색 4회(결과 있음 3) · 열람 3회" "$(sed -n 1p "$work/o")"
assert_eq "stats: 열지 않은 검색 수" "yes" "$(grep -q '아무것도 열지 않은 검색 2회' "$work/o" && echo yes || echo no)"
assert_eq "stats: 열지 않은 검색에 검색어와 기록" "yes" \
  "$(grep -q '"업로드"  → docs/wiki/기술/store-platform-facts.md' "$work/o" && echo yes || echo no)"
assert_eq "stats: 기록별 걸림/엶" "3 / 0  docs/wiki/기술/store-platform-facts.md|1 / 1  docs/wiki/home/curation-max.md" \
  "$(grep -E '^    [0-9]+ / ' "$work/o" | sed 's/^    //' | paste -sd '|' -)"

# 깨진 줄이 있으면 알린다
echo '{broken' >> "$log"
assert_eq "stats: 깨진 기록이면 1" "1" "$(stats > /dev/null 2>&1; echo $?)"

finish
