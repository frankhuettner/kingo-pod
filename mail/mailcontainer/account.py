"""Setting up an account (`mailctl config`, behind `kingo mail`): check the login, find the folders, and see which
of the case's mails the account holds already.

Signs in once over IMAP and once over SMTP; sends nothing. Folder names come from the server's
SPECIAL-USE flags (\\Sent, \\Drafts, \\All, \\Archive), with common names as a fallback.
"""

import base64
import imaplib
import re
import smtplib
import ssl
from pathlib import Path

from .settings import Config

GMAIL = {"gmail.com", "googlemail.com"}

_LIST = re.compile(r'^\((?P<flags>[^)]*)\)\s+(?P<delim>"[^"]*"|NIL)\s+(?P<name>.+)$')
_MESSAGE_ID = re.compile(rb"^message-id:[ \t]*(.*(?:\r?\n[ \t].*)*)", re.I | re.M)
FETCH_BATCH = 2000   # mails per FETCH: Kaminski's mailbox in two rounds, a big real one without a huge answer


def defaults(address):
    domain = address.rsplit("@", 1)[1].lower()
    if domain in GMAIL:
        return {"imap_host": "imap.gmail.com", "smtp_host": "smtp.gmail.com", "sent_copy": False}
    return {"imap_host": f"imap.{domain}", "smtp_host": f"smtp.{domain}", "sent_copy": True}


def decode_utf7(name):
    """IMAP's modified UTF-7 (RFC 3501) to text, e.g. Naver's Korean folder names."""
    def dec(m):
        s = m.group(1)
        if s == "":
            return "&"
        b = s.replace(",", "/")
        b += "=" * (-len(b) % 4)
        return base64.b64decode(b).decode("utf-16-be")
    return re.sub(r"&([^-]*)-", dec, name)


def encode_utf7(name):
    """Text to IMAP's modified UTF-7, for a command that names a folder (the reverse of decode_utf7)."""
    out, wide = [], []

    def flush():
        if wide:
            b = base64.b64encode("".join(wide).encode("utf-16-be")).decode().rstrip("=").replace("/", ",")
            out.append(f"&{b}-")
            wide.clear()
    for ch in name:
        if " " <= ch <= "~":
            flush()
            out.append("&-" if ch == "&" else ch)
        else:
            wide.append(ch)
    flush()
    return "".join(out)


def quoted(folder):
    """A folder's name as an IMAP command takes it: modified UTF-7, in quotes."""
    return '"' + encode_utf7(folder).replace("\\", "\\\\").replace('"', '\\"') + '"'


def message_id(value):
    """A Message-ID as two of them are compared: without the angle brackets and the line breaks of a folded header,
    in small letters. None stays None."""
    if not value:
        return None
    if isinstance(value, bytes):
        value = value.decode("ascii", "replace")
    return re.sub(r"\s+", "", value).strip("<>").lower() or None


def parse_list(lines):
    """IMAP LIST lines -> [(name, {flags})]."""
    out = []
    for raw in lines:
        if raw is None:
            continue
        line = raw.decode("utf-8", "replace") if isinstance(raw, bytes) else raw
        m = _LIST.match(line.strip())
        if not m:
            continue
        name = m.group("name").strip()
        if name.startswith('"') and name.endswith('"'):
            name = name[1:-1].replace('\\"', '"').replace("\\\\", "\\")
        out.append((decode_utf7(name), {f.lower() for f in m.group("flags").split()}))
    return out


def pick_folders(listing):
    """{inbox, sent, drafts, archive} from the listing; archive_local and create_archive follow."""
    by_flag = {}
    names = {}
    for name, flags in listing:
        if "\\noselect" in flags or "\\nonexistent" in flags:
            continue
        names[name.lower()] = name
        for f in flags:
            by_flag.setdefault(f, name)

    def find(flag, *fallbacks):
        if flag in by_flag:
            return by_flag[flag]
        for n in fallbacks:
            if n.lower() in names:
                return names[n.lower()]
        return None

    folders = {"inbox": "INBOX",
               "sent": find("\\sent", "Sent", "Sent Items", "Sent Messages", "Sent Mail"),
               "drafts": find("\\drafts", "Drafts", "Draft")}
    everything = by_flag.get("\\all")
    archive = everything or find("\\archive", "Archive", "Archives")
    result = {"folders": {**folders, "archive": archive or "Archive"},
              "archive_local": "All Mail" if everything else "Archive",
              "create_archive": archive is None}
    return result


def check_imap(host, port, address, password):
    ctx = ssl.create_default_context()
    with imaplib.IMAP4_SSL(host, port, ssl_context=ctx, timeout=30) as m:
        m.login(address, password)
        typ, data = m.list()
        if typ != "OK":
            raise RuntimeError(f"IMAP LIST failed: {typ}")
        return parse_list(data)


def count_maildir(folder):
    """The mails in a Maildir folder, without the ones marked as deleted (flag T), which only mbsync's expunge
    removes."""
    n = 0
    for sub in ("cur", "new"):
        d = Path(folder) / sub
        if d.is_dir():
            n += sum(1 for f in d.iterdir() if not f.name.startswith(".") and "T" not in f.name.partition(":2,")[2])
    return n


