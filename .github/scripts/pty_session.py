"""CI: start a program in a terminal of its own, answer what it shows, and wait for a word on the screen.

    python3 pty_session.py STEPS.json SCREENS.txt command [argument ...]

STEPS.json: {"until": "a word that ends the session with success", "seconds": 120,
             "steps": [{"see": "a regular expression on the screen", "send": "keys", "name": "..."}, ...]}

The steps are tried in their order whenever the screen has changed and then stood still for a moment. A step is used
once. Every screen that differs from the one before goes into SCREENS.txt, so a failed run can be read afterwards.
Exit code 0 when the word of "until" came, 1 when the time ran out or the program ended before.
Needs pyte (pip install pyte), which keeps the screen as a terminal would show it.
"""
import fcntl
import json
import os
import pty
import re
import select
import signal
import struct
import sys
import termios
import time

import pyte

ROWS, COLUMNS = 50, 160


def main():
    plan = json.load(open(sys.argv[1], encoding="utf-8"))
    screens_file, command = sys.argv[2], sys.argv[3:]
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.execvp(command[0], command)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLUMNS, 0, 0))
    screen = pyte.Screen(COLUMNS, ROWS)
    stream = pyte.ByteStream(screen)
    steps = [dict(step, done=False) for step in plan["steps"]]
    end = time.time() + plan.get("seconds", 120)
    shown, last_change, result, alive = None, time.time(), None, True

    def text():
        return "\n".join(line.rstrip() for line in screen.display).strip("\n")

    with open(screens_file, "w", encoding="utf-8") as out:
        def note(what):
            out.write("\n===== %s (%.1f s left)\n%s\n" % (what, end - time.time(), text()))
            out.flush()

        while time.time() < end and result is None:
            readable, _, _ = select.select([fd], [], [], 0.2)
            if readable:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    data = b""
                if not data:
                    alive = False
                else:
                    stream.feed(data)
            now = text()
            if now != shown:
                shown, last_change = now, time.time()
                note("screen")
            if plan["until"] in now:
                result = 0
            elif not alive:
                result = 1
                note("the program ended")
            elif time.time() - last_change > 0.7:          # the screen stands still: answer it
                for step in steps:
                    if not step["done"] and re.search(step["see"], now):
                        step["done"] = True
                        note("step: %s" % step.get("name", step["see"]))
                        for part in step["send"] if isinstance(step["send"], list) else [step["send"]]:
                            os.write(fd, part.encode("utf-8"))
                            time.sleep(0.3)
                        last_change = time.time()
                        break
        if result is None:
            result = 1
            note("the time ran out")
        note("the word came" if result == 0 else "ended without the word")
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.kill(pid, sig)
        except OSError:
            break
        time.sleep(0.5)
    print("steps used: %s" % ", ".join(step.get("name", step["see"]) for step in steps if step["done"]))
    print("steps not used: %s" % (", ".join(step.get("name", step["see"]) for step in steps if not step["done"]) or "none"))
    return result


if __name__ == "__main__":
    sys.exit(main())
