"""mailctl: the commands of the mail container.

  mailctl run                the service (the container's main process)
  mailctl config             set up the account: address, app password, allowed addresses, sender name; then the
                             case's mailbox, only the mails the account does not hold yet (kingo mail; also: setup)
  mailctl seed [--force]     put the case's sample mailbox into the Maildir and upload what the provider does not
                             hold yet (kingo mail seed)
  mailctl wake [source]      ask the running service for a sync (the watcher uses it)
  mailctl status             account, folders and the last sync
"""

import argparse
import getpass
import logging
import sys

from . import account, case, db, settings


def main(argv=None):
    p = argparse.ArgumentParser(prog="mailctl", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("run")
    s = sub.add_parser("config", aliases=["setup"])   # setup: the name of the homework's 3 Nov text
    s.add_argument("--address")
    s.add_argument("--password-stdin", action="store_true", help="read the app password from stdin")
    s.add_argument("--imap-host")
    s.add_argument("--smtp-host")
    s.add_argument("--allowed", help="comma-separated addresses the course mode may send to")
    s.add_argument("--name", help="the sender name on the mails it sends")
    s.add_argument("--yes", action="store_true", help="no questions; take the defaults")
    s = sub.add_parser("seed")
    s.add_argument("--force", action="store_true", help="seed again (uploads every mail a second time)")
    s = sub.add_parser("wake")
    s.add_argument("source", nargs="?", default="manual")
    sub.add_parser("status")
    args = p.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s",
                        datefmt="%Y-%m-%d %H:%M:%S", stream=sys.stdout)
    return {"run": cmd_run, "config": cmd_config, "setup": cmd_config, "seed": cmd_seed, "wake": cmd_wake,
            "status": cmd_status}[args.cmd](args)


def cmd_run(args):
    from .loop import Service
    Service().run()
    return 0


def _ask(prompt, default=""):
    answer = input(f"{prompt}{f' [{default}]' if default else ''}: ").strip()
    return answer or default


def _yes(prompt, default=True):
    answer = input(f"{prompt} {'[Y/n]' if default else '[y/N]'}: ").strip().lower()
    return default if not answer else not answer.startswith("n")


def cmd_config(args):
    """The account, then the case's mailbox (Frank, 7 Nov 2026: "kingo mail config", every question with a
    suggestion that Enter takes)."""
    paths = settings.Paths()
    old = settings.load(paths)
    address = args.address or _ask("Mail address of your test account", old.address if old else "")
    if old and address.lower() != old.address.lower() and any(paths.maildir.glob("*/cur/*")):
        print(f"This container already holds the mailbox of {old.address}. Changing the account would upload\n"
              f"those mails into {address}. Forget the old account first: ./kingo mail reset\n"
              f"(with dev.sh: ./dev.sh reset)", file=sys.stderr)
        return 2
    same = old is not None and address.lower() == old.address.lower()
    saved = settings.read_password(paths) if same and paths.password.exists() else ""
    if args.password_stdin:
        password = sys.stdin.readline().strip() or saved
    elif args.yes and saved:
        password = saved
    else:
        password = getpass.getpass("App password (input stays hidden)"
                                   + (" [Enter keeps the saved one]" if saved else "") + ": ").strip() or saved
    if not password:
        print("No app password: nothing changed.", file=sys.stderr)
        return 1
    d = account.defaults(address)
    imap_host = args.imap_host or (d["imap_host"] if args.yes or "gmail" in d["imap_host"] else _ask("IMAP server", d["imap_host"]))
    smtp_host = args.smtp_host or (d["smtp_host"] if args.yes or "gmail" in d["smtp_host"] else _ask("SMTP server", d["smtp_host"]))
    if args.allowed is not None:
        allowed = args.allowed.split(",")
    elif args.yes:
        allowed = old.allowed if old else []
    else:
        print("Course mode: replies go only to your own address and its plus addresses (name+anything@...).")
        allowed = _ask("Other addresses it may send to, e.g. your SKKU address (comma-separated, or empty)",
                       ",".join(old.allowed) if old else "").split(",")
    with_case = (settings.case_dir() / "maildir").is_dir()   # without a course case: only the account
    name = (old.name if old and old.name else "") or (case.case_name() if with_case else "")
    if args.name is not None:
        name = args.name.strip()
    elif not args.yes:
        name = _ask("Sender name on the mails it sends", name)
    print(f"Signing in to {imap_host} and {smtp_host} ... (nothing is sent)")
    try:
        cfg, password = account.configure(address, password, imap_host, smtp_host, allowed=allowed)
    except Exception as e:
        print(f"Sign-in failed: {e}", file=sys.stderr)
        return 1
    cfg.name = name
    settings.save(paths, cfg, password)
    print(f"OK. Folders: sent = {cfg.folders['sent']}, drafts = {cfg.folders['drafts']}, "
          f"archive = {cfg.folders['archive']}{' (will be created)' if cfg.create_archive else ''}")
    print(f"Course mode sends to {cfg.address}, its plus addresses" + (f" and {', '.join(cfg.allowed)}." if cfg.allowed else "."))
    print(f"Sender name: {cfg.name or cfg.address}.")
    if not with_case:
        return 0
    try:
        conn = db.connect()
    except Exception as e:
        print(f"The account is saved, but Postgres is not reachable ({e}). Once kingo-pod runs: ./kingo mail seed",
              file=sys.stderr)
        return 1
    with conn:
        rc = _case_mailbox(paths, cfg, conn, confirm=(lambda prompt: True) if args.yes else _yes)
        return _documents(conn) or rc


