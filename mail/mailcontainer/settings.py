"""Paths and settings, and the config files generated from them.

Everything lives in one volume (MAIL_DATA, default /data), never in git:

  config.json        account, servers, folders, course mode; written by `mailctl setup`
  password           the app password, mode 600; mbsync and goimapnotify read it through `cat`
  mbsyncrc, notmuch-config, goimapnotify.yaml
                     generated from config.json; edits there are overwritten
  Maildir/           the mails, the notmuch database (Maildir/.notmuch) and mbsync's sync state
                     (.mbsyncstate in each folder)

Restore the volume whole or not at all: a Maildir without its sync state uploads every mail to the
provider a second time, because mbsync does not recognise mails by Message-ID.
"""

import json
import os
from dataclasses import asdict, dataclass, field
from pathlib import Path

# Local folder names. The archive folder is named after what it holds: Gmail's All Mail has every
# mail (also those in the inbox), elsewhere Archive has only archived ones.
INBOX, SENT, DRAFTS = "INBOX", "Sent", "Drafts"
# On Gmail the folders under this one are the labels n8n may set (changes.py): Assistant/<label>.
LABELS = "Assistant"


def tool(name):
    """Path of an external program; MAIL_<NAME> overrides it (tests use their own builds)."""
    return os.environ.get(f"MAIL_{name.upper()}", name)


class Paths:
    def __init__(self, root=None):
        self.root = Path(root or os.environ.get("MAIL_DATA", "/data"))
        self.config = self.root / "config.json"
        self.password = self.root / "password"
        self.mbsyncrc = self.root / "mbsyncrc"
        self.notmuch_config = self.root / "notmuch-config"
        self.goimapnotify = self.root / "goimapnotify.yaml"
        self.maildir = self.root / "Maildir"
        self.seeded = self.root / "seeded.json"

    def folder(self, local_name):
        return self.maildir / local_name


def case_dir():
    return Path(os.environ.get("MAIL_CASE", "/opt/case"))


@dataclass
class Config:
    address: str
    imap_host: str
    smtp_host: str
    imap_port: int = 993
    smtp_port: int = 465
    smtp_tls: str = "ssl"            # ssl (port 465) or starttls (port 587); "insecure-test" only in tests
    name: str = ""                   # display name in From; `mailctl seed` sets the case's name
    folders: dict = field(default_factory=dict)   # remote names: inbox, sent, drafts, archive
    archive_local: str = "Archive"   # "All Mail" for Gmail
    create_archive: bool = False     # the provider has no archive folder: create it there (seed needs one)
    sent_copy: bool = True           # False when the provider files sent mail itself (Gmail)
    course_mode: bool = True         # send only to the own address, its plus addresses and `allowed`
    allowed: list = field(default_factory=list)
    watcher: bool = True             # goimapnotify on the inbox
    interval: int = 600              # seconds between full syncs with a running watcher
    interval_without_watcher: int = 120
    test_far_maildir: str = ""       # tests only: a local Maildir plays the provider

    @property
    def local_folders(self):
        return {"inbox": INBOX, "sent": SENT, "drafts": DRAFTS, "archive": self.archive_local}

    @property
    def gmail(self):
        """All Mail holds every mail and a folder is a label: taking a mail out of INBOX or a label folder
        only takes the label away, the mail stays."""
        return self.archive_local == "All Mail"

    @property
    def channels(self):
        """mbsync's channels: the folders the provider has, and on Gmail the labels under Assistant/."""
        return [k for k in self.local_folders if self.folders.get(k)] + (["labels"] if self.gmail else [])

    @property
    def domain(self):
        return self.address.rsplit("@", 1)[1]


def load(paths):
    if not paths.config.exists():
        return None
    data = json.loads(paths.config.read_text(encoding="utf-8"))
    data.pop("version", None)
    return Config(**data)


