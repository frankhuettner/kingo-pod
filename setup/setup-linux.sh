#!/usr/bin/env bash
# Kingo classroom — one-time setup for Linux. This is ALSO the Windows path:
# Windows students run it inside their WSL2 Ubuntu (see docs/STUDENT-GUIDE-
# WINDOWS.md). Re-runnable. Installs Podman + the Compose v2 provider binary,
# then brings the stack up and verifies it.
#
#   bash setup/setup-linux.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# ── 0. Already have Docker running here? Use it — install nothing. ───────────
# Covers Docker Desktop's WSL integration on Windows and native Docker on
# Linux. The stack runs identically on it; Podman is only installed when no
# working engine is present.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
   && docker compose version >/dev/null 2>&1; then
  say "Docker is already running — using it. Nothing to install."
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

# ── 1. Podman + rootless prerequisites + curl ────────────────────────────────
if ! command -v podman >/dev/null 2>&1; then
  say "Installing Podman ..."
  $SUDO apt-get update
  $SUDO apt-get install -y podman uidmap curl
else
  command -v curl >/dev/null 2>&1 || { $SUDO apt-get update; $SUDO apt-get install -y curl; }
fi

# Rootless podman needs a subuid/subgid range for the user (usually preset, but
# fresh WSL Ubuntu images sometimes lack it).
me="$(id -un)"
if ! grep -q "^${me}:" /etc/subuid 2>/dev/null; then
  say "Configuring rootless user namespaces for ${me} ..."
  $SUDO usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$me" 2>/dev/null || true
  podman system migrate 2>/dev/null || true
fi

# ── 2. Compose v2 provider binary ────────────────────────────────────────────
# Must be Compose v2. NOT the apt 'docker-compose' package (that is the old
# Python v1) and NOT podman-compose (breaks depends_on: service_healthy, §4).
compose_v2_ok() { docker-compose version --short 2>/dev/null | grep -qE '^v?2\.'; }
if ! compose_v2_ok; then
  say "Installing the Compose v2 provider binary ..."
  arch="$(uname -m)"   # x86_64 or aarch64
  tag="$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
         | grep -o '"tag_name":[^,]*' | cut -d'"' -f4 || true)"
  [ -n "$tag" ] || tag="v2.40.0"   # fallback if the API is rate-limited
  $SUDO curl -fsSL "https://github.com/docker/compose/releases/download/${tag}/docker-compose-linux-${arch}" \
    -o /usr/local/bin/docker-compose
  $SUDO chmod +x /usr/local/bin/docker-compose
fi
compose_v2_ok || { echo "ERROR: Compose v2 provider is not available on PATH"; exit 1; }

# Native/rootless podman needs no 'podman machine' — on WSL, WSL2 IS the Linux VM.
say "Podman: $(podman --version)   Compose: v$(docker-compose version --short)"

# ── 3. Bring the stack up and verify ─────────────────────────────────────────
say "Checking that no other software sits on Kingo's ports ..."
./kingo fixports

say "Starting the Kingo stack (first run downloads ~10 GB — do this on home Wi-Fi) ..."
./kingo up

say "Verifying the stack (smoke test) ..."
./kingo smoke

say "Done! Your class services:"
./kingo credentials
