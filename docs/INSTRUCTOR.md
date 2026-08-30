# Instructor notes — Kingo Classroom (native stack)

The class stack (Langflow, n8n, PostgreSQL, Qdrant, JupyterHub, JupyterLab,
Jupyter MCP, Metabase, CloudBeaver) now runs **natively in containers on each
student's laptop** with **Podman** (preferred) or **Docker Desktop** — there is
no VM to distribute anymore. KNIME and OpenCode install natively on the laptop.

## The one thing that matters: setup at home

The first `kingo up` downloads **~10 GB** of images, and on Windows enabling
WSL2 can require a reboot. **Students must run the setup script at home, on
their own Wi-Fi, before class.** Put this in the syllabus and repeat it.

- **Run an "install party"** in the first session (or a drop-in hour before day
  1). WSL2 on Windows is the #1 support burden — pair students who are done with
  those still setting up.
- **Minimum specs**: 8 GB RAM (16 GB recommended), ~20 GB free disk. The stack
  gets a ~5 GB budget and idles at ~3 GB (measured 2026-08-21; biggest single
  consumer: Metabase at ~1.2 GB). If 8-GB laptops still struggle, the planned
  `--lite` profile (drop Metabase + CloudBeaver, saves ~1.5 GB) is the next lever.
- **Classroom Wi-Fi fallback (USB bundle)**: if students show up without having
  pulled the images, hand them a USB stick instead of hammering the room's
  Wi-Fi — see the next section.

## USB bundle (day-1 Wi-Fi saver)

**Prepare at home**: `./kingo bundle` writes `kingo-images-<arch>.tar` (13 GB,
measured 2026-08-21) with every image the stack needs, including the
locally-built jupyterhub one. **A bundle is single-architecture** — `save`
writes only the local image blobs, which match the machine that built them —
so an arm64 tar will *not* run on an amd64 laptop, and vice versa. For a mixed
class, build BOTH and put both on each stick:

- On an **Apple-Silicon Mac**: `./kingo bundle` → `kingo-images-arm64.tar`
  (for Mac students).
- On an **amd64 machine** (a Windows PC's WSL2 Ubuntu, or any Intel/AMD Linux
  box): `./kingo bundle` → `kingo-images-amd64.tar` (for Windows students).

