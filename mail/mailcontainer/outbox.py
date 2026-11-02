"""Outbox: approved rows become a draft in the mailbox or a sent mail.

Every status change is committed at once and only from the expected old status
(UPDATE ... WHERE status = ...); a trigger in Postgres allows only the documented steps.

  approved -> drafting -> drafted                     mode draft: the mail goes into Drafts
  approved -> sending  -> sent | sent_without_copy | failed
  approved -> expired                                 the approval is older than 24 hours

A row is never sent twice automatically. If it is unclear whether a mail went out (the connection
broke during or after DATA), the row stays at `sending` with a note in `error`, for a person to check.
"""

import logging
import smtplib
import ssl
from dataclasses import dataclass, field
from email.headerregistry import Address
from email.message import EmailMessage
from email.policy import SMTP
from email.utils import formatdate, getaddresses, make_msgid

from . import case
from .persona import CC_HEADER, SENT_HEADER, TO_HEADER
from .settings import DRAFTS, SENT, read_password

log = logging.getLogger("outbox")

SMTP_TIMEOUT = 30


@dataclass
class Result:
    drafted: int = 0
    sent: int = 0
    failed: int = 0
    expired: int = 0
    stuck: int = 0
    folders: set = field(default_factory=set)   # local folders that changed and need an upload

    @property
    def changed(self):
        return bool(self.drafted or self.sent or self.folders)


class BeforeData(Exception):
    """SMTP failed before the mail was handed over: nothing went out."""


class Unclear(Exception):
    """SMTP failed while or after handing the mail over: it may have gone out."""


def process(conn, cfg, nm, paths, smtp_send=None, stopping=lambda: False):
    """One pass over the approved rows. `stopping` is asked before each row: on SIGTERM the mail being
    sent is finished, the others wait at `approved` for the next start."""
    smtp_send = smtp_send or send_smtp
    res = Result()
    res.expired = conn.execute(
        """UPDATE n8n_workshop_mail.outbox SET status = 'expired'
            WHERE status = 'approved' AND approved_at < now() - interval '24 hours'""").rowcount
    if res.expired:
        log.info("outbox: %d approvals older than 24 hours set to expired", res.expired)

    for row in conn.execute(
            "SELECT * FROM n8n_workshop_mail.outbox WHERE status = 'approved' ORDER BY approved_at, id").fetchall():
        if stopping():
            log.info("outbox: stopping; the other approvals wait for the next start")
            return res
        try:
            if row["mode"] == "draft":
                _draft(conn, cfg, nm, row, res)
            else:
                _send(conn, cfg, nm, paths, row, res, smtp_send)
        except _Skip:
            continue
        except Exception:   # e.g. the trigger refused a step; the next row still gets its turn
            log.exception("outbox %s: stopped", row["id"])

    for row in conn.execute(
            "SELECT * FROM n8n_workshop_mail.outbox WHERE status = 'sent_without_copy' ORDER BY id").fetchall():
        _file_copy(conn, cfg, nm, row, res, retry=True)
    return res


class _Skip(Exception):
    pass


def _move(conn, row_id, old, new, **cols):
    """One status step, committed at once; returns False if the row had moved on meanwhile."""
    sets = ", ".join(["status = %s"] + [f"{c} = %s" for c in cols])
    cur = conn.execute(f"UPDATE n8n_workshop_mail.outbox SET {sets} WHERE id = %s AND status = %s",
                       (new, *cols.values(), row_id, old))
    return cur.rowcount == 1


def _note(conn, row_id, error):
    conn.execute("UPDATE n8n_workshop_mail.outbox SET error = %s WHERE id = %s", (error, row_id))


def check_entries(row):
    """Each entry of to_addrs and cc_addrs must be one address ('Name <a@x>' or 'a@x'), checked before anything
    rewrites it: 'Last, First <a@x>' unquoted or a stray ';' fails the row, as it did before course mode's rewrite."""
    for field in ("to_addrs", "cc_addrs"):
        for e in row[field] or []:
            parsed = getaddresses([e])
            if len(parsed) != 1 or "@" not in parsed[0][1] or not parsed[0][1].rpartition("@")[2]:
                raise ValueError(f"{field}: not one address: {e!r}")


def transport(cfg, row):
    """The recipients the provider gets: in course mode a case contact becomes a plus address of the own one, and
    the case's person the own address (persona.py); any other address stays (not_allowed decides). Else the row's
    own."""
    if not case.course_mode(cfg):
        return list(row["to_addrs"]), list(row["cc_addrs"] or [])
    p = case.persona(cfg)
    return p.transport(row["to_addrs"]), p.transport(row["cc_addrs"] or [])


