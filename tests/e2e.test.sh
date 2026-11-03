#!/usr/bin/env bash
# e2e의 공용 함수(Maestro JUnit 결과 읽기, 빌드된 앱 찾기)를 가짜 입력으로 검사한다.
# 시뮬레이터와 Maestro 실행은 시험장에서 확인한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
. "$here/../template/scripts/harness/lib.sh"
e2e="$here/../template/scripts/harness/e2e"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- e2e_junit_to_json: Maestro 2.x가 남기는 형식 ---------------------------------
cat > "$work/junit.xml" <<'XML'
<?xml version='1.0' encoding='UTF-8'?>
<testsuites>
  <testsuite name="Test Suite" device="iPhone 16 Pro - iOS 26.2 - X" tests="3" failures="1" time="90.1">
    <testcase id="home" name="home" classname="home" file=".maestro/home.yaml" time="27.481" timestamp="2026-11-03T09:10:00" status="SUCCESS"/>
    <testcase id="settings" name="settings" classname="settings" file=".maestro/settings.yaml" time="39.685" timestamp="2026-11-03T09:10:27" status="SUCCESS">
      <properties>
        <property name="tags" value="regression,settings"/>
      </properties>
    </testcase>
    <testcase id="fail" name="fail" classname="fail" file=".maestro/fail.yaml" time="28.696" timestamp="2026-11-03T09:13:33" status="ERROR">
      <failure>Assertion is false: "총 0회 분석" is visible &amp; more</failure>
    </testcase>
  </testsuite>
</testsuites>
XML
j="$(e2e_junit_to_json "$work/junit.xml")"
assert_eq "junit: 흐름마다 하나" "3" "$(printf '%s' "$j" | jq length)"
assert_eq "junit: 이름·파일·상태·시간" "home .maestro/home.yaml SUCCESS 27.481" "$(printf '%s' "$j" | jq -r '.[0] | "\(.name) \(.file) \(.status) \(.seconds)"')"
assert_eq "junit: 태그" '["regression","settings"]' "$(printf '%s' "$j" | jq -c '.[1].tags')"
assert_eq "junit: 태그가 없으면 빈 배열" "[]" "$(printf '%s' "$j" | jq -c '.[0].tags')"
assert_eq "junit: 실패 메시지(엔티티 풀기)" 'Assertion is false: "총 0회 분석" is visible & more' "$(printf '%s' "$j" | jq -r '.[2].failure')"
assert_eq "junit: 통과한 흐름은 실패 메시지 없음" "null" "$(printf '%s' "$j" | jq -r '.[0].failure')"

cat > "$work/multi.xml" <<'XML'
    <testcase id="m" name="m" classname="m" file="m.yaml" time="1" status="ERROR">
      <failure>첫 줄
둘째 줄</failure>
    </testcase>
XML
assert_eq "junit: 여러 줄 실패 메시지는 한 줄로" "첫 줄 둘째 줄" "$(e2e_junit_to_json "$work/multi.xml" | jq -r '.[0].failure')"

# --- e2e_find_app --------------------------------------------------------------
dd="$work/dd"
mkdir -p "$dd/Build/Products/Debug-iphonesimulator/App.app" "$dd/Build/Products/Release-iphonesimulator/App.app" \
         "$dd/Build/Products/Debug-iphonesimulator/Other.app"
for a in Debug-iphonesimulator/App.app Release-iphonesimulator/App.app; do
  plutil -create xml1 "$dd/Build/Products/$a/Info.plist"
  plutil -insert CFBundleIdentifier -string com.example.app "$dd/Build/Products/$a/Info.plist"
done
plutil -create xml1 "$dd/Build/Products/Debug-iphonesimulator/Other.app/Info.plist"
plutil -insert CFBundleIdentifier -string com.example.other "$dd/Build/Products/Debug-iphonesimulator/Other.app/Info.plist"
touch -t 202601010000 "$dd/Build/Products/Debug-iphonesimulator/App.app"
touch -t 202602010000 "$dd/Build/Products/Release-iphonesimulator/App.app"
assert_eq "app: 번들 ID가 맞는 것 중 가장 최근 빌드" "$dd/Build/Products/Release-iphonesimulator/App.app" "$(e2e_find_app "$dd" com.example.app)"
assert_eq "app: 없으면 빈 문자열" "" "$(e2e_find_app "$dd" com.example.none)"

# --- 인자 ----------------------------------------------------------------------
out="$("$e2e" --bogus 2>&1)" && code=0 || code=$?
assert_eq "e2e: 알 수 없는 인자는 2" "2" "$code"

finish
