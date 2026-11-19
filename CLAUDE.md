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
- **Three images are built locally**, tagged `*:local`: JupyterHub
  (`jupyterhub/Dockerfile` — no published image runs hub+Lab standalone),
  Langflow (`langflow/Dockerfile` — upstream + `langflow/class-requirements.txt`
  + `langflow/requirements.txt` + `uv`) and Mail (`mail/Dockerfile` — Alpine + mbsync, notmuch, goimapnotify and
  a small Python service; see "The mail service"). Anything that special-cases
  one (pull's base-image list, bundle, load's retag) must handle all three. `pull` builds them only when MISSING
  (`build_missing`; a USB `load` brings images without build cache), `update`
  alone forces a build, `smoke` checks the hub can launch a Lab whenever the
  mode runs it.
- **JupyterLab (:8888) stays** although JupyterHub exists — the Jupyter MCP
  server points at it.
- **Class-wide Python packages go in `langflow/class-requirements.txt`, never
  in `langflow/requirements.txt`**, which stays at its v1.4.0 content (on
  `release-1.5`: its 1.5.0 content). Students edit that file themselves (the
  whole class added `nemoguardrails` for Workshop I), and git refuses to pull a
  commit that changes a file the folder changed too: an upstream change strands
  every such folder on every update, and only a command typed on the laptop
  gets it out (v1.4.0's ragas line did that, found 2026-11-04). The two files
  must not pin one package differently, or the build fails. The class file
  also holds `huggingface-hub<1.0`: without it a fresh build lifts the hub
  past what the base image's transformers accepts (the file says why), and
  the Dockerfile's import check fails the build.
  `kingo langflow pip install` is ephemeral by design. `requirements.txt` knowingly
  overrides two pins of the base image (`datasets<4`, `pyarrow==19`; ragas 0.4
  needs newer): the build prints pip's "dependency conflicts" notice and exits
  0, and Langflow runs fine on them (2026-09-21) — do not pin pyarrow back. A
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
- **A version change dumps the Langflow and n8n databases BEFORE `cmd_pull`**
  (`backup_dbs`; by hand `kingo backup`): both apps migrate on first start and
  cannot downgrade. It sits after the re-exec, so the fetched script runs it
  and the release that ships it is covered. With the stack down it starts
  postgres alone. Never fatal (warns, update goes on); a failed run never
  prunes (`BACKUP_KEEP` folders). A `git switch` changes `VERSION` before
  update can see it — hence the manual `kingo backup` in the `next` recipe.
- **A folder tracking `origin/release-*` rejoins `main` by itself**
  (`update_rejoin_main`, right after a successful fetch) once that branch is
  an ancestor of `origin/main`. It is a no-op until then and for every
  main-tracking folder. Do not delete a release branch from GitHub: a folder
  that has not updated since still tracks it.

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
  package in `langflow/class-requirements.txt`, an image bump `update` applies.
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
up the Langflow and n8n databases first (`./kingo backup`): both migrate on
first start and cannot downgrade.

**While another course must stay on the old version, the release goes on
`release-X.Y`, not `main`** (INSTRUCTOR.md "Two versions at once"; 1.5 was
the first, 2026-10). Nothing in `update` can keep a release on `main` away
from a folder: the OLD script on the laptop does the merge. Students opt in
with `git branch -u origin/release-X.Y` (docs/UPGRADE.md); the website
builds from `main`, so guides go there and are merged into the release
branch. Meanwhile `main` is a maintenance line: what every folder needs goes
there as a PATCH of the old line (1.4.1: n8n 2.41.6 + the backup), even where
the rule above would say MINOR, so "Kingo 1.4 / 1.5" keeps naming the one
difference students choose between.

## The mail service (n8n workshop)

- **`mail/` is copied from the workshop repo** (n8n-workshop,
  `system/kingo/apply.sh`): the container, the schema
  `mail/n8n_workshop_mail.sql` and the course case `mail/case/`. Change it
  there, not here, or the next copy undoes it.
- **No host port**: n8n and Langflow reach it only through Postgres. Its
  SERVICE_TABLE row has port `-` and path `ps` (up = its container runs), and
  every loop over the PORTS skips `-` (preflight, fixports, `dup_ports`,
  `release_after_down`; `host_ports` feeds the loopback drift guard and
  doctor's count). A new loop over the table's ports must skip it too.
- **The schema is applied by `init_stack` on every `up`** (`mail_schema`, in
  every mode), never from `postgres-init/`: an error there would abort the
  database's first start, here it is a warning. The same run gives the five
  `n8n_workshop_mail_*` roles `KINGO_PASSWORD` (public by design, like every
  login in `.env`) and makes the calendar table a copy of
  `mail/case/calendar.csv`.
- **Postgres runs `pgvector/pgvector:pg16-trixie`**, the official `postgres:16`
  on the same Debian plus pgvector: existing data opens unchanged. The schema
  creates the extension `vector` in `classroom` and the table
  `n8n_workshop_mail.chunks` (mails and documents with a vector and full text,
  for the search in Langflow; row level security keeps internal rows from the
  role `n8n_workshop_mail_reply`). `kingo mail seed` loads the case documents
  with vectors made in advance (`mail/case/documents.jsonl`), on every run.
- **A mail failure never holds up the stack**: `up` and `smoke` warn (both
  setup scripts run `smoke` right after `up`); only CI (`CI=true`) makes
  `smoke` fail on it.
- **It logs in as `n8n_workshop_mail_container`**, never as the superuser: that
  role may write the mailbox rows and move an approved outbox row on, nothing
  else. `smoke` checks the login and the tools in the image.
- **Not in `LANGFLOW_SSRF_ALLOWED_HOSTS`**: nothing listens in it, so there
  is nothing for Langflow to reach. Give it a port one day and it goes in.
- **The account lives only in the volume `mail-data`** (address, app password,
  Maildir, mbsync's sync state). `kingo mail reset` deletes that volume alone;
  `kingo reset` deletes it with everything else. Restored, it must be whole: a
  Maildir without its sync state uploads every mail a second time.
- **`stop_grace_period: 60s`**: on SIGTERM it finishes the mail it is
  sending (SMTP timeout 30 s) and sends no further one. A sync that runs
  longer is killed after 60 s, which mbsync recovers from; an interrupted
  send stays at `sending` for a person to check — it never sends a row twice
  by itself.

## `kingo claude` (Claude Code in the nono sandbox)

- **Under Linux and Windows (WSL2), Claude Code starts through
  `setup/claude/no_unix_sockets.py`; keep it in the launch line, with no switch
  around it.** nono does not cover Unix sockets there: Landlock does not see
  `connect(2)`, and nono's own guard (`linux.af_unix_mediation`) needs seccomp
  user notification, which WSL2 lacks. Docker, Podman's API socket (which
  `setup-linux.sh` turns on) and the systemd user manager listen on such sockets
  and work OUTSIDE the sandbox: one `docker run -v` from inside read a file
  outside it (found under WSL2, 2026-11-13). The file takes Unix sockets away
  with a plain seccomp filter; it names system calls by number, per processor
  type. A Mac needs none of this: the profile's key routes put nono into proxy
  mode, and there its network rules cover Unix sockets. Dropping the key routes
  from the profile would open the same gap on a Mac.
- **The CI job `claude-sandbox` is the proof, on x86-64 and arm64**: with the
  real nono and the course profile, each way out (Docker, Podman, systemd) is
  tried without the lock, where it must WORK or the check proves nothing, and
  with it, where it must not. Then the real Claude Code runs a turn and a first
  terminal session against a stand-in for the model
  (`.github/scripts/fake_model.py`, `pty_session.py`). A new Claude Code start
  screen shows up as a failed session step, with every screen in the log.
- **`kingo` starts its own nono, one fixed version (`CLAUDE_NONO_VERSION`,
  with checksums).** The profile leans on how that version behaves. To move to
  a newer nono: change the version and the four checksums, run the CI, then
  release. A nono that is installed on the laptop is only the fallback when
  the download fails.
- **What `kingo` downloads for Claude Code (nono, the browser of `look`,
  Node.js and playwright-core for `clickthrough`) lives
  in `~/.local/share/kingo`, never in a folder the sandbox can write.** `kingo`
  starts these files OUTSIDE the sandbox (nono itself; the browser for
  `--version` and `ldd`). In `~/.kingo-claude` or the course folder, a program
  in the sandbox could swap them and would run outside at the next start. The
  CI part `look` tries to write there from inside and must fail.
- **Seven profile files, because nono only ever adds.** nono joins lists and
  never takes a base entry away, so each thing is in one file and a start
  names what it needs (`"extends"` takes a list). `kingo-claude-core`: what
  every start needs (folders, variables, the rule for `look`), no way to a
  model. `kingo-claude-base`: core and the route to OpenRouter (`--in`).
  `kingo-claude-course`: n8n, Langflow, PostgreSQL. `kingo-claude`: base and
  course. `kingo-claude-login`, `-login-course`: the same with the Anthropic
  login in place of OpenRouter. `-login-open`: the login step on a Mac. A
  student's `my-nono-profile.json` (gitignored, in this folder, where the
  sandbox cannot write) must extend `kingo-claude`; with `--login`, `kingo`
  writes the login's course profile into the copy that nono reads. The CI
  parts `own` and `login` check this.
- **`kingo claude --login`: the login is made inside the sandbox, and nono
  keeps it outside** (nono's "OAuth capture", `nono-profile-login.json`).
  Claude Code holds stand-ins. Three rules: `kingo` looks at the form of the
  tokens after every login and deletes one that is not a stand-in
  (`claude_login_state`); only the login step gets the right to open the
  browser (`-login-open` with `--allow-launch-services`), never a session; and
  this way has its own config folder (`~/.kingo-claude-login`), because in
  `~/.kingo-claude` `kingo` deletes every login. The CI cannot log in: it
  checks `kingo`'s steps with a stand-in for nono (`fake_nono.sh`) and the
  sandbox of the login with the real nono. A real login was tried by hand on a
  Mac (14 Nov 2026).
- **One session with `--login` at a time** (since 1.4.17 / 1.5.16): two
  OAuth-capture sandboxes overwrite each other's store and break the login
  (nono issues 2087 and 2299; the fix, PR 2088, is in no release yet).
  `claude_login_claim` writes kingo's process number to
  `~/.kingo-claude-login.session` with noclobber before the login step and
  before the logout (`exec` keeps the number for nono). `claude_login_busy`
  counts a number only while it runs nono, bash or kingo (`ps -o comm=`);
  without `ps` (a sandbox may forbid it) a running number counts. The lock goes
  when `CLAUDE_NONO_VERSION` reaches a nono with the fix.
- **The variables for a start are one list (`envs` in `cmd_claude`), which the
  dry run names and the start exports.** Do not go back to variables in front
  of the `exec` line over several lines: a comment line between them once cut
  five of them off without any error.
- **A session starts nono with `--silent`** (Frank, 18 Nov 2026): on a Mac,
  nono's report after the end names "Fix flags" and a way to open the
  keychain, which a student must not follow. So kingo itself says before the
  start where Claude Code may write. `KINGO_CLAUDE_LOUD=1` brings nono's output
  back. The login and the logout run nono as before. The CI copies the line,
  with `--silent`, and checks on Linux and on a Mac that nothing of nono shows.
- **`--key <name>` takes any provider (`--provider anthropic|ollama|an
  address`, `--model <ID>`; Frank, 19 Nov 2026).** kingo keeps the provider
  and the model with the name (`key-<name>.conf` next to the keys); an
  OpenRouter key without `--model` has no such file and the profile it had
  before. Keep three things. Inside the sandbox it is always
  `ANTHROPIC_AUTH_TOKEN`, never `ANTHROPIC_API_KEY`: Claude Code asks in a
  session whether to use such a key, and the course's settings blank it. So
  every route puts the key into `Authorization: Bearer`, also the one to
  Anthropic's API, whose docs name that header for an API key (and refuse a
  request with a credential in both headers). An Anthropic key must be made
  for one workspace: kingo sends no `anthropic-workspace-id`. And `--model` is
  kingo's only next to
  `--key`; without it, it goes on to Claude Code (`kcl --model opus`). The
  provider's address and the model's ID go into JSON and into `sed`: both are
  checked letter by letter first (`claude_key_provider`, `claude_key_model_ok`).
- **`./kingo key add|list|remove` (and the old name, `./kingo claude key`)
  manages those keys without a start (Frank, 19 Nov 2026: "dann kann man key
  verwaltung und project laden trennen").** It needs no pod and starts no
  Claude Code. `key add` with nothing after it asks its questions in a terminal
  (Frank, 20 Nov 2026): `claude_key_ask` only collects the answers and then
  calls `claude_key_add` with the flags, so the questions never get rules of
  their own; a name with a key keeps its provider, a name without one is asked
  everything again, and an answer that looks like a key is never taken as the
  model (`claude_key_looks_like_key`). Without a terminal it stops and names
  the line with flags. `key remove` without a name asks too. `add` keeps what the
  first start with `--key` keeps, and two things that a start does not take:
  `--context <tokens>` (a line `context=` in `key-<name>.conf`; it goes to
  Claude Code as `CLAUDE_CODE_MAX_CONTEXT_TOKENS` in place of the 200000, and
  from 100000 to 1000000 as `CLAUDE_CODE_AUTO_COMPACT_WINDOW` too, which is
  what counts for a model that Claude Code knows, such as one of Anthropic's
  behind a gateway: `claude_key_window`. The core profile lets this second
  variable through, and kingo unsets it before every start, so only its own
  number comes) and
  `--ca <file>` (copied to `key-<name>.crt`; `tls_ca` in the route of the
  key's profile, because nono's proxy makes the connection, not Claude Code).
  Keep four things. A key that is there is never lost before its successor is
  accepted: `add --first` (the key without a name) and `add <name>` for a name
  with a key check the new key first, where the provider can be asked. `list`
  never shows a key. `remove` deletes only what belongs to the whole name: the
  settings of a folder are matched by the digits after the name, so that the
  name `a` never takes those of `a-b`. And an address loses `/v1` or
  `/v1/messages` at its end (`claude_key_provider`): Claude Code adds
  `/v1/messages` itself. The CI types the keys through a terminal of its own
  (`.github/scripts/with_terminal.py`, and `pty_answer.py --all` for the
  questions of `key add`, which fails when an answer is left over), since
  kingo asks in a terminal only.
- **A start with `--key` and `key add` share their rules: `claude_key_resolve`
  says what a name stands for, and `claude_key_keep` writes it (the code
  review of 19 Nov 2026 found two copies that had come apart within a day).**
  Resolve writes nothing; keep runs once nothing in the line can refuse it any
  more, and at a start before the key is asked for, so that a refused key
  leaves the name with its provider. Three rules live there. A key never goes
  to a provider that kingo cannot name: a `key-<name>.conf` changed by hand,
  with a key under the name, stops both. A name that turns into plain
  OpenRouter loses its file, or the file of before would keep the old
  provider. And `key add` never deletes a key: only a start does, for a key
  that its provider refuses (`claude_named_key`); `key add` checks a typed key
  first (`claude_key_typed_ok`) and touches no key without a terminal.
- **`claude_folder_rules` decides which folder `--in`, `--read` and `--write`
  take: one set of rules for all three.** It must keep out every folder in
  which a program of the sandbox could write something that runs outside
  later, or read keys: the home folder, hidden folders, kingo's own folders
  and where a linked hidden folder really is (`claude_private_places`), the
  folders of `PATH` and `~/bin` (`claude_command_places`, not for `--read`),
  and any folder that holds kingo-pod. It compares folders, not names
  (`claude_below`, `test -ef`): on a Mac, `~/Kingo-Pod` is kingo-pod. kingo-pod
  itself and a folder in it are not given to `--in`: they start the course, as
  `./kingo claude` does, with one line that says so (Frank, 15 Nov 2026). A
  relative folder is named from the folder kingo was started in (`_kingo_from`,
  taken before kingo's `cd`): `--in .` is the folder you are in.
- **`./kingo shortcuts` writes one marked block into the file a new terminal
  reads, and nothing else** (`$SHELL`: zsh `~/.zshrc`; bash `~/.bashrc`, on a
  Mac `~/.bash_profile`, which then reads a `~/.profile` that bash read
  before). A second run replaces the block, `remove` takes it out, a copy of
  the file comes first, the file is written in place (a link stays a link),
  and a marker without its partner stops it. The functions only call `kingo`
  by its full path (`kc` = `claude --in .`), so the logic stays here and comes
  with `update`. They are defined as `function name {` after `unalias`: an
  alias of the same name would bend `name() {` while the file is parsed. A
  name that something else has is found by asking the student's shell with the
  block off (`KINGO_SHORTCUTS_SKIP=1`), **without the terminal** (a session of
  its own through perl's `setsid`, stdin `/dev/null`, `+m` as a precaution)
  and for 10 seconds at most. Without the terminal, a question in a startup
  file gets no answer at once: zsh's `compinit` asks one when it finds
  insecure directories, and in the terminal it waited, showed on the screen and
  missed the alias (CI on Ubuntu, 15 Nov 2026). A shell later than 10 seconds:
  kingo looks for `alias name=`, `name()` and `function name` in the startup
  file only. A taken name is written only after a yes, and a name in kingo's
  block counts as a yes. CI: `.github/scripts/claude-shortcuts.sh`, zsh and
  bash, Linux and the Mac.
- **`look` on a Mac needs the `mach-register` rule in the profile** (Chrome's
  helper programs). Without it `look` falls back to `--single-process`, which
  cannot wait for a page's scripts. The CI job `claude-look-mac` runs both.
- **`clickthrough` is playwright-core as a library, not Playwright's MCP server
  or its CLI.** Both of those open a Unix socket for their browser; the sandbox
  refuses it (under Linux the lock refuses every Unix socket). Tried on 14 Nov
  2026 on the branch `wip/playwright-trial`. `clickthrough-setup.js` gives
  `chromium.launch()` kingo's browser and nono's proxy: on a Mac, Chrome does
  not take `HTTPS_PROXY` and cannot reach the internet without it.
- **`clickthrough` (Frank's word „Durchklicken“, 15 Nov 2026: `look` takes a
  picture of a page, `clickthrough` clicks through it as a person would, and
  Claude reads the internet with its web tools; first called `browse`, which
  said too little) closes http and WebSockets** in Chrome (dead proxies) and in
  every context (route), so that no page can reach n8n or Langflow. `--dev
  <port>` opens one port for the student's dev server: the bypass list sends it
  direct, the route lets it through only for pages from the dev server and for
  `page.goto` of the script. The profile opens `KINGO_DEV_PORT` (5173): a
  Seatbelt rule on a Mac, `open_port` under Linux. Never a port of kingo-pod.
- **The locks of `clickthrough` hold whatever the script does through
  Playwright's API** (a review, 15 Nov 2026): every `require` and `import` of
  Playwright gets kingo's copy, also next to a copy in `node_modules`; a route
  of the script asks lock 2 first; a context gets no proxy of its own; the
  other ways to a browser are refused (`clickthrough-setup.js` lists them, and
  what stays outside: a script that goes around the API). A newer
  playwright-core may bring a new way: the CI tries each one
  (`clickthrough_routes.js`, `clickthrough_copy.js`, `clickthrough_ways.js`).
  Scripts are `.cjs`: in a Vite project a `.js` is an ES module.

## Layout

- `compose.yml` — the 10-service stack (ports via `KINGO_PORT_*`; profiles =
  modes).
- `kingo` (bash) — the ONE CLI for Mac, Linux and Windows-in-WSL2; CI-tested
  on Linux with both engines.
- `jupyterhub/`, `cloudbeaver/`, `postgres-init/` — service config;
  `langflow/` — Dockerfile + class-requirements.txt (+ requirements.txt, frozen)
  for the local Langflow build;
  `mail/` — the mail service (copied from the workshop repo, see above).
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
  everyday guides, the CloudBeaver walkthrough, the optional-upgrade page
  (`UPGRADE.md`), instructor notes.
- `site/` — the Astro build of `docs/` (`npm run dev` to preview; deployed by
  `.github/workflows/pages.yml`).
- `.github/workflows/ci.yml` — both engines, two boot cycles plus a mode cycle.

## Windows = WSL2, one CLI

Windows students run everything inside **WSL2 Ubuntu** with the bash `kingo` —
NOT a PowerShell port. This deviates from the plan's `podman machine`-on-Windows
idea on purpose: the WSL path gives real Linux Podman (what CI tests and the
stack assumes), one CLI with no drift, and matches the install video. Do not
reintroduce a second CLI.
