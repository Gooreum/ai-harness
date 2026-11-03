#!/usr/bin/env bash
# wiki: 기록 찾기(search)와 형식 검사(check)를 가짜 프로젝트로 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
wiki="$here/../template/scripts/harness/wiki"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/.harness" "$p/docs/wiki/ui" "$p/docs/wiki/home"
echo '{"schemaVersion":1,"generator":"xcodeproj"}' > "$p/.harness/project.json"
(cd "$p" && git init -q -b main)
run() { (cd "$p" && "$wiki" "$@"); }

cat > "$p/docs/wiki/ui/sheet-item.md" <<'MD'
---
kind: fact
tags: [SwiftUI, 시트]
---

# .sheet(isPresented:)와 if let을 함께 쓰면 빈 시트가 뜬다

## 확인된 동작
값을 넣기 전에 시트가 먼저 뜬다
## 확인 방법
재현
## 함의
.sheet(item:)을 쓴다
## 안 다룬 것
fullScreenCover
MD
cat > "$p/docs/wiki/home/curation-max.md" <<'MD'
---
kind: rule
tags: [홈, 노출개수]
---

# 홈 추천은 20개까지만 보여 준다

## 규칙
21개 이상이면 자른다
## 적용 범위
홈 추천
## 근거
2026-09-07 기획 논의
## 예외
없음
MD

assert_eq "search: 단어가 든 기록을 종류·경로·제목으로" \
  "$(printf 'fact\tdocs/wiki/ui/sheet-item.md\t.sheet(isPresented:)와 if let을 함께 쓰면 빈 시트가 뜬다')" "$(run search sheet)"
assert_eq "search: 대소문자 무시, 모든 단어가 있어야" "docs/wiki/home/curation-max.md" "$(run search 홈 20개 | cut -f2)"
out="$(run search 홈 sheet)" && code=0 || code=$?
assert_eq "search: 없으면 1" "1" "$code"
assert_eq "search: 없다고 알린다" '· wiki · "홈 sheet"에 맞는 기록 없음' "$out"
assert_eq "search: 검색마다 한 줄씩 기록한다" "3" "$(wc -l < "$p/.harness/state/wiki-search.log" | tr -d ' ')"
assert_eq "search: 기록에 검색어와 결과 수" "홈 sheet	0" "$(tail -n1 "$p/.harness/state/wiki-search.log" | cut -f2-)"

assert_eq "check: 올바른 기록" "✓ wiki · 기록 2개" "$(run check)"

cat > "$p/docs/wiki/home/bad.md" <<'MD'
---
kind: policy
---

## 규칙
MD
out="$(run check 2>&1)" && code=0 || code=$?
assert_eq "check: 문제가 있으면 1" "1" "$code"
assert_eq "check: 문제를 파일별로" "$(printf '  docs/wiki/home/bad.md: kind는 fact 또는 rule이어야 합니다 (지금: policy)\n  docs/wiki/home/bad.md: tags가 필요합니다 (예: tags: [시트, SwiftUI])\n  docs/wiki/home/bad.md: 제목(# 한 줄 요약)이 없습니다\n✗ wiki · 기록 3개 중 1개에 문제')" "$out"

printf -- '---\nkind: rule\ntags: [a]\n---\n\n# 제목\n\n## 규칙\n## 근거\n' > "$p/docs/wiki/home/bad.md"
assert_eq "check: 빠진 항목을 알린다" "$(printf '  docs/wiki/home/bad.md: "## 적용 범위" 항목이 없습니다\n  docs/wiki/home/bad.md: "## 예외" 항목이 없습니다')" \
  "$(run check docs/wiki/home/bad.md 2>/dev/null || true)"
printf '# 머리말 없음\n' > "$p/docs/wiki/home/bad.md"
assert_eq "check: 머리말이 없으면" "  docs/wiki/home/bad.md: 첫 줄이 머리말(---)이 아닙니다" "$(run check docs/wiki/home/bad.md 2>/dev/null || true)"

rm -rf "$p/docs/wiki"
assert_eq "기록 폴더가 없어도 check는 통과" "✓ wiki · 기록 없음" "$(run check)"
assert_eq "기록 폴더가 없으면 search는 없음" '· wiki · "홈"에 맞는 기록 없음' "$(run search 홈 || true)"
out="$(run 2>&1)" && code=0 || code=$?
assert_eq "인자가 없으면 2" "2" "$code"

finish
