#!/usr/bin/env bash
# Kingo classroom — one-time Mac setup. Re-runnable (safe to run again if it
# stops partway). Installs Podman + the docker-compose provider, creates a
# Podman machine with enough resources, then brings the stack up and verifies.
#
#   bash setup/setup-mac.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# ── 0. Already have Docker Desktop running? Use it — install nothing. ────────
# Many students arrive with Docker Desktop from another course. That is fine:
# the stack runs identically on it. We only install Podman when there is no
# working engine.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
   && docker compose version >/dev/null 2>&1; then
  say "Docker Desktop is already running — using it. Nothing to install."
  grep -q '^KINGO_ENGINE=' .env.local 2>/dev/null || echo 'KINGO_ENGINE=docker' >> .env.local

  say "Checking that no other software sits on Kingo's ports ..."
  ./kingo fixports

  say "Starting the Kingo stack (first run downloads ~10 GB — do this on home Wi-Fi) ..."
  ./kingo up
  say "Verifying the stack (smoke test) ..."
  ./kingo smoke
  say "Done! Your class services:"
  ./kingo credentials
  exit 0
fi
if command -v docker >/dev/null 2>&1; then
  say "Note: Docker is installed but not running, so this script sets up Podman instead."
  echo "     (Prefer Docker? Quit this script (Ctrl+C), start Docker Desktop, re-run.)"
fi

# ── 1. Homebrew ──────────────────────────────────────────────────────────────
if ! command -v brew >/dev/null 2>&1; then
  # Load brew if it is installed but not yet on PATH (fresh shells on Apple Si).
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || true
  eval "$(/usr/local/bin/brew shellenv 2>/dev/null)" || true
fi
if ! command -v brew >/dev/null 2>&1; then
  say "Installing Homebrew (you may be asked for your Mac password) ..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)" || true
  eval "$(/usr/local/bin/brew shellenv 2>/dev/null)" || true
fi
command -v brew >/dev/null 2>&1 || { echo "ERROR: Homebrew still not on PATH. Open a new Terminal and re-run."; exit 1; }

# ── 2. Podman + compose provider ─────────────────────────────────────────────
say "Installing Podman and the docker-compose provider (skips what's present) ..."
brew list podman         >/dev/null 2>&1 || brew install podman
brew list docker-compose >/dev/null 2>&1 || brew install docker-compose

# ── 3. Podman machine (4 CPU / 6 GB / 40 GB) ─────────────────────────────────
# The default machine (2 CPU / 2 GB) is far too small — the stack needs ~6 GB.
if podman machine list --format '{{.Name}}' 2>/dev/null | grep -q .; then
  say "A Podman machine already exists — making sure it is running ..."
  podman info >/dev/null 2>&1 || podman machine start
else
  say "Creating the Podman machine (4 CPU, 6 GB RAM, 40 GB disk) ..."
  podman machine init --cpus 4 --memory 6144 --disk-size 40 --now
fi
podman info >/dev/null 2>&1 || { echo "ERROR: Podman machine did not come up. Try: podman machine start"; exit 1; }

# ── 4. Bring the stack up and verify ─────────────────────────────────────────
say "Checking that no other software sits on Kingo's ports ..."
./kingo fixports

say "Starting the Kingo stack (first run downloads ~10 GB — do this on home Wi-Fi) ..."
./kingo up

say "Verifying the stack (smoke test) ..."
./kingo smoke

say "Done! Your class services:"
./kingo credentials