def build(cfg, row, reply_headers):
    """The mail, the same for draft and send. From is always the signed-in address. In course mode To and Cc
    are the transport's, and the addresses as n8n wrote them go along in X-Kingo-To and X-Kingo-Cc, so the
    export shows them again when the mail comes back."""
    check_entries(row)
    msg = EmailMessage()
    msg["From"] = Address(display_name=cfg.name, addr_spec=cfg.address) if cfg.name else cfg.address
    to, cc = transport(cfg, row)
    msg["To"] = ", ".join(to)
    if cc:
        msg["Cc"] = ", ".join(cc)
    if (to, cc) != (list(row["to_addrs"]), list(row["cc_addrs"] or [])):
        msg[TO_HEADER] = ", ".join(row["to_addrs"])
        if row["cc_addrs"]:
            msg[CC_HEADER] = ", ".join(row["cc_addrs"])
    msg[SENT_HEADER] = f"outbox {row.get('id', '')}".strip()   # the export tags it own (persona.py)
    msg["Subject"] = row["subject"]
    msg["Date"] = formatdate(localtime=True)
    msg["Message-ID"] = make_msgid(domain=cfg.domain)
    if row["in_reply_to"]:
        rh = reply_headers or {}
        msg["In-Reply-To"] = rh.get("in_reply_to") or f"<{row['in_reply_to']}>"
        msg["References"] = rh.get("references") or f"<{row['in_reply_to']}>"
    body = row["body"]
    msg.set_content(body, cte="7bit" if body.isascii() else "quoted-printable")
    for name in ("To", "Cc"):   # parse now, so a broken address fails here and not halfway through SMTP
        if msg[name] is not None and msg[name].defects:
            raise ValueError(f"{name}: {msg[name].defects[0]}")
    raw = msg.as_bytes(policy=SMTP)
    raw.decode("ascii")   # 7-bit clean, so `raw` fits a text column and any SMTP server
    return msg["Message-ID"].strip("<>"), raw


def recipients(cfg, row):
    to, cc = transport(cfg, row)
    return [addr for _, addr in getaddresses(to + cc) if addr]


def not_allowed(cfg, addrs):
    """Course mode: only the own address, its plus addresses and the addresses `kingo mail` allowed."""
    own_local, own_domain = cfg.address.lower().rsplit("@", 1)
    allowed = {a.lower() for a in cfg.allowed} | {cfg.address.lower()}
    bad = []
    for a in addrs:
        local, _, domain = a.lower().rpartition("@")
        if a.lower() in allowed or (domain == own_domain and local.split("+", 1)[0] == own_local):
            continue
        bad.append(a)
    return bad


def _reply_headers_of(conn, row):
    if not row["in_reply_to"]:
        return None
    r = conn.execute("SELECT reply_headers FROM n8n_workshop_mail.messages WHERE message_id = %s",
                     (row["in_reply_to"],)).fetchone()
    return r["reply_headers"] if r else None


def _build_or_fail(conn, cfg, row, res, first_step):
    try:
        return build(cfg, row, _reply_headers_of(conn, row))
    except Exception as e:
        log.warning("outbox %s: cannot build the mail: %s", row["id"], e)
        with conn.transaction():
            if first_step == "sending" and _move(conn, row["id"], "approved", "sending"):
                _move(conn, row["id"], "sending", "failed", error=f"cannot build the mail: {e}")
                res.failed += 1
            else:
                _note(conn, row["id"], f"cannot build the mail: {e}")
        raise _Skip


def _draft(conn, cfg, nm, row, res):
    message_id, raw = _build_or_fail(conn, cfg, row, res, "drafting")
    if not _move(conn, row["id"], "approved", "drafting", message_id=message_id, raw=raw.decode("ascii")):
        return
    try:
        nm.insert(DRAFTS, raw, ["+draft", "-unread"])
    except Exception as e:
        log.error("outbox %s: draft not filed, left at drafting for a person: %s", row["id"], e)
        _note(conn, row["id"], f"draft not filed: {e}")
        res.stuck += 1
        return
    _move(conn, row["id"], "drafting", "drafted")
    res.drafted += 1
    res.folders.add(DRAFTS)
    log.info("outbox %s: draft filed", row["id"])


