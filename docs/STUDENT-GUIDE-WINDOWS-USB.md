# Kingo Classroom — Windows setup from the USB stick

This is the setup path for the **instructor's USB stick**: the ~13 GB of
container images come from the stick instead of the internet. You still need
Wi-Fi for a few small tools (a few hundred MB) — nothing near the 10 GB of
the normal path.

Setting up at home with good internet instead? Use the
[regular Windows guide](STUDENT-GUIDE-WINDOWS.md).

> **Prerequisite — WSL2 + Ubuntu must already be installed.** That is Steps
> 1–2 of the [regular Windows guide](STUDENT-GUIDE-WINDOWS.md): a 4-minute
> video, one restart, Ubuntu from the Microsoft Store. The stick cannot
> replace that part — if you haven't done it yet, do it first (ideally at
> home; it needs a reboot).

## Step 1 — Plug in the stick FIRST

Plug the USB stick in **before opening Ubuntu** — Ubuntu only sees drives
that were present when it started. Check the stick's drive letter in Windows
Explorer (say `E:`); inside Ubuntu the stick is `/mnt/e` (lowercase).

## Step 2 — Run setup with the stick

Open the **Ubuntu** app from the Start menu and paste this block (right-click
pastes), replacing `e` with your stick's drive letter:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/frankhuettner/kingo-pod.git
cd kingo-pod && bash setup/setup-linux.sh /mnt/e/kingo-images.tar
```

The script installs the small tools over Wi-Fi, **loads the images from the
stick (~5–10 minutes)** instead of downloading 10 GB, starts everything, and
verifies it. It is safe to re-run if it stops partway:

```bash
cd ~/kingo-pod && bash setup/setup-linux.sh /mnt/e/kingo-images.tar
```

**To pass the stick on quickly**: copy the file, hand the stick to the next
person, and run setup without the path — it finds the copy automatically:

```bash
cp /mnt/e/kingo-images.tar ~/kingo-pod/ && cd ~/kingo-pod && bash setup/setup-linux.sh
```

(Afterwards `rm ~/kingo-pod/kingo-images.tar` frees the 13 GB again.)

## If the stick isn't found

`bundle file not found` means the stick isn't visible inside Ubuntu yet.
Mount it by hand (use your drive letter):

```bash
sudo mkdir -p /mnt/e && sudo mount -t drvfs E: /mnt/e
```

then run the Step 2 command again. Next time: plug the stick in before
opening Ubuntu.

## Step 3 — Did it work?

You're done when the script prints **`SMOKE OK`** followed by your personal
table of addresses and logins. Reprint it any time with `./kingo credentials`.
Open the services in your normal **Windows** browser — WSL2 forwards
`localhost` automatically.

Everything else — the service addresses and logins, everyday commands
(`./kingo up` / `./kingo down`), troubleshooting, and the FAQ — is in the
[regular Windows guide](STUDENT-GUIDE-WINDOWS.md) from **Step 4** on.
