#!/usr/bin/env bash
# A trial, not a check: can Claude click through a page with Playwright inside the sandbox of `kingo claude`?
#
#   playwright-trial.sh
#
# look makes pictures of a page; it cannot click. Playwright can, in three forms, and each is tried here with the
# browser that kingo downloads (not one of Playwright's own):
#   CLI   @playwright/cli: one command per step. A browser stays open in between, and the commands reach it
#         through a Unix socket. Under Linux, kingo's lock (no_unix_sockets.py) refuses Unix sockets.
#   MCP   @playwright/mcp: a server that Claude Code starts and talks to through pipes.
#   lib   a script with playwright-core, which Claude could write itself.
# Each form runs outside the sandbox first (or nothing would be proven), then inside nono with the course profile,
# under Linux through the lock as kingo claude starts Claude Code. This script fails only when it cannot set up.
# Everything else is a line RESULT, and the list of them comes again at the end.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KINGO_DIR=$(cd "$HERE/../.." && pwd)
CFG="$HOME/.kingo-claude"
DIR="$KINGO_DIR/claude"
PW="$HOME/pw-trial"                # where Playwright is installed: outside the folders the sandbox can write
CLI_VERSION=0.1.24
MCP_VERSION=0.0.85
# Round 2: the MCP server of today opens a Unix socket for its browser (round 1: "listen EPERM ... browser-....sock").
# 0.0.69 (30 March 2026) is the last version whose code has no such socket; 0.0.70 is the first that has it.
MCP_OLD="0.0.69 0.0.70"
PROFILE=kingo-claude
OS=$(uname -s)
LOCK=()
[ "$OS" != Linux ] || LOCK=(/usr/bin/python3 -I "$KINGO_DIR/setup/claude/no_unix_sockets.py")   # as in kingo
USE_LOCK=1
RESULTS=()

