# Kingo Classroom — Mac setup from the USB stick

This is the setup path for the **instructor's USB stick**: the ~14 GB of
container images come from the stick instead of the internet. You still need
Wi-Fi for a few small tools (a few hundred MB; up to ~1 GB on a Mac that has
never had Homebrew) — nothing near the 10 GB of the normal path.

> **Jump to:** [Setup](#step-1--install-homebrew-do-this-while-you-wait-for-the-stick) ·
> [Your services](#step-6--open-your-services) ·
> [Update](#keeping-up-to-date) ·
> [Everyday use](#everyday-use) ·
> [If something breaks](#if-something-breaks) · [FAQ](#faq)

## Keeping up to date

> **Already installed? This one line brings you up to date** — newest class
> files, images and rebuilt containers, safe to run any time, from any folder:
>
> ```
> cd ~/kingo-pod && ./kingo update
> ```
>
> Run it whenever your instructor says so. It works for every install, however
> old — nothing else needs to be re-downloaded by hand.

## Before you start

- An **Apple-Silicon Mac** (M1 or newer — any Mac from 2021 on).
- **8 GB RAM** (16 GB recommended) and about **30 GB free disk space** during
  setup: the ~14 GB image file and the ~14 GB of images it loads sit side by
  side for a few minutes. The file is deleted at the end, leaving **~20 GB**
  in use. Tighter than that? See "Tight on disk space?" in Step 5 — loading
  straight from the stick needs no copy, so ~20 GB is enough.
- The instructor's **USB stick**. It holds two image files;
  `kingo-images-arm64.tar` is the one for your Mac (the other, `-amd64`, is
  for Windows PCs).
- **How long?** About **20–30 minutes**: a few minutes for Homebrew, ~5–10 to
  copy off the stick, ~3 to load the images, the rest small tools over Wi-Fi.

## Step 1 — Install Homebrew (do this while you wait for the stick)

Homebrew is the Mac's standard software installer; the setup script uses it
to install the container engine. **Two groups skip this step**: if typing
`brew --version` in Terminal shows a version number, you already have it —
and if **Docker Desktop is running**, the script installs nothing at all.

Everyone else:

1. Open the **Terminal** app (press ⌘ Space, type *Terminal*, press Enter).
2. Open **<https://brew.sh>** in your browser. Right under "Install Homebrew"
   the page shows one long install command with a copy button — copy it,
   paste it into Terminal, and press **Enter**. It asks for your **Mac
   password** (typing stays invisible — that's normal) and takes a few
   minutes.
3. If the installer ends by printing **"Next steps"** with commands to run,
   copy, paste, and run those too (they put `brew` on your PATH).

## Step 2 — Get the class folder

Open a **new** Terminal window (⌘ N — so it picks up Homebrew), copy this
command with its **copy button** (one long line), paste it, and press
**Enter** — it downloads the class folder (a few MB, this is not the big
download) into your Home folder:

```bash
cd ~ && { git clone https://github.com/frankhuettner/kingo-pod.git 2>/dev/null || true; } && cd ~/kingo-pod && git pull --ff-only
```

> **A window pops up asking to install the "Command Line Developer Tools"?**
> That can happen if you skipped Homebrew (Docker Desktop users). Click
> **Install**, wait for it to finish, then run the command above again.

## Step 3 — Copy the images from the stick

1. Plug in the USB stick and open it in **Finder**.
2. In a second Finder window, open your **Home** folder (Finder menu:
   **Go → Home**) — the `kingo-pod` folder from Step 2 is there.
3. **Drag `kingo-images-arm64.tar` from the stick into the `kingo-pod`
   folder.** (That is the Mac file — ignore `kingo-images-amd64.tar`, which
   is for Windows.)

> **Is the file safe?** The setup script checks it before using it: every
> bundle's fingerprint (a SHA-256 checksum) is stored in the class repo you
> cloned in Step 2, so it arrives over the internet from GitHub — not on the
> stick. If the copy is damaged, incomplete, or not the class file, the script
> stops and says so instead of loading it.

> **Simpler: skip this step.** Leave the stick plugged in and go straight to
> Step 4 — the setup script finds it by itself, copies the file, and **deletes
> that copy again** once everything works, so you never spend 14 GB of disk on
> it. Dragging is just the version you can watch happen; then the file is
> yours and you delete it in Step 5.

The copy takes ~5–10 minutes and is the **only** part that needs the stick —
hand it to the next student as soon as the copy is done. **You do not need to
"eject" it first:** nothing is ever written to the stick, so once the copy
finishes just unplug it and pass it on. (If macOS says *"Disk not ejected
properly,"* that is harmless here — nothing was being written to it.)

## Step 4 — Run the setup script

Copy this into the Terminal window and press **Enter**:

```bash
cd ~/kingo-pod && bash setup/setup-mac.sh
```

The script finds the copied `kingo-images-arm64.tar` by itself: it picks a
container engine, checks your ports, **loads the images from the file
(~3 minutes)** instead of downloading them, starts everything, and verifies
it. It is safe to re-run if it stops partway — and a re-run does **not** need
the stick again.

## Step 5 — Did it work?

You're done when the script prints **`SMOKE OK`** followed by your personal
table of addresses and logins. Reprint it any time with `./kingo credentials`.

The ~14 GB image file is already gone: the script deletes the copy it made
once the smoke test passes — the images live in the container engine now. Only
if you copied a file into the folder **yourself** is one still there; this
removes it:

```
rm ~/kingo-pod/kingo-images-*.tar
```

> **Tight on disk space?** Skip the copy and load straight from the stick: in
> Step 4, type `cd ~/kingo-pod && bash setup/setup-mac.sh ` (with a space at
> the end), **drag the `kingo-images-arm64.tar` file from the stick** onto the
> Terminal window, and press Enter. The stick must stay plugged in for the
> whole setup, and a re-run needs it again.

## Step 6 — Open your services

Default addresses (yours may differ — see Step 5). Open them in Safari or Chrome:

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
| `./kingo update` | get the newest class files + images (run it when the instructor announces an update) |

> **What if I just close the Terminal window?** Nothing breaks — the stack
> keeps running in the background: your services stay reachable in the
> browser, and it keeps using ~5 GB RAM. It stops only when you run
> `./kingo down` or shut down / restart the Mac. Your data survives all of
> these — closed windows, `down`, reboots. After a reboot, run `./kingo up`
> again. (Docker Desktop users: the stack may come back by itself when
> Docker starts — `./kingo status` shows what's up.)

## If something breaks

**Always start with one command** — it checks the usual suspects and tells you
what to do:

```
./kingo doctor
```

| What you see | What to do |
|---|---|
| `ERROR: Homebrew is not installed` | Do [Step 1](#step-1--install-homebrew-do-this-while-you-wait-for-the-stick), then re-run the Step 4 command in a **new** Terminal window. |
| A dialog asks to install the **Command Line Developer Tools** | Click **Install**, wait for it to finish, then run the Step 4 command again. |
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

**How do I get my own files into Langflow?**

Put them in the **`shared` folder inside `kingo-pod`** (`~/kingo-pod/shared`).
Langflow sees the same folder as **`/app/shared`** — so a file you drop in as
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