def cmd_seed(args):
    paths = settings.Paths()
    cfg = settings.load(paths)
    if not cfg:
        print("Set up the account first: ./kingo mail", file=sys.stderr)
        return 2
    try:
        conn = db.connect()
    except Exception as e:
        print(f"Not seeded: cannot reach Postgres, which notes the accounts already seeded: {e}", file=sys.stderr)
        return 1
    with conn:
        rc = _case_mailbox(paths, cfg, conn, force=args.force)
        return _documents(conn) or rc


def _case_mailbox(paths, cfg, conn, force=False, confirm=None):
    """The case's old mails into the account, but only those the provider does not hold yet (Frank, 7 Nov 2026, on a
    second kingo-pod with the same test Gmail account: "es soll selbst erkennen"). They are found by Message-ID:
    each mail of the case has its own, and only a seed puts it into an account, so nothing else can look like one.
    If the provider cannot be read, nothing is copied. `confirm(prompt)` asks before an upload (kingo mail); without
    it (kingo mail seed) the upload is what was asked for. --force copies as before, without asking the provider.
    Returns 0 or 1."""
    where = "your test Gmail account" if cfg.gmail else "your test account"
    try:
        if not force:
            case.check_not_seeded(paths, cfg, conn)
            ids = case.case_message_ids()
            try:
                held = account.provider_message_ids(cfg, None if cfg.test_far_maildir else settings.read_password(paths))
            except Exception as e:
                print(f"Mailbox: cannot read the mails in {where} ({e}), so nobody can tell which are there already. "
                      f"Nothing is uploaded. Try again: ./kingo mail seed", file=sys.stderr)
                return 1
            total, there = len(ids), sum(1 for i in ids if i in held)
            print(f"{where[0].upper()}{where[1:]} holds {there:,} of {total:,} of {case.case_owner()} mails.")
            missing = total - there
            if missing and confirm and not confirm(f"Upload the {missing:,} missing ones now?" if there else "Upload them now?"):
                print("Nothing uploaded. To upload them later: ./kingo mail seed")
                return 0
        counts = case.seed(paths, cfg, force=force, conn=conn, present=None if force else held)
    except case.AlreadySeeded as e:   # the documents may still need loading, e.g. after `kingo update`
        # Seeding again is the one answer when the upload seems stuck: it wakes the sync, which goes on where
        # it stopped (Frank, 3 Nov 2026, after an upload that stood still at 2,420 of 3,244).
        print(f"Mailbox: {e}. The upload goes on now; ./kingo mail status shows how far it is.")
        _wake(conn, "(The service goes on with its next run: {})")
        return 0
    except RuntimeError as e:
        print(f"Mailbox not seeded: {e}", file=sys.stderr)
        return 1
    if not cfg.name:
        cfg.name = case.case_name()
        settings.save(paths, cfg)
    if force or not there:
        print("Mailbox: " + ", ".join(f"{n} mails in {f}" for f, n in counts.items()) + ". Uploading starts now.")
    elif missing:
        print(f"Mailbox: {missing:,} mails to upload, the other {there:,} are there already. Uploading starts now.")
    else:
        print("Mailbox: nothing to upload. kingo-pod now copies them from Gmail into its database."
              if cfg.gmail else "Mailbox: nothing to upload. kingo-pod now copies them into its database.")
    print("./kingo mail status shows how far it is.")
    _wake(conn, "(The service will upload them on its next run: {})")
    return 0