say()  { printf '\n── %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
show() { printf '%s\n' "$1" | tail -n "${2:-6}" | cut -c1-300 | sed 's/^/         | /'; }
die()  { printf '   FAIL  %s\n' "$*"; exit 1; }
note() { RESULTS+=("$1"); printf '   RESULT  %s\n' "$1"; }
limit() {  # limit <seconds> command ...
  if command -v timeout >/dev/null 2>&1; then timeout -k 5 "$@"; else perl -e 'alarm shift; exec @ARGV' "$@"; fi
}
sweep() {  # what an attempt may have left running
  pkill -9 -f chrome-headless-shell >/dev/null 2>&1
  pkill -9 -f "$PW/" >/dev/null 2>&1
  pkill -9 -f 'http.server 8765' >/dev/null 2>&1
  return 0
}

# ── setup ────────────────────────────────────────────────────────────────────
say "what kingo claude would start"
mkdir -p "$HOME/.config/kingo"; chmod 700 "$HOME/.config/kingo"
for k in openrouter n8n langflow; do ( umask 077; printf 'ci-placeholder' > "$HOME/.config/kingo/$k.key" ); done
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude 2>&1) || { show "$dry" 8; die "kingo claude did not get as far as the start of Claude Code"; }
show "$dry" 2
NONO_BIN=$(ls "$HOME"/.local/share/kingo/nono/*/nono 2>/dev/null | head -n 1)
[ -x "$NONO_BIN" ] || die "kingo's nono is not in ~/.local/share/kingo/nono (the workflow runs ./kingo claude nono first)"
ok "nono: $("$NONO_BIN" --version | head -n 1)"

say "kingo gets the browser"
out=$(cd "$KINGO_DIR" && ./kingo claude browser 2>&1) || {
  show "$out" 6
  line=$(printf '%s\n' "$out" | sed -n 's/^ *\(sudo apt-get install -y .*\)$/\1/p')
  [ -n "$line" ] || die "kingo claude browser failed and named no packages"
  sudo apt-get update -q >/dev/null
  $line >/dev/null || die "the line that kingo named did not install: $line"
  out=$(cd "$KINGO_DIR" && ./kingo claude browser 2>&1) || { show "$out" 6; die "the browser does not run after the packages that kingo named"; }
}
BROWSER_BIN=$(find "$HOME/.local/share/kingo/browsers" -type f -name chrome-headless-shell 2>/dev/null | head -n 1)
[ -x "$BROWSER_BIN" ] || die "the browser is not in ~/.local/share/kingo/browsers"
ok "the browser: $("$BROWSER_BIN" --version 2>/dev/null | head -n 1)"

say "Node.js and Playwright, outside the sandbox"
command -v node >/dev/null 2>&1 || die "there is no Node.js on this machine"
NODE_REAL=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$(command -v node)")
NODE_HOME=$(dirname "$(dirname "$NODE_REAL")")
ok "Node.js $(node --version) at $(command -v node) (the program itself: $NODE_REAL)"
mkdir -p "$PW"
( cd "$PW" && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --ignore-scripts --no-audit --no-fund \
    "@playwright/cli@$CLI_VERSION" "@playwright/mcp@$MCP_VERSION" 2>&1 | tail -n 3 ) || die "npm did not install Playwright"
[ -x "$PW/node_modules/.bin/playwright-cli" ] && [ -f "$PW/node_modules/@playwright/mcp/cli.js" ] || die "Playwright is not in $PW"
for v in $MCP_OLD; do
  mkdir -p "$PW/old/$v"
  # a package.json of its own: without one, npm installs into the folder above, which has one
  ( cd "$PW/old/$v" && printf '{"name": "pw-trial-old", "private": true}\n' > package.json && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --ignore-scripts --no-audit --no-fund "@playwright/mcp@$v" 2>&1 | tail -n 1 ) \
    || die "npm did not install the MCP server $v"
  [ -f "$PW/old/$v/node_modules/@playwright/mcp/cli.js" ] || die "the MCP server $v is not in $PW/old/$v"
done
note "size: the MCP server 0.0.69 alone with what it needs: $(du -sh "$PW/old/0.0.69/node_modules" | cut -f1) on disk"
note "size: Playwright's CLI $CLI_VERSION and MCP server $MCP_VERSION with what they need: $(du -sh "$PW/node_modules" | cut -f1) on disk, Node.js $(node --version) besides"
skill=$(find "$PW/node_modules" -path '*skills/playwright-cli/SKILL.md' | head -n 1)
[ -z "$skill" ] || note "size: the skill that tells an agent how to use the CLI is $(wc -c < "$skill" | tr -d ' ') characters (read when needed)"

mkdir -p "$DIR/.playwright" "$CFG/tmp"
cat > "$DIR/pw-shop.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Order form</title></head><body>
<h1>Order form</h1>
<label>Name <input id="name" name="name"></label>
<label>Product <select id="product"><option>Tea</option><option>Coffee</option></select></label>
<button id="go" onclick="document.getElementById('out').textContent='Thank you, '+document.getElementById('name').value+': 1 '+document.getElementById('product').value">Order</button>
<p id="out"></p>
</body></html>
HTML
# The browser is kingo's, and it runs without Chrome's own sandbox, as look runs it (nono is the sandbox here).
config() { printf '{"browser": {"launchOptions": {"executablePath": "%s", "chromiumSandbox": false, "args": ["--no-sandbox", "--disable-gpu"%s]}}}\n' "$BROWSER_BIN" "$1"; }
config ''                       > "$DIR/.playwright/cli.config.json"   # where the CLI looks by itself
config ', "--single-process"'   > "$DIR/pw-single.json"                # Chrome as one program, as look's second try on a Mac
URL="file://$DIR/pw-shop.html"
MCP=(node "$PW/node_modules/@playwright/mcp/cli.js" --headless --isolated --allow-unrestricted-file-access)
# What Playwright needs to know. Inside nono these go after the "--": the profile lets only its own variables in.
PW_ENV=(PLAYWRIGHT_BROWSERS_PATH="$CFG/tmp/pw-home" PLAYWRIGHT_MCP_ALLOW_UNRESTRICTED_FILE_ACCESS=1 PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1)

# plain command ...: in the course folder, outside the sandbox.   boxed command ...: inside nono, as kingo claude
# runs Claude Code (under Linux through the lock, unless USE_LOCK=0). EXTRA_READ: more folders to read.
plain() {
  ( cd "$DIR" && TMPDIR="$CFG/tmp" PATH="$PW/node_modules/.bin:$PATH" limit 200 env "${PW_ENV[@]}" "$@" ) 2>&1
}
EXTRA_READ=(--read "$PW" --read "$NODE_HOME")
boxed() {
  local lock=()
  [ "$USE_LOCK" = 0 ] || lock=(${LOCK[@]+"${LOCK[@]}"})
  ( cd "$DIR" &&
    CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_TMPDIR="$CFG/tmp" TMPDIR="$CFG/tmp" NONO_NO_SAVE_PROMPT=1 \
    PATH="$PW/node_modules/.bin:$KINGO_DIR/setup/claude/bin:$PATH" KINGO_BROWSER="$BROWSER_BIN" \
      limit 200 "$NONO_BIN" run --profile "$PROFILE" --allow-cwd --read "$KINGO_DIR" ${EXTRA_READ[@]+"${EXTRA_READ[@]}"} -- \
      ${lock[@]+"${lock[@]}"} env "${PW_ENV[@]}" "$@" ) 2>&1
}

# attempt <name> <CLI|MCP|LIB> command ...: run it, keep the line with the result, show the end when it failed
LAST=""
attempt() {
  local name=$1 kind=$2 out line; shift 2
  say "$name"
  out=$("$@")
  sweep
  printf '%s\n' "$out" | grep '^   step  ' | cut -c1-200 || true
  line=$(printf '%s\n' "$out" | grep "^$kind-RESULT " | tail -n 1 | cut -c1-900)
  if [ -z "$line" ]; then line="$kind-RESULT failed: no result came back (stopped after 200 seconds, or ended before)"; fi
  case "$line" in *"-RESULT ok"*) LAST=ok ;; *) LAST=failed; show "$out" 14 ;; esac
  note "$name: ${line#*-RESULT }"
}

# ── outside the sandbox: the comparison ──────────────────────────────────────
attempt "outside the sandbox, CLI" CLI plain bash "$HERE/playwright_trial_cli.sh" "$URL"
attempt "outside the sandbox, MCP" MCP plain node "$HERE/playwright_trial_mcp.js" "$URL" -- "${MCP[@]}" --config "$DIR/.playwright/cli.config.json"
for v in $MCP_OLD; do
  attempt "outside the sandbox, MCP $v" MCP plain env MCP_TARGET_KEY=ref node "$HERE/playwright_trial_mcp.js" "$URL" -- \
    node "$PW/old/$v/node_modules/@playwright/mcp/cli.js" --headless --isolated --allow-unrestricted-file-access --config "$DIR/.playwright/cli.config.json"
done
mkdir -p "$DIR/look"
attempt "outside the sandbox, a script with playwright-core" LIB plain node "$HERE/playwright_trial_lib.js" "$PW" "$BROWSER_BIN" "$URL" "$DIR/look/pw-lib-outside.png"

# ── under the lock by itself (Linux) ─────────────────────────────────────────
if [ "$OS" = Linux ]; then
  attempt "under the lock, without nono, CLI" CLI plain "${LOCK[@]}" bash "$HERE/playwright_trial_cli.sh" "$URL"
  attempt "under the lock, without nono, MCP" MCP plain "${LOCK[@]}" node "$HERE/playwright_trial_mcp.js" "$URL" -- "${MCP[@]}" --config "$DIR/.playwright/cli.config.json"
  attempt "under the lock, without nono, MCP 0.0.69" MCP plain "${LOCK[@]}" env MCP_TARGET_KEY=ref node "$HERE/playwright_trial_mcp.js" "$URL" -- \
    node "$PW/old/0.0.69/node_modules/@playwright/mcp/cli.js" --headless --isolated --allow-unrestricted-file-access --config "$DIR/.playwright/cli.config.json"
fi

# ── inside nono ──────────────────────────────────────────────────────────────
in=inside\ nono; [ "$OS" != Linux ] || in="inside nono, under the lock"

say "Node.js inside nono, with only what the course profile lets it read"
EXTRA_READ=()
out=$(boxed node --version)
EXTRA_READ=(--read "$PW" --read "$NODE_HOME")
if printf '%s\n' "$out" | grep -q '^v[0-9]'; then note "Node.js starts inside nono with the course profile as it is"
else show "$out" 4; note "Node.js does not start inside nono with the course profile as it is: the profile would need read access to $NODE_HOME"; fi

if [ "$OS" = Linux ]; then
  USE_LOCK=0
  attempt "inside nono, without the lock, CLI" CLI boxed bash "$HERE/playwright_trial_cli.sh" "$URL"
  USE_LOCK=1
fi
attempt "$in, CLI" CLI boxed bash "$HERE/playwright_trial_cli.sh" "$URL"
say "what the CLI left in the course folder and in the temporary folder"
ls -la "$DIR/.playwright-cli" 2>/dev/null | tail -n 6 | sed 's/^/         | /'
find "$CFG/tmp" -maxdepth 3 \( -name 'pw*' -o -name 'playwright*' \) 2>/dev/null | head -n 12 | sed 's/^/         | /'

attempt "$in, MCP $MCP_VERSION" MCP boxed node "$HERE/playwright_trial_mcp.js" "$URL" -- "${MCP[@]}" --config "$DIR/.playwright/cli.config.json"
mcp_cfg="$DIR/.playwright/cli.config.json"
for v in $MCP_OLD; do
  attempt "$in, MCP $v" MCP boxed env MCP_TARGET_KEY=ref node "$HERE/playwright_trial_mcp.js" "$URL" -- \
    node "$PW/old/$v/node_modules/@playwright/mcp/cli.js" --headless --isolated --allow-unrestricted-file-access --config "$mcp_cfg"
  if [ "$LAST" != ok ] && [ "$v" = 0.0.69 ]; then
    attempt "$in, MCP $v, Chrome as one program" MCP boxed env MCP_TARGET_KEY=ref node "$HERE/playwright_trial_mcp.js" "$URL" -- \
      node "$PW/old/$v/node_modules/@playwright/mcp/cli.js" --headless --isolated --allow-unrestricted-file-access --config "$DIR/pw-single.json"
    [ "$LAST" != ok ] || mcp_cfg="$DIR/pw-single.json"
  fi
done
# from here on: the MCP server that has no socket
MCP=(env MCP_TARGET_KEY=ref node "$HERE/playwright_trial_mcp.js")
OLD=(node "$PW/old/0.0.69/node_modules/@playwright/mcp/cli.js" --headless --isolated --allow-unrestricted-file-access --config "$mcp_cfg")
attempt "$in, a script with playwright-core" LIB boxed node "$HERE/playwright_trial_lib.js" "$PW" "$BROWSER_BIN" "$URL" "$DIR/look/pw-lib.png"
[ "$LAST" = ok ] || attempt "$in, a script with playwright-core, Chrome as one program" LIB boxed node "$HERE/playwright_trial_lib.js" "$PW" "$BROWSER_BIN" "$URL" "$DIR/look/pw-lib.png" single

# A page from a web server that runs inside the sandbox too, as a student's own small app would.
say "$in: a web server on this laptop (127.0.0.1:8765), asked with curl"
out=$(boxed sh -c 'python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1 & sleep 2
  echo "curl-through-the-proxy=$(curl -s -m 10 -o /dev/null -w "%{http_code}" http://127.0.0.1:8765/pw-shop.html)"
  echo "curl-directly=$(curl -s -m 10 --noproxy "*" -o /dev/null -w "%{http_code}" http://127.0.0.1:8765/pw-shop.html)"
  kill %1 2>/dev/null')
sweep
show "$(printf '%s\n' "$out" | grep '^curl-')" 2
note "$in, a web server of one's own on 127.0.0.1: $(printf '%s\n' "$out" | grep '^curl-' | tr '\n' ' ')(200 means the page came)"
attempt "$in, MCP 0.0.69, the page from a web server on 127.0.0.1" MCP boxed sh -c 'python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1 & sleep 2; "$@"; rc=$?; kill %1 2>/dev/null; exit $rc' sh \
  "${MCP[@]}" "http://127.0.0.1:8765/pw-shop.html" -- "${OLD[@]}"

# A page of the internet: the browser has to go through nono's proxy, like every program in the sandbox.
attempt "$in, MCP 0.0.69, a page of the internet (example.com)" MCP boxed env MCP_ONLY_NAVIGATE="Example Domain" \
  "${MCP[@]}" "https://example.com/" -- "${OLD[@]}"

# A Mac only: nono can allow Unix sockets in one folder there (under Linux the lock refuses all of them, whatever
# the profile says). A copy of the course profile with such a rule for the temporary folder: does today's MCP run?
if [ "$OS" = Darwin ]; then
  cat > "$HOME/.config/nono/profiles/kingo-claude-pwtrial.json" <<JSON
{
  "extends": "kingo-claude",
  "meta": { "name": "kingo-claude-pwtrial", "version": "0.0.1", "description": "trial: Unix sockets in the temporary folder" },
  "filesystem": { "unix_socket_subtree_bind": ["$CFG/tmp"] }
}
JSON
  PROFILE=kingo-claude-pwtrial
  attempt "inside nono on a Mac, with Unix sockets allowed in the temporary folder, MCP $MCP_VERSION" MCP boxed node "$HERE/playwright_trial_mcp.js" "$URL" -- \
    node "$PW/node_modules/@playwright/mcp/cli.js" --headless --isolated --allow-unrestricted-file-access --config "$DIR/.playwright/cli.config.json"
  PROFILE=kingo-claude
fi

printf '\n══ the results\n'
for line in "${RESULTS[@]}"; do printf '   %s\n' "$line"; done
printf '\nThe trial ran to its end.\n'
