# Kingo Classroom — Native Stack Plan (VM abolished)

> **For the Claude Code instance (or human) executing this plan:** this file is
> self-contained. The source material lives in this repo
> (`github.com/frankhuettner/kingo-vm`, local checkout
> `/Users/frankhuettner/Desktop/YanboVM/FrankVM`). You will create a **new
> repo** (suggested name: `kingo-classroom`) and port the pieces listed below.
> Do not modify the old repo except to archive it.

## 1. Decision & context (2026-08-21)

Frank and colleagues decided to **abolish the VM distribution** (VirtualBox OVA
for Windows, UTM zip for Mac) and instead run the container stack **natively**:

- **Mac**: Podman (podman machine, Apple Hypervisor) — Docker Desktop as fallback
- **Windows**: Podman on WSL2 — Docker Desktop as fallback

Frank slightly prefers **Podman** → the new repo is **podman-first but
engine-agnostic** (everything must also work with Docker, because some students
will already have Docker Desktop installed).

Audience is unchanged: **students with zero IT knowledge**. Required services
(colleague requirement, verbatim: "Langflow, n8n, Postgrsql, Quadrant,
Jupyterhub, OpenCode, and Kmine"): Langflow, n8n, PostgreSQL, Qdrant,
JupyterHub, OpenCode (native laptop install now), KNIME (laptop install,
connects to the stack's PostgreSQL). Plus already in the stack: JupyterLab
(tokenless, required by the Jupyter MCP server), Jupyter MCP server, Metabase,
CloudBeaver.

## 2. Why this works (assessment already done — don't re-litigate)

- The compose stack was **designed host-portable** from the start: the `kingo`
  CLI header says "Works inside the VM ... and on any host running the stack
  directly with Docker Desktop". All state is in named volumes; all images are
  multi-arch (verified: the same stack ran on arm64 (UTM) and amd64
  (VirtualBox) during VM builds).
- The VM's two load-bearing arguments for Docker-over-Podman are **gone**:
  boot-autostart via root daemon (students now start the stack manually) and
  Compose v2 (solved via the provider mechanism, see §4).
- Published ports on podman machine / Docker Desktop are reachable at
  `localhost:<port>` on the host — **all student-facing URLs stay identical**
  to the VM guides.
- Container→container routing by service name (`postgres:5432`,
  `qdrant:6333`) is engine-independent — the guides' routing rules carry over.

Honest trade-offs vs. the VM (communicate to colleagues):
- **Lost**: one-file import; pre-baked first-run state (images pre-pulled,
  Metabase pre-configured, DB migrations done) — must be replaced by an
  idempotent `kingo up` (§6 Phase 1); Ctrl+Alt+Del shutdown; web terminal.
- **Gained**: no nested-VM overhead, native filesystem speed, ~10 GB pulls
  replace a 12 GB image download, stack updates are `kingo update` instead of
  re-downloading an image, students learn real container tooling.
- **Biggest new risk**: WSL2 enablement on student Windows laptops (§7).

## 3. What to port from this repo → new repo

| Old path (this repo) | New repo | Changes |
|---|---|---|
| `stack/docker-compose.yml` | `compose.yml` | Bind all published ports to `127.0.0.1` (see §5 security). Make host ports overridable: `127.0.0.1:${KINGO_PORT_N8N:-5678}:5678` etc. Keep service/container names, volumes, healthchecks, `depends_on: service_healthy`. |
| `stack/jupyterhub/` (Dockerfile + `jupyterhub_config.py`) | `jupyterhub/` | Unchanged. Local build stays (no published multi-arch hub+lab image exists — see §9 lessons). |
| `stack/.env` | `.env` | Unchanged (classroom creds are public-by-design, localhost-only). |
| `stack/kingo` (CLI) | `kingo` | Rework: engine detection (§4), absorb first-run init from `build/guest/bake.sh` (§6 Phase 1), keep the SERVICES health table + credentials table. |
| `build/guest/bake.sh` lines ~140–167 | into `kingo` | Metabase pre-setup (`setup_metabase`, idempotent via setup-token check) + starter-notebook creation. |
| `build/guest/bake.sh` health-check logic (`check`/`wait_all`/`assert_stable`, SERVICES table) | `kingo smoke` | Verbatim port; drop 7681 (ttyd). |
| `docs/STUDENT-GUIDE-MAC.md`, `docs/STUDENT-GUIDE-WINDOWS.md` | `docs/` | Rewrite install section (Podman instead of UTM/VirtualBox). **Keep**: credentials table, MCP explanation, KNIME section, routing rules + n8n→postgres example, architecture diagram (drop the VM box — host → engine VM (invisible) → containers). |
| `LICENSE` (MIT, Frank Huettner 2026) | `LICENSE` | Copy. Repo is intended to become public. |

**Dropped entirely** (do not port): `build/` (image bake, cloud-init, banner,
ctrl-alt-del, kingo-terminal/ttyd, UTM plist template, OVA/zip packaging),
`dist-extras/KINGO-SETUP-WINDOWS.bat`, GitHub Actions image-build workflow,
SSH/2222 forward. OpenCode is no longer baked anywhere — it becomes a native
laptop install documented in the guides (`brew install opencode` on Mac; on
Windows via the official installer/npm — **verify the current Windows story
during Phase 2**; keys per user via `opencode auth login`, nothing changes).

Ports in the new stack (9 services, unchanged numbers): 7860 Langflow,
5678 n8n, 8888 JupyterLab, 8000 JupyterHub, 4040 Jupyter MCP, 3000 Metabase,
8978 CloudBeaver, 6333 Qdrant, 5432 PostgreSQL.

## 4. Engine strategy (the one podman decision that matters)

Use **Compose v2 (the `docker-compose` binary) as podman's compose provider**
— do **NOT** use `podman-compose` (the Python reimplementation): it has gaps
around `depends_on: condition: service_healthy` and build semantics, both of
which this stack relies on. `podman compose` (the built-in subcommand)
auto-delegates to a `docker-compose` binary if one is on PATH and points it at
podman's Docker-compatible socket. The compose binary is Apache-2.0 — no
licensing issue.

- **Mac**: `brew install podman docker-compose`, then
  `podman machine init --cpus 4 --memory 6144 --disk-size 40 --now`.
  Default machine resources (2 CPU / 2 GB) are far too small — the stack needs
  ~6 GB. The setup script must pass these flags.
- **Windows**: prerequisite WSL2 (`wsl --install --no-distribution`, may need
  a reboot → setup script must be re-runnable). Then
  `winget install -e RedHat.Podman`, `podman machine init` (creates the WSL
  distro; memory is governed by WSL2 defaults ≈ 50% RAM — document `.wslconfig`
  tuning in troubleshooting). Compose binary: check whether a winget package
  exists; fallback = download `docker-compose-windows-x86_64.exe` from
  github.com/docker/compose/releases into PATH. **Verify both during Phase 2.**
- **Podman Desktop** (GUI) is optional but recommended in the guides — zero-IT
  students get a dashboard with start/stop buttons and its Compose extension
  can install the provider binary.

`kingo` CLI engine detection (in order): `$KINGO_ENGINE` override → `podman`
(machine running or startable) → `docker`. All CLI verbs (`up`, `down`,
`status`, `update`, `reset`, `smoke`) go through one `compose()` wrapper:
`podman compose ...` or `docker compose ...`. `update` keeps
`pull --ignore-buildable` + explicit `build` (jupyterhub tag is local-only —
plain pull always fails, see §9).

Podman correctness notes (already thought through, trust these):
- `restart: unless-stopped` is accepted by podman and honored while the
  machine runs; irrelevant at boot since students start the stack manually.
- Named volumes only → no SELinux `:z/:Z` labeling needed (machine VM is
  Fedora CoreOS, enforcing). If anyone adds a **bind** mount later, it needs
  `:Z`.
- netavark provides service-name DNS on the default network — compose
  networking works unchanged.

## 5. Security change required by going native

In the VM, NAT isolated the stack; port forwards bound to 127.0.0.1 on the
host. **Natively, compose publishes to 0.0.0.0 by default** → classmates on
the same Wi-Fi could reach a student's n8n/Postgres with the well-known class
credentials. Therefore every port mapping in `compose.yml` MUST be
`127.0.0.1:<port>:<port>`. Verify in `kingo smoke` (assert the listener is on
127.0.0.1 — lesson from the ttyd bug, §9, applied in reverse).

Unchanged rule (public repo): the shared `N8N_ENCRYPTION_KEY` means anyone can
decrypt shared workflow exports → guides keep the "no real API keys in shared
n8n exports" warning.

## 6. Work plan

**Phase 0 — Scaffold & port (mechanical).** New repo `kingo-classroom`
(private at first; `gh repo create frankhuettner/kingo-classroom --private`).
Copy/adapt per §3 table. MIT LICENSE, minimal README, CLAUDE.md pointing here.
*Acceptance:* `./kingo up` on Frank's Mac (podman) brings all 9 services to
the exact health codes in §8, twice in a row (`up → down → up`, the
second-boot lesson from §9).

**Phase 1 — `kingo` CLI rework.** Engine detection + `compose()` wrapper;
absorb `setup_metabase` + starter-notebook into an idempotent init step that
runs inside `kingo up` after health; `kingo smoke` = ported
`check`/`wait_all`/`assert_stable` with exact status codes; `kingo doctor` =
preflight (engine found? machine running? enough memory? ports free? —
suggests `KINGO_PORT_*` overrides on collision). *Acceptance:* fresh
`podman machine rm` → `kingo up` → smoke green → Metabase shows no setup
wizard and has the Classroom DB connected; same once with Docker Desktop
(`KINGO_ENGINE=docker`).

**Phase 2 — Setup scripts + guides.** `setup/setup-mac.sh` (brew, machine
init with resources, `kingo up`) and `setup/setup-windows.ps1` (WSL2 check +
enable, winget podman, compose binary, machine init, `kingo up`) — both
re-runnable/idempotent, both end with the smoke check and print the URL table.
Rewrite the two student guides per §3 (keep credentials table, MCP paragraph,
KNIME section, routing rules; new architecture diagram without the VM box; new
troubleshooting: WSL2/virtualization BIOS, port collisions, low RAM, Wi-Fi
pulls). Instructor doc: "students must run setup **at home before class**"
(~10 GB pull) + classroom fallback (§7). Verify the OpenCode-on-Windows and
compose-binary-winget questions flagged above. *Acceptance:* a colleague (not
Frank) completes setup on Mac and on Windows using only the guide.

**Phase 3 — CI.** GitHub Actions on ubuntu-latest, matrix over engines:
docker (preinstalled) and podman 5 (install, enable socket). Job = compose up
→ ported smoke check → second boot cycle → down. This replaces the old
image-build CI entirely. *Acceptance:* both matrix legs green on main.

**Phase 4 — Rollout extras (nice-to-have).** `kingo bundle` / `kingo load`:
`podman|docker save` all images into one tarball (~8–10 GB) for USB-stick
distribution as the classroom-Wi-Fi fallback. Delete the old repo's GitHub
releases (r6, r7, defective ones) and archive `kingo-vm` (README pointer to
the new repo). Flip `kingo-classroom` public when guides are stable.

## 7. Risks & mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| WSL2 enablement on Windows (BIOS virtualization off, Windows Home quirks, reboot mid-setup) | **High** — this is the #1 support burden | Re-runnable setup script with clear preflight messages; instructor "install party" before day 1; Docker Desktop as fallback (its installer handles WSL2 too); pair students with working setups as helpers |
| ~10 GB first pull on classroom Wi-Fi | High if not pre-empted | Home-setup requirement + Phase 4 USB bundle |
| Port collisions with existing software (5432, 3000, 8888 are common) | Medium | `KINGO_PORT_*` overrides + `kingo doctor` detection |
| 8 GB laptops: stack needs ~6 GB | Medium | Same constraint as the VM had; document minimum specs (8 GB min / 16 GB recommended, ~20 GB disk); consider a `kingo up --lite` profile (no Metabase/CloudBeaver) if it bites |
| podman-compose accidentally used as provider | Medium (silent breakage) | Setup installs the docker-compose binary explicitly; `kingo doctor` asserts the provider |
| Engine drift (works on podman, breaks on docker or vice versa) | Low | CI matrix (Phase 3) |

## 8. Reference — health table & credentials (source of truth)

Health checks (port|path|expected codes — exact codes, no "any answer counts";
4040 answering 401 without the bearer token IS healthy):

```
8888|/api|200  8000|/hub/api|200  4040|/mcp|401  7860|/health|200
5678|/healthz|200  3000|/api/health|200  8978|/|200|301|302
6333|/readyz|200  5432|tcp
```

Credentials (deliberately simple, committed, localhost-only by design — NOT a
leak): Langflow none/auto-login · n8n create-own-account · JupyterLab none
(tokenless, required by MCP) · JupyterHub any username + `kingo2026` ·
Metabase `admin@kingo.local` / `Kingo2026!` · CloudBeaver `student` /
`Kingo2026!` · Qdrant none · PostgreSQL `student` / `kingo2026`, db
`classroom` · MCP bearer `kingo-mcp-2026` · `TZ=Asia/Seoul`.

## 9. Lessons from the VM repo — do NOT relearn these

1. **Assert bind addresses, not just port responses** (the ttyd bug): a
   loopback-only listener passes every localhost check but is dead through
   any forwarding layer. Natively this flips: assert 127.0.0.1 binding (§5).
2. **Exact health codes + stability re-check**: langflow's `/health` once
   answered 200 briefly while crash-looping — hence exact codes,
   `assert_stable` (20 s later: no container in "Restarting", re-check all),
   and a **second full boot cycle** (a first-run-only bug once shipped
   because a single cycle passed).
3. **JupyterHub needs the local build**: no published multi-arch image runs
   hub+lab standalone (official hub image lacks Lab; docker-stacks lack the
   proxy). Hence `pull --ignore-buildable` + explicit `build` + sanity checks
   `docker exec kingo-jupyterhub jupyterhub-singleuser --version` and
   `python3 -c 'import jupyterlab'` — a healthy hub that can't LAUNCH a Lab
   only surfaces at first student login.
4. **Metabase pre-setup is idempotent** via the setup-token check — safe to
   run on every `kingo up`. Non-fatal on failure (worst case: wizard).
5. **JupyterLab (:8888) must stay** even though JupyterHub exists — the
   Jupyter MCP server points at it.
6. **Registry pulls flake** (rate limits on shared IPs) — keep the patient
   retry loops that fail loudly.

## 10. Open questions for Frank/colleagues (answer before/during Phase 2)

1. Is **JupyterHub still needed** when every student runs the stack on their
   own laptop (single user)? It was a colleague requirement for the shared VM;
   natively, JupyterLab alone would be simpler. Keep it for now (cheap), but
   confirm. If a **shared class server** is the hidden motivation, that's a
   different (nice) deployment of the same compose file — worth asking.
2. Docker Desktop explicitly blessed as fallback in the student guides, or
   podman-only to keep the guide linear?
3. Minimum supported laptop (8 GB RAM? Windows Home?) — decides whether the
   `--lite` profile is needed.
4. USB offline bundle wanted for day 1?

## 11. Status of the old VM track (for the record)

Frozen as of 2026-08-21. Last state: arm64 UTM zip rebuilt with all fixes
(bake #4, exit 0) but **never verified/hashed**; final Windows OVA CI run
32439757489 **failed**; `dist/SHA256SUMS.txt` stale; old GitHub releases
(r6/r7/defective) still to be deleted during Phase 4 archival. Nothing from
`dist/` should ever be distributed. `dist/Kingo.utm` is Frank's personal
registered UTM VM — never touch it.
