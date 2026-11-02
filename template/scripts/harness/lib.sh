# 하네스 스크립트 공용 함수. build·test·verify·lint가 source한다. (bash 3.2 호환)
#
# harness_init 이후 쓸 수 있는 변수
#   root          프로젝트 루트 (HARNESS_ROOT 또는 현재 디렉터리의 git 루트)
#   config        .harness/project.json 경로
#   state_dir     .harness/state — 스크립트가 남기는 로컬 상태
#   out_dir       .harness/out — 마지막 실행의 로그와 결과 번들
#   derived_data  워크트리마다 따로 쓰는 DerivedData (harness_derived_data_path 참고)

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
  derived_data="$(harness_derived_data_path "$root")"
  max_errors="${HARNESS_MAX_ERRORS:-5}"
  mkdir -p "$state_dir" "$out_dir"
}

# 워크트리($1)의 DerivedData 경로. HARNESS_DERIVED_DATA가 있으면 그 값을 쓴다.
# 프로젝트 안에 두지 않는다. 프로젝트가 ~/Desktop 같은 macOS 보호 폴더 아래 있으면
# 시뮬레이터의 테스트 프로세스가 테스트 번들을 읽지 못한다(docs/harness-log.md 2026-10-02).
# 워크트리 경로의 해시를 이름에 넣어 워크트리끼리 빌드 캐시가 섞이지 않게 한다.
harness_derived_data_path() {
  if [ -n "${HARNESS_DERIVED_DATA:-}" ]; then
    echo "$HARNESS_DERIVED_DATA"
    return 0
  fi
  echo "$HOME/Library/Developer/Xcode/DerivedData/$(basename "$1")-harness-$(printf '%s' "$1" | shasum -a 256 | cut -c1-8)"
}

