"""notmuch on the command line, and the step from its JSON to rows of n8n_workshop_mail.messages.

notmuch allows one writer at a time; only the service's loop writes (new, insert, tag).
Message-IDs come from outside, also those of strangers' mails, so they go to notmuch only quoted.
"""

import json
import os
import re
import subprocess
from datetime import datetime, timezone
from email.headerregistry import Address
from email.utils import getaddresses, parseaddr

from .persona import CC_HEADER, SENT_HEADER, TO_HEADER
from .settings import tool

EXPORTED_TAGS = {"unread", "replied", "flagged", "draft"}


class NotmuchError(RuntimeError):
    pass


def quote_id(message_id):
    return 'id:"' + message_id.replace('"', '""') + '"'


class Notmuch:
    def __init__(self, paths):
        self.paths = paths
        self.env = {**os.environ, "NOTMUCH_CONFIG": str(paths.notmuch_config)}

    def run(self, *args, input=None, timeout=120):
        proc = subprocess.run([tool("notmuch"), *args], input=input, capture_output=True,
                              env=self.env, timeout=timeout)
        if proc.returncode != 0:
            err = proc.stderr.decode("utf-8", "replace").strip()
            raise NotmuchError(f"notmuch {args[0]}: {err or 'exit code ' + str(proc.returncode)}")
        return proc.stdout.decode("utf-8", "replace")

    def json(self, *args):
        return json.loads(self.run(*args) or "null")

    # -- writing ---------------------------------------------------------------------------------

    def new(self):
        self.paths.maildir.mkdir(parents=True, exist_ok=True)
        return self.run("new", "--quiet")

    def insert(self, folder, raw: bytes, tags=()):
        """Put a finished mail into a local folder; mbsync uploads it on its next run."""
        if not (self.paths.maildir / ".notmuch").exists():
            self.new()
        self.run("insert", f"--folder={folder}", "--create-folder", "--keep", *tags, input=raw)

    def tag(self, message_id, *tags):
        query = quote_id(message_id)
        if self.count(query) == 0:
            raise NotmuchError(f"no mail with Message-ID {message_id}")
        self.run("tag", *tags, "--", query)

    # -- reading ---------------------------------------------------------------------------------

    def count(self, query):
        return int(self.run("count", "--exclude=false", "--", query).strip() or 0)

    def revision(self):
        """(number of mails, uuid, revision). The revision grows with every added or changed mail,
        not when a mail is removed; the number shows that."""
        count, uuid, rev = self.run("count", "--lastmod", "--exclude=false", "*").split()
        return int(count), uuid, int(rev)

    def files(self, message_id):
        """Every file of the mail: one per folder it is in, more if a folder holds copies."""
        return self.json("search", "--format=json", "--output=files", "--exclude=false", "--", quote_id(message_id)) or []

    def all_ids(self):
        return set(self.json("search", "--format=json", "--output=messages", "--exclude=false", "*") or [])

    def messages(self, query):
        """The matching messages, flat, with body and HTML parts."""
        tree = self.json("show", "--format=json", "--include-html", "--entire-thread=false",
                         "--exclude=false", "--decrypt=false", "--", query)
        out = []
        _flatten(tree, out)
        return out

    def threads(self, query):
        """{message_id: thread_id} for the matching messages, in one call."""
        result = {}
        for t in self.json("search", "--format=json", "--output=summary", "--exclude=false", "--", query) or []:
            for mid in parse_id_query((t.get("query") or [None])[0] or ""):
                result[mid] = t["thread"]
        return result

    def thread_of(self, message_id):
        ids = self.json("search", "--format=json", "--output=threads", "--exclude=false", "--", quote_id(message_id))
        return ids[0] if ids else None

    def reply_headers(self, message_id):
        """Headers for a reply to all, as notmuch builds them: Reply-To honoured, own address left out."""
        data = self.json("reply", "--format=json", "--reply-to=all", "--decrypt=false", "--", quote_id(message_id))
        h = data.get("reply-headers", {})
        return {
            "to": address_list(h.get("To")),
            "cc": address_list(h.get("Cc")),
            "subject": h.get("Subject") or "",
            "in_reply_to": h.get("In-reply-to") or "",
            "references": h.get("References") or "",
        }


_ID_TERM = re.compile(r'id:(?:"((?:[^"]|"")*)"|(\S+))')


def parse_id_query(q):
    return [m.group(1).replace('""', '"') if m.group(1) is not None else m.group(2) for m in _ID_TERM.finditer(q)]


