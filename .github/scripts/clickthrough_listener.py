"""CI: a service on this laptop, as n8n is one, for the question whether a page in clickthrough can reach it.

    python3 clickthrough_listener.py PORT LOG

Listens on 127.0.0.1:PORT and writes one line into LOG for every connection that arrives: ARRIVED with its first
bytes, TLS when they open a TLS handshake, EMPTY when none come in 3 seconds. A page may still reach the port by https
(nono's proxy lets it through, and Chrome turns an http image of an https page into https), but a service that speaks
http reads no request in a TLS handshake. So only ARRIVED counts.
"""
import socket
import sys
import threading

PORT, LOG = int(sys.argv[1]), sys.argv[2]
lock = threading.Lock()


def answer(conn):
    try:
        conn.settimeout(3)
        try:
            first = conn.recv(200)
        except OSError:
            first = b""
        with lock, open(LOG, "a") as log:
            if not first:
                log.write("EMPTY\n")
            elif first[:2] == b"\x16\x03":
                log.write("TLS %d bytes\n" % len(first))
            else:
                log.write("ARRIVED %r\n" % first[:120])
        conn.sendall(b"HTTP/1.0 200 OK\r\nContent-Length: 3\r\n\r\nhi\n")
    except OSError:
        pass
    finally:
        conn.close()


server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", PORT))
server.listen(50)
while True:
    c, _ = server.accept()
    threading.Thread(target=answer, args=(c,), daemon=True).start()