With both tars on one stick, students auto-pick the right one for their laptop
(the setup script and the guides' copy commands select by architecture, and
`kingo load` refuses a wrong-arch tar with a clear message). Format the stick
**exFAT** so both Mac and Windows can read it, and size it for **two** 13 GB
files: a **64 GB** stick is comfortable; a 32 GB one fits both only barely, so
prefer one 32 GB stick per architecture if that is all you have. Most sticks
ship as FAT32, which refuses files over 4 GB ("too large for the volume's
format") — reformat first: Disk Utility (Mac) → Erase → format exFAT, scheme
Master Boot Record; or Windows Explorer → right-click the stick → Format… →
exFAT. Reformatting erases the stick. Bring **several sticks**: each student
reads 13 GB from it, so one stick serializes the room. The USB guides therefore default to **copy, pass on,
then install**: the student copies the tar into their `kingo-pod` folder
(~5–10 min, the only step that needs the stick), hands the stick on, and the
setup script picks the copy up automatically — installs overlap instead of
queueing, and a failed setup re-runs without the stick. The guides tell
students to delete the copy after `SMOKE OK` (it costs 13 GB of disk until
then; loading directly from the stick stays documented as the fallback for
disk-tight laptops).

**Commit the checksum after every build.** `kingo bundle` writes the tar's
SHA-256 into `bundles.sha256`; commit and push that file. `kingo load` (and
therefore both setup scripts) then verifies every stick copy against it — and
the trusted value reaches students over HTTPS with `git clone` / `./kingo
update`, never on the stick itself. That catches a truncated copy, a stick
that got corrupted while being passed around, and a tar that is simply not
the class file. Two consequences worth knowing: if you rebuild a bundle and
forget to push, students get a clear "does not match — run ./kingo update
first" refusal; and a bundle with no entry at all loads with a warning, so
older sticks keep working. Students verifying by hand:
`shasum -a 256 <tar>` (Mac) or `sha256sum <tar>` (WSL), compared against
`bundles.sha256`. Cost: hashing 13 GB takes ~1 minute from a laptop's own
disk (the normal copy-then-install path). Only the disk-tight fallback that
loads *straight from the stick* pays a second stick read, which on a slow
USB 2 stick is several minutes — one more reason the guides default to
copying first.

The stick itself is not a trusted channel and never becomes one: nothing is
ever written to it during setup, and nothing on it is executed — the tar is
read-only data that the engine unpacks. If you can get USB sticks with a
physical write-protect switch, use them; that removes the one real risk of
passing a stick around a room of Windows laptops.

**What the student runs** — each platform has a dedicated USB guide to point
stick students at: [`STUDENT-GUIDE-MAC-USB.md`](STUDENT-GUIDE-MAC-USB.md) and
[`STUDENT-GUIDE-WINDOWS-USB.md`](STUDENT-GUIDE-WINDOWS-USB.md). In short:

- **Windows** (WSL2 + Ubuntu must already be done at home — reboot + Store;
  the USB guide repeats those steps): plug the stick in and run the guide's
  paste block — clone, then `bash setup/setup-linux.sh`. **No drive letter,
  no `cp`**: setup asks `kingo findbundle`, which searches the mounted media
  and, on WSL, mounts the Windows drives Ubuntu has not picked up (asking for
  the student's password). That case is the norm, not the exception — WSL2
  only auto-mounts removable drives that were plugged in before it started,
  so a student following the guide literally always hit `cp: cannot stat`.
- **Mac**: the guide's clone one-liner creates `~/kingo-pod`; drag the tar
  from the stick into that folder in Finder, then `cd ~/kingo-pod && bash
  setup/setup-mac.sh` — or skip the drag entirely and let setup find the
  stick under `/Volumes` by itself. Either way it copies the tar in and tells
  the student when the stick can be passed on.
- **Already set up, only images missing**:
  `./kingo load /path/to/kingo-images-<arch>.tar && ./kingo up` does it
  directly (`load` with no path auto-finds this machine's arch tar).

**What still touches the internet** — the stick replaces only the 13 GB image
download, which is the part classroom Wi-Fi can't take. A student starting
from zero still needs Wi-Fi for the small stuff: `git clone` (a few MB) and,
if no engine is present yet, the Podman/compose install (a few hundred MB on
Ubuntu; on a fresh Mac, Homebrew + the Podman machine image, up to ~1 GB).
Once the images are on disk, `kingo pull` skips them one by one, and
`kingo up`/`smoke` make no network requests at all — the whole offline path
(bundle → delete all images → Wi-Fi off → load → up → smoke) is verified
end-to-end (2026-08-21, ~3 min load from local disk; a stick adds its own
read time, plan ~5–10 min).

Bundles are cross-engine: a podman-written bundle is verified live to load
into both podman and Docker Desktop (2026-08-21) — one stick serves the whole
class regardless of engine.

## Setup paths

- **Mac**: Homebrew first — it is its own step in the guides, deliberately
  NOT done by the script (the installer wants a password and pipes a script
  from the internet; that belongs in the student's own hands, visible and
  attributable). The script refuses with instructions if brew is missing and
  no Docker is running. Then the guide's one-liner (idempotent clone-or-pull
  into `~/kingo-pod` + `bash setup/setup-mac.sh` — the same line is install,
  repair, and update; the script also self-updates on re-runs). Setup
  installs Podman + the docker-compose provider via brew, creates a Podman
  machine (4 CPU / 5 GB / 40 GB), then brings the stack up and smoke-tests
  it. (Installs from before 2026-08-29 used a ZIP download instead — no
  `.git`; `kingo update` covers those via a repo-tarball fetch, and the guide
  tells them how to migrate to the clone.)
- **Windows**: no script — students enable WSL2 + Ubuntu by following the
  4-minute video tutorial in the guide (Windows features → Virtual Machine
  Platform + WSL, reboot, Ubuntu from the Microsoft Store), then run
  `bash setup/setup-linux.sh` **inside Ubuntu**, which installs Podman + the
  Compose v2 provider and brings the stack up. On some Windows versions the
  Store route alone doesn't produce a working Ubuntu — the guides carry the
  fallback (`wsl --install` in Command Prompt installs WSL2 + Ubuntu in one
  go), reported by a student 2026-08. Compose v2 comes from apt
  (`docker-compose-v2`), not GitHub — a campus network was seen serving a
  broken file for the GitHub release download while `git clone` worked fine. This means Windows uses the
  exact same Linux runtime and the same bash `kingo` CLI as Mac/Linux/CI —
  one code path, no PowerShell port. (Deviates from the plan's `podman
  machine`-on-Windows sketch, which was flagged for Phase-2 verification.)

All setup scripts are **re-runnable**, and both handle the two most common
"my laptop is different" cases by themselves:

- **Student already has Docker Desktop** (very common): if Docker is *running*
  when the setup script starts (on Windows: WSL integration enabled for
  Ubuntu), the script uses it and installs nothing — it pins
  `KINGO_ENGINE=docker` in `.env.local`. Podman is only installed when no
  working engine is found. Manual override any time:
  `KINGO_ENGINE=docker ./kingo up`.
- **Student already has software on a class port** (their own PostgreSQL on
  5432, a dev server on 3000/8000/8888, …): setup runs `./kingo fixports`,
  which moves Kingo to the next free port and records it in `.env.local`.
  `kingo up` also refuses to start with a busy port and names the fix, instead
  of failing mid-boot with a cryptic compose error. Expect a handful of
  students whose URLs differ from your slides — `./kingo credentials` on their
  machine always prints their actual addresses.

`.env.local` is gitignored, so these per-machine changes never conflict with
`kingo update` (which does a `git pull`). Students are never told to edit the
committed `.env`.

## Python packages in Langflow

Langflow is built locally (`langflow/Dockerfile`) on top of the upstream
image, adding the packages in `langflow/requirements.txt` (statsmodels, …)
plus `uv`. To give the whole class a new package: add one line to
`langflow/requirements.txt`, commit + push, and announce **"run
`./kingo update`"** — that one command works for every install kind
(git installs pull; leftover ZIP-era Mac folders fetch the repo tarball
automatically) and rebuilds the image. A student who needs something just for themselves:
`./kingo langflow pip install <pkg>` (ephemeral — gone after `down`+`up`,
which is fine for one-offs).

## Did this laptop install from the stick, or from the Wi-Fi?

Worth knowing in a full room, and invisible afterwards otherwise: image IDs
are identical either way, and `podman images`' "CREATED" is the upstream build
date, not when the image landed. So `kingo load` writes a note
(`.kingo-install-source`, gitignored) and `./kingo doctor` reads it back:

```
  [ok] images came from a USB bundle: /mnt/e/kingo-images-amd64.tar
       loaded 2026-08-30 14:20:11+0900 — checksum verified against bundles.sha256
```

A machine that downloaded says so instead ("images came from the internet"),
and a stick whose checksum could not be confirmed shows `[??]`, not `[ok]`.
Live during a run, the same thing is visible as `Found the class images on a
USB stick …` / `Copy done — you can UNPLUG THE STICK NOW` / `Checksum OK`, and
`kingo pull` afterwards finishing in seconds instead of minutes.

## Credentials (public by design)

All logins are fixed, simple, and committed to the repo. This is **not** a leak:
every service is published on `127.0.0.1` only, so it is reachable solely from
the student's own machine. See `.env` and `./kingo credentials`.

One real rule to teach: the shared `N8N_ENCRYPTION_KEY` means anyone can decrypt
a shared n8n workflow export — **never put a real API key into a workflow you
share.**

## Verifying a machine

- `./kingo doctor` — preflight (engine ready? memory? ports free?).
- `./kingo smoke` — asserts exact health codes, that nothing is crash-looping,
  that every port is bound to `127.0.0.1`, and that JupyterHub can launch a Lab.

## Open questions to settle (see PLAN-NATIVE-STACK.md §10)

1. **Is JupyterHub still needed** now that every student runs their own
   single-user stack? JupyterLab alone would be simpler. It's kept for now
   (cheap); confirm, or decide it's for a shared class server.
2. ~~**Docker Desktop**: blessed as a fallback, or Podman-only?~~ **Settled**:
   Docker is a first-class engine — the setup scripts auto-detect a running
   Docker Desktop and use it (see "Setup paths"), CI tests both engines.
3. **Minimum laptop**: 8 GB RAM / Windows Home supported? Decides whether a
   `kingo up --lite` profile (drop Metabase/CloudBeaver) is worth adding.
4. **USB offline bundle** wanted for day 1?

Full design and rationale: `PLAN-NATIVE-STACK.md` (ported from the old
`kingo-vm` repo).
