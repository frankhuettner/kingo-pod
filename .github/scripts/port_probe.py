"""Ports for the trial of round 3.

    port_probe.py bind <host> <port>                 try to listen there, then close; prints BIND-OK, BIND-REFUSED or BIND-INUSE
    port_probe.py serve <host> <port> <dir> <secs>   serve the files of <dir> there for so many seconds
"""
import errno
import functools
import http.server
import socket
import sys
import threading


def bind(host, port):
    family = socket.AF_INET6 if ":" in host else socket.AF_INET
    s = socket.socket(family, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind((host, port))
        s.listen(1)
        print(f"BIND-OK {host}:{port}")
    except OSError as e:
        # taken by another program is not refused by the sandbox
        word = "INUSE" if e.errno == errno.EADDRINUSE else "REFUSED"
        print(f"BIND-{word} {host}:{port} {errno.errorcode.get(e.errno, e.errno)}")
    finally:
        s.close()


def serve(host, port, folder, seconds):
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass

    http.server.ThreadingHTTPServer.allow_reuse_address = True
    try:
        server = http.server.ThreadingHTTPServer((host, port), functools.partial(Quiet, directory=folder))
    except OSError as e:
        print(f"SERVE-REFUSED {host}:{port} {errno.errorcode.get(e.errno, e.errno)}", flush=True)
        sys.exit(1)
    print(f"SERVE-OK {host}:{port}", flush=True)
    threading.Timer(seconds, server.shutdown).start()
    server.serve_forever()


if __name__ == "__main__":
    if sys.argv[1] == "bind":
        bind(sys.argv[2], int(sys.argv[3]))
    else:
        serve(sys.argv[2], int(sys.argv[3]), sys.argv[4], float(sys.argv[5]))
