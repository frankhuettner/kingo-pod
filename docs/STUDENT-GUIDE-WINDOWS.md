# Kingo Classroom — Windows setup

Everything the class uses (Langflow, n8n, JupyterLab, Metabase, a database, …)
runs in containers on your own laptop. On Windows it runs inside **WSL2** —
Windows' built-in Linux. You turn WSL2 on once, then everything is a few
copy-paste commands in an Ubuntu terminal. You do **not** need to be a Linux
expert, and the setup script checks itself and tells you if something needs
fixing.

> **Jump to:** [Before you start](#before-you-start) ·
> [Setup](#step-1--turn-on-wsl2--ubuntu) ·
> [Did it work?](#step-4--did-it-work) · [If setup fails](#if-setup-fails) ·
> [Using the stack](USING-WINDOWS.md)

> **Already installed?** You don't need this page again — starting, stopping,
> updating, your files and fixing things all live in
> **[Using the stack on Windows](USING-WINDOWS.md)**.

## Before you start

- **Windows 10 or 11**, with **8 GB RAM** (16 GB recommended) and about
  **20 GB free disk space**.
- **Do this at home, before class.** Enabling WSL2 may need **one reboot**,
  and the first start downloads about **10 GB** of images. Get both done at
  home so class time isn't lost to downloads.
- **How long?** WSL2 + Ubuntu (Steps 1–2): about **15–20 minutes**, most of it
  the restart and the Store download. The stack (Step 3): a few minutes of
  install plus the 10 GB download — **15–45 minutes** depending on your
  internet. Total: plan **about an hour**, mostly unattended.

> **Already have Docker Desktop?** (e.g. from another course) — perfect, keep
> it. Do Steps 1–2 anyway (WSL2 + Ubuntu are needed either way), then before
> Step 3: open Docker Desktop → **Settings → Resources → WSL integration** →
> turn it **on for Ubuntu**, and leave Docker Desktop running. The setup
> script detects it and uses it — nothing extra gets installed. Everyone else
> gets **Podman** installed inside Ubuntu instead — same stack, same commands,
> no difference in class. (Curious why Podman? See the
> [FAQ](USING-WINDOWS.md#faq).)

## Step 1 — Turn on WSL2 + Ubuntu

**Watch this 4-minute video and do exactly what it shows:**
<https://www.youtube.com/watch?v=zZf4YH4WiZo>

It walks you through the three things Windows needs, in order:

1. In the Start menu, search **"Turn Windows features on or off"**, tick
   **Virtual Machine Platform** and **Windows Subsystem for Linux**, click OK.
2. **Restart** your laptop.
3. Open the **Microsoft Store**, search **Ubuntu**, and click **Get/Install**.

The video ends with the first launch of Ubuntu — that's our Step 2, below.

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

## Step 3 — Install and start the stack (inside Ubuntu)

> **Pasting into Ubuntu works differently than you are used to:** Ctrl+V
> often does nothing there. **Right-click into the Ubuntu window** to paste
> (on some machines it's Ctrl+Shift+V).

Copy this command with its **copy button** (it is one long line), paste it
into the Ubuntu terminal, and press **Enter**:

```bash
cd ~ && sudo apt update && sudo apt install -y git && { git clone https://github.com/frankhuettner/kingo-pod.git 2>/dev/null || true; } && cd ~/kingo-pod && git pull --ff-only && bash setup/setup-linux.sh
```

The script does four things, in order, and says so as it goes:

1. **Picks a container engine** — uses Docker Desktop if you connected it (see
   the box above), otherwise installs Podman inside Ubuntu.
2. **Checks your ports** — if other software already uses a port the class
   needs (for example your own PostgreSQL on 5432), it automatically moves
   Kingo to a free port and tells you.
3. **Downloads and starts everything** (~10 GB on the first run — be patient).
4. **Verifies it** and prints your personal table of addresses and logins.

**That one command is the whole installation — there is no second command to
run.** When it ends with **`SMOKE OK`** and your table of addresses and logins,
Step 3 is done and you go on to Step 4.

**Only if it stopped partway** (Wi-Fi hiccup, closed laptop): run the line
below to pick up where it left off. It is safe to re-run and skips what's
already done — but you do not need it if the setup finished.

```bash
cd ~/kingo-pod && bash setup/setup-linux.sh
```

(Only if the *download* itself broke off and even the re-run fails: delete the
half-finished folder with `rm -rf ~/kingo-pod` and start Step 3 from the top.)

## Step 4 — Did it work?

You're done when the script prints **`SMOKE OK`** followed by a table of web
addresses and logins. **That printed table is the truth for *your* laptop** —
if the script had to move a port in Step 3, your addresses differ from everyone
else's. Reprint it any time (in Ubuntu, inside the `kingo-pod` folder):

```bash
./kingo credentials
```

If the script ended with an ERROR instead, go to
[If setup fails](#if-setup-fails).

## You're set up — what now?

Everything from here on lives on one page: your addresses and logins, the
commands you need day to day, how to get your own files into Langflow, how to
update, and what to do when something breaks —
**[Using the stack on Windows](USING-WINDOWS.md)**. That is the page to bookmark.

The class database has a short walkthrough of its own:
[Using CloudBeaver](CLOUDBEAVER.md).

## If setup fails

**Always start with one command** (in Ubuntu, inside `kingo-pod`) — it checks
the usual suspects and tells you what to do:

```bash
./kingo doctor
```

| What you see | What to do |
|---|---|
| WSL won't enable / "Virtual Machine Platform" error | Virtualization is off in your PC's firmware. Restart, enter firmware setup (usually F2, F10, or Del during boot), enable **Virtualization** (Intel VT-x / AMD-V / "SVM"), save, run Step 1 again. |
| No Ubuntu after the restart, or Ubuntu opens and errors (`WslRegisterDistribution failed`) | In Command Prompt run `wsl --install` — it installs WSL2 **and** Ubuntu in one go, no Store needed. Restart if asked, then continue at Step 2. |
| `this Ubuntu is running under WSL 1` | In Windows PowerShell run `wsl --set-version Ubuntu 2` (takes a few minutes), then reopen Ubuntu and re-run the setup script. |
| `ERROR: could not install a working Compose v2` | Your network is blocking a download. Re-run the setup script on a different network (phone hotspot works), or run the command the error prints and screenshot what it says. |

Anything else — a port already in use, the container engine not starting, the
stack not coming up — is in
[Using the stack on Windows → If something breaks](USING-WINDOWS.md#if-something-breaks).
Still stuck? Screenshot the error and ask the instructor / TA.
