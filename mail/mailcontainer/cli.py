"""mailctl: the commands of the mail container.

  mailctl run                the service (the container's main process)
  mailctl setup              set up the account: address, app password, allowed addresses (kingo mail)
  mailctl seed [--force]     put the case's sample mailbox into the Maildir and upload it (kingo mail seed)
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
    s = sub.add_parser("setup")
    s.add_argument("--address")
    s.add_argument("--password-stdin", action="store_true", help="read the app password from stdin")
    s.add_argument("--imap-host")
    s.add_argument("--smtp-host")
    s.add_argument("--allowed", help="comma-separated addresses the course mode may send to")
    s.add_argument("--yes", action="store_true", help="no questions; take the defaults")
    s = sub.add_parser("seed")
    s.add_argument("--force", action="store_true", help="seed again (uploads every mail a second time)")
    s = sub.add_parser("wake")
    s.add_argument("source", nargs="?", default="manual")
    sub.add_parser("status")
    args = p.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s",
                        datefmt="%Y-%m-%d %H:%M:%S", stream=sys.stdout)
    return {"run": cmd_run, "setup": cmd_setup, "seed": cmd_seed, "wake": cmd_wake, "status": cmd_status}[args.cmd](args)


def cmd_run(args):
    from .loop import Service
    Service().run()
    return 0


def _ask(prompt, default=""):
    answer = input(f"{prompt}{f' [{default}]' if default else ''}: ").strip()
    return answer or default


def cmd_setup(args):
    paths = settings.Paths()
    old = settings.load(paths)
    address = args.address or _ask("Mail address of your test account", old.address if old else "")
    if old and address.lower() != old.address.lower() and any(paths.maildir.glob("*/cur/*")):
        print(f"This container already holds the mailbox of {old.address}. Changing the account would upload\n"
              f"those mails into {address}. Forget the old account first: ./kingo mail reset\n"
              f"(with dev.sh: ./dev.sh reset)", file=sys.stderr)
        return 2
    if args.password_stdin:
        password = sys.stdin.readline().strip()
    else:
        password = getpass.getpass("App password (input stays hidden): ")
    d = account.defaults(address)
    imap_host = args.imap_host or (d["imap_host"] if args.yes or "gmail" in d["imap_host"] else _ask("IMAP server", d["imap_host"]))
    smtp_host = args.smtp_host or (d["smtp_host"] if args.yes or "gmail" in d["smtp_host"] else _ask("SMTP server", d["smtp_host"]))
    if args.allowed is not None:
        allowed = args.allowed.split(",")
    elif args.yes:
        allowed = old.allowed if old else []
    else:
        print("Course mode: replies go only to your own address and its plus addresses (name+anything@...).")
        allowed = _ask("Other addresses it may send to, e.g. your private one (comma-separated, or empty)",
                       ",".join(old.allowed) if old else "").split(",")
    print(f"Signing in to {imap_host} and {smtp_host} ... (nothing is sent)")
    try:
        cfg, password = account.configure(address, password, imap_host, smtp_host, allowed=allowed)
    except Exception as e:
        print(f"Sign-in failed: {e}", file=sys.stderr)
        return 1
    if old:
        cfg.name = old.name
    settings.save(paths, cfg, password)
    print(f"OK. Folders: sent = {cfg.folders['sent']}, drafts = {cfg.folders['drafts']}, "
          f"archive = {cfg.folders['archive']}{' (will be created)' if cfg.create_archive else ''}")
    print(f"Course mode sends to {cfg.address}, its plus addresses" + (f" and {', '.join(cfg.allowed)}." if cfg.allowed else "."))
    return 0


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
    rc = 0
    with conn:
        try:
            counts = case.seed(paths, cfg, force=args.force, conn=conn)
        except case.AlreadySeeded as e:   # the documents may still need loading, e.g. after `kingo update`
            print(f"Mailbox: {e}.")
        except RuntimeError as e:
            print(f"Mailbox not seeded: {e}", file=sys.stderr)
            rc = 1
        else:
            if not cfg.name:
                cfg.name = case.case_name()
                settings.save(paths, cfg)
            print("Mailbox: " + ", ".join(f"{n} mails in {f}" for f, n in counts.items()) + ". Uploading starts now.")
            try:
                db.wake(conn, action="sync", source="seed")
            except Exception as e:
                print(f"(The service will upload them on its next run: {e})")
        try:
            docs = case.load_documents(conn)
        except Exception as e:   # no file, no table (an old schema), a vector of the wrong length
            print(f"Documents not loaded: {str(e).strip()}", file=sys.stderr)
            rc = 1
        else:
            print(f"Documents: {docs['chunks']} chunks from {docs['documents']} documents, ready for search.")
    return rc


def cmd_wake(args):
    with db.connect() as conn:
        db.wake(conn, action="sync", source=args.source)
    return 0


def cmd_status(args):
    paths = settings.Paths()
    cfg = settings.load(paths)
    if not cfg:
        print("Not set up yet: ./kingo mail")
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
    return 0