def _send(conn, cfg, nm, paths, row, res, smtp_send):
    message_id, raw = _build_or_fail(conn, cfg, row, res, "sending")
    rcpts = recipients(cfg, row)
    bad = not_allowed(cfg, rcpts) if case.course_mode(cfg) else []
    if bad or not rcpts:
        reason = ("course mode: not an allowed address: " + ", ".join(bad)) if bad else "no recipient"
        with conn.transaction():
            if _move(conn, row["id"], "approved", "sending", message_id=message_id, raw=raw.decode("ascii")):
                _move(conn, row["id"], "sending", "failed", error=reason)
                res.failed += 1
        log.info("outbox %s: not sent, %s", row["id"], reason)
        return

    if not _move(conn, row["id"], "approved", "sending", message_id=message_id, raw=raw.decode("ascii")):
        return
    try:
        refused = smtp_send(cfg, read_password(paths), cfg.address, rcpts, raw)
    except BeforeData as e:
        _move(conn, row["id"], "sending", "failed", error=str(e))
        res.failed += 1
        log.warning("outbox %s: not sent: %s", row["id"], e)
        return
    except Exception as e:  # Unclear, or anything unexpected after the mail may have left
        _note(conn, row["id"], f"unclear whether the mail went out, check Sent before sending again: {e}")
        res.stuck += 1
        log.error("outbox %s: left at sending for a person: %s", row["id"], e)
        return

    note = ("refused recipients: " + "; ".join(f"{a} ({c} {m})" for a, (c, m) in refused.items())) if refused else None
    if note:
        _note(conn, row["id"], note)
    res.sent += 1
    log.info("outbox %s: sent to %d recipient(s)", row["id"], len(rcpts) - len(refused))

    if row["in_reply_to"]:
        try:
            nm.tag(row["in_reply_to"], "+replied")
            res.folders.add("*")   # the original's folders get the Answered flag
        except Exception as e:
            log.warning("outbox %s: original not marked as replied: %s", row["id"], e)
    row = {**row, "error": note, "raw": raw.decode("ascii")}
    _file_copy(conn, cfg, nm, row, res, retry=False)


def _file_copy(conn, cfg, nm, row, res, retry):
    """The copy in Sent, if the provider does not file sent mail itself; then `sent`."""
    old = "sent_without_copy" if retry else "sending"
    if cfg.sent_copy:
        try:
            nm.insert(SENT, row["raw"].encode("ascii"), ["-unread"])
            res.folders.add(SENT)
        except Exception as e:
            if not retry:
                _move(conn, row["id"], "sending", "sent_without_copy",
                      error="; ".join(filter(None, [row.get("error"), f"copy not filed: {e}"])))
            log.warning("outbox %s: sent, but the copy is not filed: %s", row["id"], e)
            return
    _move(conn, row["id"], old, "sent")


def send_smtp(cfg, password, sender, rcpts, raw):
    """Send over SMTP with a checked certificate. Returns {refused address: (code, message)}."""
    ctx = ssl.create_default_context()
    try:
        if cfg.smtp_tls == "ssl":
            s = smtplib.SMTP_SSL(cfg.smtp_host, cfg.smtp_port, timeout=SMTP_TIMEOUT, context=ctx)
        else:
            s = smtplib.SMTP(cfg.smtp_host, cfg.smtp_port, timeout=SMTP_TIMEOUT)
            if cfg.smtp_tls == "starttls":
                s.starttls(context=ctx)
            elif cfg.smtp_tls != "insecure-test":
                raise BeforeData(f"unknown smtp_tls {cfg.smtp_tls!r}")
    except (OSError, smtplib.SMTPException) as e:
        raise BeforeData(f"no SMTP connection: {e}") from e

    try:
        try:
            s.ehlo_or_helo_if_needed()
            s.login(cfg.address, password)
            code, msg = s.mail(sender)
            if code != 250:
                raise BeforeData(f"sender refused: {code} {msg.decode(errors='replace')}")
            refused = {}
            for r in rcpts:
                code, msg = s.rcpt(r)
                if code not in (250, 251):
                    refused[r] = (code, msg.decode(errors="replace"))
            if len(refused) == len(rcpts):
                raise BeforeData("all recipients refused: " + "; ".join(f"{a} ({c} {m})" for a, (c, m) in refused.items()))
        except BeforeData:
            raise
        except (OSError, smtplib.SMTPException) as e:
            raise BeforeData(f"SMTP failed before the mail was handed over: {e}") from e

        try:
            code, msg = s.data(raw)
        except smtplib.SMTPDataError as e:   # DATA itself refused: nothing was handed over
            raise BeforeData(f"the server did not take the mail: {e.smtp_code} {e.smtp_error.decode(errors='replace')}") from e
        except (OSError, smtplib.SMTPException) as e:
            raise Unclear(f"connection lost while handing the mail over: {e}") from e
        if code != 250:   # the server answered no after the mail: it did not take it
            raise BeforeData(f"the server did not take the mail: {code} {msg.decode(errors='replace')}")
        return refused
    finally:
        try:
            s.quit()
        except Exception:
            s.close()
