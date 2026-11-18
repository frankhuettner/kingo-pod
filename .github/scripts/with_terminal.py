"""CI: run a command in a terminal of its own, and type one answer when it asks.

    python3 with_terminal.py 'the answer' command [argument ...]

kingo asks for a key in a terminal only ([ -t 0 ]), and reads it without showing it. This gives the command a
terminal (a pty), waits for the words that end kingo's question, "(it is not shown): ", and types the answer and
Enter, once. What the command printed goes to stdout, and its exit code is this program's. An answer of '' is
Enter alone. A command that never asks gets no answer.
"""
import os
import pty
import select
import sys

ANSWER, COMMAND = sys.argv[1], sys.argv[2:]
ASKS = b"(it is not shown): "

pid, fd = pty.fork()
if pid == 0:
    os.execvp(COMMAND[0], COMMAND)

seen, answered = b"", False
while True:
    ready, _, _ = select.select([fd], [], [], 60)
    if not ready:
        break   # a minute of silence: the command hangs
    try:
        data = os.read(fd, 4096)
    except OSError:   # Linux: the terminal is gone with the command
        break
    if not data:
        break
    seen += data
    if not answered and ASKS in seen:
        os.write(fd, ANSWER.encode() + b"\n")
        answered = True

_, status = os.waitpid(pid, 0)
sys.stdout.write(seen.decode("utf-8", "replace").replace("\r", ""))
sys.exit(os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") else (status >> 8))
