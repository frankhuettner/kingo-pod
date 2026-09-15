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
  `pull` skips the `*:local` tags and builds them only when MISSING
  (`build_missing` — `up` builds only the active mode's, and a USB `load`
  brings images without build cache, so a forced rebuild would need the
  network), `update` alone forces a `build`, and `smoke` checks the hub can
  actually launch a Lab whenever the mode runs it. (plan §9.3)
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
- **`kingo update` is two-stage: it re-execs ONCE when the fetch actually
  replaced `kingo` itself** (`cmd_update` / `update_reexec`): bash keeps
  executing the copy of the script it opened, so a fix living in `update`'s own
  path (the ghost healing) would never run in the update that fetched it — a
  student needed a second command for exactly that (2026-09-14). Properties,
  keep ALL of them: re-exec only after a successful fetch AND only when
  `update_fingerprint` CHANGED (a pull that is already up to date exits 0 and
  changes nothing — re-execing then printed a confusing second start on every
  update); only if the fetched script actually RUNS (`update_probe_ok` runs
  `bash <new> help` in the scrubbed env — `bash -n` merely parses and misses a
  preamble `die`, and its old warning told students to run a `./kingo version`
  that could not parse); the pre-fetch version travels in `KINGO_UPDATE_FROM`
  so the "X → Y" line support asks for survives; stage 2 is recognised ONLY by
  a `KINGO_UPDATE_STAGE=2` in `_cli_overrides` (the REAL environment) — read
  from the plain variable it could come from `.env.local` and silently disable
  every future fetch; identical for git and ZIP/rsync installs. **Stage 2 must
  get the environment a FRESH run would see** (`update_scrub_env`): stage 1
  sourced `.env`/`.env.local` with auto-export BEFORE the fetch, so passing its
  environment on would let those stale values outrank the freshly fetched files
  via the `_cli_overrides` rule — so unset every name those files assign (not
  just `KINGO_*`; `TZ`, `LANGFLOW_SECRET_KEY`, `COMPOSE_PROFILES` leak too) and
  re-export only `_cli_overrides`, so a typed `KINGO_MODE=x ./kingo update`
  still wins. That name list must be taken BEFORE the fetch as well
  (`_env_keys_before`): a name the OLD `.env` exported and the NEW one DROPS
  appears in no file afterwards, so a list read only from the fetched files
  leaves it set, and compose gives the shell environment precedence over
  `.env` — the containers would start once on a value the update deleted. It
  matches `export NAME=` too, since bash sources that just as happily. The
  exec targets `$KINGO_DIR/kingo`, resolved BEFORE the scrub
  unsets `KINGO_DIR`, never `$0` (the preamble has cd'ed). No engine check runs
  before the fetch — a student whose engine is broken must still be able to
  fetch the fix; `cmd_pull` gates it. `update` ENDS BY CALLING `cmd_up`, not a
  bare `compose up -d`: the old tail skipped the port preflight, off-mode
  cleanup, the health wait, first-run init and the status table, so an update
  could report success while a service was down. The guard is deliberately NOT
  setup's `KINGO_NO_SELFUPDATE`. The git path SPLITS `fetch` from `merge
  --ff-only` and distinguishes the two ways the merge can fail: a dirty tree
  gets the `git checkout -- .` advice, a CLEAN tree means the history diverged
  (a student's own commit, or `main` was rewritten) and gets git's own
  `fatal:`/`error:` line plus a pointer to docs/INSTRUCTOR.md "A folder that
  cannot update" — which is why the merge no longer runs `--quiet 2>/dev/null`.
  Telling a clean-tree student to run `git checkout -- .` is advice that can
  never work, and `update` would repeat it forever.
  The merge targets the TRACKING BRANCH (`@{upstream}`), never `FETCH_HEAD`:
  with a detached HEAD or a branch without an upstream every FETCH_HEAD line is
  `not-for-merge`, and `git merge --ff-only FETCH_HEAD` then exits 0 with
  "Already up to date." while the folder sits commits behind — `update` reported
  success and silently never delivered class files again (verified; the
  `git pull --ff-only` it replaced failed loudly). No upstream is therefore its
  own warned case, and INSTRUCTOR.md's recipe is `git checkout -B main
  origin/main`, NOT `git reset --hard origin/main`: a reset moves whatever ref
  HEAD is on and re-creates the same dead end. The dirty-tree test uses
  `--untracked-files=no` — a stray untracked file is not a local change to
  undo, and counting it sent diverged folders back into the dead-end advice.
  `LC_ALL=C` belongs on the `git merge` itself, not only on the greps that
  parse its output. The re-exec fingerprint (`update_fingerprint`) covers
  `kingo` AND `.env`: the re-exec is the ONLY caller of `update_scrub_env`, so
  gating it on the script alone let a fetch that changed just `.env` finish in
  a process still holding the pre-fetch values. Every step on the ZIP path
  (`mktemp`, `rsync`) is guarded, or `set -e` aborts the function that is
  required never to be fatal.
- **Test a marker line with `case`, never `printf | grep -q`** (`MODE_FROM_ENV`,
  `update_is_stage2`): `grep -q` exits at its first match and SIGPIPEs the
  `printf`, which `set -o pipefail` then reports as a FAILED pipeline — so a
  present marker reads as absent once the environment exceeds a pipe buffer
  (reproduced on bash 3.2 and 5). `case $'\n'"$var"$'\n' in *$'\n'NAME=…)`
  anchors to a line start the way `^` did, and closing the pattern with `$'\n'`
  pins the whole value (`^KINGO_UPDATE_STAGE=2` also matched `=20`).
- **Metabase pre-setup is idempotent** via the setup-token check and non-fatal
  on failure; it runs on every `kingo up` in a mode that has Metabase. (plan §9.4)
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
  `kingo fixports`, which remaps busy ports into `.env.local`. When ALL the
  ports of the current mode are busy at once (10 in full, 4 in abp),
  doctor/fixports/up must refuse and say "the stack is probably already
  running under the other engine" — remapping would be exactly wrong then
  (happens for real when both engines are installed).
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
- **Ghost containers are healed before every `up`/`update`**
  (`heal_ghost_containers`): podman can keep a `kingo-*` NAME reserved in its
  storage layer after an unclean shutdown while the container is gone from
  `podman ps -a` — `compose up` then dies with `creating container storage: the
  container name "kingo-…" is already in use … by an external entity`, and
  `doctor` truthfully reports nothing running (a student, 2026-09-14; a Store
  "reinstall" of Ubuntu does NOT wipe the distro, so it survived that too). The
  healing removes ONLY names absent from `podman ps -a` AND present in
  `podman ps -a --external`, by ID, via a plain `podman rm` and then `podman
  rm -f` — they fail in different places: plain `rm` refuses while podman's own
  mount count says "mounted" but otherwise deletes the layer directory,
  leftovers and all; `rm -f` forces the count down and then rmdir's the mount
  point, which is what fails with "directory not empty" (a student, 2026-09-15,
  `rm -f` alone failed identically on every try). `rm --storage` is NOT a third
  option: since podman 3.0 it is a hidden no-op kept for compatibility, and the
  macOS remote client rejects the flag outright — `podman rm --help` on a Mac
  shows the REMOTE client's flags, not what a student's Linux podman accepts
  (that misread cost a support round). A name podman still manages is never
  touched, ours or another course's, and if podman cannot list containers it
  touches nothing. Podman-only; a no-op on Docker. The collecting loop is fed
  by `<<<`, never a pipe (a `while` after a pipe runs in a subshell and loses
  everything). **Sample `--external` BEFORE `podman ps -a`**: the two lists
  cannot be read at one instant, and a ghost is "in `all`, not in `known`". With
  `known` read first, a container CREATED in the gap (a second terminal running
  `up`) is missing from the older `known` and present in the newer `all` — we
  would force-remove a LIVE container mid-boot. The reverse race is harmless.
  Success is judged by the NAME being free again (`ghost_name_gone`), never by
  an exit status: `podman rm -f` exits 0 for an ID it cannot resolve, so a
  plain `rm` that tore down the record but kept the name reserved would be
  announced as cleared while `up` still fails on it. The stuck-ghost error line
  is kept PER ghost — one latched line handed the student the mount point of a
  container that was not the one blocking the boot — and the loud instructor
  block plus the `die` fire ONLY for a ghost that blocks the CURRENT mode; a
  ghost that blocks nothing gets one quiet line, or it would raise the full
  alarm on every `up` and `update` forever. When podman FINDS the ghost but CANNOT delete its directory
  either way ("removing mount point …: directory not empty" = leftover FILES in
  a dead container's own directory, not a live mount — so a WSL/machine restart
  does NOT cure it and must not be advised), `heal_ghosts_report` prints ONE
  block for all stuck ghosts (podman's `Error:` line only — its stderr carries
  logrus noise) and then `die`s **only if** a stuck ghost's service runs in the
  CURRENT mode: otherwise compose's generic error seconds later would bury the
  message, but a `kingo-jupyter-mcp` ghost blocks nothing in `abp`. It points
  at docs/INSTRUCTOR.md "Stale container storage" (umount → `rm -rf` → `podman
  rm -f` → `up`; on a Mac inside `podman machine ssh`). podman names that
  directory TWICE, in a WARN line and in the `Error:` line: anything that
  extracts the path must take ONE match (`grep -m1`) — a `grep -o` that
  matched both handed a student a path with an embedded newline, so `umount`,
  `mountpoint` and `rm -rf` all acted on a name that did not exist and the
  directory was never removed (2026-09-15). It warns AGAINST both
  `podman system reset` and `podman machine reset` (the Mac one — `system reset`
  does not exist in the macOS remote client): they delete every volume, i.e. the
  student's flows, workflows, notebooks and databases. Never `rm -rf` inside the
  storage graph from `kingo` itself — podman refuses to, and so do we.
- **`langflow-data` is mounted `:z`** (`compose.yml`): Langflow copies its
  avatar SVGs out of the image into `LANGFLOW_CONFIG_DIR` with
  `shutil.copytree`, which copies extended attributes — `security.selinux`
  included. The podman machine is Fedora CoreOS, where every container gets a
  random MCS category pair and may only open files carrying its own; the
  copied files keep the pair of the container that wrote them, so every LATER
  container can list `profile_pictures/` but gets EACCES on every read, and
  the profile-picture chooser is a wall of broken images (root does not help
  — SELinux denies before the mode is even consulted). `:z` relabels the
  volume's contents to the shared label at mount, which also self-heals on
  each start; it is a no-op where SELinux is absent (Docker Desktop, CI).
  Same shape for any volume whose files were written by a container that no
  longer exists: "can list it, cannot open it" means SELinux, not `chmod`.

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
- **A bundle is only "written" once it VERIFIES**: `docker-archive` cannot
  carry zstd layers (n8n 2.x ships them), and `save` then stops at that image
  while still exiting 0 — every later image is silently missing. The image
  order from `compose config --images` is random, so 0–8 of 11 images survive
  and the FILE SIZE proves nothing; only the manifest's image count does.
  `cmd_bundle` therefore converts zstd images via skopeo (round-trip through
  the `dir` transport; image IDs are unchanged), writes to `$out.part`, checks
  the written tar against the expected image list, and only then moves it into
  place. Never delete the previous bundle up front — an instructor's good
  stick tar must survive a failed re-run. Detection needs skopeo as much as
  conversion does, so a missing skopeo only WARNS: the arm64 Mac store
  (measured 2026-08-29) is all-gzip and bundles 11/11 fine without it, so a
  hard requirement would be wrong — and PR #4's claim that an arm64 bundle
  "cannot ever have worked" does not hold. (issue #3 / PR #4)
- **Setup deletes only the bundle IT copied**: after `smoke` passes, the
  setup scripts remove the ~14 GB tar they copied off the stick (tracked in
  `COPIED_BUNDLE`) — students left it lying around on laptops that need ~20 GB
  free. (Measured 2026-08-31: both bundles are 14.5 GB / 13.5 GiB and their
  layers are stored UNCOMPRESSED, so loading adds about the same again — a USB
  setup peaks near 30 GB, which is what the USB guides now ask for.) A tar the student or instructor put in the folder is NOT ours (only a
  hint is printed), and a file on the stick itself is never touched: an
  instructor's `setup-*.sh /path/to/stick/tar` must come back with the stick
  intact.
- **The USB stick is found FOR the student, never typed by them**: WSL2
  auto-mounts only removable drives that were present when it started, so a
  student who plugs the stick in when the guide says to — the normal
  sequence — sees `cp: cannot stat /mnt/e/...`. `kingo findbundle` /
  `discover_bundle` therefore searches this folder, then mounted media
  (`/mnt/*`, `/Volumes/*`, `/media/*`), then on WSL mounts the Windows drives
  Ubuntu lacks (drive letters from `powershell.exe Get-Volume`, blind d–h
  fallback) — and both setup scripts use it before falling back to a download.
  Never remount a drive that is already mounted and non-empty (that would hit
  `/mnt/c`), and keep the copy-then-pass-the-stick-on flow: the script says
  "UNPLUG THE STICK NOW" so one stick can serve a whole room. The mount uses
  `sudo -n` and NEVER prompts: most students install from the internet with no
  stick at all, and stopping them at a password question asked while looking
  for hardware they do not own would be worse than the problem being solved
  (inside the setup scripts apt has just used sudo, so the cached timestamp
  makes it succeed exactly where it matters). `kingo load` names the manual
  mount command when it finds nothing on WSL.
- **A bundle's checksum travels by git, never on the stick**: the blobs inside
  a bundle are content-addressed (each layer file is named after its own
  sha256), so a tampered layer cannot load — but a whole tar swapped for a
  self-consistent one would pass unnoticed. `kingo bundle` therefore records
  the tar's sha256 in the COMMITTED `bundles.sha256`, and `kingo load` refuses
  a file that does not match it; students receive that value over HTTPS via
  `git clone` / `kingo update`. Keep both degradations: no entry for this tar
  (or no `bundles.sha256` at all) loads with a warning, so older sticks and
  older repos still work. `record_bundle_sum` must only ever replace ITS OWN
  line — a mixed class has two tars built on two machines.
- **USB bundles are single-architecture and arch-stamped**
  (`kingo-images-<arch>.tar`): `save` writes only the host's local image blobs,
  so an arm64 tar exec-format-crashes at `up` on an amd64 laptop. `kingo bundle`
  names by host arch; both setup scripts and the USB-guide copy commands
  auto-pick the host-arch tar; `kingo load` inspects `kingo-jupyterhub:local`'s
  arch and REFUSES a mismatch (else it loads fine, then crashes at `up`). A
  mixed class needs BOTH tars on one stick — build amd64 on an amd64 box, arm64
  on an Apple-Silicon Mac. Do NOT collapse back to a single `kingo-images.tar`
  name (kept only as an auto-detect fallback).

- **Modes are compose profiles NAMED after the modes** (`full abp bi langflow
  n8n`; every service lists the modes it runs in, postgres has no profile).
  `kingo` exports `COMPOSE_PROFILES=$KINGO_MODE`, so the plain `compose()`
  wrapper sees only the current mode's services; `compose_all()` adds
  `--profile full` and MUST be used by `down`, `reset`, `pull`, `bundle`,
  `assert_loopback` and the CI diagnostics — a `down` without it exits 0 and
  leaves the inactive profiles' containers attached, after which podman
  cannot remove the network, and `reset -v` cannot remove volumes. The flag
  REPLACES the exported profile (docker-compose does not union them): it
  shows every service only because EVERY profiled service lists `full`,
  which `assert_modes` enforces. `service_modes()` in kingo mirrors
  compose.yml's `profiles:` and `smoke` asserts they agree for every mode.
  Compose never stops what a disabled profile owns, so `up` removes the
  containers of services that are off in the mode (`stop_off_services`), and
  `status`/`smoke` flag any that still run. UNSET mode = `full`: the cohort
  that installed before modes must keep every service across `kingo update`
  — and the committed `.env` carries `COMPOSE_PROFILES=full` for exactly one
  reader, the pre-modes `kingo` that keeps running after its own `git pull`
  (its `compose up -d` would otherwise see postgres alone and still say
  "Stack updated"); the new script overrides it. The SETUP SCRIPTS pin `abp`
  on a fresh install only (a `.env.local`, kingo-* containers or kingo_*
  volumes mean "existing — keep the mode"; a stopped Mac machine is started
  to look); the pin is written next to the engine pin AFTER the engine step,
  so a run that dies early leaves no half-made `.env.local`; a `KINGO_MODE`
  from the environment is validated on a fresh install and dropped on an
  existing one; an engine `.env.local` already names is kept even while its
  stack is down. `pull`/`update`/`build` stay MODE-AGNOSTIC: every image is
  always local (`pull` builds MISSING `*:local` images, never rebuilds), so a
  class-day `mode full` never downloads on classroom Wi-Fi. `mode` checks
  the target's images AND ports (a subshell `preflight_ports` in the target
  mode) before it writes anything. `mode` never refuses a machine that ran
  yesterday — it warns below a mode's floor; on Podman-on-Mac it resizes the
  machine to the mode's target (the ONLY setup where fewer containers give
  the host nothing back until the VM shrinks — applehv has no balloon) and
  asks for a typed `yes` only when foreign containers are running. ONE sizing
  rule, `mode_cap_mb` (the mode's target, capped so macOS keeps 3 GB): setup's
  `machine init` (`kingo memory target`), doctor's advice and `mode`'s resize
  all use it — two rules made an 8 GB Mac's first `mode full` resize a
  machine that was already right. A memory pin is written only after the
  resize succeeded, and `resize_machine` never dies (a failed start puts the
  old size back). The all-ports-busy refusal counts the ports the CURRENT
  MODE publishes (`all_active_busy`): both engines share `.env.local`, so an
  invisible copy holds exactly those. A `KINGO_MODE` from the environment
  beats the file (the `_cli_overrides` rule), so `cmd_mode` refuses then;
  CI never exports it. The memory table
  (`mode_mem_mb`/`mode_floor_mb`, measured 2026-09-05 under real use — see
  INSTRUCTOR.md "Modes") is the one place to retune. The Langflow upgrade is
  NOT a memory lever (1.11.6 idles at 1.36 GB with one worker; measured).
  On WSL `kingo memory` never hands out a `.wslconfig` recipe (Frank's call,
  2026-09-05): it states the half-of-the-laptop default and lists the modes
  that fit — raising the cap on an 8 GB laptop only starves Windows.
  Never `case` textually inside `$( )` in kingo — macOS ships bash 3.2.

- **The guides in `docs/` ARE the website**: `site/` is a small Astro project
  that publishes them at <https://huettner.io/kingo-pod/> (GitHub Pages project
  site; it inherits the custom domain of `frankhuettner.github.io`). Edit the
  markdown in `docs/` — `site/scripts/sync-docs.mjs` copies it in at build time
  and rewrites the two things that differ between GitHub and the web: links
  between guides (`STUDENT-GUIDE-MAC.md` → `/kingo-pod/mac/`) and image paths.
  So the files must stay valid markdown for the GitHub view: no front matter
  (titles and menu labels live in `site/src/lib/guides.ts`), keep the `# Title`
  first line and the `Jump to:` line — the sync strips both for the web, where
  the page header and the sidebar do that job. **Never add a `CNAME` file
  here** (it would fight the main site for huettner.io), and never let a guide
  exist in two places.

- **Setup guides end when setup ends**: `STUDENT-GUIDE-*` is read once and
  stops at "it works"; everything a student needs for the rest of the term
  (services + logins, the `kingo` commands, the `shared` folder, updating,
  troubleshooting, FAQ, architecture, KNIME) lives in `USING-MAC.md` /
  `USING-WINDOWS.md`. Before that split the tail was duplicated across all
  four setup guides — byte-identical between a platform's internet and USB
  variant, and 4x the drift risk. So: never move everyday material back into
  a setup guide, and when you add something everyday, add it ONCE per
  platform. What legitimately stays in a setup guide is `If setup fails` —
  only failures of the install itself (Homebrew, dev tools, WSL2 enable,
  WSL1, Compose v2); anything about *running* the stack belongs to the using
  guide's `If something breaks`, which the setup guide points to at the end.

## Versioning

The stack is versioned with semver, and the test for which number moves is
always the same question: **can a student get there with `./kingo update`
alone?**

- **MAJOR** — no. Their data needs migrating (a PostgreSQL major changes the
  data directory format), or a `kingo` command / port / service / `.env`
  variable they were told to use is gone or renamed. A major means the
  announcement is longer than one line.
- **MINOR** — yes, and something is new: a service, a `kingo` command, a
  class package in `langflow/requirements.txt`, an image bump that `update`
  applies by itself.
- **PATCH** — yes, and nothing is new: fixes, guides, the website, CI.

A release is an annotated git tag (`v1.0.0` = the stack the first two cohorts
ran) AND the same string in the committed `VERSION` file — **bump the file in
the commit you tag**, or `kingo version` will keep naming the previous
release. It is a file rather than `git describe` because ZIP-era folders have
no `.git`, and those are exactly the installs whose age nobody can otherwise
tell. `kingo version` prints it (plus commit, engines, platform), `kingo
doctor` echoes it as its second line, and `kingo update` reports the
transition — so "send me `./kingo version`" is the first question in support.
`kingo_version()` must stay non-fatal and must never call `select_engine`: a
student whose engine is broken still has to be able to say what they run.

## Layout

- `compose.yml` — the 9-service stack (ports overridable via `KINGO_PORT_*`;
  profiles = modes, see the invariant above).
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
- `docs/` — setup guides (Mac/Windows, each in an internet and a USB-stick
  variant), the two everyday-use guides (`USING-MAC.md`, `USING-WINDOWS.md`),
  the CloudBeaver walkthrough + instructor notes. `INSTRUCTOR.md` carries the
  table of pinned image versions — change a pin in `compose.yml` or either
  Dockerfile and that table moves with it, or it starts lying.
- `site/` — the Astro build that publishes `docs/` to huettner.io/kingo-pod
  (`npm run dev` to preview; deployed by `.github/workflows/pages.yml`).
- `.github/workflows/ci.yml` — both engines, two boot cycles plus a mode
  cycle (Boot 3).

## Windows = WSL2, one CLI

Windows students run everything inside **WSL2 Ubuntu** with the bash `kingo` —
NOT a PowerShell port. This deliberately deviates from the plan's `podman
machine`-on-Windows idea (which the plan flagged for Phase-2 verification): the
WSL path gives real Linux Podman (exactly what CI tests and the stack assumes),
one CLI with no drift, and matches the WSL install video in the guide. Do not
reintroduce a second CLI.
