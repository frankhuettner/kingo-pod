#!/usr/bin/env bash
# Kingo classroom — one-time setup for Linux. This is ALSO the Windows path:
# Windows students run it inside their WSL2 Ubuntu (see
# https://huettner.io/kingo-pod/windows/). Re-runnable. Uses an already-running Docker as-is (Docker
# Desktop's WSL integration, or native Linux Docker); otherwise installs
# Podman + the Compose v2 provider binary. Either way it then brings the
# stack up and verifies it.
#
#   bash setup/setup-linux.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# ── Self-update: run the LATEST setup logic ──────────────────────────────────
# A student who cloned an older, buggier version and re-runs must not keep
# hitting the same fixed bug. Pull the newest commit and re-exec ONCE (guarded
# against a loop), but NEVER block on it: offline / USB-bundle runs, a missing
# git, or any local divergence just proceed with what is already on disk.
if [ -z "${KINGO_NO_SELFUPDATE:-}" ] && [ -d .git ] && command -v git >/dev/null 2>&1; then
  _before="$(git rev-parse HEAD 2>/dev/null || true)"
  if timeout 30 git pull --ff-only >/dev/null 2>&1; then
    _after="$(git rev-parse HEAD 2>/dev/null || true)"
    if [ -n "$_after" ] && [ "$_before" != "$_after" ]; then
      say "Updated to the latest version — re-running setup ..."
      KINGO_NO_SELFUPDATE=1 exec bash "$0" "$@"
    fi
  fi
fi

# ── 0. WSL sanity: containers need WSL 2, not WSL 1 ──────────────────────────
# The guide's video installs WSL2, but a manual install on Windows 10 can
# silently land on WSL1 — no real Linux kernel, so neither Podman nor Docker
# can work there. Catch it here, with the actual fix.
if grep -qi microsoft /proc/version 2>/dev/null && ! grep -q WSL2 /proc/version 2>/dev/null; then
  echo "ERROR: this Ubuntu is running under WSL 1 — containers need WSL 2."
  echo "Fix it in Windows PowerShell:   wsl --set-version Ubuntu 2"
  echo "(takes a few minutes; then reopen Ubuntu and re-run this script)"
  exit 1
fi

# Pin the chosen engine in gitignored .env.local, overwriting any stale pin
# left by an earlier setup run on the other engine.
pin_engine() {
  { [ -f .env.local ] && grep -v '^KINGO_ENGINE=' .env.local || true; } > .env.local.tmp
  echo "KINGO_ENGINE=$1" >> .env.local.tmp
  mv .env.local.tmp .env.local
}

# ── 0. Mode: which services this install runs ────────────────────────────────
# A FRESH install gets abp (Langflow, n8n, CloudBeaver, PostgreSQL — the class
# default, 4 GB of memory). An existing install keeps whatever it runs: a
# re-run is the guides' repair step and must never take Jupyter or Metabase
# away from anyone. "Existing" = a .env.local is there (every setup run pins
# the engine into it, and a fresh clone has none), or kingo-* containers or
# kingo_* volumes exist (a stack that is merely `down` keeps its volumes).
# A preset KINGO_MODE wins on a fresh install — that is how a colleague's
# course installs Langflow-only:  KINGO_MODE=langflow bash setup/setup-linux.sh
# (On WSL nothing is resized: Windows gives Ubuntu half the laptop's memory,
# and hands back what the containers do not use.)
# The mode is written to .env.local together with the engine (after step 1):
# a run that stops early — no Homebrew yet, say — must leave no half-made
# .env.local that turns the re-run into an "existing" install.
pin_local() { # VAR value — rewrite one line of .env.local (the same way pin_engine does)
  { [ -f .env.local ] && grep -v "^$1=" .env.local || true; } > .env.local.tmp
  echo "$1=$2" >> .env.local.tmp
  mv .env.local.tmp .env.local
}
existing_install() {
  [ -f .env.local ] && return 0
  local e
  for e in docker podman; do
    command -v "$e" >/dev/null 2>&1 || continue
    [ -n "$("$e" ps -a --filter name=kingo- -q 2>/dev/null || true)" ] && return 0
    [ -n "$("$e" volume ls -q --filter name=kingo_ 2>/dev/null || true)" ] && return 0
  done
  return 1
}
MODES="full abp bi langflow n8n"
FRESH_INSTALL=0
if existing_install; then
  # `|| true`: under pipefail a .env.local without the line (every install from
  # before modes) makes grep exit 1, which would end the script right here.
  MODE="$(grep '^KINGO_MODE=' .env.local 2>/dev/null | tail -1 | cut -d= -f2 || true)"
  [ -n "$MODE" ] || MODE=full
  if [ -n "${KINGO_MODE:-}" ] && [ "$KINGO_MODE" != "$MODE" ]; then
    say "This install already exists — keeping its mode ($MODE), not KINGO_MODE=$KINGO_MODE from the command line. Switch afterwards with: ./kingo mode $KINGO_MODE"
  else
    say "This install already exists — keeping its mode ($MODE). Lighter or heavier: ./kingo mode"
  fi
  unset KINGO_MODE   # from here on .env.local decides (kingo lets the environment override it)
