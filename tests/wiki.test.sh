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

rm "$p/docs/wiki/home/bad.md"
mkdir -p "$p/docs/wiki/build"
cp "$p/docs/wiki/home/curation-max.md" "$p/docs/wiki/build/signing.md"
printf 'build/\n' > "$p/.gitignore"
out="$(run check 2>&1)" && code=0 || code=$?
assert_eq "check: git이 무시하는 기록이면 1" "1" "$code"
assert_eq "check: 무시하는 규칙을 알린다" \
  "$(printf '  docs/wiki/build/signing.md: git이 무시하는 경로라 커밋되지 않습니다 (.gitignore:1:build/). 폴더 이름을 바꾸거나 .gitignore를 고칩니다\n✗ wiki · 기록 3개 중 1개에 문제')" "$out"
rm "$p/.gitignore"
assert_eq "check: 무시하지 않으면 통과" "✓ wiki · 기록 3개" "$(run check)"

rm -rf "$p/docs/wiki"
assert_eq "기록 폴더가 없어도 check는 통과" "✓ wiki · 기록 없음" "$(run check)"
assert_eq "기록 폴더가 없으면 search는 없음" '· wiki · "홈"에 맞는 기록 없음' "$(run search 홈 || true)"
out="$(run 2>&1)" && code=0 || code=$?
assert_eq "인자가 없으면 2" "2" "$code"

# --- done: 마무리 단계의 위키 확인 (ADR 0032) ---------------------------------------------
sd="$p/.harness/state"
done_rc() { (cd "$p" && "$wiki" done > /dev/null 2>&1) && echo 0 || echo $?; }
assert_eq "done: 시작 커밋이 없으면 막지 않는다" "0" "$(done_rc)"
gitc() { git -C "$p" -c user.name=t -c user.email=t@t "$@"; }
# 시작 전부터 있던 기록은 형식이 틀려도 이번 작업의 확인에 넣지 않는다
mkdir -p "$p/docs/wiki/old"; printf '# 예전 기록\n' > "$p/docs/wiki/old/old.md"
gitc add docs/wiki/old/old.md; gitc commit -q -m init
git -C "$p" rev-parse HEAD > "$sd/task.base"
echo '{"title":"t","mode":"simple","stage":"finish"}' > "$sd/task.json"
date -u +%FT%TZ > "$sd/task.started"
rm -f "$sd/wiki.skip"
assert_eq "done: 위키를 바꾸지 않았고 이유도 없으면 1" "1" "$(done_rc)"
out="$( (cd "$p" && "$wiki" done) 2>&1 || true)"
assert_eq "  (wiki.skip에 이유를 쓰라고 한다)" "yes" "$(printf '%s' "$out" | grep -qF .harness/state/wiki.skip && echo yes || echo no)"
printf '\n  \n' > "$sd/wiki.skip"
assert_eq "done: 이유가 비어 있으면 1" "1" "$(done_rc)"
echo "문구만 바꿔 정한 정책이 없다" > "$sd/wiki.skip"
assert_eq "done: 이유를 적었으면 통과하고 이유를 보여 준다" "✓ wiki · 이번 작업은 기록하지 않음: 문구만 바꿔 정한 정책이 없다" "$(cd "$p" && "$wiki" done)"
rm "$sd/wiki.skip"
mkdir -p "$p/docs/wiki/home"
printf -- '---\nkind: rule\n---\n\n# 제목\n' > "$p/docs/wiki/home/new.md"
assert_eq "done: 새 기록의 형식이 틀리면 1" "1" "$(done_rc)"
cat > "$p/docs/wiki/home/new.md" <<'MD'
---
kind: rule
tags: [홈]
---

# 홈 추천은 20개까지만 보여 준다

