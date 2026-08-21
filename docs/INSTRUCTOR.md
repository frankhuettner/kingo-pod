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
  uses ~6 GB RAM while running.
- **Classroom Wi-Fi fallback**: if someone shows up without having pulled the
  images, an offline USB bundle (`kingo bundle` / `kingo load`, planned) lets you
  copy the ~10 GB locally instead of hammering the room's Wi-Fi.

## Setup paths

- **Mac**: `bash setup/setup-mac.sh` — installs Homebrew (if needed), Podman +
  the docker-compose provider, a Podman machine (4 CPU / 6 GB / 40 GB), then
  brings the stack up and smoke-tests it.
- **Windows**: `setup/setup-windows.ps1` (self-elevates) only turns on WSL2 +
  Ubuntu. Students then run `bash setup/setup-linux.sh` **inside Ubuntu**, which
  installs Podman + the Compose v2 provider and brings the stack up. This means
  Windows uses the exact same Linux runtime and the same bash `kingo` CLI as
  Mac/Linux/CI — one code path, no PowerShell port. (Deviates from the plan's
  `podman machine`-on-Windows sketch, which was flagged for Phase-2 verification.)

All setup scripts are **re-runnable**. Docker Desktop is a supported fallback:
`KINGO_ENGINE=docker ./kingo up` (on Windows, enable Docker Desktop's WSL
integration first, then run it inside Ubuntu).

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
2. **Docker Desktop**: blessed as a fallback in the student guides (current
   choice), or Podman-only to keep the guide perfectly linear?
3. **Minimum laptop**: 8 GB RAM / Windows Home supported? Decides whether a
   `kingo up --lite` profile (drop Metabase/CloudBeaver) is worth adding.
4. **USB offline bundle** wanted for day 1?

Full design and rationale: `PLAN-NATIVE-STACK.md` (ported from the old
`kingo-vm` repo).
