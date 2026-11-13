#!/usr/bin/env python3
"""Start a program that cannot open Unix sockets. Linux only: `kingo claude` starts Claude Code through it there.

    python3 no_unix_sockets.py claude --add-dir ...

Why. nono keeps Claude Code away from files. Under Linux it does not keep a program from connecting to a Unix socket:
Landlock, which nono uses there, does not look at connect(2), and nono's own guard for it needs seccomp user
notification, which Windows (WSL2) does not have. Docker, Podman's API socket and the systemd user manager listen on
Unix sockets and work outside the sandbox. One `docker run -v /home:/h ...` from inside the sandbox would read and
write the files that the sandbox keeps away. On a Mac, nono blocks these connections itself.

How. A seccomp filter of the plain kind, without user notification, which WSL2 has too. The kernel applies it to this
process and to everything started from it, and nothing can take it off again. It refuses:

  - socket(AF_UNIX, ...): no new Unix socket, so there is nothing to connect or to bind
  - socketpair(AF_UNIX, SOCK_DGRAM, ...): a datagram socket can send to the path of a socket without connecting
  - io_uring_setup: io_uring can open and connect sockets without the calls above
  - every call in another calling convention (a 32-bit program on a 64-bit kernel): there the numbers differ

Pipes and socketpair(AF_UNIX, SOCK_STREAM, ...) stay, because programs start other programs with them. The sockets of
the network stay too: Claude Code reaches OpenRouter, n8n, Langflow and PostgreSQL through TCP.
"""
import ctypes
import errno
import os
import platform
import socket
import struct
import sys

# What the kernel calls this machine in a filter, and its numbers for socket, socketpair and io_uring_setup.
MACHINES = {
    "x86_64": (0xC000003E, 41, 53, 425),
    "aarch64": (0xC00000B7, 198, 199, 425),
}
AF_UNIX, SOCK_DGRAM = 1, 2
X32 = 0x40000000  # x86-64 only: calls of the x32 convention carry this bit

# A filter is a list of (code, jump if true, jump if false, value). It reads `struct seccomp_data`:
# the number of the call at 0, the calling convention at 4, the arguments from 16 on, 8 bytes each.
LOAD, EQUAL, AT_LEAST, AND, RETURN = 0x20, 0x15, 0x35, 0x54, 0x06
ALLOW, ERRNO = 0x7FFF0000, 0x00050000


def assemble(lines):
    """[(label, code, value, label if true, label if false)] -> the filter as bytes. A jump counts from the next line."""
    at = {label: i for i, (label, *_) in enumerate(lines) if label}
    out = b""
    for i, (_, code, value, yes, no) in enumerate(lines):
        out += struct.pack("=HBBI", code, at[yes] - i - 1 if yes else 0, at[no] - i - 1 if no else 0, value)
    return out


def filter_for(machine):
    convention, nr_socket, nr_socketpair, nr_io_uring_setup = MACHINES[machine]
    return assemble([
        ("", LOAD, 4, "", ""),                                   # the calling convention
        ("", EQUAL, convention, "number", "no_such_call"),
        ("number", LOAD, 0, "", ""),                             # the number of the call
        ("", AT_LEAST, X32, "no_such_call", "io_uring"),
        ("io_uring", EQUAL, nr_io_uring_setup, "no_such_call", "socket"),
        ("socket", EQUAL, nr_socket, "family", "socketpair"),
        ("socketpair", EQUAL, nr_socketpair, "pair_family", "allow"),
        ("family", LOAD, 16, "", ""),                            # socket(family, ...)
        ("", EQUAL, AF_UNIX, "refuse", "allow"),
        ("pair_family", LOAD, 16, "", ""),                       # socketpair(family, type, ...)
        ("", EQUAL, AF_UNIX, "pair_type", "allow"),
        ("pair_type", LOAD, 24, "", ""),
        ("", AND, 0xF, "", ""),                                  # the type without its flags
        ("", EQUAL, SOCK_DGRAM, "refuse", "allow"),
        ("allow", RETURN, ALLOW, "", ""),
        ("refuse", RETURN, ERRNO | errno.EPERM, "", ""),         # "Operation not permitted"
        ("no_such_call", RETURN, ERRNO | errno.ENOSYS, "", ""),  # "Function not implemented": programs then do without
    ])


class Program(ctypes.Structure):  # struct sock_fprog
    _fields_ = [("length", ctypes.c_ushort), ("filter", ctypes.c_void_p)]


def lock(machine):
    """Put the filter on this process. Raises OSError when the kernel does not take it."""
    code = filter_for(machine)
    buffer = ctypes.create_string_buffer(code, len(code))
    program = Program(len(code) // 8, ctypes.addressof(buffer))
    libc = ctypes.CDLL(None, use_errno=True)
    libc.prctl.argtypes = [ctypes.c_int] + [ctypes.c_ulong] * 4
    libc.prctl.restype = ctypes.c_int
    # 38: PR_SET_NO_NEW_PRIVS, which a filter without root needs. 22, 2: PR_SET_SECCOMP, SECCOMP_MODE_FILTER.
    for arguments in ((38, 1, 0, 0, 0), (22, 2, ctypes.addressof(program), 0, 0)):
        if libc.prctl(*arguments) != 0:
            number = ctypes.get_errno()
            raise OSError(number, os.strerror(number))


def locked():
    """True when a new Unix socket is refused."""
    try:
        socket.socket(socket.AF_UNIX).close()
    except OSError as error:
        return error.errno == errno.EPERM
    return False


def stop(why):
    sys.stderr.write(
        "kingo claude: could not lock the Unix sockets: %s.\n"
        "Claude Code was not started, because the sandbox would not hold without this lock.\n"
        "Please send these lines and the output of ./kingo version to your instructor.\n" % why)
    sys.exit(1)


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: no_unix_sockets.py program [argument ...]\n")
        return 2
    if not sys.platform.startswith("linux"):
        stop("this lock is for Linux, and this is %s" % sys.platform)
    machine = platform.machine()
    if machine not in MACHINES:
        stop("it does not know the processor %s" % machine)
    try:
        lock(machine)
    except OSError as error:
        stop("the kernel refused it (%s)" % error.strerror)
    if not locked():
        stop("a Unix socket still opens")
    try:
        os.execvp(argv[1], argv[1:])
    except OSError as error:
        sys.stderr.write("kingo claude: could not start %s: %s\n" % (argv[1], error.strerror))
        return 127


if __name__ == "__main__":
    sys.exit(main(sys.argv))
