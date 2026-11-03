#!/usr/bin/env bash
# e2e의 공용 함수(Maestro JUnit 결과 읽기, 빌드된 앱 찾기, 행동 로그 판정)를 가짜 입력으로 검사한다.
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

# --- 행동 로그: Firebase 디버그 로그(ndjson) -------------------------------------
cat > "$work/events.ndjson" <<'LOG'
Filtering the log data using "subsystem == "com.google.firebase.analytics""
{"timestamp":"2026-11-03 11:51:46.198000+0900","messageType":"Debug","eventMessage":"12.19.3 - [FirebaseAnalytics][I-ACS023072] Event logged. Event name, event params: first_open (_f), {\n    ga_debug (_dbg) = 1;\n    _elt = 1793674302824;\n}"}
{"timestamp":"2026-11-03 11:51:57.697000+0900","messageType":"Debug","eventMessage":"12.19.3 - [FirebaseAnalytics][I-ACS023072] Event logged. Event name, event params: onboarding_complete, {\n    ga_debug (_dbg) = 1;\n    skipped = 1;\n}"}
{"timestamp":"2026-11-03 11:51:58.000000+0900","messageType":"Debug","eventMessage":"12.19.3 - [FirebaseAnalytics][I-ACS023072] Event logged. Event name, event params: tab_select, {\n    tab = \"profile\";\n}"}
{"timestamp":"2026-11-03 11:51:58.100000+0900","messageType":"Debug","eventMessage":"12.19.3 - [FirebaseAnalytics][I-ACS023073] Debug mode is enabled. Marking event as debug and real-time. Event name, parameters: tab_select, {\n}"}
{"timestamp":"2026-11-03 11:51:58.922000+0900","messageType":"Debug","eventMessage":"12.19.3 - [FirebaseAnalytics][I-ACS023044] Successful upload. Got network response. Code, size: 204, 0"}
LOG
ev="$(e2e_firebase_events "$work/events.ndjson")"
assert_eq "events: 기록된 이벤트만 (I-ACS023072)" "first_open onboarding_complete tab_select" "$(jq -r 'map(.name) | join(" ")' <<<"$ev")"
assert_eq "events: 시각은 UTC 밀리초" "1793674317697" "$(jq '.[1].time' <<<"$ev")"
assert_eq "events: 파라미터 이름의 별칭(_dbg)을 뗀다" '{"ga_debug":"1","skipped":"1"}' "$(jq -c '.[1].params' <<<"$ev")"
assert_eq "events: 따옴표 친 값은 따옴표를 뗀다" "profile" "$(jq -r '.[2].params.tab' <<<"$ev")"
e2e_firebase_events "$work/events.ndjson" > "$work/ev.json"
e2e_firebase_uploads "$work/events.ndjson" > "$work/up.json"
assert_eq "uploads: 성공한 업로드 시각" "[1793674318922]" "$(jq -c . "$work/up.json")"

cat > "$work/expect.json" <<'JSON'
{ "events": [ { "name": "onboarding_complete", "params": { "skipped": 1 } }, { "name": "tab_select", "count": 1, "params": { "tab": "profile" } }, { "name": "banner_click", "count": 0 } ] }
JSON
v="$(e2e_check_events "$work/expect.json" "$work/ev.json" "$work/up.json")"
assert_eq "check: 이름·횟수·값이 맞으면 통과" "true" "$(jq .passed <<<"$v")"
assert_eq "check: count가 없으면 1회" "1" "$(jq '.checks[0].expected' <<<"$v")"
assert_eq "check: count 0은 나가면 안 되는 이벤트" "true" "$(jq '.checks[2].ok' <<<"$v")"
assert_eq "check: 마지막 이벤트 뒤에 업로드가 있으면 uploaded" "true" "$(jq .uploaded <<<"$v")"
cat > "$work/expect2.json" <<'JSON'
{ "events": [ { "name": "onboarding_complete", "params": { "skipped": 0 } }, { "name": "tab_select", "count": 2 } ] }
JSON
v="$(e2e_check_events "$work/expect2.json" "$work/ev.json" "$work/up.json")"
assert_eq "check: 값이 다르거나 횟수가 다르면 실패" "false 0 1" "$(jq -r '"\(.passed) \(.checks[0].actual) \(.checks[1].actual)"' <<<"$v")"
echo '[]' > "$work/noup.json"
v="$(e2e_check_events "$work/expect.json" "$work/ev.json" "$work/noup.json")"
assert_eq "check: 업로드가 확인되지 않으면 실패" "false false" "$(jq -r '"\(.passed) \(.uploaded)"' <<<"$v")"
echo '{ "uploaded": false, "events": [ { "name": "tab_select" } ] }' > "$work/expect3.json"
assert_eq "check: uploaded false면 업로드를 보지 않는다" "true null" "$(e2e_check_events "$work/expect3.json" "$work/ev.json" "$work/noup.json" | jq -r '"\(.passed) \(.uploaded)"')"

cat > "$work/commands.json" <<'JSON'
[ { "metadata": { "timestamp": 1000, "duration": 5 } }, { "metadata": { "timestamp": 2000, "duration": 300 } } ]
JSON
assert_eq "window: 첫 명령 시작부터 마지막 명령 끝까지" '{"start":1000,"end":2300}' "$(e2e_flow_window "$work/commands.json" | jq -c .)"

# --- 인자 ----------------------------------------------------------------------
out="$("$e2e" --bogus 2>&1)" && code=0 || code=$?
assert_eq "e2e: 알 수 없는 인자는 2" "2" "$code"

finish