def _flatten(node, out):
    if isinstance(node, dict):
        if "id" in node and "headers" in node and node.get("match", True):
            out.append(node)
    elif isinstance(node, list):
        for x in node:
            _flatten(x, out)


# -- from notmuch JSON to a row ------------------------------------------------------------------


def address_list(value):
    """'A <a@x>, "B, C" <b@y>' -> ['A <a@x>', '"B, C" <b@y>'], display names kept, ready for outbox."""
    out = []
    for name, addr in getaddresses([value or ""]):
        if not addr:
            continue
        try:
            out.append(str(Address(display_name=name, addr_spec=addr)) if name else addr)
        except Exception:
            out.append(f"{name} <{addr}>" if name else addr)
    return out


def bare_addresses(value):
    return [addr.lower() for _, addr in getaddresses([value or ""]) if addr]


def first_id(value):
    m = re.search(r"<([^<>]+)>", value or "")
    return m.group(1) if m else (value or "").strip().strip("<>") or None


def folder_of(filename, maildir):
    """.../Maildir/Sent/cur/123:2,S -> 'Sent'; nested folders keep their path."""
    rel = os.path.relpath(filename, maildir)
    parts = rel.split(os.sep)
    return "/".join(parts[:-2]) if len(parts) >= 3 else (parts[0] if parts else "")


def walk_body(parts, text, html, attachments):
    for p in parts or []:
        ctype = (p.get("content-type") or "").lower()
        content = p.get("content")
        name = p.get("filename")
        disposition = (p.get("content-disposition") or "").lower()
        if ctype.startswith("multipart/"):
            walk_body(content if isinstance(content, list) else [], text, html, attachments)
        elif ctype == "text/plain" and isinstance(content, str) and not name and disposition != "attachment":
            text.append(content)
        elif ctype == "text/html" and isinstance(content, str) and not name and disposition != "attachment":
            html.append(content)
        else:
            size = p.get("content-length")   # notmuch gives the encoded length
            if size is None and isinstance(content, str):
                size = len(content.encode("utf-8"))
            elif size and (p.get("content-transfer-encoding") or "").lower() == "base64":
                size = size * 3 // 4
            attachments.append({"name": name or "", "type": ctype, "size": size})


def to_row(msg, maildir, threads, persona=None):
    """One mail as a row. With a persona (persona.py): the own address as the case's person, and for a mail this
    service sent, the case addresses from X-Kingo-To and X-Kingo-Cc; a mail from the own address gets the tag own."""
    h = msg.get("headers", {})
    name, addr = parseaddr(h.get("From", ""))
    text, html, attachments = [], [], []
    walk_body(msg.get("body"), text, html, attachments)
    tags = set(msg.get("tags", [])) & EXPORTED_TAGS
    to, cc = h.get("To"), h.get("Cc")
    own = persona is not None and addr.lower() == persona.own and bool(h.get(SENT_HEADER))
    if own:   # sent by this service; a mail the person wrote from the own account is an ordinary mail
        tags.add("own")
        if h.get(TO_HEADER) or h.get(CC_HEADER):
            to, cc = h.get(TO_HEADER), h.get(CC_HEADER)
    case_addr = persona.case_addr if persona else (lambda a: a)
    case_text = persona.case_text if persona else (lambda t: t)
    if h.get("X-Kingo-Test"):
        tags.add("test")
    if h.get("X-Kingo-Confidential"):   # the case marks mails the reply agent must not see (resumes, evaluations)
        tags.add("confidential")
    ts = msg.get("timestamp")
    return {
        "message_id": msg["id"],
        "thread_id": threads.get(msg["id"]),
        "folders": sorted({folder_of(f, maildir) for f in msg.get("filename", [])}),
        "from_addr": case_addr(addr.lower()) or None,
        "from_name": name or None,
        "to_addrs": [case_addr(a) for a in bare_addresses(to)],
        "cc_addrs": [case_addr(a) for a in bare_addresses(cc)],
        "subject": case_text(h.get("Subject")),
        "sent_at": datetime.fromtimestamp(ts, timezone.utc).isoformat() if ts else None,
        "body_text": case_text("\n".join(text)) if text else None,
        "body_html": case_text("\n".join(html)) if html else None,
        "tags": sorted(tags),
        "attachments": attachments,
        "in_reply_to": first_id(h.get("In-Reply-To")),
    }
