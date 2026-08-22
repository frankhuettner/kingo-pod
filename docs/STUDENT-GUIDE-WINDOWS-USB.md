# Kingo Classroom — Windows setup from the USB stick

This is the setup path for the **instructor's USB stick**: the ~13 GB of
container images come from the stick instead of the internet. You still need
Wi-Fi for a few small tools (a few hundred MB) — nothing near the 10 GB of
the normal path.

Setting up at home with good internet instead? Use the
[regular Windows guide](STUDENT-GUIDE-WINDOWS.md).

> **The stick cannot replace Steps 1–2 (WSL2 + Ubuntu).** They need one
> restart and the Microsoft Store — ideally do them **at home, before class**.
> Already done? Jump straight to [Step 3](#step-3--plug-in-the-stick-first).

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

## Step 3 — Plug in the stick FIRST

Close Ubuntu if it is open, and plug the USB stick in **before opening
Ubuntu** — Ubuntu only sees drives that were present when it started. Check
the stick's drive letter in Windows Explorer (say `E:`); inside Ubuntu the
stick is `/mnt/e` (lowercase).

## Step 4 — Copy the images, pass the stick on, run setup

> **Pasting into Ubuntu works differently than you are used to:** Ctrl+V
> often does nothing there. **Right-click into the Ubuntu window** to paste
> (on some machines it's Ctrl+Shift+V).

Open the **Ubuntu** app from the Start menu. Copy this command with its
**copy button** (it is one long line), paste it into Ubuntu, replace `e`
with your stick's drive letter if it differs, and press **Enter**:

```bash
sudo apt update && sudo apt install -y git && git clone https://github.com/frankhuettner/kingo-pod.git && cp /mnt/e/kingo-images.tar ~/kingo-pod/ && cd ~/kingo-pod && bash setup/setup-linux.sh
```

The `cp` part (~5–10 minutes, right after the clone) is the **only** part
that needs the stick — as soon as the setup output starts, hand the stick to
the next student. (The stick is only read, never changed.) The setup script
finds the copied file by itself: it installs the small tools over Wi-Fi,
**loads the images from the copy (~3 minutes)** instead of downloading
10 GB, starts everything, and verifies it. If it stops partway after the
copy, re-run it — no stick needed:

```bash
cd ~/kingo-pod && bash setup/setup-linux.sh
```

> **Tight on disk space?** Skip the copy and load straight from the stick —
> use this command instead of the one above. The stick must stay plugged in
> for the whole setup, and a re-run needs it again:
>
> ```bash
> sudo apt update && sudo apt install -y git && git clone https://github.com/frankhuettner/kingo-pod.git && cd ~/kingo-pod && bash setup/setup-linux.sh /mnt/e/kingo-images.tar
> ```

## If the stick isn't found

`cp: cannot stat …` (or `bundle file not found`) means the stick isn't
visible inside Ubuntu yet. Mount it by hand (use your drive letter):

```bash
sudo mkdir -p /mnt/e && sudo mount -t drvfs E: /mnt/e
```

then redo the copy and setup (the clone already happened, so not the full
Step 4 command):

```bash
cp /mnt/e/kingo-images.tar ~/kingo-pod/ && cd ~/kingo-pod && bash setup/setup-linux.sh
```

Next time: plug the stick in before opening Ubuntu.

## Step 5 — Did it work?

You're done when the script prints **`SMOKE OK`** followed by your personal
table of addresses and logins. Reprint it any time with `./kingo credentials`.
Open the services in your normal **Windows** browser — WSL2 forwards
`localhost` automatically.

Now delete the copied image file — it has done its job, and this frees 13 GB:

```bash
rm ~/kingo-pod/kingo-images.tar
```

Everything else — the service addresses and logins, everyday commands
(`./kingo up` / `./kingo down`), troubleshooting, and the FAQ — is in the
[regular Windows guide](STUDENT-GUIDE-WINDOWS.md) from **Step 5 ("Open your
services")** on.
