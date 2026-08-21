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
- **Classroom Wi-Fi fallback (USB bundle)**: if someone shows up without having
  pulled the images, hand them a USB stick instead of hammering the room's Wi-Fi.
  Prepare at home: `./kingo bundle` writes `kingo-images.tar` (13 GB, measured
  2026-08-21 — a 16 GB stick is borderline, use 32 GB, exFAT-formatted so both
  Mac and Windows can read it) including the locally-built jupyterhub image, so
  nothing at all is downloaded in class.
  The student (setup Steps done up to the download): plug in the stick, then
  `./kingo load /Volumes/<stick>/kingo-images.tar` (Mac) or
  `./kingo load /mnt/<letter>/kingo-images.tar` (Windows/WSL — the stick's
  drive letter appears under `/mnt/`), then `./kingo up`. Bundles are
  cross-engine: saved with podman, loads into docker and vice versa.

## Setup paths

- **Mac**: `bash setup/setup-mac.sh` — installs Homebrew (if needed), Podman +
  the docker-compose provider, a Podman machine (4 CPU / 5 GB / 40 GB), then
  brings the stack up and smoke-tests it.
- **Windows**: no script — students enable WSL2 + Ubuntu by following the
  4-minute video tutorial in the guide (Windows features → Virtual Machine
  Platform + WSL, reboot, Ubuntu from the Microsoft Store), then run
  `bash setup/setup-linux.sh` **inside Ubuntu**, which installs Podman + the
  Compose v2 provider and brings the stack up. This means Windows uses the
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