else
  FRESH_INSTALL=1
  MODE="${KINGO_MODE:-abp}"
  case " $MODES " in *" $MODE "*) ;; *) echo "ERROR: KINGO_MODE=$MODE is not a mode — the modes are: $MODES"; exit 1 ;; esac
  say "Mode: $MODE — $(KINGO_MODE=$MODE ./kingo mode 2>/dev/null | head -1 | sed 's/^Mode: [a-z0-9]* — //')   (change it later: ./kingo mode)"
fi


# ── 1. Engine: keep a running stack's engine; else use a running Docker;
#      else install Podman ───────────────────────────────────────────────────
# Many students arrive with Docker Desktop from another course. That is fine:
# the stack runs identically on it. Podman is only installed when no working
# engine is present.
#
# Re-running setup must never flip a working install to the other engine —
# that would strand the class data in the old engine's volumes. So if the
# stack is already running somewhere, that engine wins, full stop — and an
# engine .env.local already names is kept even while its stack is down (a
# downed Podman stack next to a running Docker Desktop must not be re-created
# under Docker, with empty volumes).
PINNED_ENGINE="$(grep '^KINGO_ENGINE=' .env.local 2>/dev/null | tail -1 | cut -d= -f2 || true)"
RUNNING_ENGINE=""
for eng in docker podman; do
  if command -v "$eng" >/dev/null 2>&1 \
     && [ -n "$("$eng" ps --filter name=kingo- -q 2>/dev/null)" ]; then
    RUNNING_ENGINE="$eng"; break
  fi
done

if [ -n "$RUNNING_ENGINE" ]; then
  say "The Kingo stack is already running under ${RUNNING_ENGINE} — keeping it. Nothing to install."
  command -v curl >/dev/null 2>&1 || { $SUDO apt-get update; $SUDO apt-get install -y curl; }
  pin_engine "$RUNNING_ENGINE"
elif [ "$PINNED_ENGINE" = docker ] && command -v docker >/dev/null 2>&1; then
  { docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; } \
    || { echo "ERROR: this install uses Docker (see .env.local), but Docker is not running. Start Docker Desktop, wait until it says 'running', then re-run this script."; exit 1; }
  say "This install uses Docker — keeping it. Nothing to install."
  command -v curl >/dev/null 2>&1 || { $SUDO apt-get update; $SUDO apt-get install -y curl; }
  pin_engine docker
elif [ -z "$PINNED_ENGINE" ] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
   && docker compose version >/dev/null 2>&1; then
  say "Docker is already running — using it. Nothing to install."
  # kingo's health checks need curl; the Docker path installs nothing else.
  command -v curl >/dev/null 2>&1 || { $SUDO apt-get update; $SUDO apt-get install -y curl; }
  pin_engine docker
