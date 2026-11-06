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
assert_eq "app: 빌드 구성을 주면 그 구성의 앱만" "$dd/Build/Products/Debug-iphonesimulator/App.app" "$(e2e_find_app "$dd" com.example.app Debug)"
assert_eq "app: 그 구성에 번들 ID가 맞는 앱이 없으면 빈 문자열" "" "$(e2e_find_app "$dd" com.example.other Release)"
assert_eq "built_ids: 구성의 앱 번들 ID 목록" "com.example.app" "$(e2e_built_ids "$dd" Release)"
assert_eq "built_ids: 앱이 없으면 없음" "없음" "$(e2e_built_ids "$dd" Staging)"

# --- scheme_run_config ---------------------------------------------------------
root="$work/proj"
mkdir -p "$root/App.xcodeproj/xcshareddata/xcschemes" "$root/.harness/x/xcshareddata/xcschemes"
cat > "$root/App.xcodeproj/xcshareddata/xcschemes/App.xcscheme" <<'XML'
<Scheme>
   <TestAction
      buildConfiguration = "Debug">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Release"
      launchStyle = "0">
   </LaunchAction>
</Scheme>
XML
assert_eq "scheme: 여러 줄 LaunchAction의 빌드 구성" "Release" "$(scheme_run_config App)"
assert_eq "scheme: 스킴 파일이 없으면 빈 문자열" "" "$(scheme_run_config Nope)"

# --- e2e_java_ok ---------------------------------------------------------------
mkdir -p "$work/jdk/bin"; printf '#!/bin/sh\n' > "$work/jdk/bin/java"; chmod +x "$work/jdk/bin/java"
assert_eq "java: JAVA_HOME에 java가 있으면 성공" "0" "$(JAVA_HOME="$work/jdk" e2e_java_ok; echo $?)"
assert_eq "java: JAVA_HOME에 java가 없으면 실패" "1" "$(JAVA_HOME="$work/none" e2e_java_ok; echo $?)"

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

# --- e2e_check_network: 가짜 응답 서버 기록으로 판정 -------------------------------
cat > "$work/req.ndjson" <<'LOG'
{"ts": 1000, "method": "POST", "path": "api.x.com/v1/gen", "match": "POST api.x.com/v1", "status": 500}
{"ts": 2000, "method": "POST", "path": "api.x.com/v1/gen", "match": null, "status": 404}
{"ts": 5000, "method": "POST", "path": "api.x.com/v1/gen", "match": "POST api.x.com/v1", "status": 500}
LOG
echo '{"expect":[{"match":"POST api.x.com/v1","status":500}]}' > "$work/n.json"
assert_eq "network: 구간 안에 기대 응답이 있으면 통과" "true|1" "$(e2e_check_network "$work/n.json" "$work/req.ndjson" 0 1500 | jq -r '"\(.passed)|\(.checks[0].actual)"')"
assert_eq "network: 응답이 안 걸려 404만 있으면 실패" "false|POST api.x.com/v1/gen 404" "$(e2e_check_network "$work/n.json" "$work/req.ndjson" 1500 3000 | jq -r '"\(.passed)|\(.requests | join(","))"')"
assert_eq "network: 서버 기록이 없으면 실패" "false" "$(e2e_check_network "$work/n.json" "$work/none.ndjson" 0 9000 | jq .passed)"
echo '{"expect":[{"match":"POST api.x.com/v1","status":503}]}' > "$work/n2.json"
assert_eq "network: 상태 코드가 다르면 실패" "false" "$(e2e_check_network "$work/n2.json" "$work/req.ndjson" 0 9000 | jq .passed)"
echo '{}' > "$work/n3.json"
assert_eq "network: expect가 없으면 실패" "false|network.json에 expect 목록이 없습니다" "$(e2e_check_network "$work/n3.json" "$work/req.ndjson" 0 9000 | jq -r '"\(.passed)|\(.error)"')"

