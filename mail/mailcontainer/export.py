"""Export: what changed in notmuch since the last run goes into n8n_workshop_mail.messages.

notmuch counts a revision up with every added or changed mail. sync_state keeps the database's uuid
and the last exported revision; a new uuid (the database was rebuilt) means: export everything again.
A mail that notmuch no longer knows gets deleted_at; if it comes back, deleted_at is cleared. Removing
a mail does not count the revision up, so the number of mails is compared as well.

New rows are announced by a trigger on messages (NOTIFY n8n_workshop_mail_new), not here.
"""

import logging

from psycopg.types.json import Jsonb

from .notmuch import to_row

log = logging.getLogger("export")

UPSERT = """
INSERT INTO n8n_workshop_mail.messages AS m
  (message_id, thread_id, folders, from_addr, from_name, to_addrs, cc_addrs, subject, sent_at,
   body_text, body_html, tags, attachments, in_reply_to, reply_headers)
SELECT r.message_id, r.thread_id, r.folders, r.from_addr, r.from_name, r.to_addrs, r.cc_addrs, r.subject,
       r.sent_at, r.body_text, r.body_html, r.tags, coalesce(r.attachments, '[]'), r.in_reply_to, r.reply_headers
  FROM jsonb_to_recordset(%s) AS r(
       message_id text, thread_id text, folders text[], from_addr text, from_name text, to_addrs text[],
       cc_addrs text[], subject text, sent_at timestamptz, body_text text, body_html text, tags text[],
       attachments jsonb, in_reply_to text, reply_headers jsonb)
ON CONFLICT (message_id) DO UPDATE SET
  thread_id = EXCLUDED.thread_id, folders = EXCLUDED.folders, from_addr = EXCLUDED.from_addr,
  from_name = EXCLUDED.from_name, to_addrs = EXCLUDED.to_addrs, cc_addrs = EXCLUDED.cc_addrs,
  subject = EXCLUDED.subject, sent_at = EXCLUDED.sent_at, body_text = EXCLUDED.body_text,
  body_html = EXCLUDED.body_html, tags = EXCLUDED.tags, attachments = EXCLUDED.attachments,
  in_reply_to = EXCLUDED.in_reply_to, reply_headers = coalesce(EXCLUDED.reply_headers, m.reply_headers),
  deleted_at = NULL
WHERE (m.thread_id, m.folders, m.from_addr, m.from_name, m.to_addrs, m.cc_addrs, m.subject, m.sent_at,
       m.body_text, m.body_html, m.tags, m.attachments, m.in_reply_to, m.deleted_at)
      IS DISTINCT FROM
      (EXCLUDED.thread_id, EXCLUDED.folders, EXCLUDED.from_addr, EXCLUDED.from_name, EXCLUDED.to_addrs,
       EXCLUDED.cc_addrs, EXCLUDED.subject, EXCLUDED.sent_at, EXCLUDED.body_text, EXCLUDED.body_html,
       EXCLUDED.tags, EXCLUDED.attachments, EXCLUDED.in_reply_to, NULL::timestamptz)
   OR (m.reply_headers IS NULL AND EXCLUDED.reply_headers IS NOT NULL)
"""


def export(conn, nm, paths, full=False, persona=None):
    """Export changes; returns (rows written, rows marked deleted). With a persona, rows show the case's side of
    the addresses (persona.py)."""
    count, uuid, rev = nm.revision()
    state = conn.execute("SELECT notmuch_uuid, last_revision FROM n8n_workshop_mail.sync_state").fetchone()
    live = conn.execute("SELECT count(*) AS n FROM n8n_workshop_mail.messages WHERE deleted_at IS NULL").fetchone()["n"]
    if full or state["notmuch_uuid"] != uuid or state["last_revision"] is None or state["last_revision"] > rev:
        query, full = "*", True
    elif rev == state["last_revision"]:
        if live == count:
            return 0, 0
        query = None   # only removals
    else:
        query = f"lastmod:{state['last_revision'] + 1}..{rev}"

    msgs = nm.messages(query) if query else []
    threads = nm.threads(query) if msgs else {}
    rows = [to_row(m, paths.maildir, threads, persona) for m in msgs]
    for row in rows:
        if row["thread_id"] is None:
            row["thread_id"] = nm.thread_of(row["message_id"])

    # reply_headers only for rows that have none yet: one notmuch call per mail.
    ids = [r["message_id"] for r in rows]
    have = {r["message_id"] for r in conn.execute(
        "SELECT message_id FROM n8n_workshop_mail.messages WHERE message_id = ANY(%s) AND reply_headers IS NOT NULL",
        (ids,))} if ids else set()
    for row in rows:
        row["reply_headers"] = None if row["message_id"] in have else _reply_headers(nm, row["message_id"], persona)

    written = deleted = 0
    with conn.transaction():
        if rows:   # one statement, so the trigger sends one NOTIFY with the number of new rows
            written = conn.execute(UPSERT, (Jsonb(rows),)).rowcount
        if full or rev != state["last_revision"] or live != count:
            known = list(nm.all_ids())
            cur = conn.execute(
                """UPDATE n8n_workshop_mail.messages SET deleted_at = now()
                    WHERE deleted_at IS NULL AND NOT (message_id = ANY(%s))""", (known,))
            deleted = cur.rowcount
        conn.execute(
            """UPDATE n8n_workshop_mail.sync_state SET notmuch_uuid = %s, last_revision = %s""", (uuid, rev))
    if written or deleted:
        log.info("export: %d rows written, %d marked deleted%s", written, deleted, " (full)" if full else "")
    return written, deleted


def _reply_headers(nm, message_id, persona=None):
    try:
        rh = nm.reply_headers(message_id)
        if persona is not None:
            rh["to"], rh["cc"] = persona.case_entries(rh["to"]), persona.case_entries(rh["cc"])
            if rh.get("subject"):
                rh["subject"] = persona.case_text(rh["subject"])
        return rh
    except Exception as e:  # a mail notmuch cannot build a reply for still gets its row
        log.warning("no reply headers for %s: %s", message_id, e)
        return None
