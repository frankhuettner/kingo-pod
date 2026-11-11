# Kingo Classroom — using the stack on a Mac

Setup is done and the script printed `SMOKE OK`. This page is everything that
comes after: your addresses and logins, the handful of commands you need, how
to get your own files in and out, how to update, and what to do when something
goes wrong. Bookmark it — you won't need the setup guide again.

> **Jump to:** [Your services](#your-services) ·
> [Everyday use](#everyday-use) · [Modes](#modes-which-services-run) ·
> [Your files](#your-own-files--the-shared-folder) ·
> [Claude Code](#claude-code--your-coding-agent) ·
> [Update](#keeping-up-to-date) ·
> [If something breaks](#if-something-breaks) · [FAQ](#faq)

## Your services

Open these in Safari or Chrome. If setup had to move a port your addresses
differ from the defaults below — `./kingo credentials` always prints the truth
for your own Mac:

| Service | Address | Login |
|---|---|---|
| Langflow | <http://localhost:7860> | none (logs in automatically) |
| n8n | <http://localhost:5678> | create your own account on first visit |
| JupyterLab | <http://localhost:8888> | none |
| JupyterHub | <http://localhost:8000> | any username + password `kingo2026` |
| Metabase | <http://localhost:3000> | `admin@kingo.local` / `Kingo2026!` |
| CloudBeaver | <http://localhost:8978> | `student` / `Kingo2026!` — [how to connect](CLOUDBEAVER.md) |
| Qdrant | <http://localhost:6333/dashboard> | none |
| PostgreSQL | `localhost:5432` | `student` / `kingo2026` (db: `classroom`) |

Not all of these run at the same time: in **abp mode** — what setup installs —
only Langflow, n8n, Mail, CloudBeaver, Qdrant and PostgreSQL are on, and
`./kingo credentials` marks the others as *off*. See [Modes](#modes-which-services-run)
for switching.

> **CloudBeaver looks empty at first** ("No Connections") — you have to log in
> via the **gear icon → Login** before the class database shows up, and give it
> the database password once. Two minutes, step by step:
> [Using CloudBeaver](CLOUDBEAVER.md).

MCP (*Model Context Protocol*) is how AI assistants such as Claude Desktop,
Claude Code, or Cursor connect to tools. Point yours at the Jupyter MCP
endpoint `http://localhost:4040/mcp` (header
`Authorization: Bearer kingo-mcp-2026`) and it can write and run code in the
class notebook for you. `./kingo mcp` prints exactly this.

**OpenCode** (AI coding in the terminal) runs natively on your Mac — it is not
inside the stack. Install it once with (works whether or not you have Homebrew):

```
curl -fsSL https://opencode.ai/install | bash
```

then run `opencode` in any Terminal. The first run asks for an API key; change
it anytime with `opencode auth login`.

## Everyday use

Open Terminal and go to the class folder:

```
cd ~/kingo-pod
```

then one command per job:

| Command | What it does |
|---|---|
| `./kingo up` | start everything (your data stays between runs) |
| `./kingo down` | stop everything |
| `./kingo status` | which services are up? |
| `./kingo credentials` | my addresses + logins |
| `./kingo mode` | which services run — and `./kingo mode full` / `abp` / … switches (see [Modes](#modes-which-services-run)) |
| `./kingo memory` | how much memory the containers may use; `./kingo memory 5` changes it |
| `./kingo mail` | set up the mailbox for the mail assistant (n8n workshop); `./kingo mail help` shows the rest |
| `./kingo claude` | start Claude Code, your coding agent, in its sandbox (see [Claude Code](#claude-code--your-coding-agent)) |
| `./kingo doctor` | something's wrong? start here |
| `./kingo version` | which version am I running? (send this when you ask for help) |
| `./kingo update` | get the newest class files + images (run it when the instructor announces an update) |

> **What if I just close the Terminal window?** Nothing breaks — the stack
> keeps running in the background: your services stay reachable in the
> browser, and it keeps using its memory (4 GB in abp mode, up to 6 GB in
> full mode). It stops only when you run
> `./kingo down` or shut down / restart the Mac. Your data survives all of
> these — closed windows, `down`, reboots. After a reboot, run `./kingo up`
> again. (Docker Desktop users: the stack may come back by itself when
> Docker starts — `./kingo status` shows what's up.)

### Modes: which services run

Not every class week needs all ten services, and an 8 GB Mac cannot run
them all comfortably. A **mode** is the set of services that runs — the
others are simply off (nothing is deleted; every mode keeps your data):

| Mode | What runs | Memory it wants |
|---|---|---|
| `abp` (what setup installs) | Langflow, n8n, Mail, CloudBeaver, Qdrant, PostgreSQL | 4 GB |
| `full` | all ten services | 6 GB |
| `bi` | JupyterLab, JupyterHub, Jupyter MCP, Metabase, CloudBeaver, Qdrant, PostgreSQL | 4.5 GB |
| `langflow` | Langflow, PostgreSQL | 3.5 GB |
| `n8n` | n8n, Mail, PostgreSQL | 2.5 GB |

`./kingo mode` shows the current one. Switching is one line, for example:

```
cd ~/kingo-pod && ./kingo mode full
```

It takes about a minute: the stack stops, the Podman machine is resized to
what the new mode wants, and the stack comes back with the new set of
services. Your notebooks, dashboards, flows and workflows are all still
there — switch back any time with `./kingo mode abp`.

> **On a Mac with Podman, resizing the machine stops ALL containers on the
> Mac for about a minute** — Kingo's come back by themselves, containers from
> other courses do not. If any are running, `kingo` lists them and asks you to
> type `yes` first. (Docker Desktop: nothing is resized; only the services
> change.)

Want a different amount of memory than the mode asks for? `./kingo memory`
shows what the containers have and use right now; `./kingo memory 5` sets
5 GB (same one-minute restart); `./kingo memory auto` lets the mode decide
again.

### Your own files — the `shared` folder

`shared` is a folder inside `kingo-pod` that both you and Langflow can see.
Put your own files there: a SQLite database, a CSV, an Excel sheet, a PDF.

It is one folder with two names, because you and Langflow look at it from
different sides:

| Looking from | The folder is called |
|---|---|
| your Mac | `~/kingo-pod/shared` |
| inside Langflow | `/app/shared` |

So a database you drop in as `~/kingo-pod/shared/trials.sqlite` is
`/app/shared/trials.sqlite` when you type it into a Langflow component. It
works the other way round too: whatever Langflow writes there shows up on your
Mac. The folder is made for you — if it is not there, run `./kingo update`
once.

> **Opening a SQLite file in Langflow?** The SQL component wants a database
> URL, not a path, and an absolute path takes **four** slashes:
> `sqlite:////app/shared/trials.sqlite`.

One line opens the folder in Finder (then ⌘-drag it to the Finder sidebar to
keep it there):

```
open ~/kingo-pod/shared
```

Drag files in and out like in any other folder. Langflow sees them at once.

**Keep private files out of it.** Anything running inside Langflow can read,
change and delete what is in this folder — including a flow someone else built
and you imported. Never let it hold your only copy of something. Nothing
outside this one folder is reachable from Langflow.

> **Using Docker Desktop?** Files that *Langflow itself* writes into the
> folder can end up owned by the system rather than by you — deleting those
> from Finder or Terminal may then need `sudo rm`. Files **you** put in are
> never affected. With Podman (the default) this does not happen.

## Claude Code — your coding agent

Claude Code is an AI that works with you in Terminal. It reads and writes
files, runs commands, and in kingo-pod it can change your n8n workflows, your
Langflow flows and your database. It uses the model GLM 5.3 Flash, paid with
the OpenRouter key Yanbo gave you.

It runs in a **sandbox** called nono: on your Mac it can write in one folder
only, `~/kingo-pod/claude`. It can read the rest of `kingo-pod` to understand
the stack, and nothing else on your Mac.

**Install it once.** One line installs nono, the database tool `psql` and
Claude Code:

```
brew install nono libpq && curl -fsSL https://claude.ai/install.sh | bash
```

> **Already use Claude Code?** Run the line anyway: it installs Claude Code
> the way Anthropic recommends, or brings it up to date. Your own settings and
> your login stay as they are. You installed Claude Code with Homebrew or npm
> instead? Then you now have two installations. `./kingo claude` always takes
> the new one. To
> keep only the new one, remove the old one: `brew uninstall --cask claude-code`
> or `npm uninstall -g @anthropic-ai/claude-code`.

**Make a key in n8n for Claude.** In n8n, click **Settings** at the bottom of
the left sidebar, then **n8n API**, then **Create API key**. Label: `claude`.
Expiration: **Never**. Click **Save** and copy the key: n8n shows it only once.

**Start it:**

```
cd ~/kingo-pod && ./kingo claude
```

Always start it this way: only `./kingo claude` (or `./kingo yolo`) sets it
up for the course. A plain `claude` is a standard Claude Code with
Anthropic's settings — no sandbox, no keys, your own `~/.claude`.

The first time, it asks for two keys: your OpenRouter key and the n8n key you
just made. Paste each one and press Enter; you do not see a key as you paste
it. The key for Langflow it makes by itself. Then Claude Code asks a few
questions of its own: pick a look, and say **Yes** when it asks whether you
trust the folder. To stop, type `/exit`. Every next time, `./kingo claude`
starts it right away.

**Tell it your team's rules.** Claude reads the file
`~/kingo-pod/claude/AGENTS.md` at every start. Paste your team's copy of
`ws2_rules.html` into it, as the file explains, then start Claude again. This
line opens the file in TextEdit:

```
open -e ~/kingo-pod/claude/AGENTS.md
```

| Claude can | Claude cannot |
|---|---|
| read and write in `~/kingo-pod/claude` | write anywhere else on your Mac |
| read `kingo-pod`: `compose.yml`, the guides | change `kingo-pod`, or run `./kingo` |
| change your n8n workflows, Langflow flows and database | see your keys: it gets stand-ins |
| look things up on the web | see your own Claude Code settings, if you use Claude Code already |

**It asks before every command,** unless you start it with
`./kingo yolo`. Inside the sandbox, Claude Code's requests for permission do not
protect your Mac — the sandbox does that either way — but they show you every
change to your workflows, flows and database before it happens. Without them,
save your workflows and flows first with `./kingo backup` (your own tables are
not in it). And only run a command in your
own Terminal if you understand it: Claude cannot leave its sandbox, but a
command you type can.

> **A key stopped working?** `./kingo claude` checks the keys at every start.
> A key that a service refuses is deleted, and the next start asks for it
> again. The keys are kept in `~/.config/kingo/`, where Claude cannot read them.

## Keeping up to date

**One line brings your installation up to date** — newest class files, images
and rebuilt containers. Safe to run any time, from any folder:

```
cd ~/kingo-pod && ./kingo update
```

Run it whenever your instructor announces an update. It works for every
install, however old — nothing has to be downloaded by hand. Before a new
version starts, it saves a copy of your Langflow flows and n8n workflows in
`kingo-pod/backups/`, so your instructor can bring them back if something
goes wrong.

**Optional this term: Kingo 1.5.** It brings Langflow 1.12, which fixes a
memory bug in Langflow 1.8: chats with the same name share one memory, even
in different flows.
`./kingo update` does not install it by itself. Read
[the optional upgrade to Kingo 1.5](UPGRADE.md) and decide with your team
first.

## If something breaks

**Always start with one command** — it checks the usual suspects and tells you
what to do:

```
./kingo doctor
```

| What you see | What to do |
|---|---|
| Terminal says `./kingo: No such file or directory` | You're in the wrong folder. Run `cd ~/kingo-pod` first. |
| `Other software on this machine is already using ports Kingo needs` | Run `./kingo fixports`, then `./kingo up`. Kingo moves itself to free ports — your other software is untouched. Your addresses change; `./kingo credentials` shows the new ones. |
| Same message right **after** `./kingo down`, but you started nothing new | No real collision — the engine's port forwarder didn't let go. Current `kingo` frees these leftovers by itself (get it: `./kingo update`), so first just run `./kingo up` again. If it persists: `./kingo fixports` moves past it, or restart the engine (`podman machine stop && podman machine start`; Docker Desktop: quit and reopen) — **note**: an engine restart stops ALL your containers, not just Kingo's. |
| `The Kingo stack is ALREADY RUNNING under your other engine` | Nothing is broken — the stack is up under your other container engine. Follow the two commands the message prints. |
| `ALL of Kingo's ports are busy` | The stack is most likely **already running** (possibly under your other engine). Run `./kingo status` — if services show `up`, you're done, nothing is wrong. |
| I have Docker Desktop, but setup installed Podman | Docker wasn't running during setup. Both work — no need to change anything. To switch to Docker anyway: `./kingo down` (stops the Podman stack **first**), then `echo KINGO_ENGINE=docker >> .env.local`, then `./kingo up`. |
| `Podman has no ready machine` / Podman won't start | Run `podman machine start`, then `./kingo up`. Still broken: `podman machine stop`, then `podman machine start`. |
| `Docker is installed but not running` | Open the Docker Desktop app, wait until it says "running", try again. |
| Mac feels slow / fans spin (8 GB Macs) | Run a lighter [mode](#modes-which-services-run): `./kingo mode abp` (4 GB) — or, for one tool at a time, `./kingo mode langflow` (3.5 GB) or `./kingo mode n8n` (2.5 GB). The containers keep their memory no matter what, so everything else on the Mac shares the rest — above all a browser with dozens of tabs, which alone can take 2–3 GB (the Langflow and n8n tabs count too): close what you do not need. `./kingo down` when you are not using the stack also helps. |
| `brew: command not found` when you install Claude Code | The line needs Homebrew. It is missing, or Terminal does not find it. Do [Step 1 — Install Homebrew](STUDENT-GUIDE-MAC.md#step-1--install-homebrew), with its "Next steps" lines. Open a new Terminal window and run the line again. |
| Anything else | `./kingo down`, then `./kingo up`. If it persists: screenshot the error and ask the instructor / TA. |

## FAQ

**Why Podman and not Docker?** They do the same job and this stack runs
identically on both (our tests run on both, every day). We default to Podman
because it's fully open-source and free for everyone — Docker Desktop's
license requires payment at larger companies, and we don't want the tooling
you learn to expire with your student status. **If Docker Desktop is already
on your Mac, the setup script simply uses it** — you are not missing anything
either way.

**I already use Docker / have my own database. Will this break my stuff?**
No. Kingo runs in its own containers (all named `kingo-…`) with its own
storage. The only possible overlap is a port number — and setup/`fixports`
resolves that automatically by moving *Kingo*, never your software.

**The passwords are printed in a public repo?!** Yes, on purpose. Every
service is reachable **only from your own Mac** (`127.0.0.1` — people on the
same Wi-Fi cannot connect), so these are classroom conveniences, not secrets.
The one real rule: the class shares an n8n encryption key, so **never put a
real API key into an n8n workflow you share or export.**

**Where is my data?** Databases, notebooks, and workflows live in container
volumes on your Mac and survive `./kingo down`, reboots and mode switches.
Only `./kingo reset` deletes them (it asks first).

**Where did Jupyter and Metabase go?** They are off in `abp` mode, which is
what setup installs — `./kingo status` and `./kingo credentials` say so.
`./kingo mode full` turns everything on (about a minute; see
[Modes](#modes-which-services-run)); the instructor announces when a class
week needs it.

**Can I give the containers more or less memory myself?** Yes:
`./kingo memory 5` (or any number of GB). On a Mac with Podman that resizes
the Podman machine right away — and, like every machine restart, **stops ALL
containers on the Mac for about a minute**, not only Kingo's. With Docker
Desktop the memory slider is in Docker Desktop → Settings → Resources; the
same warning applies to its *Apply & restart*.

**Can I use extra Python packages (say, statsmodels)?**

- **JupyterLab** (`:8888`) already ships the data-science standards —
  pandas, statsmodels, scikit-learn, seaborn, and friends. For anything
  else, run `%pip install <package>` in a notebook cell (repeat it if the
  stack was restarted since).
- **Langflow**: the class set (statsmodels, ragas, …) is built in — `import
  statsmodels` just works in Python components. Need one more?
  `./kingo langflow pip install <package>` installs it on the spot; it lasts
  until the next `./kingo down` + `up`, so run it again after that (or ask
  the instructor to add it for everyone). If the install upgraded a compiled
  package (pyarrow, numpy, pandas — pip lists what it installed), run
  `./kingo restart langflow` before building a flow: the running Langflow
  still has the old one loaded, and the build would otherwise fail with
  "size changed, may indicate binary incompatibility".
- **JupyterHub** (`:8000`) starts a minimal Python *without* the data
  packages — use `%pip install` there too, or simply do data work in
  JupyterLab.

## How it all fits together

```
┌─ Your Mac ─────────────────────────────────────────────────┐
│                                                            │
│   Browser, KNIME, MCP clients, OpenCode                    │
│       │                                                    │
│       │  always talk to  localhost:<port>                  │
│       ▼  (published on 127.0.0.1 only)                     │
│  ┌─ Container engine (Podman or Docker) ───────────────┐   │
│  │                                                     │   │
│  │   one container per service:                        │   │
│  │   [Langflow] [n8n] [JupyterLab] [Metabase] ...      │   │
│  │       │        │                                    │   │
│  │       └────────┴──► [PostgreSQL]   [Qdrant]         │   │
│  │                                                     │   │
│  │   containers reach each other by service NAME:      │   │
│  │   postgres:5432, qdrant:6333                        │   │
│  └─────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
```

Two address rules cover everything:

1. **From your Mac** (browser, KNIME, MCP clients): always `localhost:<port>`.
2. **From one service to another** — e.g. an n8n workflow or Langflow flow
   connecting to the database: use the *service name* as host, **not**
   localhost. PostgreSQL: host `postgres`, port `5432`, database `classroom`,
   user `student`, password `kingo2026`. Qdrant: `http://qdrant:6333`.
   (Inside a container, `localhost` means the container itself — the most
   common mistake. Rule 2 is also why moved host ports never affect
   service-to-service connections.)

## KNIME (optional)

KNIME runs on your Mac itself, not in a container: download **KNIME Analytics
Platform** from <https://www.knime.com/downloads> and install it like any
other app. To use the class database, create a PostgreSQL connection with host
`localhost`, port `5432` (or your moved port from `./kingo credentials`),
database `classroom`, username `student`, password `kingo2026`. The stack must
be running (`./kingo up`) while you use it.
