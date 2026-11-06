# 하네스 스크립트 공통 함수. 플랫폼과 상관없이 passed·record·wiki와 각 묶음 스크립트가 source한다. (bash 3.2 호환)
# Xcode·시뮬레이터 함수는 ios.sh에 있다(ADR 0018).
#
# harness_init 이후 쓸 수 있는 변수
#   root          프로젝트 루트 (HARNESS_ROOT 또는 현재 디렉터리의 git 루트)
#   config        .harness/project.json 경로
#   state_dir     .harness/state — 스크립트가 남기는 로컬 상태
#   out_dir       .harness/out — 마지막 실행의 로그와 결과
#   max_errors    실패할 때 보여 줄 에러 수

harness_die() {
  echo "harness: $*" >&2
  exit 2
}

harness_init() {
  command -v jq >/dev/null 2>&1 || harness_die "jq가 필요합니다 (macOS에는 /usr/bin/jq로 기본 포함)"
  root="${HARNESS_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  root="$(cd "$root" && pwd)"
  config="$root/.harness/project.json"
  [ -f "$config" ] || harness_die ".harness/project.json이 없습니다. 하네스 저장소의 scripts/detect --write <프로젝트 경로>로 만드세요"
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

# 바뀐 파일 목록(루트 기준 경로, 한 줄에 하나). unit-test·lint·passed가 같은 기준을 쓴다.
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
      git diff --name-only "$from"
      git ls-files -o --exclude-standard | while IFS= read -r f; do
        # 작업 전부터 있던 추적 안 된 파일은 이번 작업의 변경이 아니다.
        if [ -n "$started" ] && [ "$(harness_mtime "$f")" -lt "$started" ]; then continue; fi
        printf '%s\n' "$f"
      done
    } | { grep -v '^\.harness/' || true; } | LC_ALL=C sort -u)
}

# 목록(stdin)에서 앱 빌드·테스트에 영향이 없는 파일(문서, e2e 시나리오, 에이전트 지침·규칙)을 뺀다.
harness_not_code() {
  grep -vE '\.md$|^docs/|^\.maestro/|^\.claude/|^\.agents/' || true
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

# --- E2E (Maestro) --------------------------------------------------------------

# DerivedData($1)에서 번들 ID($2)가 맞는 시뮬레이터용 앱 중 가장 최근 것의 경로.
# 빌드 구성($3, 예: Debug)을 주면 그 구성으로 빌드된 앱만 찾는다.
e2e_find_app() {
  local app id
  for app in $(ls -dt "$1"/Build/Products/${3:-*}-iphonesimulator/*.app 2>/dev/null); do
    id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist" 2>/dev/null || true)"
    if [ "$id" = "$2" ]; then
      echo "$app"
      return 0
    fi
  done
}

# DerivedData($1)에서 빌드 구성($2)으로 빌드된 시뮬레이터용 앱들의 번들 ID (쉼표로 구분)
e2e_built_ids() {
  local app ids=""
  for app in $(ls -dt "$1"/Build/Products/$2-iphonesimulator/*.app 2>/dev/null); do
    ids="$ids${ids:+, }$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist" 2>/dev/null || echo '?')"
  done
  echo "${ids:-없음}"
}

# 가짜 응답 서버 포트. 설정의 포트($1)가 기본이고, 서버가 .harness/state/network.port에 남긴 포트에 서버가
# 떠 있으면 그것을 쓴다. 서버는 적힌 포트를 다른 워크트리가 쓰고 있으면 빈 포트로 띄운다.
e2e_network_port() {
  local actual
  actual="$(cat "$state_dir/network.port" 2>/dev/null || true)"
  case "$actual" in
    "" | *[!0-9]*) ;;
    *) if nc -z 127.0.0.1 "$actual" 2>/dev/null; then echo "$actual"; return 0; fi ;;
  esac
  echo "$1"
}

# 앱($1, .app 폴더)보다 나중에 고친 코드 파일 중 첫 것. 없으면 빈 값.
# --no-build로 예전에 빌드한 앱을 설치하면 바뀐 코드 없이 통과할 수 있어 막는 데 쓴다.
# 코드가 아닌 파일(harness_not_code)은 앱에 들어가지 않으니 보지 않는다.
e2e_stale_source() {
  local built=0 t f
  for f in "$1" "$1"/*; do
    [ -e "$f" ] || continue
    t="$(harness_mtime "$f")"
    [ "$t" -gt "$built" ] && built="$t"
  done
  harness_changed_files "" | harness_not_code | while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    if [ "$(harness_mtime "$root/$f")" -gt "$built" ]; then echo "$f"; break; fi
  done
}