else
  # Podman + rootless prerequisites + curl
  if ! command -v podman >/dev/null 2>&1; then
    say "Installing Podman ..."
    $SUDO apt-get update
    $SUDO apt-get install -y podman uidmap curl
  else
    command -v curl >/dev/null 2>&1 || { $SUDO apt-get update; $SUDO apt-get install -y curl; }
  fi

  # Rootless podman needs a subuid/subgid range for the user (usually preset,
  # but fresh WSL Ubuntu images sometimes lack it).
  me="$(id -un)"
  if ! grep -q "^${me}:" /etc/subuid 2>/dev/null; then
    say "Configuring rootless user namespaces for ${me} ..."
    $SUDO usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$me" 2>/dev/null || true
    podman system migrate 2>/dev/null || true
  fi

  # Compose v2 provider binary. Must be Compose v2 — NOT the old Python
  # 'docker-compose' v1 and NOT podman-compose (breaks depends_on:
  # service_healthy, plan §4). Ubuntu 24.04's 'docker-compose-v2' package IS
  # v2, and comes over the same apt channel as Podman itself — so it works on
  # networks that mangle GitHub release downloads (a student's campus network
  # served a non-runnable file with HTTP 200, 2026-08; git clone was fine,
  # only the release CDN was intercepted). apt first, GitHub as fallback.
  compose_v2_ok() { docker-compose version --short 2>/dev/null | grep -qE '^v?2\.'; }
  if ! compose_v2_ok; then
    say "Installing the Compose v2 provider ..."
    # A broken file from an earlier failed attempt sits exactly where the
    # link below goes and makes every re-run fail the same way — clear it.
    if [ -e /usr/local/bin/docker-compose ]; then
      $SUDO rm -f /usr/local/bin/docker-compose
    fi
    $SUDO apt-get install -y docker-compose-v2 >/dev/null 2>&1 || true
    # The package ships ONLY the docker CLI plugin under /usr/libexec — no
    # command on PATH. podman's compose shim and kingo both look for
    # `docker-compose` on PATH, so link it (the plugin binary runs fine
    # standalone; it is the same binary GitHub releases ship).
    if ! command -v docker-compose >/dev/null 2>&1 \
       && [ -x /usr/libexec/docker/cli-plugins/docker-compose ]; then
      $SUDO ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
    fi
  fi
  if ! compose_v2_ok; then
    # Older Ubuntu without the docker-compose-v2 package: static binary.
    say "Downloading the Compose v2 binary from GitHub ..."
    arch="$(uname -m)"   # x86_64 or aarch64
    tag="$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
           | grep -o '"tag_name":[^,]*' | cut -d'"' -f4 || true)"
    [ -n "$tag" ] || tag="v2.40.0"   # fallback if the API is rate-limited
    $SUDO curl -fsSL "https://github.com/docker/compose/releases/download/${tag}/docker-compose-linux-${arch}" \
      -o /usr/local/bin/docker-compose
    $SUDO chmod +x /usr/local/bin/docker-compose
  fi
  compose_v2_ok || {
    echo "ERROR: could not install a working Compose v2 (docker-compose)."
    echo "Run the package install by hand to see why it fails:"
    echo "    sudo apt-get install -y docker-compose-v2"
    echo "then re-run this script. (If apt says the package does not exist,"
    echo "your Ubuntu is too old for this stack — use Ubuntu 24.04.)"
    exit 1
  }

  # Podman itself must be new enough to have the `podman compose` shim (4.7+).
  # Ubuntu 22.04's apt ships 3.4 — that install "succeeds" and then every
  # kingo command fails at the very end, so refuse HERE with the actual fix.
  if ! podman compose version >/dev/null 2>&1; then
    echo "ERROR: this Podman ($(podman --version)) has no 'compose' subcommand (needs Podman 4.7+)."
    echo "Your Ubuntu is too old — 22.04 ships Podman 3.4. Easiest fix: use Ubuntu 24.04."
    echo "On Windows: install the 'Ubuntu 24.04 LTS' app from the Microsoft Store, open it,"
    echo "and run this script there (your Windows files are untouched)."
    exit 1
  fi

  # Rootless podman's Docker-compatible API socket is a systemd USER unit
  # and is NOT enabled by default — but the compose provider (docker-compose)
  # is a Docker client and cannot start the stack without it. The first real
  # WSL run died exactly here ("Cannot connect to the Docker daemon",
  # 2026-08-22). Linger keeps the user manager (and with it this socket +
  # healthcheck timers) alive even with no terminal open.
  if [ -d /run/systemd/system ]; then
    $SUDO loginctl enable-linger "$(id -un)" 2>/dev/null || true
    if ! systemctl --user is-active --quiet podman.socket 2>/dev/null; then
      say "Enabling the Podman API socket (the compose provider needs it) ..."
      systemctl --user enable --now podman.socket || true
    fi
    systemctl --user is-active --quiet podman.socket || {
      echo "ERROR: the Podman user socket (podman.socket) did not start."
      echo "Look at:   systemctl --user status podman.socket"
      exit 1
    }
  elif grep -qi microsoft /proc/version 2>/dev/null; then
    echo "ERROR: this WSL Ubuntu is running without systemd, which Podman needs."
    echo "Fix it in Windows PowerShell:   wsl --update"
    echo "then inside Ubuntu make sure /etc/wsl.conf contains these two lines:"
    echo "    [boot]"
    echo "    systemd=true"
    echo "then in PowerShell:   wsl --shutdown   — reopen Ubuntu and re-run this script."
    exit 1
  fi

  # Native/rootless podman needs no 'podman machine' — on WSL, WSL2 IS the VM.
  say "Podman: $(podman --version)   Compose: v$(docker-compose version --short)"

  pin_engine podman
