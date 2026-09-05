# Kingo Classroom — Windows setup from the USB stick

This is the setup path for the **instructor's USB stick**: the ~14 GB of
container images come from the stick instead of the internet. You still need
Wi-Fi for a few small tools (a few hundred MB) — nothing near the 10 GB of
the normal path.

> **The stick cannot replace Steps 1–2 (WSL2 + Ubuntu).** They need one
> restart and the Microsoft Store — ideally do them **at home, before class**.
> Already done? Jump straight to [Step 3](#step-3--plug-the-stick-in-and-run-setup).

> **Jump to:** [Before you start](#before-you-start) ·
> [Setup](#step-1--turn-on-wsl2--ubuntu) ·
> [Did it work?](#step-4--did-it-work) · [If setup fails](#if-setup-fails) ·
> [Using the stack](USING-WINDOWS.md)

> **Already installed?** You don't need this page again — starting, stopping,
> updating, your files and fixing things all live in
> **[Using the stack on Windows](USING-WINDOWS.md)**.

## Before you start

- **Windows 10 or 11**, with **8 GB RAM** (16 GB recommended). Setup installs
  the class's *abp* set of services (Langflow, n8n, CloudBeaver, database);
  the everyday guide explains how to switch sets later.
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
