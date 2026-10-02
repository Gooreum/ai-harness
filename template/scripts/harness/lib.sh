# 하네스 스크립트 공용 함수. build·test·verify가 source한다. (bash 3.2 호환)
#
# harness_init 이후 쓸 수 있는 변수
#   root          프로젝트 루트 (HARNESS_ROOT 또는 현재 디렉터리의 git 루트)
#   config        .harness/project.json 경로
#   state_dir     .harness/state — 스크립트가 남기는 로컬 상태
#   out_dir       .harness/out — 마지막 실행의 로그와 결과 번들
#   derived_data  .harness/DerivedData — 워크트리마다 따로 쓰는 DerivedData

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
  derived_data="$root/.harness/DerivedData"
  mkdir -p "$state_dir" "$out_dir"
}

# 설정 값을 읽는다. 없거나 null이면 빈 문자열.
cfg() {
  jq -r "($1) // empty" "$config"
}

# xcodebuild의 -workspace/-project 인자를 container_args 배열에 담는다.
harness_container_args() {
  local ws pj
  ws="$(cfg .workspace)"
  pj="$(cfg .project)"
  if [ -n "$ws" ]; then
    container_args=(-workspace "$root/$ws")
  elif [ -n "$pj" ]; then
    container_args=(-project "$root/$pj")
  else
    harness_die "설정에 workspace도 project도 없습니다"
  fi
}

# simctl JSON(stdin)에서 이름($1)과 OS($2: latest 또는 버전)에 맞는 기기의 UDID를 찾는다.
# 같은 이름이 여러 런타임에 있으면 가장 최신 OS를 고른다.
pick_simulator() {
  jq -r --arg name "$1" --arg os "$2" '
    [ .devices | to_entries[]
      | select(.key | test("SimRuntime\\.iOS-[0-9]+-[0-9]+"))
      | (.key | capture("iOS-(?<a>[0-9]+)-(?<b>[0-9]+)") | "\(.a).\(.b)") as $ver
      | .value[] | select(.name == $name) | { udid, ver: $ver } ]
    | map(select($os == "latest" or .ver == $os or (.ver | startswith($os + "."))))
    | sort_by(.ver | split(".") | map(tonumber)) | last | .udid // empty'
}

# 설정의 시뮬레이터로 -destination 값을 만든다. 없으면 사용 가능한 이름을 보여주고 멈춘다.
harness_destination() {
  local name os json udid
  name="$(cfg .destination.simulator)"
  os="$(cfg .destination.os)"
  os="${os:-latest}"
  [ -n "$name" ] || harness_die "설정에 destination.simulator가 없습니다"
  json="$(xcrun simctl list devices available -j 2>/dev/null)" || harness_die "xcrun simctl을 실행하지 못했습니다"
  udid="$(printf '%s' "$json" | pick_simulator "$name" "$os")"
  if [ -z "$udid" ]; then
    {
      echo "harness: 시뮬레이터 '$name' (iOS $os)를 찾지 못했습니다. 설치된 iPhone:"
      printf '%s' "$json" | jq -r '[ .devices[][] | select(.name | startswith("iPhone")) | .name ] | unique | .[] | "  " + .'
      echo "  .harness/project.json의 destination.simulator를 고치세요"
    } >&2
    exit 2
  fi
  destination="id=$udid"
  destination_label="$name"
}

# --- 프로젝트 생성 (Tuist·XcodeGen) ---------------------------------------------
# 파일 추가·삭제·이동이나 manifest 변경을 놓치면 새 파일이 빌드에서 빠진다.
# 그래서 생성 입력의 지문이 지난번 생성 때와 다를 때만 다시 생성한다.

# 생성 입력의 지문: git이 보는 파일 목록 + manifest 내용
generate_fingerprint() {
  (
    cd "$root" || exit 0
    files="$(git ls-files -co --exclude-standard 2>/dev/null | grep -v '^\.harness/' || true)"
    {
      printf '%s\n' "$files" | LC_ALL=C sort
      printf '%s\n' "$files" \
        | { grep -E '(^|/)(Project|Workspace|Tuist|Package)\.swift$|^Tuist/|(^|/)project\.yml$|(^|/)Package\.resolved$' || true; } \
        | LC_ALL=C sort \
        | while IFS= read -r f; do
            if [ -f "$f" ]; then shasum -a 256 "$f"; fi
          done
    } | shasum -a 256 | cut -d' ' -f1
  )
}

