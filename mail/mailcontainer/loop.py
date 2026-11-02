"""The service: one loop, the only clock in the container.

It wakes on n8n_workshop_mail_outbox (an approval) and n8n_workshop_mail_sync (watcher, "Fetch now",
deliver_test, a change n8n asks for), at the latest after the schedule: every 10 minutes with a
running watcher, every 2 minutes without one. After every connect it listens first and then does a
full pass, so nothing missed while it was away stays behind.

Order of a pass: outbox (sending does not wait), changes, mbsync, notmuch new, export. Steps run one
after the other, because notmuch allows one writer; each catches its own errors, so a stuck send does
not hold up reading. Between two mbsync runs lie at least 15 seconds. When mbsync stops at its time limit (a big
upload, such as the course mailbox), the next full pass follows right away instead of on schedule; it
sends approved mail first, as every pass does.
"""

import json
import logging
import signal
import subprocess
import threading
import time

import psycopg

from . import case, changes, db, mbsync, outbox, settings
from .export import export
from .notmuch import Notmuch

log = logging.getLogger("loop")

MIN_SYNC_GAP = 15
DEBOUNCE = 0.5
WAIT_SLICE = 2.0
CLOCK_JUMP = 60


class Service:
    def __init__(self, paths=None, connect=None, smtp_send=None):
        self.paths = paths or settings.Paths()
        self.connect = connect or db.connect
        self.smtp_send = smtp_send
        self.stopping = False
        self.cfg = None
        self.cfg_mtime = None
        self.nm = Notmuch(self.paths)
        self.watcher = None
        self.watcher_started = 0.0
        self.watcher_backoff = 5
        self.watcher_next = 0.0
        self.last_sync = -1e9
        self.pending = set()      # channels waiting for the gap between two mbsync runs
        self.next_full = 0.0

    # -- lifecycle -------------------------------------------------------------------------------

    def stop(self, *_):
        self.stopping = True

    def run(self):
        if threading.current_thread() is threading.main_thread():
            signal.signal(signal.SIGTERM, self.stop)   # finish the current mail, then stop
            signal.signal(signal.SIGINT, self.stop)
        backoff = 2
        try:
            while not self.stopping:
                if not self._wait_for_config():
                    break
                try:
                    with self.connect() as conn:
                        db.listen(conn)
                        backoff = 2
                        log.info("connected to Postgres, listening")
                        self.full_pass(conn)
                        self.serve(conn)
                except (psycopg.OperationalError, psycopg.InterfaceError) as e:
                    log.warning("Postgres: %s; trying again in %d s", str(e).strip(), backoff)
                    self._sleep(backoff)
                    backoff = min(backoff * 2, 60)
        finally:
            self._stop_watcher()
            log.info("stopped")

    def _sleep(self, seconds):
        end = time.monotonic() + seconds
        while not self.stopping and time.monotonic() < end:
            time.sleep(min(0.5, end - time.monotonic()))

    def _wait_for_config(self):
        said = False
        while not self.stopping:
            if self._load_config():
                return True
            if not said:
                log.info("not set up yet: run ./kingo mail")
                said = True
            self._sleep(5)
        return False

    def _load_config(self):
        try:
            mtime = self.paths.config.stat().st_mtime
        except FileNotFoundError:
            return False
        if mtime != self.cfg_mtime:
            self.cfg = settings.load(self.paths)
            self.cfg_mtime = mtime
            settings.write_tools(self.paths, self.cfg)   # this image's mbsync settings, also for an old volume
            log.info("config loaded for %s", self.cfg.address)
            self._stop_watcher()
            self.next_full = 0.0
        return True

    # -- the loop --------------------------------------------------------------------------------

    def serve(self, conn):
        wall, mono = time.time(), time.monotonic()
        while not self.stopping:
            self._load_config()
            self._supervise_watcher()
            now = time.monotonic()
            jump = (time.time() - wall) - (now - mono)
            wall, mono = time.time(), now
            if jump > CLOCK_JUMP:
                log.info("the clock jumped %d s (sleep?): catching up", jump)
                self.next_full = 0.0
            if now >= self.next_full:
                self.full_pass(conn)
                continue
            if self.pending and now >= self.last_sync + MIN_SYNC_GAP:
                self.sync(conn, self.pending)
                continue

            due = min(self.next_full, self.last_sync + MIN_SYNC_GAP if self.pending else self.next_full)
            notes = list(conn.notifies(timeout=max(0.05, min(WAIT_SLICE, due - now)), stop_after=1))
            if not notes:
                continue
            notes += list(conn.notifies(timeout=DEBOUNCE))
            self.handle(conn, notes)

    def handle(self, conn, notes):
        approvals, channels, tests, full, wanted = False, set(), [], False, False
        for n in notes:
            if n.channel == db.OUTBOX:
                approvals = True
                continue
            try:
                p = json.loads(n.payload or "{}")
            except ValueError:
                p = {}
            action = p.get("action", "sync")
            if action == "deliver_test":
                tests.append(p.get("n"))
            elif action == "changes":
                wanted = True
            elif p.get("source") == "watcher":
                channels.add("inbox")
            else:   # "Fetch now", seed, anything else: everything
                full = True
        if approvals:
            self.run_outbox(conn)
        if wanted:
            self.run_changes(conn)
        if tests:
            for n in tests:
                self.deliver(conn, n)
            channels.add("inbox")
        if full:
            self.pending.update(self.cfg.channels)
        else:
            self.pending.update(channels)

    def full_pass(self, conn):
        self.run_outbox(conn)
        if self.stopping:   # no sync started after SIGTERM: the engine kills the container 60 s later
            return
        self.run_changes(conn)
        self.pending.update(self.cfg.channels)
        stopped = False
        if time.monotonic() >= self.last_sync + MIN_SYNC_GAP:
            stopped = self.sync(conn, self.pending)
        self.index(conn)
        if not stopped:
            self.next_full = time.monotonic() + self.interval()

    def interval(self):
        if self.cfg.watcher and self.watcher and self.watcher.poll() is None:
            return self.cfg.interval
        return self.cfg.interval_without_watcher

    # -- steps -----------------------------------------------------------------------------------

    def run_outbox(self, conn):
        try:
            res = outbox.process(conn, self.cfg, self.nm, self.paths, self.smtp_send,
                                 stopping=lambda: self.stopping)
        except psycopg.OperationalError:
            raise
        except Exception as e:
            log.exception("outbox")
            db.note_error(conn, f"outbox: {e}")
            return
        if res.changed:
            self.index(conn)
            if "*" in res.folders:
                self.pending.update(self.cfg.channels)
            for key, local in self.cfg.local_folders.items():
                if local in res.folders:
                    self.pending.add(key)
            self.pending.add("inbox")

    def run_changes(self, conn):
        try:
            res = changes.process(conn, self.cfg, self.nm, self.paths)
            if res.fetch_first:   # a mail to archive is only in INBOX here: fetch All Mail, then once more
                self.sync(conn, {"archive"})
                again = changes.process(conn, self.cfg, self.nm, self.paths, last_try=True)
                res.channels |= again.channels
        except psycopg.OperationalError:
            raise
        except Exception as e:
            log.exception("changes")
            db.note_error(conn, f"changes: {e}")
            return
        self.pending.update(res.channels)

    def deliver(self, conn, n):
        try:
            mid = case.deliver_test(self.paths, self.cfg, int(n))
            log.info("test mail %s delivered to the inbox as %s", n, mid)
        except Exception as e:
            log.warning("test mail %s: %s", n, e)
            db.note_error(conn, f"deliver_test({n}): {e}")
            return
        self.index(conn)

    def sync(self, conn, channels):
        requested = set(channels)
        self.pending -= requested
        channels = requested & set(self.cfg.channels)
        self.last_sync = time.monotonic()
        if not channels:
            return False
        res = mbsync.run(self.paths, channels)
        db.note_run(conn, res.ok, None if res.ok else f"mbsync: {res.errors or 'failed'}")
        self.index(conn)
        if res.stopped:   # a big upload goes on with the next full pass, now
            self.next_full = 0.0
        return res.stopped

    def index(self, conn):
        try:
            self.nm.new()
            export(conn, self.nm, self.paths, persona=case.persona(self.cfg))
        except psycopg.OperationalError:
            raise
        except Exception as e:
            log.exception("index")
            db.note_error(conn, f"index: {e}")

    # -- the watcher -----------------------------------------------------------------------------

    def _supervise_watcher(self):
        if not self.cfg.watcher or self.cfg.test_far_maildir:
            return
        if self.watcher and self.watcher.poll() is None:
            if time.monotonic() - self.watcher_started > 300:
                self.watcher_backoff = 5   # it has been up for a while: the next failure starts over
            return
        if self.watcher is not None:
            log.warning("watcher exited with %s; restarting in %d s", self.watcher.returncode, self.watcher_backoff)
            self.watcher = None
            self.watcher_next = time.monotonic() + self.watcher_backoff
            self.watcher_backoff = min(self.watcher_backoff * 2, 300)
            return
        if time.monotonic() < self.watcher_next:
            return
        try:
            self.watcher = subprocess.Popen([settings.tool("goimapnotify"), "-conf", str(self.paths.goimapnotify)])
            self.watcher_started = time.monotonic()
            log.info("watcher started")
        except OSError as e:
            log.warning("watcher not started: %s", e)
            self.watcher_next = time.monotonic() + 300

    def _stop_watcher(self):
        if self.watcher and self.watcher.poll() is None:
            # goimapnotify prints a request for donations to its author when it stops (and only then:
            # it exits on SIGTERM alone). Students see it in ./kingo logs mail, so say first whose it is.
            log.info("stopping the watcher: goimapnotify, a free tool by another author "
                     "(gitlab.com/shackra/goimapnotify) that tells this service about new mail at once; "
                     "as it stops it asks for a donation, and 'this project' there means goimapnotify")
            self.watcher.terminate()
            try:
                self.watcher.wait(10)
            except subprocess.TimeoutExpired:
                self.watcher.kill()
            log.info("watcher stopped")
        self.watcher = None
