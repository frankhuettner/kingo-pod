"""Setting up an account (`mailctl setup`, behind `kingo mail`): check the login, find the folders.

Signs in once over IMAP and once over SMTP; sends nothing. Folder names come from the server's
SPECIAL-USE flags (\\Sent, \\Drafts, \\All, \\Archive), with common names as a fallback.
"""

import base64
import imaplib
import re
import smtplib
import ssl

from .settings import Config

GMAIL = {"gmail.com", "googlemail.com"}

_LIST = re.compile(r'^\((?P<flags>[^)]*)\)\s+(?P<delim>"[^"]*"|NIL)\s+(?P<name>.+)$')


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
