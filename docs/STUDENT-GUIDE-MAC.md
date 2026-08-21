# Kingo Classroom — Mac setup

Everything the class uses (Langflow, n8n, JupyterLab, Metabase, a database, …)
runs in containers on your own Mac. **One script sets everything up**; the
script checks itself and tells you if something needs fixing.

## Before you start

- An **Apple-Silicon Mac** (M1 or newer — any Mac from 2021 on).
- **8 GB RAM** (16 GB recommended) and about **20 GB free disk space**.
- **Do this at home, before class.** The first start downloads about **10 GB**
  of images. On classroom Wi-Fi that is slow and painful; at home it is a
  one-time wait. After that, starting is quick and works offline.
- **How long?** A few minutes of setup plus the 10 GB download —
  **15–45 minutes** depending on your internet, mostly unattended.
- **Slow or no internet at home?** Your instructor can bring the images on a
  **USB stick** to class — the 10 GB then come from the stick instead of the
  Wi-Fi (see the USB box in Step 2).

> **Already have Docker Desktop?** (e.g. from another course) — perfect, keep
> it. Just make sure Docker Desktop is **running** before Step 2. The setup
> script detects it and uses it, and installs nothing new. Your existing
> containers, images, and settings are not touched. Everyone else gets
> **Podman** installed instead — same stack, same commands, no difference in
> class. (Curious why Podman? See the [FAQ](#faq).)

## Step 1 — Get the files

1. Open the project on GitHub and click the green **Code** button →
   **Download ZIP**.
2. Double-click the ZIP to unzip it. You get a folder called **`kingo-pod-main`**.
3. Move that folder somewhere easy, e.g. your **Home** folder or **Documents**.

## Step 2 — Run the setup script

1. Open the **Terminal** app (press ⌘ Space, type *Terminal*, press Enter).
2. Type `cd ` (with a space after it), then **drag the `kingo-pod-main`
   folder** from Finder onto the Terminal window, and press **Enter**.
3. Type this and press **Enter**:

   ```
   bash setup/setup-mac.sh
   ```

The script does four things, in order, and says so as it goes:

1. **Picks a container engine** — uses Docker Desktop if it's already running,
   otherwise installs Podman (a free engine). May ask for your Mac password
   once (that's Homebrew — normal).
2. **Checks your ports** — if other software on your Mac already uses a port
   the class needs (for example your own PostgreSQL on 5432), it automatically
   moves Kingo to a free port and tells you.
3. **Downloads and starts everything** (~10 GB on the first run — be patient).
4. **Verifies it** and prints your personal table of addresses and logins.

**You only do this once.** If it stops partway (Wi-Fi hiccup, closed laptop),
just run the same command again — it is safe to re-run and skips what's done.

> **Using the instructor's USB stick?** Plug the stick in, then run the same
> command with the file on the stick added: type `bash setup/setup-mac.sh `
> (with a space at the end), **drag the `kingo-images.tar` file** from the
> stick onto the Terminal window, and press Enter. Everything else is
> identical — the script takes the 10 GB of images from the stick
> (~5–10 minutes) instead of downloading them.

## Step 3 — Did it work?

You know you're done when the script prints **`SMOKE OK`** followed by a table
of web addresses. **That printed table is the truth for *your* Mac** — if the
script moved a port in Step 2, your address differs from the default table
below. You can reprint your table any time:

```
./kingo credentials
```

If the script ended with an ERROR instead, go to
[If something breaks](#if-something-breaks).

## Step 4 — Open your services

Default addresses (yours may differ — see Step 3). Open them in Safari or Chrome:

| Service | Address | Login |
|---|---|---|
| Langflow | <http://localhost:7860> | none (logs in automatically) |
| n8n | <http://localhost:5678> | create your own account on first visit |
| JupyterLab | <http://localhost:8888> | none |
| JupyterHub | <http://localhost:8000> | any username + password `kingo2026` |
| Metabase | <http://localhost:3000> | `admin@kingo.local` / `Kingo2026!` |
| CloudBeaver | <http://localhost:8978> | `student` / `Kingo2026!` |
| Qdrant | <http://localhost:6333/dashboard> | none |
| PostgreSQL | `localhost:5432` | `student` / `kingo2026` (db: `classroom`) |

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

Open Terminal in the `kingo-pod-main` folder (the `cd` + drag trick from
Step 2) and use:

```
./kingo up            # start everything (your data stays between runs)
./kingo down          # stop everything
./kingo status        # which services are up?
./kingo credentials   # my addresses + logins
./kingo doctor        # something's wrong? start here
```

## If something breaks

**Always start with one command** — it checks the usual suspects and tells you
what to do:

```
./kingo doctor
```

| What you see | What to do |
|---|---|
| `Other software on this machine is already using ports Kingo needs` | Run `./kingo fixports`, then `./kingo up`. Kingo moves itself to free ports — your other software is untouched. Your addresses change; `./kingo credentials` shows the new ones. |
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
