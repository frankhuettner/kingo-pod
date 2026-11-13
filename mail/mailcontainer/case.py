"""The course case: the sample mailbox and documents (`mailctl seed`), test mails on request (deliver_test(n)).

Mailbox and test mails only go into the local Maildir; the service's loop indexes them and mbsync
uploads them. The documents go straight into n8n_workshop_mail.chunks, with their vectors.
Placeholders in the case files: {{ME}} is the own address, {{ME_LOCAL}} and {{ME_DOMAIN}} its parts.
case.json names the case's person: {"name": "...", "address": "name@enron.example"}; with an address, course mode
shows the own address as the person's to n8n and Langflow, and sends a mail to one of the case's contacts into the
own inbox (persona.py).
"""

import base64
import functools
import json
import os
import re
import secrets
import socket
import struct
import time
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

from psycopg.types.json import Jsonb

from .account import message_id
from .persona import EXAMPLE_ADDRESS, Persona
from .settings import INBOX, SENT, case_dir

CASE_NAME = "BioFuture Investor Relations"   # the name to send under, unless the case's case.json gives one
CASE_FILE = "case.json"
DOCUMENTS = "documents.jsonl"
DOC_FIELDS = ("doc", "chunk", "chunks", "title", "date", "visibility")


class AlreadySeeded(RuntimeError):
    pass


def case_name():
    """The name the account sends under, from the case: case.json ({"name": "Vince J Kaminski"}), else CASE_NAME."""
    f = case_dir() / CASE_FILE
    if f.is_file():
        name = json.loads(f.read_text(encoding="utf-8")).get("name")
        if name:
            return name
    return CASE_NAME


def case_owner():
    """Whose mails the case holds, for a sentence: "Kaminski's" from case.json's name, else "the case's"."""
    f = case_dir() / CASE_FILE
    name = json.loads(f.read_text(encoding="utf-8")).get("name") if f.is_file() else None
    return f"{name.split()[-1]}'s" if name else "the case's"


def case_address():
    """The case's person as n8n and Langflow see the own address: case.json "address", else None."""
    f = case_dir() / CASE_FILE
    if f.is_file():
        return json.loads(f.read_text(encoding="utf-8")).get("address") or None
    return None


def course_mode(cfg):
    """Course mode is on if the config says so, and always with a case address: then the database holds the case's
    real addresses (persona.py), and only course mode keeps a mail from reaching them."""
    return cfg.course_mode or case_address() is not None


def persona(cfg):
    """Both sides of the own address for this account: the case's person and contacts only in course mode."""
    if not course_mode(cfg):
        return Persona(cfg.address, None, cfg.allowed)
    return Persona(cfg.address, case_address(), cfg.allowed, case_contacts(str(case_dir())))


@functools.lru_cache(maxsize=4)
def case_contacts(folder):
    """Every address in the case's mailbox and test mails (they all end in .example): the case's contacts, whom
    course mode never lets a mail reach. Read once per case folder."""
    found = set()
    for sub in ("maildir", "tests"):
        root = Path(folder) / sub
        if root.is_dir():
            for f in root.rglob("*"):
                if f.is_file() and not f.name.startswith("."):
                    found.update(m.group(0).lower() for m in EXAMPLE_ADDRESS.finditer(f.read_text("utf-8", "replace")))
    return frozenset(found)


def fill(raw: bytes, address):
    local, domain = address.split("@", 1)
    return (raw.replace(b"{{ME_LOCAL}}", local.encode())
               .replace(b"{{ME_DOMAIN}}", domain.encode())
               .replace(b"{{ME}}", address.encode()))


def _split(raw: bytes):
    raw = raw.replace(b"\r\n", b"\n")
    i = raw.find(b"\n\n")
    return (raw, b"") if i < 0 else (raw[:i + 1], raw[i + 1:])


def header(raw: bytes, name):
    head, _ = _split(raw)
    m = re.search(rb"^" + re.escape(name.encode()) + rb":[ \t]*(.*(?:\n[ \t].*)*)", head, re.I | re.M)
    return m.group(1).decode("utf-8", "replace").strip() if m else None


def _seed_name(name):
    """A case mail's file name without what mbsync adds (",U=<uid>") and the flags (":2,S")."""
    return name.split(",U=", 1)[0].split(":2,", 1)[0]


def _deliver(folder: Path, name, raw: bytes, mtime=None, sub="cur"):
    """Maildir delivery: write to tmp, then rename, so no reader sees half a file."""
    for d in ("tmp", "new", "cur"):
        (folder / d).mkdir(parents=True, exist_ok=True)
    tmp = folder / "tmp" / name
    tmp.write_bytes(raw)
    if mtime:
        os.utime(tmp, (mtime, mtime))   # mbsync passes it on as the arrival date (CopyArrivalDate)
    final = folder / sub / name
    os.rename(tmp, final)
    return final


def load_documents(conn):
    """Make the case documents in n8n_workshop_mail.chunks a copy of documents.jsonl.

    The same for every account, so this runs on every `kingo mail seed`, also once the mailbox is
    seeded: a corrected document arrives with `kingo update`. The vectors were made in advance
    (case/embed_documents.py) with the model the course uses. The container's role may write
    only rows with a `doc`, so the mails' chunks stay as n8n wrote them.
    """
    src = case_dir() / DOCUMENTS
    if not src.is_file():
        raise RuntimeError(f"no case documents at {src}")
    rows = [json.loads(line) for line in src.read_text(encoding="utf-8").splitlines() if line.strip()]
    with conn.transaction():
        conn.execute("DELETE FROM n8n_workshop_mail.chunks WHERE metadata ? 'doc'")
        with conn.cursor() as cur:
            cur.executemany(
                "INSERT INTO n8n_workshop_mail.chunks (text, metadata, embedding) VALUES (%s, %s, %s::vector)",
                [(r["text"], Jsonb({k: r.get(k) for k in DOC_FIELDS}), vector_text(r["embedding"])) for r in rows])
    return {"documents": len({r["doc"] for r in rows}), "chunks": len(rows)}