## 규칙
20개에서 자른다
## 적용 범위
홈
## 근거
기획 논의
## 예외
없음
MD
assert_eq "done: 이번에 바꾼 기록(커밋 전)만 검사해 통과한다" "✓ wiki · 이번에 바꾼 기록 1개" "$(cd "$p" && "$wiki" done)"
gitc add docs/wiki/home/new.md; gitc commit -q -m wiki
assert_eq "done: 커밋한 기록도 센다" "0" "$(done_rc)"
git -C "$p" rev-parse HEAD > "$sd/task.base"
gitc rm -q docs/wiki/home/new.md
assert_eq "done: 기록을 지운 것도 바꾼 것으로 본다" "✓ wiki · 기록 1개를 지움" "$(cd "$p" && "$wiki" done)"
gitc commit -q -m rm
git -C "$p" rev-parse HEAD > "$sd/task.base"
# 한글·공백 경로도 이번에 바꾼 기록으로 센다(core.quotePath, 파일마다 따로 검사)
mkdir -p "$p/docs/wiki/홈 화면"
printf -- '---\nkind: rule\n---\n\n# 제목\n' > "$p/docs/wiki/홈 화면/bad.md"
out="$( (cd "$p" && "$wiki" done) 2>&1 || true)"
assert_eq "done: 한글·공백 경로의 기록도 형식을 검사한다" "yes|no" \
  "$(printf '%s' "$out" | grep -qF '이번에 바꾼 기록 1개 중 1개에 문제' && echo yes || echo no)|$(printf '%s' "$out" | grep -qF '파일이 없습니다' && echo yes || echo no)"
rm -rf "$p/docs/wiki/홈 화면"
# 작업 전부터 있던 추적 안 된 초안은 이번 작업의 변경이 아니다
# 형식이 맞는 초안이라, 이번 변경으로 잘못 세면 통과(0)가 나온다
printf -- '---\nkind: rule\ntags: [a]\n---\n\n# 초안\n\n## 규칙\nx\n## 적용 범위\nx\n## 근거\nx\n## 예외\n없음\n' > "$p/docs/wiki/old/draft.md"
assert_eq "  (초안 형식은 맞다)" "0" "$( (cd "$p" && "$wiki" check docs/wiki/old/draft.md > /dev/null) && echo 0 || echo 1)"
touch -t 202001010000 "$p/docs/wiki/old/draft.md"
assert_eq "done: 작업 전부터 있던 추적 안 된 초안은 세지 않는다" "1" "$(done_rc)"
rm "$p/docs/wiki/old/draft.md"
# git이 무시하는 곳에 쓴 기록은 그 사실을 알린다
printf 'docs/wiki/tmp/\n' > "$p/.gitignore"
mkdir -p "$p/docs/wiki/tmp"; printf '# x\n' > "$p/docs/wiki/tmp/x.md"
out="$( (cd "$p" && "$wiki" done) 2>&1 || true)"
assert_eq "done: 무시되는 경로에 쓴 기록을 알린다" "yes" "$(printf '%s' "$out" | grep -qF 'git이 무시하는 경로에 쓴 기록' && echo yes || echo no)"
rm -rf "$p/docs/wiki/tmp" "$p/.gitignore"
# 하위 폴더에 설치한 프로젝트(모노레포)도 프로젝트 루트 기준으로 본다
m="$work/mono"; mp="$m/apps/ios"
mkdir -p "$mp/.harness/state" "$mp/docs/wiki/home"
echo '{"schemaVersion":1}' > "$mp/.harness/project.json"
git -C "$m" init -q -b main; git -C "$m" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$m" rev-parse HEAD > "$mp/.harness/state/task.base"
echo '{"title":"t","mode":"simple","stage":"finish"}' > "$mp/.harness/state/task.json"
printf -- '---\nkind: rule\n---\n\n# 제목\n' > "$mp/docs/wiki/home/bad.md"
git -C "$m" add apps/ios/docs/wiki/home/bad.md; git -C "$m" -c user.name=t -c user.email=t@t commit -q -m bad
assert_eq "done: 하위 폴더 설치에서도 커밋한 기록의 형식을 검사한다" "1" "$( (cd "$mp" && "$wiki" done > /dev/null 2>&1) && echo 0 || echo $?)"

finish
