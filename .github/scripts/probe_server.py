"""CI: a server outside the sandbox, for the question whether a program inside can reach it without nono's proxy.

    python3 probe_server.py PORT SOCKET WORD

It answers every connection on 127.0.0.1:PORT and on the Unix socket SOCKET with a small HTTP answer that holds WORD.
"""
import os
import socket
import sys
import threading

PORT, PATH, WORD = int(sys.argv[1]), sys.argv[2], sys.argv[3]
BODY = (WORD + "\n").encode()
ANSWER = b"HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nContent-Length: %d\r\n\r\n%s" % (len(BODY), BODY)


def serve(server):
    while True:
        conn, _ = server.accept()
        try:
            conn.settimeout(3)
            conn.recv(4096)
            conn.sendall(ANSWER)
        except OSError:
            pass
        finally:
            conn.close()


tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
tcp.bind(("127.0.0.1", PORT))
tcp.listen(8)
if os.path.exists(PATH):
    os.unlink(PATH)
unix = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
unix.bind(PATH)
unix.listen(8)
threading.Thread(target=serve, args=(unix,), daemon=True).start()
serve(tcp)
