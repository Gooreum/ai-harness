#!/usr/bin/env python3
"""harness 가짜 응답 서버 (MCP + HTTP, 한 프로세스).

- 실제 서버로 만들기 어려운 응답(지연, 400·500, 빈 응답)을 실제 서버 대신 돌려준다(발표 슬라이드 85, ADR 0017).
- AI는 MCP 도구(stdio JSON-RPC)로 응답을 걸고, 앱은 테스트로 실행될 때 요청을
  http://127.0.0.1:<포트>/<호스트>/<경로> 로 보낸다. 실제 서버로는 넘기지 않는다.
- 프로젝트의 .harness/project.json에 e2e.network.port가 있을 때만 도구를 내놓고 HTTP 서버를 띄운다.
- 걸어 둔 응답은 그 프로젝트의 .harness/state/network.json에, 받은 요청은 network-requests.ndjson에 둔다.
  HTTP 서버는 요청마다 파일을 읽으므로, 같은 프로젝트를 연 다른 세션이 건 응답도 그대로 쓴다.
- bash로는 HTTP 서버를 짤 수 없어 python3 표준 라이브러리로 쓴다(원칙의 예외, ADR 0017).
"""
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVER_NAME = "harness-network"


def plugin_version():
    """플러그인 버전. 손으로 맞추면 어긋나서(0.9.2에 머물렀다) plugin.json에서 읽는다."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".claude-plugin", "plugin.json")
    try:
        with open(path, encoding="utf-8") as f:
            return str(json.load(f).get("version") or "0")
    except (OSError, ValueError):
        return "0"


VERSION = plugin_version()
MAX_REQUESTS = 200
METHODS = ("GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS")


# --- 프로젝트 ----------------------------------------------------------------

def find_root():
    start = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    d = os.path.abspath(start)
    while True:
        if os.path.isfile(os.path.join(d, ".harness", "project.json")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def read_port(root):
    if not root:
        return None
    try:
        with open(os.path.join(root, ".harness", "project.json")) as f:
            port = ((json.load(f).get("e2e") or {}).get("network") or {}).get("port")
    except (OSError, ValueError, AttributeError):
        return None
    return port if isinstance(port, int) and 0 < port < 65536 else None


ROOT = find_root()
PORT = read_port(ROOT)
STATE = os.path.join(ROOT, ".harness", "state") if ROOT else None
MOCKS_FILE = os.path.join(STATE, "network.json") if STATE else None
REQUESTS_FILE = os.path.join(STATE, "network-requests.ndjson") if STATE else None
lock = threading.Lock()
server_note = ""  # HTTP 서버를 못 띄웠을 때 도구 결과에 붙인다
IDENTITY_PATH = "__harness/root"
PORT_FILE = os.path.join(STATE, "network.port") if STATE else None


def load_mocks():
    try:
        with open(MOCKS_FILE) as f:
            mocks = json.load(f).get("mocks", [])
        return mocks if isinstance(mocks, list) else []
    except (OSError, ValueError, AttributeError):
        return []


def save_mocks(mocks):
    os.makedirs(STATE, exist_ok=True)
    tmp = MOCKS_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"mocks": mocks}, f, ensure_ascii=False, indent=2)
    os.replace(tmp, MOCKS_FILE)


def record_request(entry):
    with lock:
        os.makedirs(STATE, exist_ok=True)
        lines = []
        try:
            with open(REQUESTS_FILE) as f:
                lines = f.read().splitlines()
        except OSError:
            pass
        lines.append(json.dumps(entry, ensure_ascii=False))
        with open(REQUESTS_FILE, "w") as f:
            f.write("\n".join(lines[-MAX_REQUESTS:]) + "\n")


def split_match(match):
    """'POST host/path' → ('POST', 'host/path'), 'host/path' → (None, 'host/path')"""
    parts = match.strip().split(None, 1)
    if len(parts) == 2 and parts[0].upper() in METHODS:
        return parts[0].upper(), parts[1].strip().lstrip("/")
    return None, match.strip().lstrip("/")


def find_mock(method, target):
    """메서드가 맞고 주소가 match로 시작하는 응답 중 가장 긴(구체적인) 것."""
    best = None
    for m in load_mocks():
        want_method, prefix = split_match(m.get("match", ""))
        if want_method and want_method != method:
            continue
        if not target.startswith(prefix):
            continue
        if best is None or len(prefix) > len(split_match(best["match"])[1]):
            best = m
    return best


# --- HTTP: 앱이 보내는 요청 ------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):  # stderr를 MCP 로그로 어지럽히지 않는다
        pass

    def handle_any(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        target = self.path.lstrip("/")
        if target == IDENTITY_PATH:
            # 포트가 겹쳤을 때 같은 프로젝트(같은 폴더)의 서버인지 알아보는 데 쓴다.
            self.respond(200, ROOT or "", {"Content-Type": "text/plain; charset=utf-8"})
            return
        mock = find_mock(self.command, target)
        record_request({
            "time": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "ts": int(time.time() * 1000),  # e2e가 흐름 구간(ms)으로 나눌 때 쓴다
            "method": self.command,
            "path": target,
            "match": mock["match"] if mock else None,
            "status": mock.get("status", 200) if mock else 404,
        })
        if mock is None:
            self.respond(404, json.dumps({"error": f"걸린 응답이 없다: {self.command} {target}"},
                                         ensure_ascii=False), {"Content-Type": "application/json"})
            return
        delay = mock.get("delay") or 0
        if delay:
            time.sleep(float(delay))
        body = mock.get("body")
        if body is None:
            body = ""
        elif not isinstance(body, str):
            body = json.dumps(body, ensure_ascii=False)
        headers = dict(mock.get("headers") or {})
        if body and not any(k.lower() == "content-type" for k in headers):
            headers["Content-Type"] = "application/json" if body.lstrip()[:1] in "{[" else "text/plain; charset=utf-8"
        self.respond(int(mock.get("status", 200)), body, headers)

    def respond(self, status, body, headers):
        data = body.encode("utf-8")
        try:
            self.send_response(status)
            for k, v in headers.items():
                self.send_header(k, str(v))
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass  # 앱이 타임아웃으로 먼저 끊었다

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = do_OPTIONS = handle_any


def serving_root(port):
    """포트에 떠 있는 응답 서버의 프로젝트 폴더. 응답 서버가 아니면 None."""
    import urllib.request
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/{IDENTITY_PATH}", timeout=1) as r:
            return r.read().decode("utf-8")
    except Exception:
        return None


def write_port(port):
    """실제로 띄운 포트를 남긴다. scripts/harness/e2e가 project.json보다 먼저 읽는다."""
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(PORT_FILE, "w") as f:
            f.write(f"{port}\n")
    except OSError:
        pass


def start_http():
    """project.json의 포트로 띄운다. 같은 프로젝트의 다른 세션이 이미 띄웠으면 그 서버를 같이 쓴다
    (응답·요청 기록이 같은 파일이라 그대로 동작한다). 다른 폴더(같은 프로젝트의 다른 워크트리 등)가 쓰고 있으면
    빈 포트로 띄운다. 포트가 커밋되는 project.json에 있어 워크트리끼리 겹쳤다(ReadSharp 원본과 워크트리가 둘 다 18787)."""
    global server_note, PORT
    try:
        httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    except OSError as e:
        owner = serving_root(PORT)
        if owner is not None and os.path.realpath(owner) == os.path.realpath(ROOT):
            write_port(PORT)
            return
        try:
            httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        except OSError as e2:
            server_note = f"응답 서버를 띄우지 못했다({e2.strerror})."
            return
        used = PORT
        PORT = httpd.server_address[1]
        server_note = (f"포트 {used}을 다른 폴더({owner or '응답 서버가 아닌 프로그램'})가 쓰고 있어 {PORT}로 띄웠다({e.strerror}). "
                       "scripts/harness/e2e는 이 포트를 .harness/state/network.port에서 읽는다.")
    write_port(PORT)
    httpd.daemon_threads = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()


# --- MCP 도구 -----------------------------------------------------------------

TOOLS = [
    {
        "name": "mock_set",
        "description": ("실제 서버 대신 돌려줄 응답을 건다. 앱이 http://127.0.0.1:<포트>/<호스트>/<경로>로 보낸 요청 중 "
                        "match로 시작하는 것에 이 응답을 준다. 같은 match가 있으면 바꾼다. "
                        "가짜 응답은 프로젝트 코드에 목 파일로 만들지 말고 여기에 건다."),
        "inputSchema": {
            "type": "object",
            "properties": {
                "match": {"type": "string", "description": "'[메서드] 호스트/경로' 앞부분. 예: 'POST generativelanguage.googleapis.com/v1beta/models'"},
                "status": {"type": "integer", "description": "HTTP 상태 코드. 기본 200"},
                "delay": {"type": "number", "description": "응답 전에 기다릴 초. 기본 0"},
                "body": {"description": "응답 본문(문자열 또는 JSON). 없으면 빈 응답"},
                "headers": {"type": "object", "description": "응답 헤더"},
            },
            "required": ["match"],
        },
    },
    {"name": "mock_list", "description": "걸어 둔 응답 목록", "inputSchema": {"type": "object", "properties": {}}},
    {
        "name": "mock_clear",
        "description": "걸어 둔 응답을 지운다. match를 주면 그것만, 없으면 전부",
        "inputSchema": {"type": "object", "properties": {"match": {"type": "string"}}},
    },
    {
        "name": "requests",
        "description": "앱이 이 서버로 보낸 최근 요청(메서드, 호스트/경로, 맞은 응답, 상태). match를 고를 때 주소를 추측하지 말고 이걸 본다",
        "inputSchema": {"type": "object", "properties": {"limit": {"type": "integer", "description": "기본 20"}}},
    },
]


def base_url():
    return f"http://127.0.0.1:{PORT}"


def text(obj):
    note = f"\n주의: {server_note}" if server_note else ""
    return {"content": [{"type": "text", "text": json.dumps(obj, ensure_ascii=False, indent=2) + note}]}


def error(msg):
    return {"content": [{"type": "text", "text": msg}], "isError": True}


def call_tool(name, args):
    if name == "mock_set":
        match = (args.get("match") or "").strip()
        if not match:
            return error("match가 필요하다")
        status = args.get("status", 200)
        if not isinstance(status, int) or not 100 <= status <= 599:
            return error(f"status는 100~599 정수여야 한다: {status}")
        delay = args.get("delay", 0)
        if not isinstance(delay, (int, float)) or delay < 0 or delay > 300:
            return error(f"delay는 0~300초여야 한다: {delay}")
        mock = {"match": match, "status": status}
        if delay:
            mock["delay"] = delay
        if args.get("body") is not None:
            mock["body"] = args["body"]
        if args.get("headers"):
            if not isinstance(args["headers"], dict):
                return error("headers는 객체여야 한다")
            mock["headers"] = args["headers"]
        with lock:
            mocks = [m for m in load_mocks() if m.get("match") != match] + [mock]
            save_mocks(mocks)
        return text({"set": mock, "baseURL": base_url(), "count": len(mocks)})
    if name == "mock_list":
        return text({"baseURL": base_url(), "mocks": load_mocks()})
    if name == "mock_clear":
        match = (args.get("match") or "").strip()
        with lock:
            before = load_mocks()
            after = [m for m in before if match and m.get("match") != match]
            save_mocks(after)
        return text({"removed": len(before) - len(after), "mocks": after})
    if name == "requests":
        limit = args.get("limit") or 20
        try:
            with open(REQUESTS_FILE) as f:
                lines = f.read().splitlines()
        except OSError:
            lines = []
        return text({"baseURL": base_url(), "requests": [json.loads(l) for l in lines[-int(limit):] if l]})
    return error(f"없는 도구: {name}")


# --- JSON-RPC (stdio, 줄마다 메시지 하나) ------------------------------------------

def handle(msg):
    method = msg.get("method")
    if method == "initialize":
        return {
            "protocolVersion": (msg.get("params") or {}).get("protocolVersion", "2025-06-18"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": SERVER_NAME, "version": VERSION},
        }
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS if PORT else []}
    if method == "tools/call":
        if not PORT:
            return error("이 프로젝트는 가짜 응답 서버를 켜지 않았다(.harness/project.json의 e2e.network.port)")
        p = msg.get("params") or {}
        return call_tool(p.get("name"), p.get("arguments") or {})
    raise KeyError(method)


def main():
    if PORT:
        start_http()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if "id" not in msg:
            continue  # 알림(notifications/*)에는 답하지 않는다
        try:
            reply = {"jsonrpc": "2.0", "id": msg["id"], "result": handle(msg)}
        except KeyError:
            reply = {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601, "message": f"없는 메서드: {msg.get('method')}"}}
        except Exception as e:  # 도구 하나가 실패해도 서버는 계속 돈다
            reply = {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32603, "message": str(e)}}
        sys.stdout.write(json.dumps(reply, ensure_ascii=False) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
