"""CI: run a command in a terminal of its own and type answers into it, as a student would.

    python3 pty_answer.py [--all] SECONDS [ANSWER ...] -- command [argument ...]

Each ANSWER is typed, with Enter, when the program shows a question: output that ends with ": " and then stands still
for a moment. An empty ANSWER is Enter alone. What the terminal showed goes to stdout, without carriage returns. The
exit code is the program's, and 124 when the time ran out (the program is killed then). With --all, every ANSWER
must be taken: an answer left over at the end is a question that the program did not ask, and the exit code is 126
(kingo key add, 20 Nov 2026: a test whose dialog lost a question must not pass). Needs no package: unlike
pty_session.py it keeps no screen, it only reads what the program writes.
"""
import os
import pty
import select
import signal
import sys
import time


def main():
    args = sys.argv[1:]
    strict = args[0] == "--all"
    if strict:
        args = args[1:]
    seconds = float(args[0])
    rest = args[1:]
    split = rest.index("--")
    answers, command = rest[:split], rest[split + 1:]
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(command[0], command)
    shown = bytearray()
    since = bytearray()            # what came since the last answer
    last = time.time()
    end = last + seconds
    while True:
        if time.time() > end:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
            sys.stdout.write(shown.decode(errors="replace").replace("\r", ""))
            sys.stdout.write("\n[pty_answer: the time ran out]\n")
            sys.exit(124)
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            try:
                data = os.read(fd, 4096)
            except OSError:        # Linux: the program has ended
                data = b""
            if not data:
                break
            shown += data
            since += data
            last = time.time()
        elif answers and since.endswith(b": ") and time.time() - last > 0.3:
            os.write(fd, answers.pop(0).encode() + b"\n")
            since = bytearray()
    _, status = os.waitpid(pid, 0)
    sys.stdout.write(shown.decode(errors="replace").replace("\r", ""))
    if strict and answers:
        sys.stdout.write("\n[pty_answer: %d answer(s) left, for questions that never came]\n" % len(answers))
        sys.exit(126)
    if os.WIFEXITED(status):
        sys.exit(os.WEXITSTATUS(status))
    sys.exit(128 + os.WTERMSIG(status))


main()