def folder_counts(cfg, paths, password=None):
    """[(folder, mails here, mails at the provider)] for every synced folder, the labels left out: how far a sync
    is, in either direction (the course mailbox goes up; a real mailbox would come down). At the provider by IMAP
    STATUS, in tests from the Maildir that plays it; None where a folder cannot be read."""
    pairs = [(local, cfg.folders[key]) for key, local in cfg.local_folders.items() if cfg.folders.get(key)]
    if cfg.test_far_maildir:
        far = {f: count_maildir(Path(cfg.test_far_maildir) / f) for _, f in pairs}
    else:
        far = {}
        ctx = ssl.create_default_context()
        with imaplib.IMAP4_SSL(cfg.imap_host, cfg.imap_port, ssl_context=ctx, timeout=30) as m:
            m.login(cfg.address, password)
            for _, f in pairs:
                typ, data = m.status(quoted(f), "(MESSAGES)")
                hit = re.search(rb"MESSAGES (\d+)", data[0] or b"") if typ == "OK" and data else None
                far[f] = int(hit.group(1)) if hit else None
    return [(local, count_maildir(paths.folder(local)), far[f]) for local, f in pairs]


def seed_folders(cfg):
    """The provider's folders a seed fills: on Gmail All Mail, which holds Sent too; elsewhere the archive folder
    (unless it is still to be created) and Sent."""
    keys = ["archive"] if cfg.gmail else (["sent"] if cfg.create_archive else ["archive", "sent"])
    return [cfg.folders[k] for k in keys if cfg.folders.get(k)]


def provider_message_ids(cfg, password=None):
    """The Message-IDs of every mail in seed_folders(cfg), read in one pass (FETCH of that one header, FETCH_BATCH
    mails at a time, read-only): which of the case's mails the account holds already, so a second kingo-pod on the
    same test account uploads none of them twice (Frank, 7 Nov 2026: "es soll selbst erkennen"). In tests from the
    Maildir that plays the provider. Raises when a folder cannot be read: then nobody can tell what is there."""
    ids = set()
    if cfg.test_far_maildir:
        for f in seed_folders(cfg):
            for sub in ("cur", "new"):
                d = Path(cfg.test_far_maildir) / f / sub
                for p in sorted(d.iterdir()) if d.is_dir() else []:
                    if p.is_file() and not p.name.startswith("."):
                        hit = _MESSAGE_ID.search(p.read_bytes().replace(b"\r\n", b"\n").split(b"\n\n", 1)[0])
                        ids.add(message_id(hit.group(1)) if hit else None)
        ids.discard(None)
        return ids
    ctx = ssl.create_default_context()
    with imaplib.IMAP4_SSL(cfg.imap_host, cfg.imap_port, ssl_context=ctx, timeout=60) as m:
        m.login(cfg.address, password)
        for f in seed_folders(cfg):
            typ, data = m.select(quoted(f), readonly=True)
            if typ != "OK":
                raise RuntimeError(f"cannot open the folder {f}: {data}")
            n = int(data[0])
            for start in range(1, n + 1, FETCH_BATCH):
                typ, data = m.fetch(f"{start}:{min(start + FETCH_BATCH - 1, n)}", "(BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)])")
                if typ != "OK":
                    raise RuntimeError(f"cannot read the folder {f}: {data}")
                for part in data:
                    if isinstance(part, tuple):
                        hit = _MESSAGE_ID.search(part[1])
                        if hit:
                            ids.add(message_id(hit.group(1)))
    ids.discard(None)
    return ids


def check_smtp(host, port, tls, address, password):
    ctx = ssl.create_default_context()
    if tls == "ssl":
        s = smtplib.SMTP_SSL(host, port, timeout=30, context=ctx)
    else:
        s = smtplib.SMTP(host, port, timeout=30)
        s.starttls(context=ctx)
    try:
        s.login(address, password)
    finally:
        try:
            s.quit()
        except Exception:
            s.close()


def configure(address, password, imap_host=None, smtp_host=None, imap_port=993, smtp_port=465,
              allowed=(), listing=None, check=True):
    """Check the account and return its Config (not yet saved)."""
    address = address.strip()
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", address):
        raise ValueError(f"not a mail address: {address!r}")
    d = defaults(address)
    if address.rsplit("@", 1)[1].lower() in GMAIL:
        password = password.replace(" ", "")   # Google shows app passwords in groups of four
    imap_host = imap_host or d["imap_host"]
    smtp_host = smtp_host or d["smtp_host"]
    smtp_tls = "ssl" if smtp_port == 465 else "starttls"
    if check:
        listing = check_imap(imap_host, imap_port, address, password)
        check_smtp(smtp_host, smtp_port, smtp_tls, address, password)
    picked = pick_folders(listing or [])
    cfg = Config(address=address, imap_host=imap_host, smtp_host=smtp_host, imap_port=imap_port,
                 smtp_port=smtp_port, smtp_tls=smtp_tls, sent_copy=d["sent_copy"],
                 allowed=sorted({a.strip().lower() for a in allowed if a.strip()}), **picked)
    return cfg, password