# 외부 의존성 선언의 지문
deps_fingerprint() {
  (
    cd "$root" || exit 0
    for f in Tuist/Package.swift Tuist/Package.resolved Package.resolved; do
      if [ -f "$f" ]; then shasum -a 256 "$f"; fi
    done | shasum -a 256 | cut -d' ' -f1
  )
}

# 실패한 단계의 로그 끝부분을 보여준다.
harness_report_step_failure() { # 단계 명령 로그
  echo "✗ $1 실패 ($2)"
  tail -n 20 "$3" | sed 's/^/  /'
  echo "  로그: ${3#$root/}"
}

# 생성기 프로젝트면 필요할 때만 install·generate를 실행한다. $1이 force면 항상 실행한다.
# 실행했으면 generated_now=1. 실패하면 요약을 출력하고 1을 반환한다.
harness_ensure_generated() {
  local force="${1:-}" gen install target fp dfp
  generated_now=0
  gen="$(cfg .commands.generate)"
  [ -n "$gen" ] || return 0
  install="$(cfg .commands.install)"
  target="$root/$(cfg '.workspace // .project')"

  if [ -n "$install" ]; then
    dfp="$(deps_fingerprint)"
    if [ "$force" = force ] || [ "$(cat "$state_dir/install.fingerprint" 2>/dev/null || true)" != "$dfp" ]; then
      if ! (cd "$root" && bash -c "$install") > "$out_dir/install.log" 2>&1; then
        harness_report_step_failure install "$install" "$out_dir/install.log"
        return 1
      fi
      printf '%s\n' "$dfp" > "$state_dir/install.fingerprint"
    fi
  fi

  fp="$(generate_fingerprint)"
  if [ "$force" != force ] && [ -e "$target" ] \
    && [ "$(cat "$state_dir/generate.fingerprint" 2>/dev/null || true)" = "$fp" ]; then
    return 0
  fi
  # Tuist는 생성 뒤 Xcode를 여는 것이 기본값이라 끈다.
  if ! (cd "$root" && export TUIST_GENERATE_OPEN=false && bash -c "$gen") > "$out_dir/generate.log" 2>&1; then
    harness_report_step_failure generate "$gen" "$out_dir/generate.log"
    return 1
  fi
  generate_fingerprint > "$state_dir/generate.fingerprint"
  generated_now=1
}

# --- 결과 요약 ---------------------------------------------------------------

# xcresult가 기록한 파일 URL의 %XX 인코딩을 푼다 (한글·공백 경로).
decode_file_urls() {
  perl -pe 's{(file://[^"#]*)}{ (my $u = $1) =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge; $u }ge'
}

# build-results JSON(stdin)의 이슈($2: errors|warnings)를 최대 $3개 "경로:줄:열: 메시지"로 출력한다.
# 경로는 루트($1) 기준 상대 경로로 바꾼다. xcresult의 줄·열 번호는 0부터 시작한다.
format_issues() {
  decode_file_urls | jq -r --arg root "$1/" --arg kind "$2" --argjson max "${3:-5}" '
    def num($s; $key): ($s | [scan($key + "=([0-9]+)")[0]] | first);
    (.[$kind] // [])[:$max][]
    | (.sourceURL // "") as $u
    | if $u == "" then
        "  \(.targetName // "?"): \(.message)"
      else
        ($u | ltrimstr("file://") | split("#")) as $p
        | ($p[0] | ltrimstr($root)) as $path
        | num($p[1] // ""; "StartingLineNumber") as $line
        | num($p[1] // ""; "StartingColumnNumber") as $col
        | "  \($path)"
          + (if $line then ":\(($line | tonumber) + 1)" else "" end)
          + (if $col then ":\(($col | tonumber) + 1)" else "" end)
          + ": \(.message)"
      end'
}
