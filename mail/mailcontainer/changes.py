"""Changes n8n asks for on a mail already in the mailbox (table n8n_workshop_mail.changes).

The service makes the change here, in the Maildir, and mbsync carries it to the provider on its next
run, as with everything else. Nothing deletes a mail:

  read, unread, star, unstar   notmuch tags; notmuch writes them into the file names (S, F), and mbsync
                               pushes flags. With every provider.
  archive                      the mail's file in INBOX goes, and mbsync takes it out of the provider's
                               INBOX. On Gmail that only takes the label Inbox off; All Mail keeps the
                               mail. Hence Gmail only, and only for a mail that is in All Mail here too.
  inbox                        a copy goes into INBOX; Gmail keeps one mail per Message-ID and puts the
                               label Inbox back on (tested against Gmail, 30 Oct).
  label, unlabel               the same with the folder Assistant/<label>, which Gmail shows as a label.

A copy gets the flags of the file it comes from and a new name without mbsync's UID, so mbsync
uploads it as a new mail.
"""

import logging
import os
import time
import uuid
from dataclasses import dataclass, field

from .notmuch import folder_of
from .settings import INBOX, LABELS

log = logging.getLogger("changes")

TAGS = {"read": ["-unread"], "unread": ["+unread"], "star": ["+flagged"], "unstar": ["-flagged"]}


class Later(Exception):
    """The mail to archive is only in INBOX here: fetch All Mail first."""


@dataclass
class Result:
    channels: set = field(default_factory=set)   # what mbsync should run now
    fetch_first: bool = False


def process(conn, cfg, nm, paths, last_try=False):
    rows = conn.execute("""SELECT id, message_id, action, label FROM n8n_workshop_mail.changes
                            WHERE status = 'pending' ORDER BY id""").fetchall()
    res = Result()
    if not rows:
        return res
    nm.new()   # file names as they are now: mbsync may have renamed some since
    for r in rows:
        try:
            res.channels |= apply(r, cfg, nm, paths, last_try)
        except Later:
            res.fetch_first = True
            continue
        except Exception as e:
            log.warning("change %s (%s %s): %s", r["id"], r["action"], r["message_id"], e)
            conn.execute("""UPDATE n8n_workshop_mail.changes SET status = 'failed', error = %s, done_at = now()
                             WHERE id = %s""", (str(e)[:2000], r["id"]))
            continue
        conn.execute("UPDATE n8n_workshop_mail.changes SET status = 'done', done_at = now() WHERE id = %s", (r["id"],))
        log.info("change %s: %s%s %s", r["id"], r["action"], f" {r['label']}" if r["label"] else "", r["message_id"])
    return res


def apply(row, cfg, nm, paths, last_try=False):
    action, mid = row["action"], row["message_id"]
    files = nm.files(mid)
    if not files:
        raise ValueError("the mail is not in the mailbox (any more)")
    if action in TAGS:
        nm.tag(mid, *TAGS[action])
        return set(cfg.channels)   # the flags of every copy
    if not cfg.gmail:
        raise ValueError(f"{action} works only with Gmail, where a folder is a label")
    folder = INBOX if action in ("archive", "inbox") else f"{LABELS}/{row['label']}"
    here = [f for f in files if folder_of(f, paths.maildir) == folder]
    if action in ("archive", "unlabel"):
        if action == "archive" and here and not any(folder_of(f, paths.maildir) == cfg.archive_local for f in files):
            if not last_try:
                raise Later()
            raise ValueError("the mail is not in All Mail here, so it stays in the inbox")
        for f in here:
            os.remove(f)
        if here:
            nm.new()
    elif not here:   # inbox, label
        copy(files[0], paths.folder(folder))
        nm.new()
    return {"inbox"} if folder == INBOX else {"labels"}


def copy(src, folder):
    """A copy of a Maildir file in another folder, with its flags, as a new mail for mbsync."""
    name = os.path.basename(src)
    flags = "".join(c for c in (name.rsplit(":2,", 1)[1] if ":2," in name else "") if c in "DFPRS")
    for sub in ("cur", "new", "tmp"):
        (folder / sub).mkdir(parents=True, exist_ok=True)
    new = f"{int(time.time())}.{uuid.uuid4().hex}.kingo:2,{flags}"
    tmp = folder / "tmp" / new
    with open(src, "rb") as f_in, open(tmp, "wb") as f_out:
        f_out.write(f_in.read())
    os.replace(tmp, folder / "cur" / new)
