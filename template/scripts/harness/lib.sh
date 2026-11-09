# 하네스 스크립트 공통 함수. passed·record·wiki·setup·doctor·pr-video가 source한다. (bash 3.2 호환)
# 하네스는 플랫폼을 모른다. 빌드·테스트 도구는 저장소가 가진다(ADR 0024).
#
# harness_init 이후 쓸 수 있는 변수
#   root          프로젝트 루트 (HARNESS_ROOT, 아니면 현재 디렉터리에서 가장 가까운 .harness/project.json, 없으면 git 루트)
#   config        .harness/project.json 경로
#   state_dir     .harness/state — 스크립트가 남기는 로컬 상태
#   out_dir       .harness/out — 마지막 실행의 로그와 결과
#   max_errors    실패할 때 보여 줄 에러 수

harness_die() {
  echo "harness: $*" >&2
  exit 2
}

# 프로젝트 루트: 현재 디렉터리에서 위로 올라가며 .harness/project.json을 찾는다. 훅과 같은 기준이다.
# 모노레포의 하위 폴더(apps/ios 등)에 설치해도 그 폴더가 루트가 된다. git 최상위를 넘어가지 않는다.
# 못 찾으면 git 최상위, 그것도 없으면 현재 디렉터리. ai-bouncer의 bouncer_project_root와 같다.
harness_find_root() {
  local top d
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  d="$(pwd -P)"
  while :; do
    [ -f "$d/.harness/project.json" ] && { printf '%s\n' "$d"; return 0; }
    { [ "$d" = "$top" ] || [ "$d" = / ]; } && break
    d="$(dirname "$d")"
  done
  printf '%s\n' "${top:-$(pwd)}"
}

harness_init() {
  command -v jq >/dev/null 2>&1 || harness_die "jq가 필요합니다 (macOS에는 /usr/bin/jq로 기본 포함)"
  root="${HARNESS_ROOT:-$(harness_find_root)}"
  root="$(cd "$root" && pwd)"
  config="$root/.harness/project.json"
  [ -f "$config" ] || harness_die ".harness/project.json이 없습니다. 하네스 저장소에서 scripts/init <프로젝트 경로>로 설치하세요"
  state_dir="$root/.harness/state"
  out_dir="$root/.harness/out"
  max_errors="${HARNESS_MAX_ERRORS:-5}"
  mkdir -p "$state_dir" "$out_dir"
}

# 진행 중인 작업(task.json의 stage가 done이 아님)을 시작한 커밋. 없으면 빈 값.
# 시작 커밋은 단계 훅(stage-context.sh)이 새 작업을 시작할 때 .harness/state/task.base에 적는다(ai-bouncer의 base_sha).
harness_task_base() {
  local stage sha
  [ -f "$state_dir/task.json" ] && [ -f "$state_dir/task.base" ] || return 0
  stage="$(jq -r '.stage // ""' "$state_dir/task.json" 2>/dev/null)" || return 0
  [ -n "$stage" ] && [ "$stage" != done ] || return 0
  sha="$(cat "$state_dir/task.base")"
  git -C "$root" cat-file -e "$sha^{commit}" 2>/dev/null && printf '%s\n' "$sha"
  return 0
}

# 파일($1)의 수정 시각(초)
harness_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

# 바뀐 파일 목록(루트 기준 경로, 한 줄에 하나). 루트가 git 하위 폴더면 그 안의 변경만 본다(--relative). passed와 리뷰 기록 훅이 같은 기준을 쓴다.
# $1이 있으면 그 브랜치에서 갈라진 뒤의 모든 변경.
# 없으면, 작업 중이면 작업을 시작한 커밋 이후의 변경(작업 중에 커밋해도 빠지지 않는다)과, 추적 안 된 파일 중
# 작업을 시작한 뒤에 고친 것. 작업 중이 아니면 커밋하지 않은 변경(HEAD 대비 수정 + 새 파일).
# 하네스 산출물(.harness/)은 뺀다. 지운 파일도 목록에 남으므로 필요하면 호출한 쪽에서 거른다.
harness_changed_files() {
  local base="${1:-}" from="HEAD" started=""
  if [ -n "$base" ]; then
    from="$(git -C "$root" merge-base "$base" HEAD 2>/dev/null)" \
      || harness_die "--base $base: 기준 커밋을 찾지 못했습니다"
  else
    base="$(harness_task_base)"
    if [ -n "$base" ]; then
      from="$base"
      [ -f "$state_dir/task.started" ] && started="$(harness_mtime "$state_dir/task.started")"
    fi
  fi
  (cd "$root" && {
      git -c core.quotePath=false diff --name-only --relative "$from"
      git -c core.quotePath=false ls-files -o --exclude-standard | while IFS= read -r f; do
        # 작업 전부터 있던 추적 안 된 파일은 이번 작업의 변경이 아니다.
        if [ -n "$started" ] && [ "$(harness_mtime "$f")" -lt "$started" ]; then continue; fi
        printf '%s\n' "$f"
      done
    } | { grep -v '^\.harness/' || true; } | LC_ALL=C sort -u)
}

# 설정 값을 읽는다. 없거나 null이면 빈 문자열.
cfg() {
  jq -r "($1) // empty" "$config"
}


# --- 정책·결정 기록 (wiki) -------------------------------------------------------
# 기록 형식은 하네스 저장소의 docs/wiki.md에 있다.

# 머리말(첫 --- 와 다음 --- 사이)의 키($2) 값
wiki_meta() {
  awk -v key="$2" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
    NR > 1 { i = index($0, ":"); if (i && substr($0, 1, i - 1) == key) { v = substr($0, i + 1); sub(/^ +/, "", v); print v; exit } }' "$1"
}
wiki_kind() { local k; k="$(wiki_meta "$1" kind)"; echo "${k:-?}"; }
wiki_title() { grep -m1 '^# ' "$1" | sed 's/^# //' || true; }

# 기록($1)의 형식 문제를 한 줄에 하나씩 출력한다. 문제가 없으면 아무것도 출력하지 않는다.
wiki_problems() {
  local f="$1" kind tags sections s
  if [ "$(head -n1 "$f")" != "---" ]; then
    echo "첫 줄이 머리말(---)이 아닙니다"
    return 0
  fi
  kind="$(wiki_meta "$f" kind)"
  tags="$(wiki_meta "$f" tags)"
  case "$kind" in
    fact) sections="확인된 동작|확인 방법|함의|안 다룬 것" ;;
    rule) sections="규칙|적용 범위|근거|예외" ;;
    *) echo "kind는 fact 또는 rule이어야 합니다 (지금: ${kind:-없음})"; sections="" ;;
  esac
  case "$tags" in \[*[!\ ]*\]) ;; *) echo "tags가 필요합니다 (예: tags: [시트, SwiftUI])" ;; esac
  [ -n "$(wiki_title "$f")" ] || echo "제목(# 한 줄 요약)이 없습니다"
  local IFS='|'
  for s in $sections; do
    grep -qx "## $s" "$f" || echo "\"## $s\" 항목이 없습니다"
  done
}
