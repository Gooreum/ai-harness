#!/usr/bin/env bash
# 개발 중인 하네스를 프로젝트에 설치하거나 갱신한다.
# 여러 번 실행해도 결과가 같다. 정식 설치·갱신 도구(init/sync/doctor)는 후보 14에서 만든다.
# 무엇을 어떻게 다루는지는 docs/template.md에 있다.
set -euo pipefail

usage() {
  cat <<'EOF'
사용법: scripts/dev-install.sh <프로젝트 경로>

  template/의 파일을 프로젝트에 설치한다.
  - scripts/harness/, .harness/.gitignore, .claude/rules/harness/는 template과 같게 맞춘다
  - AGENTS.md는 하네스 관리 블록만 넣거나 바꾸고, 프로젝트 영역은 건드리지 않는다
  - .claude/settings.json에는 권한 규칙을 합친다 (기존 내용 유지)
  - .claude/settings.local.json에 이 저장소를 로컬 마켓플레이스로 등록하고 플러그인을 켠다
  - .harness/project.json이 없으면 scripts/detect로 초안을 만든다
EOF
}

case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "") usage >&2; exit 2 ;;
esac
command -v jq >/dev/null 2>&1 || { echo "dev-install: jq가 필요합니다" >&2; exit 1; }
[ -d "$1" ] || { echo "dev-install: 디렉터리가 없습니다: $1" >&2; exit 2; }

target_project_dir="$(cd "$1" && pwd)"                  # 하네스를 설치할 iOS 프로젝트
harness_repo_dir="$(cd "$(dirname "$0")/.." && pwd)"    # 이 스크립트가 있는 하네스 저장소
template_dir="$harness_repo_dir/template"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

changes=""
todos=""
changed() { changes="$changes    $1"$'\n'; }
todo() { todos="$todos    $1"$'\n'; }

# 내용이 다를 때만 덮어쓴다. 실행 권한도 원본을 따른다.
install_file() { # template 기준 상대 경로
  local template_file="$template_dir/$1" project_file="$target_project_dir/$1"
  if [ -f "$project_file" ] && cmp -s "$template_file" "$project_file"; then return 0; fi
  mkdir -p "$(dirname "$project_file")"
  cp -p "$template_file" "$project_file"
  changed "$1"
}

# 내용이 바뀔 때만 파일을 쓴다.
write_if_changed() { # 대상경로 새내용파일 표시이름
  local dest_file="$1" new_content_file="$2" label="$3"
  if [ -f "$dest_file" ] && cmp -s "$new_content_file" "$dest_file"; then return 0; fi
  mkdir -p "$(dirname "$dest_file")"
  cp "$new_content_file" "$dest_file"
  changed "$label"
}

# --- 1. 프로젝트 설정 파일 -------------------------------------------------------

if [ ! -f "$target_project_dir/.harness/project.json" ]; then
  if ! "$harness_repo_dir/scripts/detect" --write "$target_project_dir" > /dev/null 2> "$tmp_dir/detect.log"; then
    cat "$tmp_dir/detect.log" >&2
    exit 1
  fi
  changed ".harness/project.json (detect 초안)"
  todo ".harness/project.json의 값이 맞는지 확인한다 (스킴, 시뮬레이터, 명령)"
fi

# --- 2. 통째로 관리하는 파일 -------------------------------------------------------

(cd "$template_dir" && find scripts/harness .harness .claude/rules/harness -type f ! -name '.DS_Store') | LC_ALL=C sort > "$tmp_dir/managed"
while IFS= read -r rel_path; do
  install_file "$rel_path"
done < "$tmp_dir/managed"

# 템플릿에서 사라진 하네스 규칙은 프로젝트에서도 지운다.
if [ -d "$target_project_dir/.claude/rules/harness" ]; then
  (cd "$target_project_dir" && find .claude/rules/harness -type f ! -name '.DS_Store') | LC_ALL=C sort > "$tmp_dir/installed-rules"
  while IFS= read -r rel_path; do
    if ! grep -qxF "$rel_path" "$tmp_dir/managed"; then
      rm "$target_project_dir/$rel_path"
      changed "$rel_path (삭제: template에 없음)"
    fi
  done < "$tmp_dir/installed-rules"
fi

if [ ! -d "$target_project_dir/.claude/rules/project" ]; then
  install_file ".claude/rules/project/.gitkeep"
fi

# --- 3. AGENTS.md ------------------------------------------------------------

