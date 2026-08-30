# Kingo Classroom — Mac setup from the USB stick

This is the setup path for the **instructor's USB stick**: the ~13 GB of
container images come from the stick instead of the internet. You still need
Wi-Fi for a few small tools (a few hundred MB; up to ~1 GB on a Mac that has
never had Homebrew) — nothing near the 10 GB of the normal path.

Setting up at home with good internet instead? Use the
[regular Mac guide](STUDENT-GUIDE-MAC.md).

## Before you start

- An **Apple-Silicon Mac** (M1 or newer — any Mac from 2021 on).
- **8 GB RAM** (16 GB recommended) and about **25 GB free disk space** during
  setup (you delete the 13 GB image file at the end, leaving ~20 GB in use).
- The instructor's **USB stick**. It holds two image files;
  `kingo-images-arm64.tar` is the one for your Mac (the other, `-amd64`, is
  for Windows PCs).

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

Now delete the copied image file — it has done its job, and this frees 13 GB:

```
rm ~/kingo-pod/kingo-images-*.tar
```

Everything else — the service addresses and logins, everyday commands
(`./kingo up` / `./kingo down`), troubleshooting, and the FAQ — is in the
[regular Mac guide](STUDENT-GUIDE-MAC.md) from **Step 4 ("Open your
services")** on.

> **Tight on disk space?** Skip the copy and load straight from the stick: in
> Step 4, type `cd ~/kingo-pod && bash setup/setup-mac.sh ` (with a space at
> the end), **drag the `kingo-images-arm64.tar` file from the stick** onto the
> Terminal window, and press Enter. The stick must stay plugged in for the
> whole setup, and a re-run needs it again.
