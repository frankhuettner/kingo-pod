#!/usr/bin/env bash
# Round 3 of the trial, not a check: may a program inside the sandbox of `kingo claude` listen on one port of
# localhost, and on no other port and no other address?
#
#   port-trial.sh
#
# Mac: nono opens listening only for all ports at once ("Seatbelt cannot filter by TCP port"). Seatbelt's own rules
# name an address and a port, as the course profile already does for PostgreSQL. So a copy of the course profile gets
# three such rules for port 8101 (unsafe_macos_seatbelt_rules). Does Seatbelt keep to them when a program listens?
# Linux: nono's open_port for 8101, which Landlock limits to the port number, not to the address.
# Then: the page from such a server, clicked through with playwright-core inside the sandbox; and a page of the
# internet, with and without nono's proxy given to the browser.
# This script fails only when it cannot set up. Everything else is a line RESULT, listed again at the end.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KINGO_DIR=$(cd "$HERE/../.." && pwd)
CFG="$HOME/.kingo-claude"
DIR="$KINGO_DIR/claude"
SITE="$DIR/site"
PW="$HOME/pw-trial3"
CORE_VERSION=1.65.1
PORT=8101          # the one that is opened
OTHER=8102         # one that is not
POD=5678           # the port of n8n in the pod
PG=5432            # the port of PostgreSQL in the pod
OS=$(uname -s)
LOCK=()
[ "$OS" != Linux ] || LOCK=(/usr/bin/python3 -I "$KINGO_DIR/setup/claude/no_unix_sockets.py")   # as in kingo
PROFILE=kingo-claude
RESULTS=()