# --- e2e_network_port: 서버가 남긴 포트가 떠 있으면 그것을 쓴다 -----------------------------
root="$work/net"; state_dir="$root/.harness/state"; mkdir -p "$state_dir"
assert_eq "port: 남긴 포트가 없으면 설정 포트" "18787" "$(e2e_network_port 18787)"
python3 -c 'import socket,time,sys; s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(); print(s.getsockname()[1], flush=True); time.sleep(20)' > "$work/listen.port" &
listener=$!
for _ in $(seq 1 50); do [ -s "$work/listen.port" ] && break; sleep 0.1; done
lp="$(cat "$work/listen.port")"
echo "$lp" > "$state_dir/network.port"
assert_eq "port: 남긴 포트에 서버가 떠 있으면 그 포트" "$lp" "$(e2e_network_port 18787)"
kill "$listener" 2>/dev/null || true; wait "$listener" 2>/dev/null || true
assert_eq "port: 남긴 포트에 서버가 없으면 설정 포트" "18787" "$(e2e_network_port 18787)"
echo "abc" > "$state_dir/network.port"
assert_eq "port: 숫자가 아니면 설정 포트" "18787" "$(e2e_network_port 18787)"

# --- e2e_stale_source: --no-build로 설치할 앱이 바뀐 코드보다 오래됐는지 -----------------------
root="$work/stale"; state_dir="$root/.harness/state"
mkdir -p "$root/App" "$root/docs" "$root/Build/A.app" "$state_dir"
echo 'a' > "$root/App/A.swift"
(cd "$root" && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@t commit -qm init)
echo 'plist' > "$root/Build/A.app/Info.plist"
touch -t 202601010100 "$root/Build/A.app" "$root/Build/A.app/Info.plist"
echo 'b' >> "$root/App/A.swift"; touch -t 202601010000 "$root/App/A.swift"
assert_eq "stale: 앱이 바뀐 코드보다 새것이면 빈 값" "" "$(e2e_stale_source "$root/Build/A.app")"
touch -t 202601010200 "$root/App/A.swift"
assert_eq "stale: 앱보다 나중에 고친 코드를 알린다" "App/A.swift" "$(e2e_stale_source "$root/Build/A.app")"
touch -t 202601010000 "$root/App/A.swift"
echo 'x' > "$root/docs/a.md"; mkdir -p "$root/.maestro" && echo 'x' > "$root/.maestro/a.yaml"
assert_eq "stale: 문서·시나리오는 보지 않는다" "" "$(e2e_stale_source "$root/Build/A.app")"

# --- 시뮬레이터 잠금: 워크트리 두 곳이 같은 기기를 동시에 쓰지 않게 ---------------------------------
export HARNESS_SIM_LOCK_DIR="$work/simlocks"
root="$work/wt1"
claimed_simulator=""
harness_claim_simulator U1 && r=0 || r=1
assert_eq "lock: 빈 기기는 잡는다" "0|$work/wt1" "$r|$(sed -n 1p "$HARNESS_SIM_LOCK_DIR/U1/owner")"
sleep 30 & other=$!
mkdir -p "$HARNESS_SIM_LOCK_DIR/U2" && printf '%s\n%s\n' "$work/wt2" "$other" > "$HARNESS_SIM_LOCK_DIR/U2/owner"
harness_claim_simulator U2 && r=0 || r=1
assert_eq "lock: 다른 워크트리가 쓰는 중이면 실패하고 누가 쓰는지 알린다" "1|$work/wt2" "$r|$sim_busy_owner"
kill "$other" 2>/dev/null || true; wait "$other" 2>/dev/null || true
harness_claim_simulator U2 && r=0 || r=1
assert_eq "lock: 프로세스가 끝난 잠금은 무시한다" "0" "$r"
harness_release_simulator
assert_eq "lock: 놓으면 잠금을 지운다" "no" "$([ -d "$HARNESS_SIM_LOCK_DIR/U2" ] && echo yes || echo no)"
unset HARNESS_SIM_LOCK_DIR

sims='{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-2":[{"udid":"A","name":"iPhone 17 Pro"},{"udid":"B","name":"iPhone 17"},{"udid":"P","name":"iPad Pro"}],
  "com.apple.CoreSimulator.SimRuntime.iOS-18-0":[{"udid":"C","name":"iPhone 16"}]}}'
assert_eq "candidates: 고른 기기가 먼저, 같은 런타임의 iPhone만" "A iPhone 17 Pro|B iPhone 17" "$(printf '%s' "$sims" | simulator_candidates A | paste -sd'|' -)"

# --- 인자 ----------------------------------------------------------------------
out="$("$e2e" --bogus 2>&1)" && code=0 || code=$?
assert_eq "e2e: 알 수 없는 인자는 2" "2" "$code"

finish
