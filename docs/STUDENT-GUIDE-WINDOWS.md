# Kingo Classroom — Windows setup

Everything the class uses (Langflow, n8n, JupyterLab, Metabase, a database, …)
runs in containers on your own laptop. On Windows it runs inside **WSL2** —
Windows' built-in Linux. You turn WSL2 on once, then everything is a few
copy-paste commands in an Ubuntu terminal. You do **not** need to be a Linux
expert, and the setup script checks itself and tells you if something needs
fixing.

## Before you start

- **Windows 10 or 11**, with **8 GB RAM** (16 GB recommended) and about
  **20 GB free disk space**.
- **Do this at home, before class.** Enabling WSL2 may need **one reboot**,
  and the first start downloads about **10 GB** of images. Get both done at
  home so class time isn't lost to downloads.

> **Already have Docker Desktop?** (e.g. from another course) — perfect, keep
> it. Do Steps 1–2 anyway (WSL2 + Ubuntu are needed either way), then before
> Step 3: open Docker Desktop → **Settings → Resources → WSL integration** →
> turn it **on for Ubuntu**, and leave Docker Desktop running. The setup
> script detects it and uses it — nothing extra gets installed. Everyone else
> gets **Podman** installed inside Ubuntu instead — same stack, same commands,
> no difference in class. (Curious why Podman? See the [FAQ](#faq).)

## Step 1 — Turn on WSL2 + Ubuntu

**Watch this 4-minute video and do exactly what it shows:**
<https://www.youtube.com/watch?v=zZf4YH4WiZo>

It walks you through the three things Windows needs, in order:

1. In the Start menu, search **"Turn Windows features on or off"**, tick
   **Virtual Machine Platform** and **Windows Subsystem for Linux**, click OK.
2. **Restart** your laptop.
3. Open the **Microsoft Store**, search **Ubuntu**, and click **Get/Install**.

The video ends with the first launch of Ubuntu — that's our Step 2, below.

## Step 2 — First launch of Ubuntu

Open the **Ubuntu** app from the Start menu. The first time, it asks you to
pick a **Linux username and password**. The password stays **invisible while
you type — that's normal**, just type it and press Enter. Remember it: some
commands ask for it later.

✔ You know this step worked when you see a colored prompt ending in `$`.

## Step 3 — Install and start the stack (inside Ubuntu)

In the Ubuntu terminal, paste this block (right-click pastes) and press
**Enter**:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/frankhuettner/kingo-pod.git
cd kingo-pod && bash setup/setup-linux.sh
```

The script does four things, in order, and says so as it goes:

1. **Picks a container engine** — uses Docker Desktop if you connected it (see
   the box above), otherwise installs Podman inside Ubuntu.
2. **Checks your ports** — if other software already uses a port the class
   needs (for example your own PostgreSQL on 5432), it automatically moves
   Kingo to a free port and tells you.
3. **Downloads and starts everything** (~10 GB on the first run — be patient).
4. **Verifies it** and prints your personal table of addresses and logins.

**You only do this once.** If it stops partway (Wi-Fi hiccup, closed laptop),
run it again — it is safe to re-run and skips what's done:

```bash
cd ~/kingo-pod && bash setup/setup-linux.sh
```

(Only if the *download* itself broke off and even the re-run fails: delete the
half-finished folder with `rm -rf ~/kingo-pod` and start Step 3 from the top.)

## Step 4 — Did it work?

You know you're done when the script prints **`SMOKE OK`** followed by a table
of web addresses. **That printed table is the truth for *your* laptop** — if
the script moved a port in Step 3, your address differs from the default table
below. Reprint your table any time (in Ubuntu, inside the `kingo-pod` folder):

```bash
./kingo credentials
```

If the script ended with an ERROR instead, go to
[If something breaks](#if-something-breaks).

## Step 5 — Open your services

Use your normal **Windows** browser — WSL2 forwards `localhost` from Ubuntu to
Windows automatically. Default addresses (yours may differ — see Step 4):

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

**OpenCode** (AI coding in the terminal) runs inside your Ubuntu — install it
once with:

```bash
curl -fsSL https://opencode.ai/install | bash
```

then run `opencode`. The first run asks for an API key; change it anytime with
`opencode auth login`.

## Everyday use

Open the **Ubuntu** app, then:

```bash
cd kingo-pod
./kingo up            # start everything (your data stays between runs)
./kingo down          # stop everything
./kingo status        # which services are up?
./kingo credentials   # my addresses + logins
./kingo doctor        # something's wrong? start here
```

## If something breaks

**Always start with one command** (in Ubuntu, inside `kingo-pod`) — it checks
the usual suspects and tells you what to do:

```bash
./kingo doctor
```

| What you see | What to do |
|---|---|
| WSL won't enable / "Virtual Machine Platform" error | Virtualization is off in your PC's firmware. Restart, enter firmware setup (usually F2, F10, or Del during boot), enable **Virtualization** (Intel VT-x / AMD-V / "SVM"), save, run Step 1 again. |
| `this Ubuntu is running under WSL 1` | In Windows PowerShell run `wsl --set-version Ubuntu 2` (takes a few minutes), then reopen Ubuntu and re-run the setup script. |
| `Other software on this machine is already using ports Kingo needs` | Run `./kingo fixports`, then `./kingo up`. Kingo moves itself to free ports — your other software is untouched. Your addresses change; `./kingo credentials` shows the new ones. |
| `The Kingo stack is ALREADY RUNNING under your other engine` | Nothing is broken — the stack is up under your other container engine. Follow the two commands the message prints. |
| `ALL of Kingo's ports are busy` | The stack is most likely **already running** (possibly under your other engine). Run `./kingo status` — if services show `up`, you're done, nothing is wrong. |
| I have Docker Desktop, but setup installed Podman | Docker wasn't running or its WSL integration was off during setup. Both engines work — no need to change anything. To switch anyway: turn on WSL integration for Ubuntu, then `./kingo down` (stops the Podman stack **first**), then `echo KINGO_ENGINE=docker >> .env.local`, then `./kingo up`. |
| Laptop feels slow (8 GB machines) | The stack needs ~6 GB RAM. Close other apps. If it stays bad, create the file `C:\Users\<you>\.wslconfig` **in Windows** containing `[wsl2]` on one line and `memory=6GB` on the next, run `wsl --shutdown` in PowerShell, then start the stack again. |
| Ubuntu terminal says `./kingo: No such file or directory` | You're in the wrong folder. Run `cd ~/kingo-pod` first. |
| Anything else | `./kingo down`, then `./kingo up`. If it persists: screenshot the error and ask the instructor / TA. |

## FAQ

**Why Podman and not Docker?** They do the same job and this stack runs
identically on both (our tests run on both, every day). We default to Podman
because it's fully open-source and free for everyone — Docker Desktop's
license requires payment at larger companies, and we don't want the tooling
you learn to expire with your student status. **If Docker Desktop is already
on your laptop, the setup script simply uses it** — you are not missing
anything either way.

**I already use Docker / have my own database. Will this break my stuff?**
No. Kingo runs in its own containers (all named `kingo-…`) with its own
storage. The only possible overlap is a port number — and setup/`fixports`
resolves that automatically by moving *Kingo*, never your software.

**The passwords are printed in a public repo?!** Yes, on purpose. Every
service is reachable **only from your own laptop** (`127.0.0.1` — people on
the same Wi-Fi cannot connect; WSL2's localhost forwarding keeps it that way).
So these are classroom conveniences, not secrets. The one real rule: the class
shares an n8n encryption key, so **never put a real API key into an n8n
workflow you share or export.**

**Where is my data?** Databases, notebooks, and workflows live in container
volumes inside WSL2 and survive `./kingo down` and reboots. Only
`./kingo reset` deletes them (it asks first).

**Where are my Windows files inside Ubuntu?** Your Windows drives are mounted
under `/mnt` — e.g. `C:\Users\you\Documents` is `/mnt/c/Users/you/Documents`.

## How it all fits together

```
┌─ Your laptop (Windows) ────────────────────────────────────┐
│                                                            │
│   Browser, KNIME (on Windows)                              │
│       │  always talk to  localhost:<port>                  │
│       ▼  (WSL2 forwards localhost into Ubuntu)             │
│  ┌─ Ubuntu on WSL2 (Windows' built-in Linux) ─────────┐    │
│  │                                                    │    │
│  │   container engine (Podman or Docker) runs one     │    │
│  │   container per service:                           │    │
│  │   [Langflow] [n8n] [JupyterLab] [Metabase] ...     │    │
│  │       │        │                                   │    │
│  │       └────────┴──► [PostgreSQL]   [Qdrant]        │    │
│  │                                                    │    │
│  │   containers reach each other by service NAME:     │    │
│  │   postgres:5432, qdrant:6333                       │    │
│  └────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────┘
```

Two address rules cover everything:

1. **From your laptop** (Windows browser, KNIME): always `localhost:<port>`.
2. **From one service to another** — e.g. an n8n workflow or Langflow flow
   connecting to the database: use the *service name* as host, **not**
   localhost. PostgreSQL: host `postgres`, port `5432`, database `classroom`,
   user `student`, password `kingo2026`. Qdrant: `http://qdrant:6333`.
   (Inside a container, `localhost` means the container itself — the most
   common mistake. Rule 2 is also why moved host ports never affect
   service-to-service connections.)

## KNIME (optional)

KNIME runs on **Windows** itself, not inside Ubuntu: download **KNIME
Analytics Platform** from <https://www.knime.com/downloads> and install it
like any other program. To use the class database, create a PostgreSQL
connection with host `localhost`, port `5432` (or your moved port from
`./kingo credentials`), database `classroom`, username `student`, password
`kingo2026`. The stack must be running (`./kingo up` in Ubuntu) while you use
it.
