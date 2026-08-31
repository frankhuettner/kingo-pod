# Kingo Classroom — using the stack on a Mac

Setup is done and the script printed `SMOKE OK`. This page is everything that
comes after: your addresses and logins, the handful of commands you need, how
to get your own files in and out, how to update, and what to do when something
goes wrong. Bookmark it — you won't need the setup guide again.

> **Jump to:** [Your services](#your-services) ·
> [Everyday use](#everyday-use) · [Your files](#your-own-files--the-shared-folder) ·
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
| `./kingo doctor` | something's wrong? start here |
| `./kingo version` | which version am I running? (send this when you ask for help) |
| `./kingo update` | get the newest class files + images (run it when the instructor announces an update) |

> **What if I just close the Terminal window?** Nothing breaks — the stack
> keeps running in the background: your services stay reachable in the
> browser, and it keeps using ~5 GB RAM. It stops only when you run
> `./kingo down` or shut down / restart the Mac. Your data survives all of
> these — closed windows, `down`, reboots. After a reboot, run `./kingo up`
> again. (Docker Desktop users: the stack may come back by itself when
> Docker starts — `./kingo status` shows what's up.)

### Your own files — the `shared` folder

Your own data files — a CSV, an Excel sheet, a PDF — go into the **`shared`
folder inside `kingo-pod`** (`~/kingo-pod/shared`). Langflow sees the same
folder as **`/app/shared`** — so a file you drop in as
`~/kingo-pod/shared/sales.csv` is `/app/shared/sales.csv` in a Langflow
component, and anything Langflow writes there appears on your Mac. The folder
is created for you; if it isn't there yet, run `./kingo update` once.

One line opens it in Finder (and ⌘-drag it to the Finder sidebar to keep it
there):

```
open ~/kingo-pod/shared
```

Treat the folder as **shared with Langflow**: anything running inside Langflow
— including a flow someone else built and you imported — can read, change and
delete files there. So keep private files out of it, and never let it hold the
only copy of something. Nothing outside this one folder is reachable from
Langflow.

> **Using Docker Desktop?** Files that *Langflow itself* writes into the
> folder can end up owned by the system rather than by you — deleting those
> from Finder or Terminal may then need `sudo rm`. Files **you** put in are
> never affected. With Podman (the default) this does not happen.

## Keeping up to date

**One line brings your installation up to date** — newest class files, images
and rebuilt containers. Safe to run any time, from any folder:

```
cd ~/kingo-pod && ./kingo update
```

Run it whenever your instructor announces an update. It works for every
install, however old — nothing has to be downloaded by hand.

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
| Mac feels slow / fans spin (8 GB Macs) | The stack needs ~5 GB RAM while running. Close other apps and browser tabs, or `./kingo down` when not using it. |
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
volumes on your Mac and survive `./kingo down` and reboots. Only
`./kingo reset` deletes them (it asks first).

**Can I use extra Python packages (say, statsmodels)?**

- **JupyterLab** (`:8888`) already ships the data-science standards —
  pandas, statsmodels, scikit-learn, seaborn, and friends. For anything
  else, run `%pip install <package>` in a notebook cell (repeat it if the
  stack was restarted since).
- **Langflow**: the class set (statsmodels, …) is built in — `import
  statsmodels` just works in Python components. Need one more?
  `./kingo langflow pip install <package>` installs it on the spot; it lasts
  until the next `./kingo down` + `up`, so run it again after that (or ask
  the instructor to add it for everyone).
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
