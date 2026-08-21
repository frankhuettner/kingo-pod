# Kingo Classroom — Mac setup

Runs on any Apple-Silicon Mac (M1 or newer, i.e. Macs from 2021 on) with at
least **8 GB of RAM** (16 GB recommended) and about **20 GB of free disk
space**. The whole class stack runs in containers on your own Mac — there is
no virtual machine to import anymore.

> **Do this at home, before class.** The very first start downloads about
> **10 GB** of images. On classroom Wi-Fi that is slow and painful; at home it
> is a one-time wait. After that, starting is quick and works offline.

## 1. Get the files

1. Open the project on GitHub and click the green **Code** button →
   **Download ZIP**.
2. Double-click the downloaded ZIP to unzip it. You now have a folder like
   `kingo-classroom`.
3. Move that folder somewhere easy, e.g. your **Home** folder or **Documents**.

## 2. Run the one-time setup

1. Open the **Terminal** app (press ⌘ Space, type *Terminal*, Enter).
2. Type `cd ` (with a space) and then **drag the `kingo-classroom` folder** from
   Finder onto the Terminal window, and press **Enter**.
3. Type this and press **Enter**:

   ```
   bash setup/setup-mac.sh
   ```

The script installs Podman (the container engine) and starts everything. It may
ask for your Mac password once (for Homebrew). **You only do this once.** When
it finishes it prints the list of web addresses below.

*If anything stops halfway, just run the same command again — it is safe to
re-run.*

## 3. Open the services

Open these in Safari or Chrome:

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

(You can reprint this table any time with `./kingo credentials`.)

MCP (*Model Context Protocol*) is how AI assistants such as Claude Desktop,
Claude Code, or Cursor connect to tools. Point yours at the Jupyter MCP
endpoint `http://localhost:4040/mcp` (header
`Authorization: Bearer kingo-mcp-2026`) and it can write and run code in the
class notebook for you.

**OpenCode** (AI coding in the terminal) now runs natively on your Mac — it is
no longer inside the stack. Install it once with:

```
brew install opencode
```

then run `opencode` in any Terminal. The first run asks for an API key; it is
saved and can be changed anytime with `opencode auth login`.

## 4. Everyday use

Open Terminal in the `kingo-classroom` folder (step 2 above) and use:

- **Start**: `./kingo up`  (or open **Podman Desktop** and press start)
- **Stop**: `./kingo down`  — your data (databases, notebooks, workflows) stays
- **Check**: `./kingo status`  — shows which services are up
- **Problems?** `./kingo doctor`  — checks the engine, memory and ports

Podman Desktop (optional, from <https://podman-desktop.io>) gives you the same
thing with start/stop buttons if you prefer clicking to typing.

## How it all fits together

```
┌─ Your Mac ─────────────────────────────────────────────────┐
│                                                            │
│   Browser, KNIME, MCP clients, OpenCode                    │
│       │                                                    │
│       │  always talk to  localhost:<port>                  │
│       ▼  (published on 127.0.0.1 by Podman)                │
│  ┌─ Podman machine — a tiny, invisible Linux VM ───────┐   │
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
2. **From one service to another** — for example an n8n workflow or a Langflow
   flow that connects to the database: use the *service name* as host, **not**
   localhost. For PostgreSQL that is host `postgres`, port `5432`, database
   `classroom`, user `student`, password `kingo2026`; for Qdrant it is
   `http://qdrant:6333`. (Inside a container, `localhost` means the container
   itself — the most common mistake.)

## KNIME (optional)

KNIME runs on your Mac itself, not in a container: download **KNIME Analytics
Platform** from <https://www.knime.com/downloads> and install it like any other
app. To use the class database from KNIME, create a PostgreSQL connection with
host `localhost`, port `5432`, database `classroom`, username `student`,
password `kingo2026` — the stack must be running (`./kingo up`) while you use it.

## If something breaks

1. **`./kingo doctor`** — it checks the most common problems and tells you what
   to fix.
2. **A port is already in use** (e.g. you already run Postgres.app on 5432):
   `./kingo doctor` names the port. Open the `.env` file, uncomment the matching
   `KINGO_PORT_...` line, set a free number, save, and run `./kingo up` again.
   The browser address changes to the new number; nothing else does.
3. **Only 8 GB of RAM / Mac feels slow**: close other apps and browser tabs. The
   stack needs about 6 GB while running.
4. **Podman won't start**: run `podman machine start`, then `./kingo up`. If it
   stays broken, `podman machine stop` then `podman machine start`.
5. **Prefer Docker?** If you already have **Docker Desktop**, you can use it
   instead: start Docker Desktop, then run `KINGO_ENGINE=docker ./kingo up`.
6. Still stuck? Ask the instructor / TA.