fi
# The mode from step 0, written next to the engine pin (see there for why not earlier).
if [ "$FRESH_INSTALL" = 1 ]; then pin_local KINGO_MODE "$MODE"; fi

# CI hook: stop after the engine + compose install. Lets ci.yml run this real
# code on stock Ubuntu 24.04 (the field failed exactly here, 2026-08) without
# pulling the 10 GB stack.
if [ -n "${KINGO_SETUP_ENGINE_ONLY:-}" ]; then
  say "KINGO_SETUP_ENGINE_ONLY set — engine and compose are ready, stopping here."
  exit 0
fi


# ── 2. Ports, then images (USB bundle or download), then up and verify ───────
say "Checking that no other software sits on Kingo's ports ..."
./kingo fixports

# USB bundle: `setup-linux.sh /mnt/e/kingo-images-<arch>.tar` loads the images
# from the instructor's stick instead of downloading; a kingo-images-<arch>.tar
# (or a legacy kingo-images.tar) sitting in this folder — copied from the stick
# — is picked up automatically. Bundles are single-arch, so we look for THIS
# machine's arch first; `kingo load` refuses a wrong-arch tar. Either way the
# pull below then skips everything that is already present.
BUNDLE="${1:-}"
if [ -z "$BUNDLE" ]; then
  bundle_arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  for cand in "kingo-images-$bundle_arch.tar" kingo-images.tar; do
    [ -f "$cand" ] && BUNDLE="$cand" && break
  done
fi
# Nothing in this folder — look on the instructor's stick. On WSL this also
# mounts the stick when Windows has it but Ubuntu does not, which is the
# NORMAL case (students plug it in only when the guide asks for it, long after
# Ubuntu started). Copy it here so the stick can be passed on right away and a
# re-run never needs it again; if the copy does not fit, load off the stick.
if [ -z "$BUNDLE" ]; then
  say "Checking whether an instructor's USB stick is plugged in (a few seconds) ..."
  STICK="$(./kingo findbundle 2>/dev/null || true)"
  [ -n "$STICK" ] || say "No stick found — the images will be downloaded instead."
  if [ -n "$STICK" ]; then
    say "Found the class images on a USB stick ($STICK)."
    say "Copying them to this folder (5-10 minutes) so you can pass the stick on ..."
    _tmp="./$(basename "$STICK").part"
    rm -f "$_tmp"
    if cp "$STICK" "$_tmp"; then
      mv "$_tmp" "./$(basename "$STICK")"
      BUNDLE="$(basename "$STICK")"
      COPIED_BUNDLE="$BUNDLE"   # ours to delete once the stack is verified
      say "Copy done — you can UNPLUG THE STICK NOW and pass it to the next student."
    else
      rm -f "$_tmp"
      say "Could not copy it (not enough disk space?) — loading straight from the stick instead. Keep it plugged in."
      BUNDLE="$STICK"
    fi
  fi
fi

if [ -n "$BUNDLE" ]; then
  say "Loading the container images from the USB bundle ($BUNDLE) — no big download needed ..."
  ./kingo load "$BUNDLE"
  case "$BUNDLE" in
    */*) : ;;  # loaded straight from a stick path — never ours to delete
    *)   [ "$BUNDLE" = "${COPIED_BUNDLE:-}" ] \
           || echo "    (you can delete $BUNDLE in this folder afterwards to free ~14 GB)" ;;
  esac
fi

say "Making sure all container images are present (~10 GB download on a first run without the USB bundle — every mode's images, so switching modes later never downloads) ..."
./kingo pull

say "Starting the Kingo stack ..."
./kingo up

say "Verifying the stack (smoke test) ..."
./kingo smoke

# Everything works, so the 14 GB copy has done its job: the images live in the
# container engine now, and a re-run needs neither the copy nor the stick.
# Students were asked to delete it by hand and mostly did not — on a laptop
# that needs ~20 GB free that is a lot to leave lying around. Deleted ONLY if
# this script made the copy itself (COPIED_BUNDLE): a tar the student or the
# instructor put in the folder, and the instructor's file on the stick, are
# never ours to remove.
if [ -n "${COPIED_BUNDLE:-}" ] && [ -f "$COPIED_BUNDLE" ]; then
  say "Removing $COPIED_BUNDLE (~14 GB) — the images are installed, the file is no longer needed."
  rm -f "$COPIED_BUNDLE"
fi

say "Done! Your class services:"
./kingo credentials
