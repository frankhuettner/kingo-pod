# CLAUDE.md — notes for AI agents editing this repo

**Kingo Classroom**: the classroom stack run natively (Podman/Docker, no VM),
ported from the old `kingo-vm` repo. Design and rationale live in
[`PLAN-NATIVE-STACK.md`](PLAN-NATIVE-STACK.md); support recipes in
[`docs/INSTRUCTOR.md`](docs/INSTRUCTOR.md).

Every rule below has a scar behind it — a bug that reached students. Rules are
kept short; the full incident write-ups are in this file's history
(`git log -p CLAUDE.md`).

## Security and ports

- **Every published port binds to `127.0.0.1`** (`127.0.0.1:${KINGO_PORT_X:-N}:N`).
  Native compose would otherwise publish on `0.0.0.0` and expose the well-known
  class credentials to the whole Wi-Fi. `kingo smoke` asserts it.
- **Credentials are public by design** and committed in `.env`; safe only
  because everything is loopback-bound. Keep the "no real keys in shared n8n
  exports" warning.
- **Per-machine state lives in `.env.local`** (gitignored, sourced after `.env`;
  a value typed on the command line still wins — the `_cli_overrides` rule).
  Students are never told to edit the committed `.env`: it would break
  `kingo update`'s pull. Setup pins the engine there, `kingo fixports` writes
  moved ports there.
- **Port collisions are auto-resolved, never fatal mid-boot**: `up` preflights
  all 10 host ports (incl. Qdrant gRPC 6334) and points at `kingo fixports`.
  When ALL ports of the current mode are busy at once (`all_active_busy`),
  doctor/fixports/up refuse with "the stack is probably already running under
  the other engine" — remapping would be exactly wrong then.
