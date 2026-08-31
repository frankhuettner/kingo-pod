# Kingo Classroom — Mac setup

Everything the class uses (Langflow, n8n, JupyterLab, Metabase, a database, …)
runs in containers on your own Mac. **One script sets everything up**; the
script checks itself and tells you if something needs fixing.

> **Jump to:** [Before you start](#before-you-start) ·
> [Setup](#step-1--install-homebrew) ·
> [Did it work?](#step-3--did-it-work) · [If setup fails](#if-setup-fails) ·
> [Using the stack](USING-MAC.md)

> **Already installed?** You don't need this page again — starting, stopping,
> updating, your files and fixing things all live in
> **[Using the stack on a Mac](USING-MAC.md)**.

## Before you start

- An **Apple-Silicon Mac** (M1 or newer — any Mac from 2021 on).
- **8 GB RAM** (16 GB recommended) and about **20 GB free disk space**.
- **Do this at home, before class.** The first start downloads about **10 GB**
  of images. On classroom Wi-Fi that is slow and painful; at home it is a
  one-time wait. After that, starting is quick and works offline.
- **How long?** A few minutes of setup plus the 10 GB download —
  **15–45 minutes** depending on your internet, mostly unattended.

> **Already have Docker Desktop?** (e.g. from another course) — perfect, keep
> it. Just make sure Docker Desktop is **running** before Step 2, and you can
> skip Step 1 (Homebrew). The setup script detects Docker and uses it, and
> installs nothing new. Your existing containers, images, and settings are not
> touched. Everyone else gets **Podman** installed instead — same stack, same
> commands, no difference in class. (Curious why Podman? See the
> [FAQ](USING-MAC.md#faq).)

## Step 1 — Install Homebrew

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

## Step 2 — Install and start the stack

One command gets the class folder and runs the setup script. Open a **new**
Terminal window (⌘ N — so it picks up Homebrew), copy this command with its
**copy button** (it is one long line), paste it, and press **Enter**:

```bash
cd ~ && { git clone https://github.com/frankhuettner/kingo-pod.git 2>/dev/null || true; } && cd ~/kingo-pod && git pull --ff-only && bash setup/setup-mac.sh
```

> **A window pops up asking to install the "Command Line Developer Tools"?**
> That can happen if you skipped Homebrew (Docker Desktop users). Click
> **Install**, wait for it to finish, then run the command above again.

> **Set up with the older ZIP instructions before?** Just run the command
> above — it creates a fresh `kingo-pod` folder in your Home folder and keeps
> all your work (your data lives in the container engine, not in the folder).
> Afterwards, delete the old `kingo-pod-main` folder.

The script does four things, in order, and says so as it goes:

1. **Picks a container engine** — uses Docker Desktop if it's already running,
   otherwise installs Podman (a free engine) via Homebrew.
2. **Checks your ports** — if other software on your Mac already uses a port
   the class needs (for example your own PostgreSQL on 5432), it automatically
   moves Kingo to a free port and tells you.
3. **Downloads and starts everything** (~10 GB on the first run — be patient).
4. **Verifies it** and prints your personal table of addresses and logins.

**That one command is the whole installation — there is no second command to
run.** When it ends with **`SMOKE OK`** and your table of addresses and logins,
this step is done.

**You normally do this once** — but the same line is safe to run again any
time, from anywhere: it updates you to the newest class version and skips
everything already done. If it stops partway (Wi-Fi hiccup, closed laptop),
just run it again.

## Step 3 — Did it work?

You're done when the script prints **`SMOKE OK`** followed by a table of web
addresses and logins. **That printed table is the truth for *your* Mac** — if
the script had to move a port in Step 2, your addresses differ from everyone
else's. Reprint it any time:

```
./kingo credentials
```

If the script ended with an ERROR instead, go to
[If setup fails](#if-setup-fails).

## You're set up — what now?

Everything from here on lives on one page: your addresses and logins, the
commands you need day to day, how to get your own files into Langflow, how to
update, and what to do when something breaks —
**[Using the stack on a Mac](USING-MAC.md)**. That is the page to bookmark.

The class database has a short walkthrough of its own:
[Using CloudBeaver](CLOUDBEAVER.md).

## If setup fails

**Always start with one command** — it checks the usual suspects and
tells you what to do:

```
./kingo doctor
```

| What you see | What to do |
|---|---|
| `ERROR: Homebrew is not installed` | Do [Step 1](#step-1--install-homebrew), then re-run the Step 2 command in a **new** Terminal window. |
| A dialog asks to install the **Command Line Developer Tools** | Click **Install**, wait for it to finish, then run the Step 2 command again. |

Anything else — a port already in use, the container engine not starting, the
stack not coming up — is in
[Using the stack on a Mac → If something breaks](USING-MAC.md#if-something-breaks).
Still stuck? Screenshot the error and ask the instructor / TA.
