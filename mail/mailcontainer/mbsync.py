"""mbsync: the only program that writes to the provider over IMAP."""

import logging
import subprocess
from dataclasses import dataclass

from .settings import tool

log = logging.getLogger("mbsync")

TIMEOUT = 600


@dataclass
class Result:
    ok: bool
    pushed: bool     # something changed at the provider
    pulled: bool     # something changed here
    errors: str      # mbsync's complaints, also refusals by the provider (e.g. a mail over its size limit)
    stopped: bool = False   # stopped after TIMEOUT: the loop starts the next run right away


def run(paths, channels=None):
    """Sync the given channels (inbox, sent, drafts, archive), or all of them."""
    names = sorted(channels) if channels else ["all"]
    cmd = [tool("mbsync"), "-c", str(paths.mbsyncrc), "-q", "-e", *names]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        # A big upload (the course mailbox: 2,000 mails took 13 minutes) runs into this; the next run goes on
        # where this one stopped, without doubles (Gmail test, 29 Oct). The loop starts it right away: waiting
        # for the schedule made 16,006 mails take 3 hours 42 minutes instead of about 2 (30 Oct).
        log.warning("mbsync %s: stopped after %d s; the next run goes on", " ".join(names), TIMEOUT)
        return Result(False, False, False, f"mbsync took longer than {TIMEOUT} s", stopped=True)
    code = proc.returncode
    errors = "\n".join(line for line in (proc.stderr + proc.stdout).splitlines() if line.strip())
    res = Result(ok=(code & ~96) == 0, pushed=bool(code & 32), pulled=bool(code & 64), errors=errors)
    if not res.ok:
        log.warning("mbsync %s: exit %d: %s", " ".join(names), code, errors or "no message")
    elif res.pushed or res.pulled:
        log.info("mbsync %s:%s%s", " ".join(names), " uploaded" if res.pushed else "", " fetched" if res.pulled else "")
    return res