say()  { printf '\n── %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
show() { printf '%s\n' "$1" | tail -n "${2:-6}" | cut -c1-300 | sed 's/^/         | /'; }
die()  { printf '   FAIL  %s\n' "$*"; exit 1; }
note() { RESULTS+=("$1"); printf '   RESULT  %s\n' "$1"; }
limit() { if command -v timeout >/dev/null 2>&1; then timeout -k 5 "$@"; else perl -e 'alarm shift; exec @ARGV' "$@"; fi; }
sweep() {
  pkill -9 -f chrome-headless-shell >/dev/null 2>&1
  pkill -9 -f "port_probe.py serve" >/dev/null 2>&1
  return 0
}

# ── setup ────────────────────────────────────────────────────────────────────
say "what kingo claude would start"
mkdir -p "$HOME/.config/kingo"; chmod 700 "$HOME/.config/kingo"
for k in openrouter n8n langflow; do ( umask 077; printf 'ci-placeholder' > "$HOME/.config/kingo/$k.key" ); done
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude 2>&1) || { show "$dry" 8; die "kingo claude did not get as far as the start of Claude Code"; }
NONO_BIN=$(ls "$HOME"/.local/share/kingo/nono/*/nono 2>/dev/null | head -n 1)
[ -x "$NONO_BIN" ] || die "kingo's nono is not in ~/.local/share/kingo/nono"
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

say "Node.js and playwright-core $CORE_VERSION, outside the sandbox"
command -v node >/dev/null 2>&1 || die "there is no Node.js on this machine"
mkdir -p "$PW"
( cd "$PW" && printf '{"name": "pw-trial3", "private": true}\n' > package.json &&
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --ignore-scripts --no-audit --no-fund "playwright-core@$CORE_VERSION" 2>&1 | tail -n 1 ) \
  || die "npm did not install playwright-core"
[ -f "$PW/node_modules/playwright-core/package.json" ] || die "playwright-core is not in $PW"
ok "Node.js $(node --version), playwright-core $CORE_VERSION ($(du -sh "$PW/node_modules" | cut -f1))"
command -v python3 >/dev/null 2>&1 || die "there is no python3 on this machine"

mkdir -p "$SITE" "$DIR/look" "$CFG/tmp"
cat > "$SITE/pw-shop.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Order form</title></head><body>
<h1>Order form</h1>
<label>Name <input id="name" name="name"></label>
<label>Product <select id="product"><option>Tea</option><option>Coffee</option></select></label>
<button id="go" onclick="document.getElementById('out').textContent='Thank you, '+document.getElementById('name').value+': 1 '+document.getElementById('product').value">Order</button>
<p id="out"></p>
</body></html>
HTML

say "a copy of the course profile that opens port $PORT"
P="$HOME/.config/nono/profiles/kingo-claude-port.json"
if [ "$OS" = Darwin ]; then
  cat > "$P" <<JSON
{
  "extends": "kingo-claude",
  "meta": { "name": "kingo-claude-port", "version": "0.0.1", "description": "trial: listen on localhost:$PORT only" },
  "unsafe_macos_seatbelt_rules": [
    "(allow network-bind (local tcp \"localhost:$PORT\"))",
    "(allow network-inbound (local tcp \"localhost:$PORT\"))",
    "(allow network-outbound (remote tcp \"localhost:$PORT\"))"
  ]
}
JSON
else
  cat > "$P" <<JSON
{
  "extends": "kingo-claude",
  "meta": { "name": "kingo-claude-port", "version": "0.0.1", "description": "trial: port $PORT opened with open_port" },
  "network": { "open_port": [$PORT] }
}
JSON
fi
out=$("$NONO_BIN" profile validate "$P" 2>&1) || { show "$out" 8; die "nono does not take the profile with the port"; }
show "$out" 2
ok "nono takes the profile"
sed 's/^/         | /' "$P"

# plain command ...: outside the sandbox.   boxed command ...: inside nono with $PROFILE, as kingo claude runs
# Claude Code (under Linux through the lock).
plain() { ( cd "$DIR" && limit 120 "$@" ) 2>&1; }
boxed() {
  ( cd "$DIR" &&
    CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_TMPDIR="$CFG/tmp" TMPDIR="$CFG/tmp" NONO_NO_SAVE_PROMPT=1 \
    PATH="$KINGO_DIR/setup/claude/bin:$PATH" KINGO_BROWSER="$BROWSER_BIN" \
      limit 150 "$NONO_BIN" run --profile "$PROFILE" --allow-cwd --read "$KINGO_DIR" --read "$PW" -- \
      ${LOCK[@]+"${LOCK[@]}"} "$@" ) 2>&1
}

# probe <label> <expected: OK, REFUSED or ANY> <plain|boxed> <host> <port>
probe() {
  local label=$1 want=$2 run=$3 out got verdict
  out=$($run python3 "$HERE/port_probe.py" bind "$4" "$5")
  got=$(printf '%s\n' "$out" | grep -o 'BIND-\(OK\|REFUSED\|INUSE\).*' | tail -n 1)
  if [ -z "$got" ]; then show "$out" 8; got="no answer"; fi
  case "$want:$got" in
    ANY:*) verdict="" ;;
    *:BIND-"$want"*) verdict=" (as expected)" ;;
    *) verdict=" (NOT as expected: $want was expected)" ;;
  esac
  note "$label, listen on $4:$5: ${got#BIND-}$verdict"
}
if [ "$OS" = Darwin ]; then ALL=REFUSED; PGW=REFUSED; else ALL=OK; PGW=OK; fi

# ── listening ────────────────────────────────────────────────────────────────
say "outside the sandbox, as a comparison: every port can be listened on here"
for hp in "127.0.0.1 $PORT" "127.0.0.1 $OTHER" "0.0.0.0 $PORT" "::1 $PORT" "127.0.0.1 $POD" "127.0.0.1 $PG"; do
  probe "outside the sandbox" OK plain $hp
done

say "inside nono with the course profile as it is"
PROFILE=kingo-claude
probe "course profile as it is" REFUSED boxed 127.0.0.1 "$PORT"

say "inside nono with the profile that opens port $PORT"
PROFILE=kingo-claude-port
probe "with port $PORT opened" OK boxed 127.0.0.1 "$PORT"
probe "with port $PORT opened, another port" REFUSED boxed 127.0.0.1 "$OTHER"
probe "with port $PORT opened, all addresses (also the WLAN)" "$ALL" boxed 0.0.0.0 "$PORT"
probe "with port $PORT opened, localhost in IPv6" ANY boxed ::1 "$PORT"
probe "with port $PORT opened, the port of n8n" REFUSED boxed 127.0.0.1 "$POD"
probe "with port $PORT opened, the port of PostgreSQL (Linux: open_port, Mac: a rule for connecting only)" "$PGW" boxed 127.0.0.1 "$PG"

# ── a server inside, and who reaches it ──────────────────────────────────────
say "inside nono: a server on 127.0.0.1:$PORT, asked with curl and clicked through with playwright-core"
PROFILE=kingo-claude-port
out=$(boxed sh -c 'python3 "$1" serve 127.0.0.1 "$2" "$3" 60 & srv=$!; sleep 2
  echo "curl-directly=$(curl -s -m 10 --noproxy "*" -o /dev/null -w "%{http_code}" "http://127.0.0.1:$2/pw-shop.html")"
  echo "curl-through-the-proxy=$(curl -s -m 10 -o /dev/null -w "%{http_code}" "http://127.0.0.1:$2/pw-shop.html")"
  node "$4" "$5" "$6" "http://127.0.0.1:$2/pw-shop.html" "$7"
  kill $srv 2>/dev/null' sh "$HERE/port_probe.py" "$PORT" "$SITE" "$HERE/playwright_trial_page.js" "$PW" "$BROWSER_BIN" "$DIR/look/port-shop.png")
sweep
printf '%s\n' "$out" | grep -E '^(SERVE-|curl-|   step  )' | sed 's/^/         | /'
note "server inside on 127.0.0.1:$PORT: $(printf '%s\n' "$out" | grep -E '^(SERVE-|curl-)' | tr '\n' ' ')"
line=$(printf '%s\n' "$out" | grep '^PAGE-RESULT ' | tail -n 1)
[ -n "$line" ] || { show "$out" 10; line="PAGE-RESULT failed: no result came back"; }
note "playwright-core inside, the page from that server: ${line#PAGE-RESULT }"

say "outside the sandbox: does a program on this laptop reach the server inside?"
boxed python3 "$HERE/port_probe.py" serve 127.0.0.1 "$PORT" "$SITE" 20 > "$CFG/tmp/serve.log" 2>&1 &
bg=$!
sleep 6
code=$(curl -s -m 10 --noproxy '*' -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/pw-shop.html")
wait "$bg" 2>/dev/null
sweep
note "from outside the sandbox to the server inside on 127.0.0.1:$PORT: HTTP $code ($(grep -o 'SERVE-[A-Z]* [^ ]*' "$CFG/tmp/serve.log" | head -n 1))"

if [ "$ALL" = OK ]; then
  say "Linux: the server inside on all addresses, asked at the address of this machine in its network"
  if [ "$OS" = Darwin ]; then ip=$(ipconfig getifaddr en0 2>/dev/null); else ip=$(hostname -I 2>/dev/null | awk '{print $1}'); fi
  boxed python3 "$HERE/port_probe.py" serve 0.0.0.0 "$PORT" "$SITE" 20 > "$CFG/tmp/serve-all.log" 2>&1 &
  bg=$!
  sleep 6
  code=$(curl -s -m 10 --noproxy '*' -o /dev/null -w '%{http_code}' "http://$ip:$PORT/pw-shop.html")
  wait "$bg" 2>/dev/null
  sweep
  note "server inside on 0.0.0.0:$PORT, asked at $ip (the address of this machine in its network): HTTP $code"
fi

# ── a page of the internet ───────────────────────────────────────────────────
PROFILE=kingo-claude
for how in direct proxy; do
  say "inside nono with the course profile: a page of the internet with playwright-core ($how)"
  out=$(boxed node "$HERE/playwright_trial_page.js" "$PW" "$BROWSER_BIN" "https://example.com/" "$DIR/look/port-internet-$how.png" "$how")
  sweep
  printf '%s\n' "$out" | grep '^   step  ' | sed 's/^/         | /'
  line=$(printf '%s\n' "$out" | grep '^PAGE-RESULT ' | tail -n 1)
  [ -n "$line" ] || { show "$out" 10; line="PAGE-RESULT failed: no result came back"; }
  note "playwright-core inside, example.com, $( [ "$how" = proxy ] && echo "the browser told about nono's proxy" || echo "the browser not told about the proxy"): ${line#PAGE-RESULT }"
done

printf '\n══ the results\n'
for line in "${RESULTS[@]}"; do printf '   %s\n' "$line"; done
printf '\nThe trial ran to its end.\n'
