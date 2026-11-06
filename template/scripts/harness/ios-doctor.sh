# doctor의 iOS 묶음 점검. doctor가 project.json의 platforms에 ios가 있을 때 source하고 doctor_ios를 부른다.
# doctor의 problem·warn과 root·config를 쓴다. (bash 3.2 호환)

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ios.sh"

doctor_ios() {
  if [ "$(jq -r '.ios | type' "$config")" != object ]; then
    problem ".harness/project.json에 ios 설정이 없다 (platforms에는 ios가 있다)" "하네스 저장소에서 scripts/sync <이 프로젝트>로 옛 설정을 옮긴다"
    return 0
  fi
  derived_data="$(harness_derived_data_path "$root")"
  harness_use_buildable_xcode

  # --- 도구 ---
  command -v xcodebuild > /dev/null 2>&1 || problem "xcodebuild가 없다" "Xcode를 설치하고 xcode-select로 지정한다"
  local generator key path sim os
  generator="$(ios_cfg .generator)"
  case "$generator" in
    tuist | xcodegen)
      command -v "$generator" > /dev/null 2>&1 || problem "${generator}가 없다 (generator: $generator)" "${generator}를 설치한다"
      ;;
  esac
  if [ -d "$root/.maestro" ] && ! command -v maestro > /dev/null 2>&1; then
    warn "maestro가 없어 e2e를 돌릴 수 없다" "curl -fsSL https://get.maestro.mobile.dev | bash"
  fi
  if [ -d "$root/.maestro" ] && ! e2e_java_ok; then
    warn "Maestro가 쓸 Java가 없어 e2e를 돌릴 수 없다" "brew install openjdk@17 후 JAVA_HOME 지정"
  fi

  # --- 설정 ---
  # 앱이 없는 Swift 패키지(spm)는 앱 스킴이 없다.
  [ "$generator" = spm ] || [ -n "$(ios_cfg .app.scheme)" ] || problem ".harness/project.json에 ios.app.scheme이 없다"
  # 생성기를 쓰는 프로젝트의 워크스페이스·프로젝트는 생성물이라, 아직 없어도 build가 만든다.
  if [ "$generator" != "tuist" ] && [ "$generator" != "xcodegen" ]; then
    for key in workspace project; do
      path="$(ios_cfg ".$key")"
      [ -z "$path" ] || [ -e "$root/$path" ] || problem ".harness/project.json의 ios.$key '$path'가 없다"
    done
  fi
  if [ -z "${HARNESS_OFFLINE:-}" ] && command -v xcrun > /dev/null 2>&1; then
    sim="$(ios_cfg .destination.simulator)"
    os="$(ios_cfg .destination.os)"
    if [ -n "$sim" ] && [ -z "$(xcrun simctl list devices available -j 2> /dev/null | pick_simulator "$sim" "${os:-latest}")" ]; then
      warn "시뮬레이터 '$sim' (iOS ${os:-latest})가 없어 최신 런타임의 iPhone을 대신 쓴다" "그 기기를 꼭 써야 하면 Xcode > Settings > Components에서 런타임을 설치한다"
    fi
  fi
}