def vector_text(b64):
    """float32, little-endian, base64 (as embed_documents.py writes them) -> pgvector's '[...]'."""
    raw = base64.b64decode(b64)
    return "[" + ",".join(f"{x:.9g}" for x in struct.unpack(f"<{len(raw) // 4}f", raw)) + "]"


def check_not_seeded(paths, cfg, conn=None):
    """Raise AlreadySeeded if this account got the case mailbox before: the volume notes it, and with `conn` so does
    the table n8n_workshop_mail.seeded, which outlives `kingo mail reset`."""
    if paths.seeded.exists():
        raise AlreadySeeded(f"already seeded ({paths.seeded.read_text().strip()}); nothing is copied twice")
    if conn is not None:
        row = conn.execute("SELECT seeded_at FROM n8n_workshop_mail.seeded WHERE address = %s",
                           (cfg.address.lower(),)).fetchone()
        if row:
            raise AlreadySeeded(f"already seeded: {cfg.address} got the case mailbox on {row['seeded_at']:%Y-%m-%d} "
                               f"(a reset does not change that); nothing is copied twice")


def case_message_ids():
    """The Message-IDs of the case's old mails (Archive and Sent), as account.message_id writes them; None for a mail
    without one, which nothing can find at the provider. Every mail of the Enron case has its own
    (<v-...@kaminski.enron.example>), and fill() leaves it alone."""
    src = case_dir() / "maildir"
    out = []
    for case_folder in ("Archive", "Sent"):
        d = src / case_folder / "cur"
        for f in sorted(d.iterdir()) if d.is_dir() else []:
            if not f.name.startswith("."):
                out.append(message_id(header(f.read_bytes(), "Message-ID")))
    return out


def seed(paths, cfg, force=False, conn=None, present=None):
    """Put the case's old mails into the local folders: Archive -> the archive folder, Sent -> Sent.

    Only once per account: after `kingo mail reset` the Maildir has lost mbsync's state, and a seed would upload
    every mail a second time. The volume notes it, and with `conn` so does the table n8n_workshop_mail.seeded,
    which outlives the reset. A mail already in its folder is skipped (by its file name, before the ",U=" that
    mbsync adds), so a seed that stopped half way can simply run again (Frank, 3 Nov 2026: "kann man das
    idempotent machen?"). So is a mail whose Message-ID is in `present`, the Message-IDs the provider holds
    (account.provider_message_ids): a second kingo-pod on the same test account, a new laptop, gets them from the
    provider instead (Frank, 7 Nov 2026). With all of them there, nothing is copied and the account is noted as
    seeded all the same.
    """
    if not force:
        check_not_seeded(paths, cfg, conn)
    address = cfg.address.lower()
    src = case_dir() / "maildir"
    if not src.is_dir():
        raise RuntimeError(f"no case mailbox at {src}")
    counts = {}
    for case_folder, local in (("Archive", cfg.archive_local), ("Sent", SENT)):
        n = 0
        here = {_seed_name(p.name) for sub in ("cur", "new") if (paths.folder(local) / sub).is_dir()
                for p in (paths.folder(local) / sub).iterdir()}
        for f in sorted((src / case_folder / "cur").iterdir()):
            if f.name.startswith("."):
                continue
            n += 1
            if _seed_name(f.name) in here:
                continue
            raw = f.read_bytes()
            if present is not None and message_id(header(raw, "Message-ID")) in present:
                continue
            raw = fill(raw, cfg.address)
            date = header(raw, "Date")
            mtime = parsedate_to_datetime(date).timestamp() if date else None
            _deliver(paths.folder(local), f.name, raw, mtime)
        counts[local] = n
    paths.seeded.write_text(json.dumps({"at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                                        "folders": counts}) + "\n")
    if conn is not None:
        conn.execute("""INSERT INTO n8n_workshop_mail.seeded (address, folders) VALUES (%s, %s)
                        ON CONFLICT (address) DO UPDATE SET seeded_at = now(), folders = EXCLUDED.folders""",
                     (address, Jsonb(counts)))
    return counts


def make_test_mail(n, address):
    """Test mail n, ready for the inbox: a fresh Message-ID, so it can be delivered again, and the
    header X-Kingo-Test, from which the export sets the tag `test`. The Date stays the case's date:
    the quiet period counts the date of the mail."""
    src = case_dir() / "tests" / f"{n:02d}.eml"
    if not src.is_file():
        raise FileNotFoundError(f"there is no test mail {n} ({src.name})")
    raw = fill(src.read_bytes(), address)
    head, body = _split(raw)
    old = header(raw, "Message-ID") or f"<bf-ir-test-{n:02d}@case.biofuture.example.com>"
    local, _, domain = old.strip("<>").partition("@")
    new = f"<{local}.{int(time.time())}{secrets.token_hex(2)}@{domain or 'case.biofuture.example.com'}>"
    head = re.sub(rb"^Message-ID:.*(?:\n[ \t].*)*\n", b"", head, flags=re.I | re.M)
    head += f"Message-ID: {new}\nX-Kingo-Test: {n:02d}\n".encode()
    return new.strip("<>"), head + body


def deliver_test(paths, cfg, n):
    message_id, raw = make_test_mail(n, cfg.address)
    name = f"{int(time.time())}.{os.getpid()}_{secrets.token_hex(3)}.{socket.gethostname()}"
    _deliver(paths.folder(INBOX), name, raw, sub="new")
    return message_id
