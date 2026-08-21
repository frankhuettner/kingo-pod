# Kingo Classroom — Windows setup

You need a Windows 10 or 11 laptop with at least **8 GB of RAM** (16 GB
recommended) and about **20 GB of free disk space**.

On Windows, the class stack runs inside **WSL2** — Windows' built-in Linux. You
turn WSL2 on once, then run everything from an Ubuntu terminal. This is the same
Linux setup Mac and our tests use, so it's the best-tested path. You do **not**
need to become a Linux expert — it's a few copy-paste commands.

> **Do this at home, before class.** Enabling WSL2 may need **one reboot**, and
> the first start downloads about **10 GB** of images. Get it done at home so
> class time isn't lost to downloads.

## 1. Turn on WSL2 + Ubuntu

Easiest: in the project's `setup` folder, right-click **`setup-windows.ps1`** →
**Run with PowerShell** → click **Yes** on the Administrator prompt. If it says
a reboot is needed, **restart and run it again.**

(Or do it by hand: open **PowerShell as Administrator**, run `wsl --install`,
and reboot.)

**New to WSL? This 4-minute beginner video walks through exactly this** —
enabling WSL2, installing Ubuntu, and setting your Linux username/password:
<https://www.youtube.com/watch?v=zZf4YH4WiZo>

## 2. First launch of Ubuntu

Open the **Ubuntu** app from the Start menu. The first time, it asks you to
pick a **Linux username and password** (the password stays **invisible** while
you type — that's normal). Remember this password: some commands ask for it.

## 3. Install and start the stack (inside Ubuntu)

In the Ubuntu terminal, paste this block and press **Enter**:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/frankhuettner/kingo-pod.git
cd kingo-pod && bash setup/setup-linux.sh
```

That installs Podman (the container engine) and starts everything. The first run
downloads ~10 GB — be patient. When it finishes it prints the list of web
addresses below. **You only do this once.**

*If anything stops halfway, just run `bash setup/setup-linux.sh` again — it's
safe to re-run.*

## 4. Open the services

Open these in your normal **Windows** browser (WSL2 forwards `localhost` from
Ubuntu to Windows automatically):

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

(Reprint any time with `./kingo credentials` inside the `kingo-pod` folder.)

MCP (*Model Context Protocol*) is how AI assistants such as Claude Desktop,
Claude Code, or Cursor connect to tools. Point yours at the Jupyter MCP endpoint
`http://localhost:4040/mcp` (header `Authorization: Bearer kingo-mcp-2026`) and
it can write and run code in the class notebook for you.

**OpenCode** (AI coding in the terminal) runs inside your Ubuntu now — install it
once with:

```bash
curl -fsSL https://opencode.ai/install | bash
```

then run `opencode`. The first run asks for an API key; it is saved and can be
changed anytime with `opencode auth login`.

## 5. Everyday use

Open the **Ubuntu** app, then:

```bash
cd kingo-pod
./kingo up          # start everything (your data stays between runs)
./kingo status      # show which services are up
./kingo down        # stop everything
./kingo doctor      # check the engine, memory and ports if something's off
```

## How it all fits together

```
┌─ Your laptop (Windows) ────────────────────────────────────┐
│                                                            │
│   Browser, KNIME (on Windows)                              │
│       │  always talk to  localhost:<port>                  │
│       ▼  (WSL2 forwards localhost into Ubuntu)             │
│  ┌─ Ubuntu on WSL2 (Windows' built-in Linux) ─────────┐    │
│  │                                                    │    │
│  │   Podman runs one container per service:           │    │
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
2. **From one service to another** — for example an n8n workflow or a Langflow
   flow that connects to the database: use the *service name* as host, **not**
   localhost. For PostgreSQL that is host `postgres`, port `5432`, database
   `classroom`, user `student`, password `kingo2026`; for Qdrant it is
   `http://qdrant:6333`. (Inside a container, `localhost` means the container
   itself — the most common mistake.)

## KNIME (optional)

KNIME runs on **Windows** itself, not inside Ubuntu: download **KNIME Analytics
Platform** from <https://www.knime.com/downloads> and install it like any other
program. To use the class database from KNIME, create a PostgreSQL connection
with host `localhost`, port `5432`, database `classroom`, username `student`,
password `kingo2026` — the stack must be running (`./kingo up` in Ubuntu) while
you use it.

## If something breaks

1. **`./kingo doctor`** (inside `kingo-pod`) — checks the most common problems.
2. **WSL won't enable / "Virtual Machine Platform" error**: virtualization is
   probably off in your PC's firmware. Restart, enter firmware setup (usually
   F2, F10, or Del at boot), turn on **Virtualization** (Intel VT-x / AMD-V /
   "SVM"), save, and run the setup again.
3. **A port is already in use**: `doctor` names the port. Edit `.env` (in Ubuntu:
   `nano .env`), uncomment the matching `KINGO_PORT_...` line, set a free number,
   save (Ctrl+O, Enter, Ctrl+X), and run `./kingo up` again.
4. **Only 8 GB of RAM / laptop feels slow**: close other apps. If the stack is
   short on memory, create `C:\Users\<you>\.wslconfig` (in Windows) with:

   ```
   [wsl2]
   memory=6GB
   ```

   then run `wsl --shutdown` in PowerShell and start the stack again.
5. **Prefer Docker?** If you install **Docker Desktop** and turn on its **WSL
   integration** for Ubuntu, run `KINGO_ENGINE=docker ./kingo up` inside Ubuntu.
6. Still stuck? Ask the instructor / TA.
