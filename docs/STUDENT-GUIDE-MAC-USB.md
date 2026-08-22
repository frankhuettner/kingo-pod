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
- The instructor's **USB stick** with `kingo-images.tar` on it.

## Step 1 — Get the files

1. Open the project on GitHub and click the green **Code** button →
   **Download ZIP**.
2. Double-click the ZIP to unzip it. You get a folder called **`kingo-pod-main`**.
3. Move that folder somewhere easy, e.g. your **Home** folder or **Documents**.

## Step 2 — Install Homebrew (do this while you wait for the stick)

Homebrew is the Mac's standard software installer; the setup script uses it
to install the container engine. **Two groups skip this step**: if typing
`brew --version` in Terminal shows a version number, you already have it —
and if **Docker Desktop is running**, the script installs nothing at all.

Everyone else:

1. Open the **Terminal** app (press ⌘ Space, type *Terminal*, press Enter).
2. Paste this — it is the official installer from [brew.sh](https://brew.sh) —
   and press **Enter**. It asks for your **Mac password** (typing stays
   invisible — that's normal) and takes a few minutes:

   ```
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

3. If the installer ends by printing **"Next steps"** with commands to run,
   copy, paste, and run those too (they put `brew` on your PATH).

## Step 3 — Copy the images from the stick

1. Plug in the USB stick and open it in **Finder**.
2. **Drag `kingo-images.tar` into your `kingo-pod-main` folder.**

The copy takes ~5–10 minutes and is the **only** part that needs the stick —
hand it to the next student as soon as the copy is done. (The stick is only
read, never changed.)

## Step 4 — Run the setup script

1. Open a **new** Terminal window (⌘ N — so it picks up Homebrew).
2. Type `cd ` (with a space after it), **drag the `kingo-pod-main` folder**
   from Finder onto the Terminal window, and press **Enter**.
3. Type this and press **Enter**:

   ```
   bash setup/setup-mac.sh
   ```

The script finds the copied `kingo-images.tar` by itself: it picks a
container engine, checks your ports, **loads the images from the file
(~3 minutes)** instead of downloading them, starts everything, and verifies
it. It is safe to re-run if it stops partway — and a re-run does **not** need
the stick again.

## Step 5 — Did it work?

You're done when the script prints **`SMOKE OK`** followed by your personal
table of addresses and logins. Reprint it any time with `./kingo credentials`.

Now delete the copied image file — it has done its job, and this frees 13 GB:

```
rm kingo-images.tar
```

Everything else — the service addresses and logins, everyday commands
(`./kingo up` / `./kingo down`), troubleshooting, and the FAQ — is in the
[regular Mac guide](STUDENT-GUIDE-MAC.md) from **Step 5 ("Open your
services")** on.

> **Tight on disk space?** Skip the copy and load straight from the stick: in
> Step 4, type `bash setup/setup-mac.sh ` (with a space at the end), **drag
> the `kingo-images.tar` file from the stick** onto the Terminal window, and
> press Enter. The stick must stay plugged in for the whole setup, and a
> re-run needs it again.
