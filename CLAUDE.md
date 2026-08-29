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
- **Langflow is ALSO built locally** (`langflow/Dockerfile`, tag
  `kingo-langflow:local`): upstream Langflow + the class's Python packages
  (`langflow/requirements.txt`, e.g. statsmodels) + `uv` for `kingo langflow`.
  Anything that special-cases the jupyterhub local build (pull's base-image
  list, bundle, load's retag) must handle BOTH `*:local` images. Student
  installs via `kingo langflow pip install` are ephemeral by design (lost on
  container recreation) — class-wide packages go in requirements.txt instead.
- **`kingo update` must reach ZIP-era installs too** (Mac installs from
  before 2026-08-29 came from a ZIP download — no `.git`; since then the Mac
  guide uses the same idempotent clone-or-pull one-liner as Windows): for a
  no-git folder it fetches the repo tarball and rsyncs it over the folder —
  rsync's rename-replace makes overwriting the running script safe. Never
  fatal offline (degrades to images-only). One command updates EVERY install
  kind; don't tell ZIP-era students to re-download by hand, and don't remove
  the tarball fallback while any of those folders may still exist.
- **Metabase pre-setup is idempotent** via the setup-token check and non-fatal
  on failure; it runs on every `kingo up`. (plan §9.4)
- **Credentials are public by design** and committed (`.env`); they are safe
  only because everything is loopback-bound. Keep the "no real keys in shared
  n8n exports" warning.
- **Per-machine state lives in `.env.local`** (gitignored, sourced after
  `.env`; a `KINGO_ENGINE` from the command line still wins). Students are
  NEVER told to edit the committed `.env` — that would break `kingo update`'s
  `git pull`. Setup scripts pin the engine there; `kingo fixports` writes
  moved ports there.
- **Port collisions are auto-resolved, never fatal mid-boot**: `kingo up`
  preflights all 10 host ports (incl. Qdrant gRPC 6334) and points at
  `kingo fixports`, which remaps busy ports into `.env.local`. When ALL 10
  ports are busy at once, doctor/fixports/up must refuse and say "the stack is
  probably already running under the other engine" — remapping would be
  exactly wrong then (happens for real when both engines are installed).
- **Port attribution must expand podman's port RANGES**: podman collapses
  adjacent published ports into ONE range mapping
  (`127.0.0.1:6333-6334->6333-6334/tcp`) — Qdrant's 6333+6334 is exactly
  that. ALL parsing of `ps --format '{{.Ports}}'` goes through
  `published_host_ports`; never reintroduce a bare `:[0-9]+->` grep. A missed
  port makes our OWN running service look foreign: `fixports` then moved
  Qdrant on every setup re-run, `status` said DOWN on a healthy Qdrant, and
  `up` refused on a running stack (issue #1 / PR #2). The healing guard below
  shares the same parser so it can never unexpose a live container's forward.
- **Leaked engine forwards are healed surgically, never by engine restart**:
  on macOS, gvproxy (the podman machine's port forwarder) can keep a host
  port LISTENing after `down` removed its container. (The 2026-08-29 sighting
  of busy 6333/6334 that motivated this turned out to be the range-attribution
  bug above — the stack was in fact running; the healing stays as guarded
  defense-in-depth.) `kingo down` and the `up` preflight drop such forwards via
  gvproxy's forwarder API (host socket, else the in-machine gateway endpoint)
  — but ONLY provably-orphaned ones: gvproxy lists the forward AND no running
  podman container publishes that port; if `podman ps` fails, touch nothing
  (the stack might be running invisibly). The all-ports-busy refusal path is
  deliberately NOT auto-healed. Never advise a blanket engine/machine restart
  in guides or error text without the "stops ALL your containers" warning —
  students may run containers from other courses.
- **A running Docker is a first-class engine, not a grudging fallback**: both
  setup scripts detect an already-running Docker (Desktop) and use it,
  installing nothing; Podman is only installed when no working engine exists.
  Many students arrive with Docker from other courses — the guides' FAQ
  explains the Podman default; do not make the guides Podman-only.
- **Second boot cycle** in CI (up → down → up → smoke): catches first-run-only
  survivors. (plan §9.2)
- **Student guides contain no multi-line command blocks**: students paste
  whole blocks at once (sudo's password prompt then swallows the rest, or an
  up/down menu executes in sequence). Every runnable block is ONE
  `&&`-chained line with its own copy button; command *menus* are markdown
  tables. ASCII diagrams are exempt.
- **USB bundles are single-architecture and arch-stamped**
  (`kingo-images-<arch>.tar`): `save` writes only the host's local image blobs,
  so an arm64 tar exec-format-crashes at `up` on an amd64 laptop. `kingo bundle`
  names by host arch; both setup scripts and the USB-guide copy commands
  auto-pick the host-arch tar; `kingo load` inspects `kingo-jupyterhub:local`'s
  arch and REFUSES a mismatch (else it loads fine, then crashes at `up`). A
  mixed class needs BOTH tars on one stick — build amd64 on an amd64 box, arm64
  on an Apple-Silicon Mac. Do NOT collapse back to a single `kingo-images.tar`
  name (kept only as an auto-detect fallback).

## Layout

- `compose.yml` — the 9-service stack (ports overridable via `KINGO_PORT_*`).
- `kingo` (bash) — the ONE CLI, used on Mac, Linux, and Windows-in-WSL2, and
  CI-tested on Linux with both engines.
- `jupyterhub/`, `cloudbeaver/`, `postgres-init/` — service config, ported as-is.
- `langflow/` — Dockerfile + requirements.txt for the local Langflow build
  (class Python packages + uv).
- `setup/setup-mac.sh` (brew podman + machine; Homebrew itself is a guide
  prerequisite — the script deliberately refuses to install it, Frank's call),
  `setup/setup-linux.sh` (apt+podman, also the Windows/WSL path) — both
  re-runnable AND self-updating (git pull + re-exec once, guarded by
  KINGO_NO_SELFUPDATE; mac has no `timeout`, so it bounds stalls via git's
  lowSpeed options). All guides install via the same idempotent clone-or-pull
  one-liner. There is deliberately NO
  Windows setup script: students enable WSL2 + Ubuntu by following the video
  tutorial in the guide (Frank's call — a .ps1 was tried and dropped as too
  complicated), then run setup-linux.sh inside Ubuntu.
- `docs/` — student guides (Mac/Windows, each in an internet and a USB-stick
  variant) + instructor notes.
- `.github/workflows/ci.yml` — both engines, two boot cycles.

## Windows = WSL2, one CLI

Windows students run everything inside **WSL2 Ubuntu** with the bash `kingo` —
NOT a PowerShell port. This deliberately deviates from the plan's `podman
machine`-on-Windows idea (which the plan flagged for Phase-2 verification): the
WSL path gives real Linux Podman (exactly what CI tests and the stack assumes),
one CLI with no drift, and matches the WSL install video in the guide. Do not
reintroduce a second CLI.