# 바뀐 파일 목록(루트 기준 경로, 한 줄에 하나). verify·lint가 같은 기준을 쓴다.
# 인자가 없으면 커밋하지 않은 변경(HEAD 대비 수정 + 새 파일), $1이 있으면 그 브랜치에서 갈라진 뒤의 모든 변경.
# 하네스 산출물(.harness/)은 뺀다. 지운 파일도 목록에 남으므로 필요하면 호출한 쪽에서 거른다.
harness_changed_files() {
  local base="${1:-}" merge_base=""
  if [ -n "$base" ]; then
    merge_base="$(git -C "$root" merge-base "$base" HEAD 2>/dev/null)" \
      || harness_die "--base $base: 기준 커밋을 찾지 못했습니다"
  fi
  (cd "$root" && {
      if [ -n "$merge_base" ]; then git diff --name-only "$merge_base"; else git diff --name-only HEAD; fi
      git ls-files -o --exclude-standard
    } | { grep -v '^\.harness/' || true; } | LC_ALL=C sort -u)
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

# --- 모듈 --------------------------------------------------------------------

# 모듈(디렉터리 $1, 스킴 $2)에 실행할 테스트가 있으면 성공.
# 생성된 스킴 파일이 있으면 테스트 액션에 테스트 대상이 있는지 본다. Tests 폴더만 있고 테스트 타깃이
# 없는 모듈도 있어서다. 스킴 파일이 없으면 testsDir($3) 폴더가 있는지로 판단한다.
module_has_tests() {
  local f
  for f in "$root/$1"/*.xcodeproj/xcshareddata/xcschemes/"$2".xcscheme; do
    if [ -f "$f" ]; then
      grep -q '<TestableReference' "$f"
      return $?
    fi
  done
  [ -n "${3:-}" ] && [ -d "$root/$1/$3" ]
}

# --- 결과 요약 ---------------------------------------------------------------

# 결과 번들($1)의 빌드 결과 JSON. 번들이 없거나 읽지 못하면 빈 문자열.
harness_build_results() {
  if [ -d "$1" ]; then xcrun xcresulttool get build-results --path "$1" --compact 2>/dev/null || true; fi
}

# 결과 번들($1)의 테스트 요약 JSON. 번들이 없거나 테스트가 돌지 않았으면 빈 문자열.
harness_test_summary() {
  if [ -d "$1" ]; then xcrun xcresulttool get test-results summary --path "$1" --compact 2>/dev/null || true; fi
}

# 빌드 결과 JSON($1)에서 개수($2: errorCount|warningCount)를 읽는다. JSON이 없으면 0.
build_count() {
  if [ -z "$1" ]; then echo 0; return 0; fi
  case "$2" in
    errorCount) printf '%s' "$1" | jq '.errorCount // (.errors | length)' ;;
    *) printf '%s' "$1" | jq '.warningCount // (.warnings | length)' ;;
  esac
}

# 빌드 실패 원인을 출력한다. 빌드 결과 JSON($1)에 에러가 있으면 위치와 메시지를,
# 없으면(인자 오류, 스크립트 단계 실패 등) 로그($2)의 에러 줄을 보여준다.
harness_print_build_errors() {
  local json="$1" log="$2" count
  count="$(build_count "$json" errorCount)"
  if [ "$count" -gt 0 ]; then
    printf '%s' "$json" | format_issues "$root" errors "$max_errors"
    if [ "$count" -gt "$max_errors" ]; then echo "  … 에러 $((count - max_errors))개 더 있음"; fi
  else
    { grep -E 'error:|ERROR' "$log" || tail -n 20 "$log"; } | head -n 20 | sed 's/^/  /' || true
  fi
}

# 테스트 요약 JSON(stdin)의 실패를 최대 $1개 "테스트: 메시지"로 출력한다.
# 위치 정보가 없을 때(번들 로드 실패, 크래시 등) 쓰는 대체 출력이다.
format_test_failures() {
  jq -r --argjson max "${1:-5}" '
    (.testFailures // [])[:$max][]
    | "  \(.testIdentifierString // .testName): \(.failureText | split("\n")[0])"'
}

# 테스트 트리 JSON(stdin, xcresulttool get test-results tests)에서 실패한 테스트의
# 실패 메시지를 최대 $1개 "테스트ID<TAB>메시지"로 출력한다. 메시지는 보통 "File.swift:42: ..." 형태다.
failed_test_messages() {
  jq -r --argjson max "${1:-5}" '
    [ .. | objects | select(.nodeType? == "Test Case" and .result? == "Failed")
      | (.nodeIdentifier // .name) as $id
      | ([ .children[]? | select(.nodeType == "Failure Message") | .name ] | if length == 0 then [""] else . end)[]
      | "\($id)\t\(split("\n")[0] // "")" ]
    | .[:$max][]'
}

# git이 아는 파일 중 이름($1)이 같은 파일이 하나뿐이면 루트 기준 경로를, 아니면 이름 그대로 출력한다.
resolve_source_path() {
  local matches
  matches="$(cd "$root" && git ls-files -- "$1" "*/$1" 2>/dev/null || true)"
  if [ -n "$matches" ] && [ "$(printf '%s\n' "$matches" | wc -l | tr -d ' ')" = 1 ]; then
    echo "$matches"
  else
    echo "$1"
  fi
}

# 실패한 테스트를 "경로:줄: 메시지"와 테스트 ID로 출력한다. 위치를 못 찾으면 요약의 실패 문구를 쓴다.
harness_print_test_failures() { # 결과번들 요약JSON
  local tests lines re id msg
  tests="$(xcrun xcresulttool get test-results tests --path "$1" --compact 2>/dev/null || true)"
  lines=""
  if [ -n "$tests" ]; then lines="$(printf '%s' "$tests" | failed_test_messages "$max_errors")"; fi
  if [ -z "$lines" ]; then
    printf '%s' "$2" | format_test_failures "$max_errors"
    return 0
  fi
  re='^([^:]+\.swift):([0-9]+): (.*)$'
  while IFS=$'\t' read -r id msg; do
    if [[ $msg =~ $re ]]; then
      echo "  $(resolve_source_path "${BASH_REMATCH[1]}"):${BASH_REMATCH[2]}: ${BASH_REMATCH[3]}"
    elif [ -n "$msg" ]; then
      echo "  $msg"
    fi
    echo "    ↳ $id"
  done <<EOF
$lines
EOF
}

# 산출물 경로를 루트 기준으로 출력한다.
harness_print_artifacts() { # 로그 결과번들
  echo "  로그: ${1#$root/}"
  if [ -d "$2" ]; then echo "  결과: ${2#$root/}"; fi
}

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
        (if .targetName then "  \(.targetName): \(.message)" else "  \(.message)" end)
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

# --- 컨벤션 검사 (lint) ---------------------------------------------------------
# .harness/conventions.json 형식은 하네스 저장소의 docs/conventions.md에 있다.

# 컨벤션 파일($1)을 검사한다. 문제가 있으면 첫 문제를 출력하고 끝낸다.
conventions_check() {
  local problem
  jq -e . "$1" >/dev/null 2>&1 || harness_die "$1: JSON 형식이 아닙니다"
  problem="$(jq -r '
    def bad($i; $msg): "rules[\($i)]: \($msg)";
    if .schemaVersion != 1 then "schemaVersion은 1이어야 합니다"
    elif (.rules | type) != "array" then "rules는 배열이어야 합니다"
    elif (.passScore != null) and ((.passScore | type) != "number" or .passScore < 0 or .passScore > 100) then "passScore는 0~100 숫자여야 합니다"
    else
      ([.rules | to_entries[] | .key as $i | .value as $r |
        if ($r.id | type) != "string" or ($r.id | test("^[a-z0-9_.]+$") | not) then bad($i; "id는 영문 소문자·숫자·_·.만 씁니다")
        elif ($r.severity | IN("error", "warning", "info") | not) then bad($i; "\($r.id): severity는 error·warning·info 중 하나입니다")
        elif ($r.regex | type) != "string" or $r.regex == "" then bad($i; "\($r.id): regex가 필요합니다")
        elif ($r.description | type) != "string" or $r.description == "" then bad($i; "\($r.id): description이 필요합니다")
        elif ($r.penalty != null) and (($r.penalty | type) != "number" or $r.penalty < 0) then bad($i; "\($r.id): penalty는 0 이상 숫자입니다")
        else empty end] | first)
      // ([.rules[].id] | group_by(.) | map(select(length > 1) | .[0]) | first | if . then "id가 겹칩니다: \(.)" else empty end)
      // empty
    end' "$1")"
  [ -z "$problem" ] || harness_die ".harness/conventions.json: $problem"
}

# 컨벤션 파일($1)을 SwiftLint 설정으로 옮긴다. JSON은 YAML이기도 해서 SwiftLint가 그대로 읽는다.
# 컨벤션 규칙만 켠다(only_rules). SwiftLint 기본 규칙은 판정에 넣지 않는다.
conventions_to_swiftlint() {
  jq '{
    only_rules: ["custom_rules"],
    custom_rules: (.rules | map({ key: .id, value: (
      { name: .id, regex: .regex, message: .description,
        severity: (if .severity == "error" then "error" else "warning" end) }
      + (if .matchKinds then { match_kinds: .matchKinds } else {} end)
      + (if .included then { included: .included } else {} end)
      + (if .excluded then { excluded: .excluded } else {} end)) }) | from_entries)
  }' "$1"
}

