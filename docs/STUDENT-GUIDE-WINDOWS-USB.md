# Kingo Classroom — Windows setup from the USB stick

This is the setup path for the **instructor's USB stick**: the ~14 GB of
container images come from the stick instead of the internet. You still need
Wi-Fi for a few small tools (a few hundred MB) — nothing near the 10 GB of
the normal path.

> **The stick cannot replace Steps 1–2 (WSL2 + Ubuntu).** They need one
> restart and the Microsoft Store — ideally do them **at home, before class**.
> Already done? Jump straight to [Step 3](#step-3--plug-the-stick-in-and-run-setup).

> **Jump to:** [Setup](#step-1--turn-on-wsl2--ubuntu) ·
> [Your services](#step-5--open-your-services) ·
> [Update](#keeping-up-to-date) ·
> [Everyday use](#everyday-use) · [Your files](#your-own-files--the-shared-folder) ·
> [If something breaks](#if-something-breaks) · [FAQ](#faq)

## Keeping up to date

> **Already installed? This one line brings you up to date** — newest class
> files, images and rebuilt containers, safe to run any time, from any folder
> (in **Ubuntu**, not PowerShell):
>
> ```bash
> cd ~/kingo-pod && ./kingo update
> ```
>
> Run it whenever your instructor says so. It works for every install, however
> old — nothing else needs to be re-downloaded by hand.

## Before you start

- **Windows 10 or 11**, with **8 GB RAM** (16 GB recommended).
- About **30 GB free disk space** during setup: the ~14 GB image file and the
  ~14 GB of images it loads sit side by side for a few minutes. The file is
  deleted at the end, leaving **~20 GB** in use. Tighter than that? See
  "Tight on disk space?" in Step 3 — loading straight from the stick needs no
  copy, so ~20 GB is enough.
- The instructor's **USB stick**. It holds two image files; the setup script
  picks the right one for your laptop — you do not need to know which.
- **How long?** Steps 1–2 (WSL2 + Ubuntu, at home): **15–20 minutes**, most of
  it the restart and the Store download. Step 3 in class: **15–20 minutes** —
  ~5–10 to copy off the stick, ~3 to load the images, the rest small tools
  over Wi-Fi.

## Step 1 — Turn on WSL2 + Ubuntu

**Watch this 4-minute video and do exactly what it shows:**
<https://www.youtube.com/watch?v=zZf4YH4WiZo>

It walks you through the three things Windows needs, in order:

1. In the Start menu, search **"Turn Windows features on or off"**, tick
   **Virtual Machine Platform** and **Windows Subsystem for Linux**, click OK.
2. **Restart** your laptop.
3. Open the **Microsoft Store**, search **Ubuntu**, and click **Get/Install**.

The video ends with the first launch of Ubuntu — that's Step 2, below.

> **No Ubuntu after the restart, or it opens and shows an error?** On some
> Windows versions the Store route isn't enough. Open **Command Prompt** from
> the Start menu and run:
>
> ```
> wsl --install
> ```
>
> This installs WSL2 **and** Ubuntu in one go — no Store needed. Approve the
> admin prompt if one appears, restart again if it asks, then continue with
> Step 2.

## Step 2 — First launch of Ubuntu

Open the **Ubuntu** app from the Start menu. The first time, it asks you to
pick a **Linux username and password**. The password stays **invisible while
you type — that's normal**, just type it and press Enter. Remember it: some
commands ask for it later.

✔ You know this step worked when you see a colored prompt ending in `$`.

## Step 3 — Plug the stick in and run setup

> **Pasting into Ubuntu works differently than you are used to:** Ctrl+V
> often does nothing there. **Right-click into the Ubuntu window** to paste
> (on some machines it's Ctrl+Shift+V).

The stick holds **two image files** — `kingo-images-amd64.tar` (for normal
Windows PCs) and `kingo-images-arm64.tar` (for the rare ARM laptop). You do
not have to know which is yours, or which drive letter the stick has: the
setup script finds the stick, picks the file for your machine, and copies it.

**Plug the stick in** — before or after opening Ubuntu, either is fine.
(Windows hands a stick to Ubuntu automatically only when it was plugged in
first; otherwise the script mounts it, which is why Ubuntu may ask for your
password.)

Open the **Ubuntu** app from the Start menu. Copy this command with its
**copy button** (it is one long line), paste it into Ubuntu, and press
**Enter**:

```bash
cd ~ && sudo apt update && sudo apt install -y git && { git clone https://github.com/frankhuettner/kingo-pod.git 2>/dev/null || true; } && cd ~/kingo-pod && git pull --ff-only && bash setup/setup-linux.sh
```

> **Is the file safe?** The setup script checks it before using it: every
> bundle's fingerprint (a SHA-256 checksum) is stored in the class repo the
> line above clones, so it arrives over the internet from GitHub — not on the
> stick. If the copy is damaged, incomplete, or not the class file, the script
> stops and says so instead of loading it.

The copy (~5–10 minutes) is the **only** part that needs the stick. The
script prints **"you can UNPLUG THE STICK NOW"** the moment it is done — from
then on the stick is free for the next student, and everything else runs
without it. **You do not need to "safely remove" it:** nothing is ever written
to the stick, so just unplug it and pass it on. (If Windows says the drive is
*"still in use,"* that is only WSL reading it — it is safe to pull.) The rest
of the script installs the small tools over Wi-Fi, **loads the images from the
copy (~3 minutes)** instead of downloading 10 GB, starts everything, and
verifies it.

**That one command is the whole installation — there is no second command to
run.** When it ends with **`SMOKE OK`** and your table of addresses and logins,
this step is done. **Only if it stopped partway** after the copy, run the line
below to pick it up again — no stick needed:

```bash
cd ~/kingo-pod && bash setup/setup-linux.sh
```

> **Tight on disk space?** If the copy does not fit, the script says so and
> loads straight from the stick instead — keep it plugged in for the whole
> setup then. You can also force that from the start (a re-run needs the stick
> again), replacing `e` with your drive letter:
>
> ```bash
> cd ~ && sudo apt update && sudo apt install -y git && { git clone https://github.com/frankhuettner/kingo-pod.git 2>/dev/null || true; } && cd ~/kingo-pod && git pull --ff-only && bash setup/setup-linux.sh /mnt/e/kingo-images-$(dpkg --print-architecture).tar
> ```

## If the stick isn't found

`no USB bundle found` means the script could not find a stick at all. First
just plug the stick in and run the Step 3 command again — that is usually the
whole fix, and it needs no drive letter. If it still is not found, mount it by
hand; nothing is broken, and you do **not** need to restart anything.

Not sure which drive letter the stick has? This lists your Windows drives
from inside Ubuntu (the stick is the ~64 GB one):

```bash
powershell.exe -NoProfile -Command "Get-Volume | Format-Table DriveLetter,FileSystemLabel,Size"
```

Now mount it by hand (replace `e`/`E:` with your drive letter):

```bash
sudo mkdir -p /mnt/e && sudo mount -t drvfs E: /mnt/e
```

then run setup again — it finds the now-mounted stick by itself (the clone
already happened, so this is shorter than the Step 3 command):

```bash
cd ~/kingo-pod && bash setup/setup-linux.sh
```

Still nothing? Then copy the file in **Windows** instead: open the stick in
Explorer, copy `kingo-images-amd64.tar` into your `Downloads` folder, and run
this in Ubuntu (replace `YourName` with your Windows user name):

```bash
cp /mnt/c/Users/YourName/Downloads/kingo-images-amd64.tar ~/kingo-pod/ && cd ~/kingo-pod && bash setup/setup-linux.sh
```

Next time: plug the stick in before opening Ubuntu.

## Step 4 — Did it work?

You're done when the script prints **`SMOKE OK`** followed by your personal
table of addresses and logins. Reprint it any time with `./kingo credentials`.

The ~14 GB image file is already gone: the script deletes the copy it made
once the smoke test passes — the images live in the container engine now. Only
if you copied a file into the folder **yourself** is one still there; this
removes it:

```bash
rm ~/kingo-pod/kingo-images-*.tar
```

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

**OpenCode** (AI coding in the terminal) runs inside your Ubuntu — install it
once with:

```bash
curl -fsSL https://opencode.ai/install | bash
```

then run `opencode`. The first run asks for an API key; change it anytime with
`opencode auth login`.

## Everyday use

Open the **Ubuntu** app and go to the class folder:

```bash
cd kingo-pod
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

> **What if I just close the Ubuntu window?** Nothing breaks — the stack
> keeps running in the background: your services stay reachable in the
> browser, and it keeps using ~5 GB RAM. It stops only when you run
> `./kingo down` or shut down / restart Windows. Your data survives all of
> these — closed windows, `down`, reboots. After a reboot, open Ubuntu and
> run `./kingo up` again. (Docker Desktop users: the stack may come back by
> itself when Docker starts — `./kingo status` shows what's up.)

### Your own files — the `shared` folder

Your own data files — a CSV, an Excel sheet, a PDF — go into the **`shared`
folder inside `kingo-pod`** (`~/kingo-pod/shared`).
Langflow sees the same folder as **`/app/shared`** — so a file you drop in as
`~/kingo-pod/shared/sales.csv` is `/app/shared/sales.csv` in a Langflow
component, and anything Langflow writes there appears on your laptop, in
the Ubuntu home folder. The folder is created for you; if it isn't there
yet, run `./kingo update` once.

**Where is that folder in Windows?** Ubuntu's files show up in File Explorer.
Open Explorer and follow the left sidebar: **Linux → Ubuntu → home → *your
Linux user name* → kingo-pod → shared** (your user name is the one you picked
in Step 2, so the folder is called something else than `frank` below). You can
also paste `\\wsl.localhost\Ubuntu\home\` into the address bar and click
onwards from there.

![File Explorer at Linux → Ubuntu → home → frank → kingo-pod, with the shared folder highlighted](img/wsl-shared-1-explorer.png)

Drag files in and out like in any other folder — Langflow sees them
immediately, and files Langflow writes appear here.

![The shared folder open in Explorer, next to an Ubuntu terminal in the same folder](img/wsl-shared-2-folder.png)

Quickest way to get there, from Ubuntu — this opens the folder in Explorer:

```bash
cd ~/kingo-pod/shared && explorer.exe .
```

Then right-click **shared** in Explorer's sidebar → **Pin to Quick access**,
and it is one click away from then on.

Treat the folder as **shared with Langflow**: anything running inside Langflow
— including a flow someone else built and you imported — can read, change and
delete files there. So keep private files out of it, and never let it hold the
only copy of something. Nothing outside this one folder is reachable from
Langflow.

> **Using Docker Desktop?** Files that *Langflow itself* writes into the
> folder end up owned by `root` inside Ubuntu — deleting those needs
> `sudo rm`. Files **you** put in are never affected. With Podman (the
> default) this does not happen.

## If something breaks

**Always start with one command** (in Ubuntu, inside `kingo-pod`) — it checks
the usual suspects and tells you what to do:

```bash
./kingo doctor
```

| What you see | What to do |
|---|---|
| WSL won't enable / "Virtual Machine Platform" error | Virtualization is off in your PC's firmware. Restart, enter firmware setup (usually F2, F10, or Del during boot), enable **Virtualization** (Intel VT-x / AMD-V / "SVM"), save, run Step 1 again. |
| No Ubuntu after the restart, or Ubuntu opens and errors (`WslRegisterDistribution failed`) | In Command Prompt run `wsl --install` — it installs WSL2 **and** Ubuntu in one go, no Store needed. Restart if asked, then continue at Step 2. |
| `ERROR: could not install a working Compose v2` | Your network is blocking a download. Re-run the setup script on a different network (phone hotspot works), or run the command the error prints and screenshot what it says. |
| `Cannot connect to the Docker daemon at unix:///run/user/…/podman.sock` | Podman's API socket is off. Run `systemctl --user enable --now podman.socket`, then `./kingo up`. (Current versions of setup and `kingo` do this automatically — `git pull` gets you there.) |
| `this Ubuntu is running under WSL 1` | In Windows PowerShell run `wsl --set-version Ubuntu 2` (takes a few minutes), then reopen Ubuntu and re-run the setup script. |
| `Other software on this machine is already using ports Kingo needs` | Run `./kingo fixports`, then `./kingo up`. Kingo moves itself to free ports — your other software is untouched. Your addresses change; `./kingo credentials` shows the new ones. |
| Same message right **after** `./kingo down`, but you started nothing new | No real collision — the port forwarding didn't let go. First just run `./kingo up` again (current `kingo` frees such leftovers where it can — get it: `./kingo update`). If it persists: `./kingo fixports` moves past it, or run `wsl --shutdown` in Command Prompt (Windows) and reopen Ubuntu — **note**: that stops everything running in WSL (including Docker Desktop's backend), not just Kingo. |
| `The Kingo stack is ALREADY RUNNING under your other engine` | Nothing is broken — the stack is up under your other container engine. Follow the two commands the message prints. |
| `ALL of Kingo's ports are busy` | The stack is most likely **already running** (possibly under your other engine). Run `./kingo status` — if services show `up`, you're done, nothing is wrong. |
| I have Docker Desktop, but setup installed Podman | Docker wasn't running or its WSL integration was off during setup. Both engines work — no need to change anything. To switch anyway: turn on WSL integration for Ubuntu, then `./kingo down` (stops the Podman stack **first**), then `echo KINGO_ENGINE=docker >> .env.local`, then `./kingo up`. |
| Laptop feels slow (8 GB machines) | The stack needs ~5 GB RAM. Close other apps. If it stays bad, create the file `C:\Users\<you>\.wslconfig` **in Windows** containing `[wsl2]` on one line and `memory=5GB` on the next, run `wsl --shutdown` in PowerShell, then start the stack again. |
| Ubuntu terminal says `./kingo: No such file or directory` | You're in the wrong folder. Run `cd ~/kingo-pod` first. |
| USB stick: `bundle file not found` | See "[If the stick isn't found](#if-the-stick-isnt-found)" above. |
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
