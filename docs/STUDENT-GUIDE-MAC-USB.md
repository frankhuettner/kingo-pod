# Kingo Classroom — Mac setup from the USB stick

This is the setup path for the **instructor's USB stick**: the ~13 GB of
container images come from the stick instead of the internet. You still need
Wi-Fi for a few small tools (a few hundred MB; up to ~1 GB on a Mac that has
never had Homebrew) — nothing near the 10 GB of the normal path.

Setting up at home with good internet instead? Use the
[regular Mac guide](STUDENT-GUIDE-MAC.md).

## Before you start

- An **Apple-Silicon Mac** (M1 or newer — any Mac from 2021 on).
- **8 GB RAM** (16 GB recommended) and about **20 GB free disk space**.
- The instructor's **USB stick** with `kingo-images.tar` on it.

## Step 1 — Get the files

1. Open the project on GitHub and click the green **Code** button →
   **Download ZIP**.
2. Double-click the ZIP to unzip it. You get a folder called **`kingo-pod-main`**.
3. Move that folder somewhere easy, e.g. your **Home** folder or **Documents**.

## Step 2 — Plug in the stick and run setup

1. Plug in the USB stick.
2. Open the **Terminal** app (press ⌘ Space, type *Terminal*, press Enter).
3. Type `cd ` (with a space after it), **drag the `kingo-pod-main` folder**
   from Finder onto the Terminal window, and press **Enter**.
4. Type `bash setup/setup-mac.sh ` (with a space at the end), **drag the
   `kingo-images.tar` file from the stick** onto the Terminal window, and
   press **Enter**.

The script picks a container engine (may ask for your Mac password once —
that's Homebrew, normal), checks your ports, **loads the images from the
stick (~5–10 minutes)** instead of downloading them, starts everything, and
verifies it. It is safe to re-run if it stops partway — it skips what's done.

## Step 3 — Did it work?

You're done when the script prints **`SMOKE OK`** followed by your personal
table of addresses and logins. Reprint it any time with `./kingo credentials`.
Hand the stick to the next student — it is only read, never changed.

Everything else — the service addresses and logins, everyday commands
(`./kingo up` / `./kingo down`), troubleshooting, and the FAQ — is in the
[regular Mac guide](STUDENT-GUIDE-MAC.md) from **Step 3** on.