def _wake(conn, note):
    try:
        db.wake(conn, action="sync", source="seed")
    except Exception as e:
        print(note.format(e))


def _documents(conn):
    """The case documents into n8n_workshop_mail.chunks; 0 or 1."""
    try:
        docs = case.load_documents(conn)
    except Exception as e:   # no file, no table (an old schema), a vector of the wrong length
        print(f"Documents not loaded: {str(e).strip()}", file=sys.stderr)
        return 1
    print(f"Documents: {docs['chunks']} chunks from {docs['documents']} documents, ready for search.")
    return 0


def cmd_wake(args):
    with db.connect() as conn:
        db.wake(conn, action="sync", source=args.source)
    return 0


def cmd_status(args):
    paths = settings.Paths()
    cfg = settings.load(paths)
    if not cfg:
        print("Not set up yet: ./kingo mail config")
        return 1
    print(f"Account:     {cfg.address} ({cfg.imap_host}, {cfg.smtp_host})")
    print(f"Folders:     " + ", ".join(f"{k} = {v}" for k, v in cfg.folders.items()))
    locked = case.course_mode(cfg) and not cfg.course_mode
    print(f"Course mode: {'on' if case.course_mode(cfg) else 'off'}" + (" (the case is loaded)" if locked else "")
          + (f", also to {', '.join(cfg.allowed)}" if cfg.allowed else ""))
    print(f"Seeded:      {'yes' if paths.seeded.exists() else 'no'}")
    try:
        with db.connect() as conn:
            st = conn.execute("SELECT * FROM n8n_workshop_mail.sync_state").fetchone()
            n = conn.execute("SELECT count(*) AS n FROM n8n_workshop_mail.messages WHERE deleted_at IS NULL").fetchone()["n"]
        print(f"Mails:       {n} in Postgres")
        print(f"Last sync:   {st['last_run_at']}  last ok: {st['last_ok_at']}")
        if st["last_error"]:
            print(f"Last error:  {st['last_error_at']}: {st['last_error']}")
    except Exception as e:
        print(f"Postgres:    not reachable ({e})")
    print_folder_counts(cfg, paths)
    return 0


def print_folder_counts(cfg, paths):
    """Each synced folder, here and at the provider: while the numbers differ, the sync is still running (Frank,
    3 Nov 2026: "wäre ein status oder ein progress irgendwo möglich?"). Every folder, not only the case's two:
    with a real mailbox there are more, and the mails come down instead of up."""
    where = "Gmail" if cfg.gmail else cfg.imap_host
    try:
        rows = account.folder_counts(cfg, paths, None if cfg.test_far_maildir else settings.read_password(paths))
    except Exception as e:
        print(f"At {where}:    not reachable ({e})")
        return
    width = max(len(f) for f, _, _ in rows)
    print(f"Mails here and at {where}:")
    for folder, here, far in rows:
        far_text = f"{far:>6,}" if far is not None else "     ?"
        note = "" if far == here else "  (cannot read it)" if far is None else "  (not yet the same: still syncing)"
        print(f"  {folder:<{width}}  {here:>6,} here  {far_text} at {where}{note}")
    if any(far is None for _, _, far in rows):
        print("Sync:        cannot tell, a folder could not be read")
    elif all(far == here for _, here, far in rows):
        print(f"Sync:        done, every folder is the same here and at {where}")
    else:
        print("Sync:        still running. Keep kingo-pod running and your laptop awake; it goes on by itself.")
