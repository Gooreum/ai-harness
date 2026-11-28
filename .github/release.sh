#!/usr/bin/env bash
# main에 머지되면 plugin/.claude-plugin/plugin.json의 버전을 읽어 v<버전> 태그를 달고 GitHub 릴리스를 만든다.
# 버전을 올리지 않은 머지면 태그가 이미 있으므로, 이 스크립트는 아무것도 하지 않는다.
# 노트에는 지난 태그 이후 커밋 제목과 비교 링크를 적는다. DRY_RUN=1이면 노트만 출력한다.
set -euo pipefail

v="$(jq -r '.version // empty' plugin/.claude-plugin/plugin.json)"
[ -n "$v" ] || { echo "plugin.json에 version이 없다" >&2; exit 1; }
tag="v$v"
if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
  echo "$tag 태그가 이미 있어 릴리스를 만들지 않는다"
  exit 0
fi
prev="$(git describe --tags --abbrev=0 --match 'v*' HEAD 2> /dev/null || true)"
day="$(git log -1 --format=%cs HEAD)"
notes="$(mktemp)"
{
  echo "## 바뀐 점"
  git log --no-merges --format='- %s' ${prev:+"$prev..HEAD"}
  if [ -n "$prev" ]; then
    echo
    echo "전체 변경: https://github.com/${GITHUB_REPOSITORY:-Gooreum/ai-harness}/compare/$prev...$tag"
  fi
} > "$notes"
if [ -n "${DRY_RUN:-}" ]; then
  echo "$tag ($day)"
  cat "$notes"
  exit 0
fi
git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
  tag -a "$tag" -m "harness $v ($day)"
git push origin "$tag"
gh release create "$tag" --verify-tag --title "$tag ($day)" --notes-file "$notes" --latest
echo "$tag 릴리스를 만들었다"