def save(paths, cfg, password=None):
    """Write config.json (and the password, if given) and regenerate the tool configs."""
    paths.root.mkdir(parents=True, exist_ok=True)
    if password is not None:
        fd = os.open(paths.password, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(password)
        os.chmod(paths.password, 0o600)
    _write(paths.config, json.dumps({"version": 1, **asdict(cfg)}, indent=2, ensure_ascii=False) + "\n")
    write_tools(paths, cfg)


def write_tools(paths, cfg):
    """The tools' configs from config.json; the service writes them again when it starts, so a new image
    brings its settings to an old volume."""
    _write(paths.mbsyncrc, mbsyncrc(cfg, paths))
    _write(paths.notmuch_config, notmuch_config(cfg, paths))
    _write(paths.goimapnotify, goimapnotify_yaml(cfg, paths))
    for name in cfg.local_folders.values():
        for sub in ("cur", "new", "tmp"):
            (paths.folder(name) / sub).mkdir(parents=True, exist_ok=True)


def _write(path, text):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def read_password(paths):
    return paths.password.read_text(encoding="utf-8").strip()


def _q(s):
    """A quoted string for mbsync's config parser."""
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def mbsyncrc(cfg, paths):
    if cfg.test_far_maildir:
        far = cfg.test_far_maildir.rstrip("/")
        remote = f"""MaildirStore remote
Path {_q(far + "/")}
Inbox {_q(far + "/INBOX")}
SubFolders Verbatim
"""
    else:
        remote = f"""IMAPAccount main
Host {cfg.imap_host}
Port {cfg.imap_port}
User {_q(cfg.address)}
PassCmd {_q("cat " + str(paths.password))}
AuthMechs PLAIN LOGIN
TLSType IMAPS
CertificateFile {_q(os.environ.get("MAIL_CA_FILE", "/etc/ssl/certs/ca-certificates.crt"))}
Timeout 60

IMAPStore remote
Account main
"""
    channels = []
    for key, local in cfg.local_folders.items():
        far = cfg.folders.get(key)
        if not far:
            continue
        create = "Both" if key == "archive" and cfg.create_archive else "Near"
        # Gmail: a mail taken out of INBOX here is taken out there, which archives it (changes.py)
        gone = "Sync PullNew PullGone PullFlags PushNew PushFlags PushGone\nExpunge Both\n" \
            if key == "inbox" and cfg.gmail else ""
        channels.append(f"""Channel {key}
Far {_q(":remote:" + far)}
Near {_q(":local:" + local)}
Create {create}
{gone}""")
    if cfg.gmail:   # the labels under Assistant/, created there when n8n sets a new one (changes.py)
        channels.append(f"""Channel labels
Far {_q(":remote:" + LABELS + "/")}
Near {_q(":local:" + LABELS + "/")}
Patterns *
Create Both
Sync PullNew PullGone PullFlags PushNew PushFlags PushGone
Expunge Both
""")
    names = " ".join(cfg.channels)
    return f"""# Generated by mailctl from config.json; edits here are overwritten.
# Only mbsync writes to the provider, and it never deletes there: new mails and flags go both ways,
# disappearances only from the provider to here. Exception on Gmail: a mail taken out of INBOX or a
# label folder here is taken out there too, which only takes the label away (All Mail keeps it).

Sync PullNew PullGone PullFlags PushNew PushFlags
Expunge Near
SyncState *
CopyArrivalDate yes

{remote}
MaildirStore local
Path {_q(str(paths.maildir) + "/")}
Inbox {_q(str(paths.folder(INBOX)))}
SubFolders Verbatim

{chr(10).join(channels)}
Group all
Channels {names}
"""


def notmuch_config(cfg, paths):
    ignore = ";".join([".mbsyncstate", ".mbsyncstate.journal", ".mbsyncstate.new", ".mbsyncstate.lock",
                       ".uidvalidity", ".isyncuidmap.db"])
    return f"""# Generated by mailctl from config.json; edits here are overwritten.
[database]
path={paths.maildir}

[user]
name={cfg.name}
primary_email={cfg.address}

[new]
tags=
ignore={ignore}

[search]
exclude_tags=

[maildir]
synchronize_flags=true

[show]
extra_headers=In-Reply-To;References;X-Kingo-Test;X-Kingo-Confidential;X-Kingo-Sent;X-Kingo-To;X-Kingo-Cc
"""


def goimapnotify_yaml(cfg, paths):
    wake = json.dumps("mailctl wake watcher")
    events = "\n".join(f"        {e}: {wake}\n        {e}Post: SKIP" for e in ("onNewMail", "onChangedMail", "onDeletedMail"))
    return f"""# Generated by mailctl from config.json; edits here are overwritten.
# goimapnotify only listens (IDLE, or NOOP every 60 s); the service does the syncing.
configurations:
  - host: {json.dumps(cfg.imap_host)}
    port: {cfg.imap_port}
    tls: true
    tlsOptions:
      rejectUnauthorized: true
    username: {json.dumps(cfg.address)}
    passwordCMD: {json.dumps("cat " + str(paths.password))}
    wait: 1
    boxes:
      - mailbox: {json.dumps(cfg.folders.get("inbox", INBOX))}
{events}
"""