- **All parsing of `ps --format '{{.Ports}}'` goes through
  `published_host_ports`**, which expands podman's port RANGES
  (`6333-6334->6333-6334`). A bare `:[0-9]+->` grep misses Qdrant's second port,
  and a missed port makes our own service look foreign: fixports moved Qdrant on
  every re-run, status said DOWN, up refused a running stack (issue #1 / PR #2).
- **Leaked gvproxy forwards** (macOS: a host port still LISTENing after `down`)
  are released by `down` and the `up` preflight ONLY when provably orphaned:
  gvproxy lists the forward AND no running podman container publishes the port;
  if `podman ps` fails, touch nothing. The all-ports-busy path is deliberately
  not auto-healed. Never advise an engine/machine restart in guides or error
  text without the "stops ALL your containers" warning — students run
  containers from other courses.

## Engines, images, builds

- **Compose provider is the `docker-compose` binary**, never `podman-compose`
  (no `depends_on: condition: service_healthy`, no build semantics).
- **A running Docker (Desktop) is a first-class engine**: both setup scripts
  detect and use it, installing nothing; Podman is installed only when no
  working engine exists. Do not make the guides Podman-only.
- **Two images are built locally**, tagged `*:local`: JupyterHub
  (`jupyterhub/Dockerfile` — no published image runs hub+Lab standalone) and
  Langflow (`langflow/Dockerfile` — upstream + `langflow/requirements.txt` +
  `uv`). Anything that special-cases one (pull's base-image list, bundle, load's
  retag) must handle both. `pull` builds them only when MISSING
  (`build_missing`; a USB `load` brings images without build cache), `update`
  alone forces a build, `smoke` checks the hub can launch a Lab whenever the
  mode runs it.
- **JupyterLab (:8888) stays** although JupyterHub exists — the Jupyter MCP
  server points at it.
- **Class-wide Python packages go in `langflow/requirements.txt`**;
  `kingo langflow pip install` is ephemeral by design. The Dockerfile installs
  them with `uv pip install --python /app/.venv/bin/python`: since 1.12 the
  UBI base puts a second venv (`/opt/app-root`, with its own pip) on PATH, and
  a bare `pip` can install where Langflow never imports. ragas 0.4.3, its last
  release, imports a module langchain-community 0.4 removed;
  `langflow/vertexai-stub.py` stands in for it, and the build's closing
  `import ragas` is the guard — keep it. A
  COMPILED package (pyarrow, numpy, pandas) is upgraded in the build, never
  under a running server: the process keeps the old shared library mapped and
  the next lazy import mixes the two ("IpcReadOptions size changed"). For a
  machine already in that state the fix is `./kingo restart langflow`, which
  keeps the pip installs; `down`+`up` "fixes" it by wiping them.
- **`langflow-data` is mounted `:z`**: Langflow copies its avatar SVGs with
  `shutil.copytree`, xattrs included, so on the Fedora CoreOS machine every
  later container gets EACCES on them (SELinux MCS labels — root does not help).
  `:z` relabels at mount; a no-op without SELinux. "Can list it, cannot open
  it" on any volume means SELinux, not `chmod`.
- **Exact health codes are the source of truth**: `8888/api→200`,
  `8000/hub/api→200`, `4040/mcp→401`, `7860/health→200`, `5678/healthz→200`,
  `3000/api/health→200`, `8978/→200|301|302`, `6333/readyz→200`, `5432 tcp`.
  "Any answer counts" once passed a crash-looping service.
- **Metabase pre-setup is idempotent** (setup-token check), non-fatal, and runs
  on every `up` in a mode that has Metabase.
- **CI runs two boot cycles** (up → down → up → smoke) plus a mode cycle; the
  second boot catches first-run-only survivors.

## `kingo update` (`cmd_update` — keep every property)

- **One command updates EVERY install kind**: git folders fetch and
  fast-forward; no-git folders (Mac ZIP installs from before 2026-08-29) fetch
  the repo tarball and rsync it over the folder — rsync's rename-replace makes
  overwriting the running script safe. Never fatal offline (degrades to
  images-only); every step on the ZIP path is guarded against `set -e`. Do not
  remove the tarball fallback while such folders may exist, and do not tell
  those students to re-download by hand.
- **No engine check before the fetch** — a student with a broken engine must
  still get the fix; `cmd_pull` gates it. **`update` ends by calling `cmd_up`**,
  never a bare `compose up -d`, which skipped preflight, off-mode cleanup, the
  health wait, first-run init and the status table.
- **The git path splits `fetch` from `merge --ff-only` and merges the tracking
  branch (`@{upstream}`), never `FETCH_HEAD`**: on a detached HEAD or a branch
  without upstream, `merge FETCH_HEAD` exits 0 "Already up to date" while the
  folder sits behind, and update silently never delivered files again. No
  upstream is its own warned case. The merge runs with `LC_ALL=C` and without
  `--quiet 2>/dev/null` because its failure is diagnosed: a DIRTY tree
  (`--untracked-files=no` — a stray file is not a local change) gets the
  `git checkout -- .` advice; a CLEAN tree means diverged history (a student's
  own commit, or a rewritten `main`) and gets git's `fatal:`/`error:` line plus
  a pointer to INSTRUCTOR.md "A folder that cannot update", whose recipe is
  `git checkout -B main origin/main`, NOT `git reset --hard` (a reset re-creates
  the same dead end).
- **It re-execs ONCE when the fetch changed what this process already read**:
  bash keeps executing the copy it opened, so a fix in update's own path would
  never run in the update that fetched it (2026-09-14). Re-exec only after a
  successful fetch AND only when `update_fingerprint` (covers `kingo` AND
  `.env`) changed, and only if the fetched script actually RUNS
  (`update_probe_ok` runs `bash <new> help` in the scrubbed env — `bash -n`
  only parses). The pre-fetch version travels in `KINGO_UPDATE_FROM` for the
  "X → Y" line. Stage 2 is recognised ONLY by `KINGO_UPDATE_STAGE=2` in
  `_cli_overrides`, the real environment — from the plain variable it could
  come from `.env.local` and disable every future fetch. The exec targets
  `$KINGO_DIR/kingo`, resolved before the scrub, never `$0`. The guard is
  deliberately not setup's `KINGO_NO_SELFUPDATE`.
- **Stage 2 gets the environment a FRESH run would see** (`update_scrub_env`):
  stage 1 sourced `.env`/`.env.local` with auto-export before the fetch, and
  compose gives the shell environment precedence over `.env`, so passing it on
  would let stale values outrank the fetched files. Unset every name those files
  assign (`TZ`, `LANGFLOW_SECRET_KEY`, `COMPOSE_PROFILES` leak too; `export
  NAME=` counts), collected BEFORE the fetch as well (`_env_keys_before` — a
  name the new `.env` drops appears in no file afterwards), then re-export only
  `_cli_overrides` so a typed `KINGO_MODE=x ./kingo update` still wins.

## Podman storage: ghost containers (`heal_ghost_containers`, `heal_ghosts_report`)

- After an unclean shutdown podman can keep a `kingo-*` NAME reserved in its
  storage layer while the container is gone from `podman ps -a`; `compose up`
  then dies with "container name … already in use … by an external entity" and
  `doctor` truthfully sees nothing running (2026-09-14; it survives a Store
  "reinstall" of Ubuntu). `up` and `update` heal this first.
- **Heal ONLY names absent from `podman ps -a` AND present in
  `podman ps -a --external`**, by ID. A name podman still manages — ours or
  another course's — is never touched; if podman cannot list, touch nothing.
  Podman-only, no-op on Docker.
- **Sample `--external` BEFORE `podman ps -a`**: a container created between
  the two reads (a second terminal running `up`) would otherwise look like a
  ghost and be force-removed live. The reverse race is harmless.
- **Try plain `podman rm`, then `podman rm -f`** — they fail in different
  places (plain refuses while the mount count says mounted; `-f` forces it down
  and then fails at `rmdir` with "directory not empty"). `rm --storage` is NOT a
  third option: a hidden no-op since podman 3.0, rejected outright by the macOS
  remote client. `podman rm --help` on a Mac shows the remote client's flags,
  not a student's Linux podman (cost a support round).
- **Judge success by the NAME being free again** (`ghost_name_gone`), never by
  exit status: `rm -f` exits 0 for an ID it cannot resolve.
- **Keep the error line PER ghost**, and raise the loud instructor block plus
  `die` ONLY for a ghost whose service runs in the CURRENT mode (else compose's
  generic error would bury it); a ghost that blocks nothing gets one quiet
  line, not the full alarm on every `up` forever. Print podman's `Error:` line
  only (stderr carries logrus noise) and take ONE match when extracting the
  directory — podman names it twice, and a `grep -o` that matched both handed a
  student a path with an embedded newline (2026-09-15).
- **"directory not empty" = leftover FILES in a dead container's directory**,
  not a live mount: a WSL/machine restart does not cure it and must not be
  advised. The recipe is INSTRUCTOR.md "Stale container storage" (umount →
  `rm -rf` → `podman rm -f` → `up`; inside `podman machine ssh` on a Mac;
  rootless needs `podman unshare`). Never `rm -rf` inside the storage graph
  from `kingo` itself, and warn AGAINST `podman system reset` / `podman machine
  reset`: they delete every volume, i.e. the student's data.

## Modes (compose profiles named after the modes)

- Modes are `full abp bi langflow n8n`; every service lists its modes as
  profiles, postgres has none. `kingo` exports `COMPOSE_PROFILES=$KINGO_MODE`.
  **`compose_all()` adds `--profile full`** — which REPLACES, not unions; it
  shows everything only because every profiled service lists `full`, enforced
  by `assert_modes` — **and MUST be used by `down`, `reset`, `pull`, `bundle`,
  `assert_loopback` and CI diagnostics**, or inactive profiles' containers stay
  attached and podman cannot remove the network. `service_modes()` mirrors
  compose.yml and `smoke` asserts they agree.
- Compose never stops what a disabled profile owns: `up` removes off-mode
  containers (`stop_off_services`); `status`/`smoke` flag any still running.
- **UNSET mode = `full`** (the pre-modes cohort keeps every service across
  update). The committed `.env` carries `COMPOSE_PROFILES=full` for exactly one
  reader, the pre-modes `kingo` running after its own pull; the new script
  overrides it.
- **Setup pins `abp` on a FRESH install only** (a `.env.local`, `kingo-*`
  containers or `kingo_*` volumes mean existing — keep the mode; a stopped Mac
  machine is started to look). The pin is written with the engine pin AFTER
  the engine step, so an early death leaves no half-made `.env.local`. A
  `KINGO_MODE` from the environment is validated on a fresh install and dropped
  on an existing one; `cmd_mode` refuses when the environment overrides the
  file; CI never exports it.
- **`pull`/`update`/`build` are mode-agnostic** — every image is always local,
  so a class-day `mode full` never downloads. `mode` checks the target's images
  and ports before writing anything, warns (never refuses) below a mode's
  floor, and on Podman-on-Mac resizes the machine (applehv has no balloon),
  asking for a typed `yes` only when foreign containers run. **ONE sizing
  rule, `mode_cap_mb`** (target capped so macOS keeps 3 GB), shared by setup's
  `machine init`, doctor and `mode`. A memory pin is written only after the
  resize succeeded; `resize_machine` never dies. The memory table
  (`mode_mem_mb`/`mode_floor_mb`, measured 2026-09-05; INSTRUCTOR.md "Modes")
  is the one place to retune; a Langflow upgrade is not a memory lever. On WSL
  `kingo memory` never hands out a `.wslconfig` recipe (Frank's call,
  2026-09-05).

## USB bundles (`kingo bundle` / `load` / `findbundle`)

- **A bundle is only "written" once it VERIFIES**: `docker-archive` cannot
  carry zstd layers (n8n 2.x), `save` stops there and still exits 0, and the
  image order is random, so file size proves nothing — only the manifest's
  image count does. `cmd_bundle` converts zstd images via skopeo, writes
  `$out.part`, checks it against the expected image list, then moves it into
  place. Never delete the previous bundle up front. A missing skopeo only
  WARNS: the arm64 store is all-gzip and bundles fine without it. (issue #3 /
  PR #4)
- **Bundles are single-architecture and arch-stamped**
  (`kingo-images-<arch>.tar`); setup and the copy commands auto-pick the host
  arch, `kingo load` refuses a mismatch (it would load fine and crash at `up`).
  Keep the plain name only as an auto-detect fallback.
- **The checksum travels by git, never on the stick**: `kingo bundle` records
  the tar's sha256 in the committed `bundles.sha256` (`record_bundle_sum`
  replaces only its own line — two tars from two machines); `kingo load`
  refuses a mismatch, and loads with a warning when there is no entry or no
  file at all.
- **The stick is found FOR the student** (`discover_bundle`: this folder,
  mounted media, then on WSL the Windows drives Ubuntu lacks — WSL2 auto-mounts
  only drives present at start). Never remount a mounted non-empty drive
  (`/mnt/c`); the mount uses `sudo -n` and never prompts (most students have
  no stick); keep the copy-then-"UNPLUG THE STICK NOW" flow so one stick
  serves a room.
- **Setup deletes only the bundle IT copied** (`COPIED_BUNDLE`, ~14 GB, after
  smoke passes); a tar the student put there, or the file on the stick, is
  never touched. A USB setup peaks near 30 GB (layers stored uncompressed),
  which is what the USB guides ask for.

## Guides and the website

- **The guides in `docs/` ARE the website**: `site/` (Astro) publishes them at
  <https://huettner.io/kingo-pod/>; `site/scripts/sync-docs.mjs` rewrites
  cross-links and image paths at build time. Files stay valid GitHub markdown:
  no front matter, keep the `# Title` line and the `Jump to:` line. Never add a
  `CNAME` here; never let a guide exist in two places.
- **No multi-line command blocks in student guides**: students paste whole
  blocks (sudo's prompt swallows the rest). Every runnable block is ONE
  `&&`-chained line with its own copy button; command menus are tables; ASCII
  diagrams are exempt.
- **Setup guides end when setup ends** (`STUDENT-GUIDE-*`, incl. `If setup
  fails` for install-only failures); everything for the rest of the term lives
  ONCE per platform in `USING-MAC.md` / `USING-WINDOWS.md`. Never move everyday
  material back into a setup guide.
- **`INSTRUCTOR.md` carries the pinned-image table**: change a pin in
  `compose.yml` or either Dockerfile and move that table too.

## Bash (`kingo` runs on macOS bash 3.2)

- **Test a marker line with `case $'\n'"$var"$'\n' in *$'\n'NAME=…$'\n'*)`,
  never `printf | grep -q`**: `grep -q` exits at its first match and SIGPIPEs
  the printf, which `pipefail` reports as failure once the input exceeds a pipe
  buffer (reproduced on bash 3.2 and 5). Close the pattern with `$'\n'` — `=2`
  also matched `=20`.
- Feed a collecting `while` loop with `<<<`, never a pipe (the subshell loses
  the variables). Never `case` textually inside `$( )`. No associative arrays.
- `LC_ALL=C` goes on the command whose output is parsed, not only on the greps.

## Versioning

Semver, and the test for which number moves is always: **can a student get
there with `./kingo update` alone?**

- **MAJOR** — no. Data needs migrating (a PostgreSQL major), or a `kingo`
  command / port / service / `.env` variable students were told to use is gone
  or renamed. The announcement is longer than one line.
- **MINOR** — yes, and something is new: a service, a `kingo` command, a class
  package in `langflow/requirements.txt`, an image bump `update` applies.
- **PATCH** — yes, and nothing is new: fixes, guides, the website, CI.

A release is an annotated git tag AND the same string in the committed
`VERSION` file — **bump the file in the commit you tag**, or `kingo version`
keeps naming the previous release. A file rather than `git describe` because
ZIP-era folders have no `.git`. `kingo version` prints it, `kingo doctor`
echoes it, `kingo update` reports the transition — "send me `./kingo version`"
is the first question in support. `kingo_version()` stays non-fatal and never
calls `select_engine`: a student with a broken engine must still be able to
say what they run.

**Pin bumps ride the `next` branch first** (INSTRUCTOR.md "Trying an update
before the class gets it"): `update` follows `@{upstream}`, so a TA on `next`
gets the bump and `main` sees nothing. `VERSION` there carries `-rc.N`; fixes
are new commits, never a force-push (it strands the TA's folder); release =
fast-forward `main` to `next`, then the tagged `VERSION` commit. The TA backs
up the Langflow and n8n databases first: both migrate on first start and
cannot downgrade.

## Layout

- `compose.yml` — the 9-service stack (ports via `KINGO_PORT_*`; profiles =
  modes).
- `kingo` (bash) — the ONE CLI for Mac, Linux and Windows-in-WSL2; CI-tested
  on Linux with both engines.
- `jupyterhub/`, `cloudbeaver/`, `postgres-init/` — service config;
  `langflow/` — Dockerfile + requirements.txt for the local Langflow build.
- `setup/setup-mac.sh` (brew podman + machine; Homebrew is a guide
  prerequisite — the script refuses to install it, Frank's call) and
  `setup/setup-linux.sh` (apt + podman, also the Windows/WSL path): both
  re-runnable and self-updating (git pull + re-exec once, guarded by
  `KINGO_NO_SELFUPDATE`; mac has no `timeout`, so git's lowSpeed options bound
  stalls). All guides install via the same idempotent clone-or-pull one-liner.
  There is deliberately NO Windows setup script: students enable WSL2 + Ubuntu
  by video, then run setup-linux.sh inside Ubuntu (a .ps1 was tried and
  dropped).
- `docs/` — setup guides (Mac/Windows, internet and USB variants), the two
  everyday guides, the CloudBeaver walkthrough, instructor notes.
- `site/` — the Astro build of `docs/` (`npm run dev` to preview; deployed by
  `.github/workflows/pages.yml`).
- `.github/workflows/ci.yml` — both engines, two boot cycles plus a mode cycle.

## Windows = WSL2, one CLI

Windows students run everything inside **WSL2 Ubuntu** with the bash `kingo` —
NOT a PowerShell port. This deviates from the plan's `podman machine`-on-Windows
idea on purpose: the WSL path gives real Linux Podman (what CI tests and the
stack assumes), one CLI with no drift, and matches the install video. Do not
reintroduce a second CLI.