# swiftlint JSON 결과($2)를 위반 목록으로 바꾼다. 심각도·감점은 컨벤션 파일($1)에서 가져오고,
# 경로는 루트($3) 기준으로 줄인다. 심각한 것부터, 같은 심각도는 파일·줄 순서로 정렬한다.
lint_violations() {
  local real prefixes
  real="$(cd "$3" && pwd -P)"
  prefixes="$(jq -cn --arg a "$3" --arg b "$real" '[$a, $b, ($b | sub("^/private/"; "/"))] | unique | map(. + "/")')"
  jq --slurpfile conv "$1" --argjson prefixes "$prefixes" '
    ($conv[0].rules | map({ key: .id, value: . }) | from_entries) as $rules
    | { error: 10, warning: 5, info: 1 } as $default
    | { error: 0, warning: 1, info: 2 } as $order
    | map(select($rules[.rule_id]) | $rules[.rule_id] as $r
        | .file as $f
        | { rule: .rule_id, severity: $r.severity,
            penalty: ($r.penalty // $default[$r.severity]),
            file: (reduce $prefixes[] as $p ($f; if startswith($p) then .[($p | length):] else . end)),
            line: .line, column: .character, message: $r.description })
    | sort_by($order[.severity], .file, .line, .column)' "$2"
}