awk '/<!-- harness:begin/{f=1} f{print} /<!-- harness:end -->/{f=0}' "$template_dir/AGENTS.md" > "$tmp_dir/block"
agents_md="$target_project_dir/AGENTS.md"
if [ ! -f "$agents_md" ]; then
  app_scheme="$(jq -r '.app.scheme // empty' "$target_project_dir/.harness/project.json")"
  sed "1s/^# 프로젝트 이름\$/# ${app_scheme:-프로젝트 이름}/" "$template_dir/AGENTS.md" > "$tmp_dir/agents"
  write_if_changed "$agents_md" "$tmp_dir/agents" "AGENTS.md (새로 만듦)"
  todo "AGENTS.md 위쪽 프로젝트 영역(소개, 구조, 프로젝트 규칙)을 채운다"
elif grep -q '<!-- harness:begin' "$agents_md"; then
  # 관리 블록만 template의 블록으로 바꾼다.
  awk -v block="$tmp_dir/block" '
    /<!-- harness:begin/ { while ((getline line < block) > 0) print line; skip = 1; next }
    skip && /<!-- harness:end -->/ { skip = 0; next }
    !skip { print }' "$agents_md" > "$tmp_dir/agents"
  write_if_changed "$agents_md" "$tmp_dir/agents" "AGENTS.md (관리 블록 갱신)"
else
  { cat "$agents_md"; echo; cat "$tmp_dir/block"; } > "$tmp_dir/agents"
  write_if_changed "$agents_md" "$tmp_dir/agents" "AGENTS.md (끝에 관리 블록 추가)"
  todo "AGENTS.md의 기존 내용을 프로젝트 영역(소개, 구조, 프로젝트 규칙)으로 정리하고, 관리 블록과 겹치거나 충돌하는 내용을 지운다"
fi

# --- 4. CLAUDE.md ------------------------------------------------------------

if [ ! -f "$target_project_dir/CLAUDE.md" ]; then
  install_file "CLAUDE.md"
elif ! grep -qx '@AGENTS.md' "$target_project_dir/CLAUDE.md"; then
  todo "CLAUDE.md에 @AGENTS.md import가 없다. 그 전까지 Claude Code는 AGENTS.md를 읽지 않는다. 내용을 AGENTS.md 프로젝트 영역으로 옮기고 template/CLAUDE.md 형태로 바꾼다"
fi

# --- 5. 권한 규칙: .claude/settings.json에 합친다 -------------------------------------

settings_json="$target_project_dir/.claude/settings.json"
if [ -f "$settings_json" ]; then
  jq -s '
    def addMissing($a; $b): ($a // []) + [ ($b // [])[] | . as $x | select((($a // []) | index($x)) | not) ];
    .[0] as $p | .[1] as $t
    | $p
    | .permissions.deny = addMissing($p.permissions.deny; $t.permissions.deny)
    | .permissions.ask = addMissing($p.permissions.ask; $t.permissions.ask)' \
    "$settings_json" "$template_dir/.claude/settings.json" > "$tmp_dir/settings"
  write_if_changed "$settings_json" "$tmp_dir/settings" ".claude/settings.json (권한 규칙 합침)"
else
  install_file ".claude/settings.json"
fi

# --- 6. 로컬 플러그인: .claude/settings.local.json ------------------------------------

local_settings_json="$target_project_dir/.claude/settings.local.json"
local_settings_input="$local_settings_json"   # 아직 없으면 빈 JSON에서 시작한다
if [ ! -f "$local_settings_input" ]; then
  echo '{}' > "$tmp_dir/empty.json"
  local_settings_input="$tmp_dir/empty.json"
fi
jq --arg path "$harness_repo_dir" '
  .extraKnownMarketplaces["ios-ai-harness"] = { source: { source: "directory", path: $path } }
  | .enabledPlugins["ios-harness@ios-ai-harness"] = true' "$local_settings_input" > "$tmp_dir/local"
write_if_changed "$local_settings_json" "$tmp_dir/local" ".claude/settings.local.json (로컬 플러그인 켬)"
if git -C "$target_project_dir" rev-parse --git-dir > /dev/null 2>&1 \
  && ! git -C "$target_project_dir" check-ignore -q .claude/settings.local.json; then
  todo ".claude/settings.local.json이 git에서 무시되지 않는다. 이 저장소의 절대 경로가 들어 있으니 .gitignore에 추가한다"
fi

# --- 결과 ---------------------------------------------------------------------

if [ -z "$changes" ]; then
  echo "✓ dev-install · 바뀐 것 없음 · $target_project_dir"
else
  echo "✓ dev-install · $target_project_dir"
  echo "  바꾼 파일:"
  printf '%s' "$changes"
fi
if [ -n "$todos" ]; then
  echo "  직접 할 일:"
  printf '%s' "$todos"
fi
