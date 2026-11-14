"""CI: run under setup/claude/no_unix_sockets.py and see what the lock refuses and what it leaves alone.

    python3 no_unix_sockets.py python3 probe_calls.py        every line must say "ok"
    python3 probe_calls.py --unlocked                        the same calls without the lock, as a comparison

Exit code 0 when all is as it should be.
"""
import asyncio
import ctypes
import errno
import os
import socket
import subprocess
import sys

UNLOCKED = "--unlocked" in sys.argv
NONBLOCK = getattr(socket, "SOCK_NONBLOCK", 0)
bad = []


def line(ok, what, got):
    print("%-4s %-58s %s" % ("ok" if ok else "BAD", what, got))
    if not ok:
        bad.append(what)


def attempt(call):
    """-> "works", or the name of the error the call ended with"""
    try:
        made = call()
    except OSError as error:
        return errno.errorcode.get(error.errno, str(error.errno))
    for one in made if isinstance(made, tuple) else (made,):
        one.close()
    return "works"


def refused(what, call, error="EPERM"):
    got = attempt(call)
    line(got == ("works" if UNLOCKED else error), what + (" opens" if UNLOCKED else " is refused"), got)


def stays(what, call):
    got = attempt(call)
    line(got == "works", what + " works", got)


def io_uring_setup():
    libc = ctypes.CDLL(None, use_errno=True)
    params = ctypes.create_string_buffer(120)          # struct io_uring_params, zeroed
    libc.syscall.restype = ctypes.c_long
    fd = libc.syscall(ctypes.c_long(425), ctypes.c_long(4), ctypes.byref(params))
    if fd < 0:
        number = ctypes.get_errno()
        raise OSError(number, os.strerror(number))
    os.close(fd)
    return ()


# Unix sockets: none can be made, of any type, with or without flags
for name, kind in (("SOCK_STREAM", socket.SOCK_STREAM), ("SOCK_DGRAM", socket.SOCK_DGRAM), ("SOCK_SEQPACKET", socket.SOCK_SEQPACKET)):
    refused("socket(AF_UNIX, %s)" % name, lambda kind=kind: socket.socket(socket.AF_UNIX, kind))
    refused("socket(AF_UNIX, %s | SOCK_NONBLOCK)" % name, lambda kind=kind: socket.socket(socket.AF_UNIX, kind | NONBLOCK))
refused("socketpair(AF_UNIX, SOCK_DGRAM)", lambda: socket.socketpair(socket.AF_UNIX, socket.SOCK_DGRAM))

# io_uring: the kernel may have it turned off for everybody (then the comparison says EPERM, and that is fine too)
got = attempt(io_uring_setup) if sys.platform.startswith("linux") else "ENOSYS"
line(got in (("works", "EPERM", "ENOSYS") if UNLOCKED else ("ENOSYS",)),
     "io_uring_setup" + (" (comparison)" if UNLOCKED else " is refused as not there"), got)

# what programs need to start other programs and to use the network
stays("socketpair(AF_UNIX, SOCK_STREAM)", lambda: socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM))
stays("socketpair(AF_UNIX, SOCK_SEQPACKET)", lambda: socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET))
stays("socket(AF_INET, SOCK_STREAM)", lambda: socket.socket(socket.AF_INET, socket.SOCK_STREAM))
stays("socket(AF_INET, SOCK_DGRAM)", lambda: socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
stays("socket(AF_INET6, SOCK_STREAM)", lambda: socket.socket(socket.AF_INET6, socket.SOCK_STREAM))

a, b = socket.socketpair()
a.sendall(b"through the pair")
line(b.recv(64) == b"through the pair", "bytes go through a socketpair", "")
a.close(), b.close()

r, w = os.pipe()
os.write(w, b"through the pipe")
line(os.read(r, 64) == b"through the pipe", "bytes go through a pipe", "")
os.close(r), os.close(w)

out = subprocess.run(["sh", "-c", "echo from a child | cat"], capture_output=True, text=True)
line(out.returncode == 0 and out.stdout.strip() == "from a child", "a child with pipes runs", out.stdout.strip())

asyncio.run(asyncio.sleep(0))
line(True, "an asyncio loop runs", "")

# a TCP connection on this machine, both ends here
server = socket.socket()
server.bind(("127.0.0.1", 0))
server.listen(1)
client = socket.socket()
client.connect(server.getsockname())
peer, _ = server.accept()
client.sendall(b"over tcp")
line(peer.recv(64) == b"over tcp", "TCP on this machine works", "")
for one in (peer, client, server):
    one.close()

print("%s: %s" % ("without the lock" if UNLOCKED else "with the lock", "all as expected" if not bad else "%d not as expected" % len(bad)))
sys.exit(1 if bad else 0)
