# mail — the mailbox of the mail assistant (n8n workshop)

Copied from the workshop repo by its `system/kingo/apply.sh`. Change it there, not here.

The service `mail` keeps one test mailbox per student in step with the tables of schema `n8n_workshop_mail` in `classroom`, and sends what a person approved in n8n. n8n and Langflow never talk to it directly, only through Postgres: the tables, and `NOTIFY` as wake-up calls.

| | |
|---|---|
| `Dockerfile`, `mailctl`, `mailcontainer/` | the image `kingo-mail:local`: Alpine 3.24 with mbsync 1.5.1, notmuch 0.40, goimapnotify 2.5.4 and the Python service |
| `n8n_workshop_mail.sql` | tables, triggers, functions and roles; `kingo up` applies it on every start (`init_stack` → `mail_schema`) and gives the roles the class password |
| `case/` | the course case, with placeholders for the student's address: the sample mailbox (`kingo mail seed`): the mailbox of Vince Kaminski, head of research at Enron, as it stood on 30 April 2001 (3,244 real mails from the public Enron corpus, every address rewritten to `.example`, names real); `case.json` (the name the account sends under and the case's person, whom n8n sees in place of your address); `documents.jsonl` (documents with their vectors for `n8n_workshop_mail.chunks`; none in this case); `calendar.csv` (quiet periods, of which `kingo up` makes the table `calendar` a copy; none in this case); `tests/NN.eml`, the test mails for `deliver_test(n)`: 140 mails Kaminski received in May 2001, the month after the mailbox, in the order they came in, each with its own sender, To and Cc (in `.example`), your address in place of Kaminski's |

Commands: `./kingo mail config` (set up; `./kingo mail` and `./kingo mail setup` do the same), `./kingo mail seed`, `./kingo mail status`, `./kingo mail reset`, `./kingo logs mail`.

The account (address, app password, the Maildir with its notmuch index, mbsync's sync state) lives in the volume `mail-data`. Restore it whole or not at all: a Maildir without its sync state uploads every mail to the provider a second time. Which accounts got the case mailbox is noted in Postgres (`n8n_workshop_mail.seeded`), so `kingo mail reset` does not allow seeding the same account twice.

Rules the service keeps: nothing goes out without an approval in n8n, and no row is ever sent twice automatically. In course mode (on by default) it sends only to the account's own address, its plus addresses and the addresses `kingo mail` allowed; a mail to one of the case's contacts goes to a plus address of the own one instead, so it lands in your own inbox, and a mail to anyone else is refused, with the reason in the outbox row. n8n and Langflow see the case's addresses as real ones: your own address as the case's person (`case/case.json`, without `.example`), every other case address without `.example` (the files in `case/` keep it), a reply under the address it was written to (headers `X-Kingo-To`, `X-Kingo-Cc`); a mail this service sent carries `X-Kingo-Sent` and the tag `own`. With the case in place, course mode cannot be switched off. Approvals older than 24 hours expire.

## Licence, and what this service is for

Teaching software for the n8n workshop, under the licence of kingo-pod (MIT, see `LICENSE` in the repository root): it comes "as is", without warranty of any kind, as the licence says. Use it only with a mailbox made for the course, never with an account whose mail matters to you or to anyone else. The rules above (course mode, approvals) make mistakes unlikely; they are no guarantee.

The image `kingo-mail:local` is built on Alpine Linux and contains other people's programs under their own licences, as Alpine 3.24 lists them: isync (mbsync), notmuch and goimapnotify (GPL-3.0-or-later), py3-psycopg (LGPL-2.0-or-later), Python (PSF-2.0), libpq (PostgreSQL), tini (MIT), and Alpine's base (BusyBox GPL-2.0-only, musl MIT, ca-certificates MPL-2.0 and MIT). The service runs mbsync, notmuch and goimapnotify as programs of their own. Their sources: Alpine's build recipes at <https://gitlab.alpinelinux.org/alpine/aports> and the projects' own pages. The mails in `case/` come from the public Enron corpus.
