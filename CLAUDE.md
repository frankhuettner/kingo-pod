# CLAUDE.md — notes for AI agents editing this repo

This is **Kingo Classroom**: the classroom stack run natively (Podman/Docker,
no VM). The full design, rationale, and work plan live in
[`PLAN-NATIVE-STACK.md`](PLAN-NATIVE-STACK.md) — read it before making changes.
It was ported from the old `kingo-vm` repo.

## Invariants — do NOT break these (each has a scar behind it)

- **Every published port binds to `127.0.0.1`** in `compose.yml`
  (`127.0.0.1:${KINGO_PORT_X:-N}:N`). Native compose otherwise publishes on
  `0.0.0.0`, exposing services with the well-known class creds to the whole
  Wi-Fi. `kingo smoke` asserts this. (plan §5)
- **Exact health codes** are the source of truth (plan §8): `8888/api→200`,
  `8000/hub/api→200`, `4040/mcp→401`, `7860/health→200`, `5678/healthz→200`,
  `3000/api/health→200`, `8978/→200|301|302`, `6333/readyz→200`, `5432 tcp`.
  "Any answer counts" once passed while a service was crash-looping.
- **Compose provider = the `docker-compose` binary**, never `podman-compose`
  (it lacks `depends_on: condition: service_healthy` + build semantics). (plan §4)
- **JupyterHub is built locally** (`jupyterhub/Dockerfile`, tag
  `kingo-jupyterhub:local`): no published image runs hub+Lab standalone. So
  `update` uses `pull --ignore-buildable` + an explicit `build`, and `smoke`
  checks the hub can actually launch a Lab. (plan §9.3)
- **JupyterLab (:8888) stays** even though JupyterHub exists — the Jupyter MCP
  server points at it. (plan §9.5)
- **Metabase pre-setup is idempotent** via the setup-token check and non-fatal
  on failure; it runs on every `kingo up`. (plan §9.4)
- **Credentials are public by design** and committed (`.env`); they are safe
  only because everything is loopback-bound. Keep the "no real keys in shared
  n8n exports" warning.
- **Second boot cycle** in CI (up → down → up → smoke): catches first-run-only
  survivors. (plan §9.2)

## Layout

- `compose.yml` — the 9-service stack (ports overridable via `KINGO_PORT_*`).
- `kingo` (bash) — the ONE CLI, used on Mac, Linux, and Windows-in-WSL2, and
  CI-tested on Linux with both engines.
- `jupyterhub/`, `cloudbeaver/`, `postgres-init/` — service config, ported as-is.
- `setup/setup-mac.sh` (brew+podman machine), `setup/setup-linux.sh` (apt+podman,
  also the Windows/WSL path), `setup/setup-windows.ps1` (only enables WSL2 +
  Ubuntu, then hands off to setup-linux.sh) — all re-runnable.
- `docs/` — student guides (Mac/Windows) + instructor notes.
- `.github/workflows/ci.yml` — both engines, two boot cycles.

## Windows = WSL2, one CLI

Windows students run everything inside **WSL2 Ubuntu** with the bash `kingo` —
NOT a PowerShell port. This deliberately deviates from the plan's `podman
machine`-on-Windows idea (which the plan flagged for Phase-2 verification): the
WSL path gives real Linux Podman (exactly what CI tests and the stack assumes),
one CLI with no drift, and matches the WSL install video in the guide. Do not
reintroduce a second CLI.
