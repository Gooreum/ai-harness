#!/usr/bin/env bash
# plugin/mcp/network.py: MCP 도구로 건 가짜 응답을 HTTP로 돌려주는지, 켠 프로젝트에서만 동작하는지 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
server="$here/../plugin/mcp/network.py"
work="$(mktemp -d)"
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; rm -rf "$work"; }
trap cleanup EXIT

port_a=$((20000 + RANDOM % 20000))
port_b=$((port_a + 1))
mkproj() { # 이름 [포트]
  mkdir -p "$work/$1/.harness" "$work/$1/sub"
  if [ -n "${2:-}" ]; then
    jq -n --argjson p "$2" '{schemaVersion: 1, e2e: {network: {port: $p}}}' > "$work/$1/.harness/project.json"
  else
    echo '{"schemaVersion":1}' > "$work/$1/.harness/project.json"
  fi
}

# start 이름 fd — 서버를 띄우고 그 fd로 요청을 보낼 수 있게 한다(bash 3.2라 fd 번호를 직접 준다). 출력은 $work/<이름>.out
start() {
  mkfifo "$work/$1.in"
  (cd "$work/$1/sub" && exec python3 "$server" < "$work/$1.in" > "$work/$1.out" 2>"$work/$1.err") &
  pids+=($!)
  disown $! 2>/dev/null || true
  eval "exec $2>\"$work/$1.in\""
  eval "fd_$1=$2"
}
# rpc 이름 id 메서드 [params] — 요청을 보내고 그 id의 답을 기다려 출력한다
rpc() {
  local fd p="${4:-}"; eval "fd=\$fd_$1"
  [ -n "$p" ] || p='{}'
  jq -cn --argjson id "$2" --arg m "$3" --argjson p "$p" '{jsonrpc: "2.0", id: $id, method: $m, params: $p}' >&"$fd"
  for _ in $(seq 1 50); do
    local r; r="$(jq -c --argjson id "$2" 'select(.id == $id)' "$work/$1.out" 2>/dev/null || true)"
    [ -n "$r" ] && { echo "$r"; return; }
    sleep 0.1
  done
  echo "timeout"
}
call() { local a="${4:-}"; [ -n "$a" ] || a='{}'; rpc "$1" "$2" tools/call "$(jq -cn --arg n "$3" --argjson a "$a" '{name: $n, arguments: $a}')"; }
wait_port() { for _ in $(seq 1 50); do nc -z 127.0.0.1 "$1" 2>/dev/null && return; sleep 0.1; done; }

mkproj a "$port_a"
mkproj b "$port_b"
mkproj off
start a 5
start b 6
start off 7

assert_eq "initialize: 서버 이름" "harness-network" "$(rpc a 1 initialize '{"protocolVersion":"2025-06-18"}' | jq -r .result.serverInfo.name)"
assert_eq "initialize: 버전은 plugin.json에서 읽는다" "$(jq -r .version "$here/../plugin/.claude-plugin/plugin.json")" "$(rpc a 901 initialize '{"protocolVersion":"2025-06-18"}' | jq -r .result.serverInfo.version)"
assert_eq "켠 프로젝트: 도구 4개" "mock_set,mock_list,mock_clear,requests" "$(rpc a 2 tools/list | jq -r '[.result.tools[].name] | join(",")')"
assert_eq "안 켠 프로젝트: 도구 없음" "0" "$(rpc off 2 tools/list | jq '.result.tools | length')"
assert_eq "안 켠 프로젝트: 부르면 오류" "true" "$(call off 3 mock_list | jq .result.isError)"

wait_port "$port_a"
url="http://127.0.0.1:$port_a"
assert_eq "걸린 응답이 없으면 404" "404" "$(curl -s -o /dev/null -w '%{http_code}' "$url/api.example.com/v1/x")"

call a 10 mock_set '{"match":"POST api.example.com/v1/gen","status":500}' >/dev/null
assert_eq "500을 건다" "500" "$(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{"a":1}' "$url/api.example.com/v1/gen?key=x")"
assert_eq "메서드가 다르면 안 맞는다" "404" "$(curl -s -o /dev/null -w '%{http_code}' "$url/api.example.com/v1/gen")"

call a 11 mock_set '{"match":"api.example.com/v1","body":{"ok":true}}' >/dev/null
assert_eq "본문 JSON" '{"ok": true}|application/json' "$(curl -s -D "$work/h" "$url/api.example.com/v1/list"; echo "|$(grep -i '^content-type' "$work/h" | cut -d' ' -f2 | tr -d '\r')")"
assert_eq "더 구체적인 match가 이긴다" "500" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$url/api.example.com/v1/gen")"

call a 12 mock_set '{"match":"slow.example.com","delay":1.2,"status":200}' >/dev/null
t0=$(date +%s)
curl -s -o /dev/null "$url/slow.example.com/x"
assert_eq "지연" "yes" "$([ $(( $(date +%s) - t0 )) -ge 1 ] && echo yes || echo no)"
assert_eq "빈 응답" "0" "$(curl -s "$url/slow.example.com/x" | wc -c | tr -d ' ')"

assert_eq "잘못된 status는 거부" "true" "$(call a 13 mock_set '{"match":"x","status":42}' | jq .result.isError)"
assert_eq "requests: 받은 요청과 맞은 응답" "POST api.example.com/v1/gen?key=x → POST api.example.com/v1/gen 500" \
  "$(call a 14 requests '{"limit":50}' | jq -r '.result.content[0].text | fromjson | .requests[1] | "\(.method) \(.path) → \(.match) \(.status)"')"
assert_eq "응답은 프로젝트 안에 저장" "3" "$(jq '.mocks | length' "$work/a/.harness/state/network.json")"

# 다른 프로젝트와 섞이지 않는다
wait_port "$port_b"
assert_eq "다른 프로젝트엔 응답이 없다" "404" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$port_b/api.example.com/v1/gen")"
assert_eq "다른 프로젝트 목록은 비었다" "0" "$(call b 20 mock_list | jq '.result.content[0].text | fromjson | .mocks | length')"

# 같은 프로젝트를 연 두 번째 세션: 포트를 못 잡아도 같은 파일을 읽는다
mkdir -p "$work/a2" && ln -s "$work/a/.harness" "$work/a2/.harness" && mkdir -p "$work/a2/sub"
start a2 8
assert_eq "두 번째 세션: 포트가 쓰이는 중이라고 알린다" "yes" "$(call a2 1 mock_list | jq -r '.result.content[0].text' | grep -q '이미 쓰고 있어' && echo yes || echo no)"
call a2 2 mock_set '{"match":"GET api.example.com/v2","status":400}' >/dev/null
assert_eq "두 번째 세션이 건 응답을 첫 서버가 준다" "400" "$(curl -s -o /dev/null -w '%{http_code}' "$url/api.example.com/v2")"

call a 30 mock_clear '{"match":"slow.example.com"}' >/dev/null
assert_eq "하나 지우기" "3" "$(jq '.mocks | length' "$work/a/.harness/state/network.json")"
call a 31 mock_clear >/dev/null
assert_eq "전부 지우기" "0" "$(jq '.mocks | length' "$work/a/.harness/state/network.json")"

finish
