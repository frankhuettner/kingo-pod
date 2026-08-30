#!/usr/bin/env bash
# Kingo classroom — one-time Mac setup. Re-runnable (safe to run again if it
# stops partway). Uses an already-running Docker Desktop as-is; otherwise
# installs Podman + the docker-compose provider and creates a Podman machine
# with enough resources. Either way it then brings the stack up and verifies.
# Homebrew is a PREREQUISITE (its own step in the guide) — this script never
# installs Homebrew itself.
#
#   bash setup/setup-mac.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# ── Self-update: run the LATEST setup logic ──────────────────────────────────
# A student who cloned an older, buggier version and re-runs must not keep
# hitting the same fixed bug. Pull the newest commit and re-exec ONCE (guarded
# against a loop), but NEVER block on it: offline runs, a missing git, a
# ZIP-era folder (no .git), or any local divergence just proceed with what is
# already on disk. macOS ships no `timeout`; the lowSpeed options bound a
# stalled network instead.
if [ -z "${KINGO_NO_SELFUPDATE:-}" ] && [ -d .git ] && command -v git >/dev/null 2>&1; then
  _before="$(git rev-parse HEAD 2>/dev/null || true)"
  if git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=15 pull --ff-only >/dev/null 2>&1; then
    _after="$(git rev-parse HEAD 2>/dev/null || true)"
    if [ -n "$_after" ] && [ "$_before" != "$_after" ]; then
      say "Updated to the latest version — re-running setup ..."
      KINGO_NO_SELFUPDATE=1 exec bash "$0" "$@"
    fi
  fi
fi

# Pin the chosen engine in gitignored .env.local, overwriting any stale pin
# left by an earlier setup run on the other engine.
pin_engine() {
  { [ -f .env.local ] && grep -v '^KINGO_ENGINE=' .env.local || true; } > .env.local.tmp
  echo "KINGO_ENGINE=$1" >> .env.local.tmp
  mv .env.local.tmp .env.local
}

# ── 1. Engine: keep a running stack's engine; else use a running Docker
#      Desktop; else install Podman ──────────────────────────────────────────
# Many students arrive with Docker Desktop from another course. That is fine:
# the stack runs identically on it. Podman is only installed when no working
# engine is present.
#
# Re-running setup must never flip a working install to the other engine —
# that would strand the class data in the old engine's volumes. So if the
# stack is already running somewhere, that engine wins, full stop.
RUNNING_ENGINE=""
for eng in docker podman; do
  if command -v "$eng" >/dev/null 2>&1 \
     && [ -n "$("$eng" ps --filter name=kingo- -q 2>/dev/null)" ]; then
    RUNNING_ENGINE="$eng"; break
  fi
done

if [ -n "$RUNNING_ENGINE" ]; then
  say "The Kingo stack is already running under ${RUNNING_ENGINE} — keeping it. Nothing to install."
  pin_engine "$RUNNING_ENGINE"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
   && docker compose version >/dev/null 2>&1; then
  say "Docker Desktop is already running — using it. Nothing to install."
  pin_engine docker
else
  if command -v docker >/dev/null 2>&1; then
    say "Note: Docker is installed but not running, so this script sets up Podman instead."
    echo "     (Prefer Docker? Quit this script (Ctrl+C), start Docker Desktop, re-run.)"
  fi

  # Homebrew is a prerequisite, deliberately NOT installed here (Frank's
  # call, 2026-08): its installer wants a password and curl-pipes a script —
  # that belongs in the student's own hands as an explicit guide step, not
  # buried mid-script. We only look in the standard locations, since a fresh
  # install is often not on the shell's PATH yet.
  if ! command -v brew >/dev/null 2>&1; then
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || true
    eval "$(/usr/local/bin/brew shellenv 2>/dev/null)" || true
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "ERROR: Homebrew is not installed (and no running Docker Desktop was found)."
    echo "Install it first — that is its own step in the Mac guide: open"
    echo "    https://brew.sh"
    echo "and run the install command shown there. Then open a NEW Terminal"
    echo "window and re-run this script."
    exit 1
  fi

  # Podman + compose provider
  say "Installing Podman and the docker-compose provider (skips what's present) ..."
  brew list podman         >/dev/null 2>&1 || brew install podman
  brew list docker-compose >/dev/null 2>&1 || brew install docker-compose

  # Podman machine (4 CPU / 5 GB / 40 GB) — the default machine (2 CPU / 2 GB)
  # is far too small. Measured (2026-08-21): the full stack idles at ~3 GB, so
  # 5120 MB leaves ~2 GB for notebooks/flows while keeping ~3 GB of an 8-GB
  # Mac for macOS + browser.
  if podman machine list --format '{{.Name}}' 2>/dev/null | grep -q .; then
    say "A Podman machine already exists — making sure it is running ..."
    podman info >/dev/null 2>&1 || podman machine start
  else
    say "Creating the Podman machine (4 CPU, 5 GB RAM, 40 GB disk) ..."
    podman machine init --cpus 4 --memory 5120 --disk-size 40 --now
  fi
  podman info >/dev/null 2>&1 || { echo "ERROR: Podman machine did not come up. Try: podman machine start"; exit 1; }

  pin_engine podman
fi

# ── 2. Ports, then images (USB bundle or download), then up and verify ───────
say "Checking that no other software sits on Kingo's ports ..."
./kingo fixports

# USB bundle: `setup-mac.sh /Volumes/<stick>/kingo-images-arm64.tar` loads the
# images from the instructor's stick instead of downloading; a
# kingo-images-<arch>.tar (or a legacy kingo-images.tar) sitting in this folder
# — copied from the stick — is picked up automatically. Bundles are single-arch
# (Macs are arm64), so we look for this machine's arch first; `kingo load`
# refuses a wrong-arch tar. Either way the pull below then skips what's present.
BUNDLE="${1:-}"
if [ -z "$BUNDLE" ]; then
  case "$(uname -m)" in arm64|aarch64) bundle_arch=arm64 ;; *) bundle_arch=amd64 ;; esac
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
  STICK="$(./kingo findbundle 2>/dev/null || true)"
  if [ -n "$STICK" ]; then
    say "Found the class images on a USB stick ($STICK)."
    say "Copying them to this folder (5-10 minutes) so you can pass the stick on ..."
    _tmp="./$(basename "$STICK").part"
    rm -f "$_tmp"
    if cp "$STICK" "$_tmp"; then
      mv "$_tmp" "./$(basename "$STICK")"
      BUNDLE="$(basename "$STICK")"
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
    */*) : ;;  # loaded straight from a stick path — nothing to clean up here
    *)   echo "    (you can now delete $BUNDLE in this folder to free ~13 GB)" ;;
  esac
fi

say "Making sure all container images are present (~10 GB download on a first run without the USB bundle) ..."
./kingo pull

say "Starting the Kingo stack ..."
./kingo up

say "Verifying the stack (smoke test) ..."
./kingo smoke

say "Done! Your class services:"
./kingo credentials
