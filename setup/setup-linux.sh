#!/usr/bin/env bash
# Kingo classroom — one-time setup for Linux. This is ALSO the Windows path:
# Windows students run it inside their WSL2 Ubuntu (see docs/STUDENT-GUIDE-
# WINDOWS.md). Re-runnable. Uses an already-running Docker as-is (Docker
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

# ── 1. Engine: keep a running stack's engine; else use a running Docker;
#      else install Podman ───────────────────────────────────────────────────
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
  command -v curl >/dev/null 2>&1 || { $SUDO apt-get update; $SUDO apt-get install -y curl; }
  pin_engine "$RUNNING_ENGINE"
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
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

  # Compose v2 provider binary. Must be Compose v2 — NOT the apt
  # 'docker-compose' package (the old Python v1) and NOT podman-compose
  # (breaks depends_on: service_healthy, plan §4).
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

  # Native/rootless podman needs no 'podman machine' — on WSL, WSL2 IS the VM.
  say "Podman: $(podman --version)   Compose: v$(docker-compose version --short)"

  pin_engine podman
fi

# ── 2. Ports, then bring the stack up and verify ─────────────────────────────
say "Checking that no other software sits on Kingo's ports ..."
./kingo fixports

say "Downloading the container images (~10 GB on the first run — the long part; do this on home Wi-Fi) ..."
./kingo pull

say "Starting the Kingo stack ..."
./kingo up

say "Verifying the stack (smoke test) ..."
./kingo smoke

say "Done! Your class services:"
./kingo credentials
