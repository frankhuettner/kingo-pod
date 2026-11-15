"""CI: a stand-in for a dev server such as Vite's, for clickthrough --dev: http and a WebSocket on one port.

    python3 clickthrough_devserver.py PORT LOG

Prints LISTENING once it listens, or LISTEN-DENIED and the error when the system refuses (the sandbox, on a Mac).
Writes one line into LOG for every request (REQ, with its path and Origin) and for the WebSocket's message (WS).
GET / is a page that fetches /api and opens a WebSocket to /hmr, as Vite's page reloads itself over one.
GET /redirect?to=<address> sends the browser on to that address (302), for clickthrough_routes.js.
"""
import base64
import hashlib
import socket
import sys
import threading
import urllib.parse

PORT, LOG = int(sys.argv[1]), sys.argv[2]
lock = threading.Lock()
PAGE = b"""<!doctype html><meta charset="utf-8"><title>dev page</title><p id="api">waiting</p><script>
fetch('/api').then(r => r.text()).then(t => { document.getElementById('api').textContent = t; });
const ws = new WebSocket('ws://' + location.host + '/hmr');
ws.onopen = () => ws.send('ping');
ws.onmessage = (e) => { document.title = 'DEV-WS ' + e.data; };
ws.onerror = () => { document.title = 'DEV-WS error'; };
</script>"""


def log(line):
    with lock, open(LOG, "a") as f:
        f.write(line + "\n")


def reply(conn, status, body, kind="text/html"):
    conn.sendall(b"HTTP/1.1 " + status + b"\r\nContent-Type: " + kind.encode() + b"\r\nContent-Length: "
                 + str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)


def websocket(conn, headers):
    key = headers.get("sec-websocket-key", "")
    accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
    conn.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                 b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n")
    head = conn.recv(2)
    length = head[1] & 0x7F
    if length == 126:
        length = int.from_bytes(conn.recv(2), "big")
    mask = conn.recv(4)
    data = bytes(b ^ mask[i % 4] for i, b in enumerate(conn.recv(length)))
    log("WS " + data.decode(errors="replace"))
    conn.sendall(b"\x81\x04pong")
    try:
        conn.settimeout(3)
        conn.recv(64)
    except OSError:
        pass


def answer(conn):
    try:
        conn.settimeout(5)
        raw = b""
        while b"\r\n\r\n" not in raw:
            chunk = conn.recv(4096)
            if not chunk:
                return
            raw += chunk
        lines = raw.split(b"\r\n\r\n", 1)[0].decode(errors="replace").split("\r\n")
        method, path = (lines[0].split(" ") + ["", ""])[:2]
        headers = {k.strip().lower(): v.strip() for k, _, v in (l.partition(":") for l in lines[1:])}
        log("REQ %s %s origin=%s" % (method, path, headers.get("origin")))
        if headers.get("upgrade", "").lower() == "websocket":
            websocket(conn, headers)
        elif path == "/":
            reply(conn, b"200 OK", PAGE)
        elif path == "/api":
            reply(conn, b"200 OK", b"dev answer", "text/plain")
        elif path.startswith("/redirect?to="):
            to = urllib.parse.unquote(path.split("=", 1)[1]).encode()
            conn.sendall(b"HTTP/1.1 302 Found\r\nLocation: " + to + b"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        else:
            reply(conn, b"404 Not Found", b"no", "text/plain")
    except OSError:
        pass
    finally:
        conn.close()


server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    server.bind(("127.0.0.1", PORT))
    server.listen(20)
except OSError as e:
    print("LISTEN-DENIED %s" % e, flush=True)
    sys.exit(3)
print("LISTENING", flush=True)
while True:
    c, _ = server.accept()
    threading.Thread(target=answer, args=(c,), daemon=True).start()
