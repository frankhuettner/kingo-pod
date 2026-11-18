#!/usr/bin/env bash
# CI for look on a Mac: does Claude see the pages it writes inside the sandbox of `kingo claude`?
#
#   claude-look-mac.sh
#
# On a Mac, nono's sandbox keeps two things from Chrome (found on 14 Nov 2026):
#   - the sleep and wake notices of the system (IOKit, RootDomainUserClient). Chrome 159 goes on without them;
#     older builds crash.
#   - registering a Mach service, which Chrome does for its helper programs. The course profile has one rule that
#     allows exactly that name. Without the rule, look starts Chrome as one program (--single-process), which
#     cannot wait for a page's scripts.
# The checks: kingo gets its own nono and the browser; a program in the sandbox cannot change either; look makes
# pictures and a PDF inside nono with the course profile and waits for scripts; clickthrough fills in a form and opens a
# page of the internet through nono's proxy, and its pages cannot reach a service on this laptop by http or
# WebSocket, whatever the script does (its own routes, a copy of Playwright of its own, the other ways of Playwright's
# API); under a copy of the profile without the rule, look falls back to one program and says so.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KINGO_DIR=$(cd "$HERE/../.." && pwd)
CFG="$HOME/.kingo-claude"
DIR="$KINGO_DIR/claude"
PROFILE=kingo-claude
MODE=""                            # KINGO_BROWSER_MODE; kingo claude sets none
NONO_BIN=""
NODE_BIN_FOR_CLICKTHROUGH="" PW_DIR=""   # Node.js and playwright-core for clickthrough; filled in after kingo claude browser

say()  { printf '\n── %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
show() { printf '%s\n' "$1" | tail -n "${2:-6}" | cut -c1-200 | sed 's/^/         | /'; }
fail() { printf '   FAIL  %s\n' "$*"; exit 1; }
has()  { case "$1" in *"$2"*) return 0 ;; esac; return 1; }

# in_sandbox command ...: run it as kingo claude runs Claude Code; prints its output and nono's
in_sandbox() {
  ( cd "$DIR" &&
    CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_TMPDIR="$CFG/tmp" TMPDIR="$CFG/tmp" NONO_NO_SAVE_PROMPT=1 \
    PATH="$KINGO_DIR/setup/claude/bin:$PATH" KINGO_BROWSER="$BROWSER_BIN" KINGO_BROWSER_MODE="$MODE" \
    KINGO_NODE="$NODE_BIN_FOR_CLICKTHROUGH" KINGO_PLAYWRIGHT="$PW_DIR" KINGO_DEV_PORT=5173 \
      "$NONO_BIN" run --silent --profile "$PROFILE" --allow-cwd --read "$KINGO_DIR" -- "$@" ) 2>&1 || true
}
# clickthrough_block <where> command ...: a listener on the runner stands for n8n; the pages of clickthrough_block.js try to reach it
# by http and by WebSocket (setup/claude/clickthrough-setup.js closes both). curl reaches it first, or the check proves nothing.
clickthrough_block() {
  local where=$1 port=18765 log="$CFG/tmp/clickthrough-listener.log" out pid; shift
  mkdir -p "$CFG/tmp"; : > "$log"
  python3 "$HERE/clickthrough_listener.py" "$port" "$log" & pid=$!
  sleep 1
  curl -s -m 5 "http://127.0.0.1:$port/control" > /dev/null || true
  grep -q '/control' "$log" || { kill "$pid"; fail "the listener on port $port does not answer curl"; }
  : > "$log"
  out=$("$@" "$HERE/clickthrough_block.js" "$port" "$HERE/clickthrough_shop.html" https://github.com/ 2>&1) || true
  sleep 2; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  has "$out" BLOCK-DONE || { show "$out" 20; fail "$where, clickthrough_block.js did not finish"; }
  ! grep -q '^ARRIVED' "$log" || { show "$(cat "$log")" 12; fail "$where, a page in clickthrough reached a service on this laptop"; }
  has "$out" "BLOCK-GOTO clickthrough opens https pages and files" || { show "$out" 20; fail "$where, page.goto on an http address did not stop with clickthrough's words"; }
  ok "$where: no request arrived from the pages ($(grep -c '^TLS' "$log" || true) TLS handshakes, no request in them); page.goto said: $(printf '%s\n' "$out" | sed -n 's/^BLOCK-GOTO //p' | cut -c1-60) ..."
}
# clickthrough_dev <where> command ...: clickthrough --dev with a stand-in dev server (clickthrough_devserver.py) on the runner,
# outside nono, as a student's own terminal runs npm run dev. Its page loads, fetches and opens its WebSocket; a page
# of the internet must not reach it by http.
clickthrough_dev() {
  local where=$1 port=5173 log="$CFG/tmp/clickthrough-dev.log" out pid; shift
  mkdir -p "$CFG/tmp"; : > "$log"
  python3 "$HERE/clickthrough_devserver.py" "$port" "$log" > /dev/null & pid=$!
  sleep 1
  out=$("$@" --dev "$port" "$HERE/clickthrough_dev.js" "$port" https://github.com/ 2>&1) || true
  sleep 1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  has "$out" DEV-DONE || { show "$out" 20; show "$(cat "$log")" 8; fail "$where, clickthrough_dev.js did not finish"; }
  has "$out" "DEV-TITLE DEV-WS pong" || { show "$out" 20; show "$(cat "$log")" 8; fail "$where, the dev page's WebSocket did not answer"; }
  has "$out" "DEV-API dev answer" || { show "$out" 20; show "$(cat "$log")" 8; fail "$where, the dev page could not fetch from its server"; }
  has "$out" "DEV-AGAIN dev answer" || { show "$out" 20; show "$(cat "$log")" 8; fail "$where, page.goto of the script did not open the dev page from a data: page"; }
  ! grep -q 'from-internet-http' "$log" || { show "$(cat "$log")" 10; fail "$where, a page that does not come from the dev server reached it by http"; }
  ok "$where: the dev page loaded, fetched from its server and its WebSocket answered, also after page.goto from a data: page; no other page reached it by http, nor sent the tab there (a form, location, window.open)"
  if grep -q 'from-internet-ws' "$log"; then echo "   RESULT  a WebSocket of a page of the internet reached the dev server (expected: clickthrough cannot see WebSockets)"; fi
}
# clickthrough_dev_inside command ...: may a dev server listen inside nono? Reported, never a failure.
clickthrough_dev_inside() {
  local out
  out=$("$@" bash -c '"$1" "$2" 5173 "$3" & s=$!; sleep 2; clickthrough --dev 5173 "$4" 5173 https://github.com/; kill $s 2>/dev/null' _ \
    "/usr/bin/python3" "$HERE/clickthrough_devserver.py" "$CFG/tmp/clickthrough-dev-inside.log" "$HERE/clickthrough_dev.js")
  if has "$out" LISTEN-DENIED; then
    echo "   RESULT  inside nono a program may not listen on the dev port: $(printf '%s\n' "$out" | sed -n 's/^LISTEN-DENIED //p' | head -n 1)"
  elif has "$out" "DEV-TITLE DEV-WS pong"; then
    echo "   RESULT  inside nono a dev server may listen on the dev port, and clickthrough reaches it"
  else
    echo "   RESULT  inside nono: unclear"; show "$out" 12
  fi
}
# clickthrough_routes <where> command ...: the script's own routes (clickthrough_routes.js), with the stand-in dev server and a
# listener that stands for n8n. No page reaches the dev server past a route of the script, lock 2 stays after
# unrouteAll, and a redirect that Node.js would follow for route.fetch reaches nothing.
clickthrough_routes() {
  local where=$1 log="$CFG/tmp/clickthrough-routes-dev.log" llog="$CFG/tmp/clickthrough-routes-listener.log" out dpid lpid; shift
  mkdir -p "$CFG/tmp"; : > "$log"; : > "$llog"
  python3 "$HERE/clickthrough_devserver.py" 5173 "$log" > /dev/null & dpid=$!
  python3 "$HERE/clickthrough_listener.py" 18765 "$llog" & lpid=$!
  sleep 1
  out=$("$@" --dev 5173 "$HERE/clickthrough_routes.js" 5173 18765 2>&1) || true
  sleep 2; kill "$dpid" "$lpid" 2>/dev/null; wait "$dpid" "$lpid" 2>/dev/null || true
  has "$out" ROUTES-DONE || { show "$out" 20; show "$(cat "$log")" 8; fail "$where, clickthrough_routes.js did not finish"; }
  ! grep -q 'from-internet-http' "$log" || { show "$(cat "$log")" 10; fail "$where, a page reached the dev server by http past a route of the script"; }
  ! grep -q . "$llog" || { show "$(cat "$llog")" 8; fail "$where, a request reached the listener: a redirect that route.fetch followed in Node.js"; }
  if has "$out" "ROUTES-DEV dev answer"; then
    ok "$where: past the script's routes no page reached the dev server, lock 2 stayed after unrouteAll, and route.fetch followed no redirect"
  else
    # route.fetch sends the request from Node.js; inside nono through nono's proxy, which need not take the dev port
    case "$where" in outside*) show "$out" 12; fail "$where, the dev page did not come through route.fetch: the redirect was not tried" ;; esac
    echo "   RESULT  $where: the dev page did not come through route.fetch ($(printf '%s\n' "$out" | grep '^ROUTES-DEV' | cut -c1-60)), so the redirect was not tried here"
    ok "$where: past the script's routes no page reached the dev server, and lock 2 stayed after unrouteAll"
  fi
}
# clickthrough_copy <where> command ...: a folder with a copy of Playwright of its own in node_modules, as a Vite project
# may hold one: here a copy of kingo's, which would start the browser without the locks. A script there gets kingo's
# copy all the same: clickthrough_copy.js tries the ways to Playwright, and clickthrough_block.js, which names the browser
# itself there, reaches no service.
clickthrough_copy() {
  local where=$1 d="$DIR/copy" port=18765 log="$CFG/tmp/clickthrough-copy-listener.log" out pid w; shift
  rm -rf "$d"; mkdir -p "$d/node_modules" "$CFG/tmp"
  cp -R "$PW_DIR/node_modules/playwright-core" "$d/node_modules/"
  cp "$HERE/clickthrough_copy.js" "$HERE/clickthrough_block.js" "$d/"
  out=$("$@" "$d/clickthrough_copy.js" 2>&1) || true
  has "$out" COPY-DONE || { show "$out" 20; fail "$where, clickthrough_copy.js did not finish"; }
  for w in require require-playwright createRequire import import-playwright; do
    has "$out" "COPY $w kingo" || { show "$(printf '%s\n' "$out" | grep '^COPY')" 12; fail "$where, $w next to a copy of its own did not give kingo's playwright-core"; }
  done
  for w in require-path require-file import-path; do
    has "$out" "COPY $w refused clickthrough: the script loads a copy of Playwright of its own" \
      || { show "$(printf '%s\n' "$out" | grep '^COPY')" 12; fail "$where, $w loaded the copy of its own"; }
  done
  : > "$log"
  python3 "$HERE/clickthrough_listener.py" "$port" "$log" & pid=$!
  sleep 1
  out=$("$@" "$d/clickthrough_block.js" "$port" "$HERE/clickthrough_shop.html" https://github.com/ own 2>&1) || true
  sleep 2; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  rm -rf "$d"
  has "$out" BLOCK-DONE || { show "$out" 20; fail "$where, clickthrough_block.js next to a copy of Playwright did not finish"; }
  ! grep -q '^ARRIVED' "$log" || { show "$(cat "$log")" 12; fail "$where, next to a copy of Playwright of its own, a page reached a service on this laptop"; }
  has "$out" "BLOCK-GOTO clickthrough opens https pages and files" || { show "$out" 20; fail "$where, next to a copy of Playwright, page.goto on an http address did not stop with clickthrough's words"; }
  ok "$where: next to a copy of Playwright of its own, require and import by name get kingo's, the copy by its path is refused, and no page reached the listener"
}
# clickthrough_ways <where> command ...: the other ways of Playwright's API past the locks (clickthrough_ways.js). Each stops
# with clickthrough's words, and nothing connects to the listener.
clickthrough_ways() {
  local where=$1 port=18765 log="$CFG/tmp/clickthrough-ways-listener.log" out pid n; shift
  mkdir -p "$CFG/tmp"; : > "$log"
  python3 "$HERE/clickthrough_listener.py" "$port" "$log" & pid=$!
  sleep 1
  out=$("$@" "$HERE/clickthrough_ways.js" "$port" "$HERE/clickthrough_shop.html" 2>&1) || true
  sleep 2; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  has "$out" WAYS-DONE || { show "$out" 24; fail "$where, clickthrough_ways.js did not finish"; }
  n=$(printf '%s\n' "$out" | grep -c '^WAYS .* refused clickthrough' || true)
  [ "$n" = 15 ] || { show "$(printf '%s\n' "$out" | grep '^WAYS')" 24; fail "$where, $n of the 15 other ways were refused"; }
  ! grep -q . "$log" || { show "$(cat "$log")" 8; fail "$where, a page connected to the listener (a context with a proxy of its own, or ignoreDefaultArgs)"; }
  ok "$where: 15 other ways refused (launchServer, connect, connectOverCDP, bind, newBrowserCDPSession, firefox, webkit, clientCertificates twice, six arguments for Chrome); nothing connected to the listener"
}
# outside command ...: as in_sandbox, without nono
outside() {
  ( cd "$DIR" && KINGO_BROWSER="$BROWSER_BIN" KINGO_BROWSER_MODE="$MODE" \
    KINGO_NODE="$NODE_BIN_FOR_CLICKTHROUGH" KINGO_PLAYWRIGHT="$PW_DIR" "$@" ) 2>&1 || true
}
pictures() { # <how many> <name>
  local i
  for i in $(seq 1 "$1"); do
    python3 "$HERE/png_check.py" "$DIR/look/$2-$i.png" | sed 's/^/         | /' || fail "look/$2-$i.png is missing or shows nothing"
  done
  [ ! -e "$DIR/look/$2-$(( $1 + 1 )).png" ] || fail "there are more than $1 pictures of $2"
}

say "what kingo claude would start"
mkdir -p "$HOME/.config/kingo"; chmod 700 "$HOME/.config/kingo"
for k in openrouter n8n langflow; do ( umask 077; printf 'ci-placeholder' > "$HOME/.config/kingo/$k.key" ); done
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude) || fail "kingo claude did not get as far as the start of Claude Code"
show "$dry" 2
has "$dry" "--append-system-prompt When you have written or changed an HTML page, look at it" \
  || fail "kingo claude does not tell Claude Code how to look at a page"
has "$dry" "run it with: clickthrough <script.cjs>" || fail "kingo claude does not tell Claude Code how to try a page with clickthrough"
if has "$dry" no_unix_sockets.py; then fail "on a Mac, kingo claude would start Claude Code through the lock for Linux"; fi
ok "kingo claude tells Claude Code how to look at a page"
# The ports of kingo-pod, which clickthrough --dev refuses: in_sandbox below sets none, so clickthrough takes its own list,
# which must be kingo's (from its service table).
pods=$(printf '%s\n' "$dry" | sed -n 's/^  ports: .*KINGO_POD_PORTS=//p' | tr ' ' '\n' | grep . | sort -n | tr '\n' ' ' || true)
list=$(sed -n 's/.*KINGO_POD_PORTS:-\([0-9 ]*\)}.*/\1/p' "$KINGO_DIR/setup/claude/bin/clickthrough" | head -n 1 || true)
[ -n "$pods" ] || fail "the dry run does not name the ports of kingo-pod"
[ "$(printf '%s\n' $list | sort -n | tr '\n' ' ')" = "$pods" ] || fail "clickthrough's list of the ports of kingo-pod is not kingo's: '$list'; kingo says: $pods"
ok "clickthrough's list of the ports of kingo-pod is kingo's: $pods"
# --in on a Mac: no n8n there, and nothing for the user's own terminal; a dev server cannot listen in the sandbox here
mkdir -p "$HOME/projects/thesis"
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$HOME/projects/thesis") || fail "kingo claude --in did not get as far as the start of Claude Code"
if has "$dry" 'N8N_BASE_URL'; then fail "kingo claude --in tells Claude Code about n8n, which is not there"; fi
if has "$dry" "in their own terminal (npm run dev)"; then fail "kingo claude --in asks Claude Code to send the user to their own terminal, which CLAUDE_IN_HINT forbids"; fi
has "$dry" "On this Mac the sandbox lets no program listen on that port" || fail "on a Mac, kingo claude --in does not tell Claude Code that it cannot start a dev server"
ok "kingo claude --in names no n8n, and says that a dev server cannot listen in the sandbox on a Mac"
(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude > /dev/null) || fail "kingo claude did not write the profile of the course again"

say "kingo gets its own nono"
if command -v nono >/dev/null 2>&1; then echo "         | on the PATH of this job: $(command -v nono)"; fi
out=$(cd "$KINGO_DIR" && ./kingo claude nono 2>&1) || { show "$out" 8; fail "kingo claude nono failed"; }
show "$out" 3
NONO_BIN=$(ls "$HOME"/.local/share/kingo/nono/*/nono 2>/dev/null | head -n 1 || true)
[ -x "$NONO_BIN" ] || fail "kingo's nono is not in ~/.local/share/kingo/nono"
grep -q "^CLAUDE_NONO_VERSION=$("$NONO_BIN" --version | sed -n 's/^nono \([0-9.]*\).*/\1/p')\$" "$KINGO_DIR/kingo" \
  || fail "the nono that kingo downloaded says another version than kingo names: $("$NONO_BIN" --version)"
"$NONO_BIN" profile validate "$HOME/.config/nono/profiles/kingo-claude.json" > "$CFG/tmp/validate.log" 2>&1 \
  || { show "$(cat "$CFG/tmp/validate.log")" 6; fail "nono does not take the course profile"; }
grep -q 'allow mach-register (global-name-prefix .*org.chromium.Chromium.MachPortRendezvousServer\.' "$HOME/.config/nono/profiles/kingo-claude-core.json" \
  || fail "the core profile, which every profile of kingo claude extends, has no rule for Chrome's Mach service"
ok "nono is the one kingo downloaded ($("$NONO_BIN" --version | head -n 1)), and it takes the course profile"

say "kingo gets the browser"
out=$(cd "$KINGO_DIR" && ./kingo claude browser 2>&1) || { show "$out" 8; fail "kingo claude browser failed"; }
show "$out" 3
BROWSER_BIN=$(find "$HOME/.local/share/kingo/browsers" -type f -name chrome-headless-shell 2>/dev/null | head -n 1 || true)
[ -x "$BROWSER_BIN" ] || fail "the browser is not in ~/.local/share/kingo/browsers"
[ ! -e "$CFG/browsers" ] || fail "there is a browser in $CFG, a folder the sandbox can write"
ok "the browser is there: $BROWSER_BIN"
NODE_BIN_FOR_CLICKTHROUGH=$(ls "$HOME"/.local/share/kingo/node/*/node 2>/dev/null | head -n 1 || true)
PW_DIR=$(ls -d "$HOME"/.local/share/kingo/playwright/*/ 2>/dev/null | head -n 1 || true); PW_DIR=${PW_DIR%/}
[ -x "$NODE_BIN_FOR_CLICKTHROUGH" ] || fail "kingo claude browser did not get Node.js into ~/.local/share/kingo/node"
[ -f "$PW_DIR/node_modules/playwright-core/package.json" ] || fail "kingo claude browser did not get playwright-core into ~/.local/share/kingo/playwright"
ok "Node.js $("$NODE_BIN_FOR_CLICKTHROUGH" --version) and playwright-core, for clickthrough"

cat > "$DIR/look-cv.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Probe</title>
<style>body{font-family:sans-serif;margin:40px}h1{color:#1a4d8f}.bar{height:60px;background:linear-gradient(90deg,#e4572e,#f3a712,#76b041)}
.cols{display:flex;gap:20px;margin-top:20px}.cols div{flex:1;border:1px solid #888;padding:10px}</style></head>
<body><h1>Curriculum Vitae 이력서</h1><div class="bar"></div>
<div class="cols"><div><b>Education</b><br>MBA, 2026</div><div><b>Experience</b><br>Analyst, 2021 to 2025</div></div>
</body></html>
HTML
python3 - "$DIR/look-long.html" <<'PY'
import sys
rows = "".join("<tr><td>%d</td><td>Project %d</td></tr>" % (i, i) for i in range(1, 121))
open(sys.argv[1], "w").write("<!doctype html><meta charset=utf-8><style>td{border:1px solid #999;padding:6px}</style>"
                             "<h1 style='color:#1a4d8f'>Projects</h1><table>%s</table><p>END-OF-PAGE</p>" % rows)
PY
# 400 pixels at first; half a second later a script makes the page 3000 pixels high
cat > "$DIR/look-late.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;font-family:sans-serif}
.first{height:400px;background:linear-gradient(#e4572e,#76b041)}</style></head>
<body><div class="first">first</div><div id="more"></div>
<script>setTimeout(function () { var d = document.getElementById('more'); d.style.height = '2600px';
  d.style.background = 'linear-gradient(#1a4d8f,#f3a712)'; d.textContent = 'late'; }, 500)</script></body></html>
HTML
rm -rf "$DIR/look"

say "the comparison outside the sandbox: Chrome with its helper programs"
out=$(cd "$DIR" && KINGO_BROWSER="$BROWSER_BIN" KINGO_BROWSER_MODE="" bash "$KINGO_DIR/setup/claude/bin/look" look-late.html 2>&1) || true
has "$out" "is 1000 x 3000 pixels, in 3 picture(s)" || { show "$out" 12; fail "outside the sandbox look does not work on this machine: the checks below would prove nothing"; }
ok "outside the sandbox look waits for the script: 3000 pixels, three pictures"
rm -rf "$DIR/look"

# kingo starts nono and the browser outside the sandbox. A program inside must not be able to swap them.
say "the sandbox cannot change what kingo downloaded"
out=$(in_sandbox sh -c 'for f in "$@"; do if ( : >> "$f" ) 2>/dev/null; then echo "WROTE $f"; else echo "refused $f"; fi; done' sh \
  "$DIR/look-write-probe" "$BROWSER_BIN" "$(dirname "$BROWSER_BIN")/new-file" "$NONO_BIN" "$(dirname "$NONO_BIN")/new-file" \
  "$HOME/.local/share/kingo/new-file" "$NODE_BIN_FOR_CLICKTHROUGH" "$(dirname "$NODE_BIN_FOR_CLICKTHROUGH")/new-file" \
  "$PW_DIR/node_modules/playwright-core/package.json" "$PW_DIR/new-file")
show "$(printf '%s\n' "$out" | grep -E '^(WROTE|refused) ')" 10
has "$out" "WROTE $DIR/look-write-probe" || { show "$out" 20; fail "the probe proves nothing: it could not write in the course folder either"; }
[ "$(printf '%s\n' "$out" | grep -c '^refused ')" = 9 ] || fail "a program in the sandbox can write where kingo keeps nono, the browser, Node.js or playwright-core"
rm -f "$DIR/look-write-probe"
ok "inside the sandbox, the browser, nono, Node.js, playwright-core and their folders cannot be written"

# On a Mac, nono lists after the end what the sandbox refused, with "Fix flags" and a way to open the keychain (Frank's
# terminal, 18 Nov 2026). kingo claude starts nono with --silent: neither that report nor the banner shows.
say "nono is silent as kingo claude starts it: no banner, and no report with Fix flags at the end"
mkdir -p "$HOME/.claude" && echo outside > "$HOME/.claude/silent-probe.txt"   # as on a student's Mac: a folder the sandbox keeps closed
probe='cat "$HOME/.claude/silent-probe.txt"; cat "$HOME/.CFUserTextEncoding"; ls "$HOME/.claude"; echo probe-$((6*7))'
out=$(in_sandbox sh -c "$probe")
has "$out" probe-42 || { show "$out" 20; fail "the probe did not run in the sandbox"; }
if has "$out" "Capabilities" || has "$out" "Fix flags" || has "$out" "Sandbox denial"; then show "$out" 30; fail "nono, started as kingo claude starts it, still shows its banner or its report"; fi
loud=$( ( cd "$DIR" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_TMPDIR="$CFG/tmp" TMPDIR="$CFG/tmp" NONO_NO_SAVE_PROMPT=1 \
    "$NONO_BIN" run --profile "$PROFILE" --allow-cwd --read "$KINGO_DIR" -- sh -c "$probe" ) 2>&1 || true)
has "$loud" probe-42 && has "$loud" "Capabilities" || { show "$loud" 30; fail "without --silent, nono shows no banner: the check of --silent proves nothing"; }
if has "$loud" "Sandbox denial"; then echo "         | without --silent, nono reports what it refused: $(printf '%s\n' "$loud" | grep -c '(read)') paths"; else echo "         | without --silent, nono printed no report of refusals for this probe; it printed:"; show "$loud" 14; fi
if has "$out" "outside"; then fail "the sandbox let the probe read a file in ~/.claude"; fi
ok "with --silent, nono shows neither its banner nor a report; without it, the banner is there"
# nono writes its report of refusals only in a terminal (the run above has none, and shows none). script gives it
# one; perl ends a run that waits for a key. Only a report in spite of --silent fails: a runner without a terminal
# for script proves nothing, and says so.
in_terminal() {
  ( cd "$DIR" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_TMPDIR="$CFG/tmp" TMPDIR="$CFG/tmp" NONO_NO_SAVE_PROMPT=1 \
      perl -e 'alarm 90; exec @ARGV' script -q /dev/null "$NONO_BIN" run "$@" --profile "$PROFILE" --allow-cwd --read "$KINGO_DIR" -- sh -c "$probe" ) < /dev/null 2>&1 || true
}
loud=$(in_terminal)
out=$(in_terminal --silent)
if has "$out" "Capabilities" || has "$out" "Fix flags" || has "$out" "Sandbox denial"; then show "$out" 30; fail "in a terminal, nono with --silent still shows its banner or its report"; fi
if has "$loud" "Sandbox denial" && has "$out" probe-42; then
  echo "         | in a terminal, without --silent: $(printf '%s\n' "$loud" | grep -m 1 'Sandbox denial' | tr -d '\r')"
  if has "$loud" "Fix flags"; then echo "         | and it names Fix flags; with --silent, neither shows"; fi
  ok "in a terminal, nono reports what it refused, and with --silent it does not"
else
  echo "         | not shown on this runner: in a terminal, nono printed (without --silent, then with):"; show "$loud" 12; show "$out" 6
fi

# clickthrough: a script as Claude would write it fills in a form and sends it; then a page of the internet. On a Mac,
# Chrome does not take HTTPS_PROXY: clickthrough-setup.js gives it nono's proxy, or the page would not come.
say "clickthrough inside nono: a form is filled in and sent, and a page of the internet comes"
out=$(in_sandbox clickthrough "$HERE/clickthrough_check.js" "$HERE/clickthrough_shop.html" look/clickthrough-shop.png https://github.com/)
show "$(printf '%s\n' "$out" | grep '^CLICKTHROUGH-')" 3
has "$out" "CLICKTHROUGH-SAID Thank you, Mina: 1 Coffee" || { show "$out" 20; fail "clickthrough did not fill in and send the form inside the sandbox"; }
python3 "$HERE/png_check.py" "$DIR/look/clickthrough-shop.png" | sed 's/^/         | /' || fail "clickthrough made no picture of the page"
printf '%s\n' "$out" | grep '^CLICKTHROUGH-TITLE ' | grep -q GitHub || { show "$out" 20; fail "clickthrough did not get a page of the internet inside the sandbox"; }
ok "clickthrough filled in the form, read the answer, made a picture, and opened github.com"

# Outside nono a direct connection to 127.0.0.1 works; inside nono a page could go through nono's proxy, which lets the
# laptop's own addresses through when the network is open.
say "clickthrough: a page cannot reach a service on this laptop by http or WebSocket"
clickthrough_block "outside nono, without a proxy" outside bash "$KINGO_DIR/setup/claude/bin/clickthrough"
clickthrough_block "inside nono" in_sandbox clickthrough

# clickthrough --dev: the student's dev server on this laptop. On a Mac the profile has one Seatbelt rule for the dev port
# (KINGO_DEV_PORT, 5173), as for PostgreSQL.
say "clickthrough --dev 5173: the dev server's page works, and nothing else opens"
grep -q 'remote tcp \\"localhost:5173\\"' "$HOME/.config/nono/profiles/kingo-claude-core.json" \
  || fail "kingo did not open the dev port 5173 in the core profile (Seatbelt rule)"
out=$(in_sandbox clickthrough --dev 5678 "$HERE/clickthrough_dev.js")
has "$out" "is a port of kingo-pod" || { show "$out" 6; fail "clickthrough --dev 5678 did not refuse n8n's port"; }
ok "clickthrough --dev refuses n8n's port"
clickthrough_dev "outside nono, without a proxy" outside bash "$KINGO_DIR/setup/claude/bin/clickthrough"
clickthrough_dev "inside nono" in_sandbox clickthrough
clickthrough_block "inside nono, with --dev 5173" in_sandbox clickthrough --dev 5173
clickthrough_dev_inside in_sandbox

# Whatever the script does (setup/claude/clickthrough-setup.js): the locks hold for every way of Playwright's API.
say "clickthrough: the locks hold, whatever the script does (its own routes, a copy of Playwright of its own, other ways)"
clickthrough_routes "outside nono, without a proxy" outside bash "$KINGO_DIR/setup/claude/bin/clickthrough"
clickthrough_routes "inside nono" in_sandbox clickthrough
clickthrough_copy "outside nono, without a proxy" outside bash "$KINGO_DIR/setup/claude/bin/clickthrough"
clickthrough_copy "inside nono" in_sandbox clickthrough
clickthrough_ways "outside nono, without a proxy" outside bash "$KINGO_DIR/setup/claude/bin/clickthrough"
clickthrough_ways "inside nono" in_sandbox clickthrough

say "clickthrough in a Vite project, where a .js is an ES module; and --dev without leading zeros"
mkdir -p "$DIR/vite"; printf '{ "name": "a-vite-project", "type": "module" }\n' > "$DIR/vite/package.json"
cp "$HERE/clickthrough_check.js" "$DIR/vite/try.js"; cp "$HERE/clickthrough_check.js" "$DIR/vite/try.cjs"
out=$(in_sandbox clickthrough vite/try.js "$HERE/clickthrough_shop.html" look/vite.png)
has "$out" "Write the script as a .cjs file" || { show "$out" 6; fail "clickthrough did not stop at a .js in a project of type module, or did not say to write a .cjs"; }
out=$(in_sandbox clickthrough vite/try.cjs "$HERE/clickthrough_shop.html" look/vite.png)
has "$out" "CLICKTHROUGH-SAID Thank you, Mina: 1 Coffee" || { show "$out" 12; fail "clickthrough did not run the .cjs in a project of type module"; }
rm -rf "$DIR/vite"
out=$(in_sandbox clickthrough --dev 05678 "$HERE/clickthrough_dev.js")
has "$out" "a number without leading zeros" || { show "$out" 6; fail "clickthrough --dev 05678 did not refuse the leading zero"; }
ok "in a project of type module clickthrough asks for a .cjs, and the .cjs runs; --dev 05678 is refused"
rm -rf "$DIR/look"

# A font that the user installed: the system knows it by name; when the sandbox cannot read its file, the browser
# draws a box for every letter (found on 14 Nov 2026 with Pretendard). Reports, and fails only on boxes.
say "a font that the user installed (~/Library/Fonts)"
mkdir -p "$HOME/Library/Fonts"
if curl -fsSL -m 60 -o "$HOME/Library/Fonts/Pacifico-Regular.ttf" https://raw.githubusercontent.com/google/fonts/main/ofl/pacifico/Pacifico-Regular.ttf; then
  glyphs() { sed -n 's/.*<title>GLYPHS=\([^<]*\)<.*/\1/p' | head -n 1; }
  out=""
  for try in 1 2 3 4 5 6; do   # the system needs a moment to take a new font in
    out=$("$BROWSER_BIN" --headless --no-sandbox --disable-gpu --virtual-time-budget=3000 --user-data-dir="$CFG/tmp/font-outside-$try" --dump-dom "file://$HERE/font_check.html#Pacifico" 2>/dev/null | glyphs)
    [ "$out" = "Pacifico:own" ] && break; sleep 5
  done
  echo "         | outside the sandbox: ${out:-nothing}"
  if [ "$out" = "Pacifico:own" ]; then
    out=$(in_sandbox "$BROWSER_BIN" --headless --no-sandbox --disable-gpu --virtual-time-budget=3000 --user-data-dir="$CFG/tmp/font-inside" --dump-dom "file://$HERE/font_check.html#Pacifico" | glyphs)
    echo "         | inside the sandbox, course profile: ${out:-nothing}"
    [ "$out" != "Pacifico:boxes" ] || fail "inside the sandbox, a font that the user installed is drawn as boxes"
    [ "$out" = "Pacifico:own" ] && ok "the browser draws the user's font inside the sandbox" \
      || echo "   RESULT  inside the sandbox the user's font is not drawn with its own letters: ${out:-nothing}"
    # the comparison: a copy of the core profile without the folder of the user's fonts, and a copy of the base
    # profile that extends that copy
    grep -v 'Library/Fonts' "$HOME/.config/nono/profiles/kingo-claude-core.json" > "$HOME/.config/nono/profiles/kingo-claude-core-ci.json"
    sed 's/"extends": "kingo-claude-core"/"extends": "kingo-claude-core-ci"/' "$HOME/.config/nono/profiles/kingo-claude-base.json" > "$HOME/.config/nono/profiles/kingo-claude-base-ci.json"
    grep -q '"extends": "kingo-claude-core-ci"' "$HOME/.config/nono/profiles/kingo-claude-base-ci.json" || fail "the copy of the base profile does not extend the copy of the core profile"
    if "$NONO_BIN" profile validate "$HOME/.config/nono/profiles/kingo-claude-base-ci.json" >/dev/null 2>&1; then
      PROFILE=kingo-claude-base-ci
      out=$(in_sandbox "$BROWSER_BIN" --headless --no-sandbox --disable-gpu --virtual-time-budget=3000 --user-data-dir="$CFG/tmp/font-inside-2" --dump-dom "file://$HERE/font_check.html#Pacifico" | glyphs)
      PROFILE=kingo-claude
      echo "   RESULT  without the folder of the user's fonts in the profile: ${out:-nothing}"
    fi
  else
    echo "   RESULT  the font did not arrive in the browser outside the sandbox either: nothing to compare"
  fi
else
  echo "   RESULT  the font could not be downloaded: not checked"
fi

say "look inside nono with the course profile, as kingo claude sets it up"
out=$(in_sandbox look look-cv.html)
has "$out" "in 1 picture(s)" || { show "$out" 30; fail "look made no picture of a short page"; }
if has "$out" "What a script adds later"; then show "$out" 30; fail "look fell back to one program under the course profile: the rule for the Mach service does not work"; fi
pictures 1 look-cv
ok "a short page: one picture, and it shows something"
out=$(in_sandbox look look-long.html)
n=$(printf '%s\n' "$out" | sed -n 's/.* in \([0-9]*\) picture(s).*/\1/p')
[ "${n:-0}" -ge 3 ] || { show "$out" 30; fail "look did not cut a long page into several pictures"; }
pictures "$n" look-long
ok "a long page: $n pictures"
out=$(in_sandbox look look-cv.html --pdf)
[ "$(head -c 4 "$DIR/look/look-cv.pdf" 2>/dev/null)" = "%PDF" ] || { show "$out" 30; fail "look --pdf made no PDF"; }
ok "the page as it prints: a PDF of $(wc -c < "$DIR/look/look-cv.pdf" | tr -d ' ') bytes"
out=$(in_sandbox look look-late.html)
has "$out" "is 1000 x 3000 pixels, in 3 picture(s)" || { show "$out" 30; fail "look did not wait for the script, or did not cut the page into 3 pictures"; }
pictures 3 look-late
ok "look waited for the script: 3000 pixels, three pictures"

say "the same asked to run as one program (KINGO_BROWSER_MODE=single)"
MODE=single
out=$(in_sandbox look look-cv.html)
has "$out" "in 1 picture(s)" || { show "$out" 30; fail "as one program, look made no picture"; }
has "$out" "What a script adds later is not on them" || { show "$out" 30; fail "as one program, look does not say that it could not wait for scripts"; }
ok "one picture, and look says that it did not wait for scripts"
MODE=""

say "a profile without the rule for the Mach service: look must fall back to one program"
# the rule is in the core profile (its list also has the rule for the dev port, which stays): a copy of the core
# profile without it, and a copy of the base profile that extends that copy
COPY="$HOME/.config/nono/profiles/kingo-claude-core-ci.json"
sed 's/"extends": "kingo-claude-core"/"extends": "kingo-claude-core-ci"/' "$HOME/.config/nono/profiles/kingo-claude-base.json" > "$HOME/.config/nono/profiles/kingo-claude-base-ci.json"
grep -q '"extends": "kingo-claude-core-ci"' "$HOME/.config/nono/profiles/kingo-claude-base-ci.json" || fail "the copy of the base profile does not extend the copy of the core profile"
python3 - "$HOME/.config/nono/profiles/kingo-claude-core.json" "$COPY" <<'PYTHON'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
new, n = re.subn(r'\n\s*"\(allow mach-register [^\n]*",?\n', "\n", text)
assert n == 1, n
open(sys.argv[2], "w", encoding="utf-8").write(new)
PYTHON
if grep -q 'allow mach-register' "$COPY"; then fail "the copy of the profile still has the rule"; fi
"$NONO_BIN" profile validate "$HOME/.config/nono/profiles/kingo-claude-base-ci.json" > "$CFG/tmp/validate.log" 2>&1 || { show "$(cat "$CFG/tmp/validate.log")" 6; fail "nono does not take the copy of the profile"; }
PROFILE=kingo-claude-base-ci
rm -rf "$DIR/look"
out=$(in_sandbox look look-late.html)
n=$(printf '%s\n' "$out" | sed -n 's/.* in \([0-9]*\) picture(s).*/\1/p')
[ "${n:-0}" -ge 1 ] || { show "$out" 30; fail "without the rule, look made no picture: the fallback to one program does not work"; }
has "$out" "What a script adds later is not on them" || { show "$out" 30; fail "without the rule, look made pictures but did not say that it could not wait: is the rule needed at all?"; }
pictures "$n" look-late
ok "without the rule, look runs Chrome as one program: $n picture(s), and it says that it did not wait"
out=$(in_sandbox look look-cv.html --pdf)
[ "$(head -c 4 "$DIR/look/look-cv.pdf" 2>/dev/null)" = "%PDF" ] || { show "$out" 30; fail "without the rule, look --pdf made no PDF"; }
ok "without the rule, the PDF comes too"
say "a folder of one's own (kingo claude --in), and the student's own profile, on a Mac"
OWN="$HOME/projects/thesis"; MINE="$KINGO_DIR/my-nono-profile.json"
rm -rf "$OWN" "$MINE"; mkdir -p "$OWN" "$HOME/Documents"
# kingo-pod itself is not refused: it starts the course (claude-shortcuts.sh in checks that).
for d in / "$HOME" "$HOME/Documents" "$HOME/Library" "$(dirname "$KINGO_DIR")"; do
  if out=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$d" 2>&1); then show "$out" 3; fail "kingo claude --in took the folder $d"; fi
done
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$OWN") || fail "kingo claude --in did not get as far as the start of Claude Code"
has "$dry" "nono run --silent --profile kingo-claude-base --allow-cwd --read $KINGO_DIR/setup/claude -- claude --settings $HOME/.kingo-claude/settings-in.json --permission-mode default --append-system-prompt You were started with" \
  || { show "$dry" 3; fail "kingo claude --in would not start Claude Code with the base profile and its own settings"; }
[ -z "$(ls -A "$OWN")" ] || fail "kingo put a file into the folder"
out=$( ( cd "$OWN" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_TMPDIR="$CFG/tmp" TMPDIR="$CFG/tmp" NONO_NO_SAVE_PROMPT=1 GIT_CONFIG_NOSYSTEM=1 \
    PATH="$KINGO_DIR/setup/claude/bin:$PATH" KINGO_BROWSER="$BROWSER_BIN" \
    "$NONO_BIN" run --silent --profile kingo-claude-base --allow-cwd --read "$KINGO_DIR/setup/claude" -- \
    sh -c 'echo "n8n=${N8N_BASE_URL:-none} model=${ANTHROPIC_BASE_URL:+set}"; : >> here.txt && echo WROTE-HERE; cat "$1/VERSION" 2>&1; ( : >> "$1/setup/claude/x" ) 2>/dev/null && echo WROTE-KINGO; cp "$1/setup/claude/README.md" page.md && look "$2" | head -n 1; git init -q . && git add -A && git -c user.name=ci -c user.email=ci@example.com commit -q -m one && echo "commits=$(git log --oneline | wc -l | tr -d " ")"' \
    sh "$KINGO_DIR" "$DIR/look-cv.html" ) 2>&1 || true )
has "$out" "n8n=none model=set" || { show "$out" 20; fail "the base profile has something of the course in it, or lost the way to the model"; }
has "$out" WROTE-HERE || { show "$out" 20; fail "the sandbox could not write in the folder"; }
if has "$out" "$(cat "$KINGO_DIR/VERSION")"; then fail "the rest of kingo-pod can be read from a folder of one's own"; fi
if has "$out" WROTE-KINGO; then fail "setup/claude can be written from a folder of one's own"; fi
has "$out" "commits=1" || { show "$out" 20; fail "git does not work in the folder inside the sandbox"; }
ok "in a folder of one's own: it writes there, reads setup/claude and not the rest of kingo-pod, nothing of the course, git works"
# --read and --write on a Mac: what kingo would start, and what Seatbelt gives with the two folders
NOTES="$HOME/projects/notes"; OUT2="$HOME/projects/out"
rm -rf "$NOTES" "$OUT2"; mkdir -p "$NOTES" "$OUT2"; printf 'notes-probe\n' > "$NOTES/note.txt"
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$OWN" --read "$NOTES" --write "$OUT2") || fail "kingo claude --in --read --write did not get as far as the start of Claude Code"
has "$dry" "nono run --silent --profile kingo-claude-base --allow-cwd --read $KINGO_DIR/setup/claude --read $NOTES --allow $OUT2 -- claude --settings $HOME/.kingo-claude/settings-in.json --add-dir=$NOTES --add-dir=$OUT2 --permission-mode default" \
  || { show "$dry" 3; fail "kingo claude --in --read --write does not give the two folders to nono and to Claude Code"; }
if out=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --read "$HOME/Library" 2>&1); then show "$out" 3; fail "kingo claude --read took ~/Library"; fi
# On a Mac, a name in other capitals is the same folder (APFS, as on the students' Macs): ~/library is ~/Library.
# kingo compares the folders, not their names (the review of 18 Nov 2026 found --write ~/Kingo-Pod taken).
mac_refuses() { # why, arguments of kingo claude
  local why=$1; shift
  if out=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude "$@" 2>&1); then show "$out" 3; fail "kingo claude $* did not stop"; fi
  has "$out" "$why" || { show "$out" 3; fail "kingo claude $* stopped, but not because: $why"; }
}
# kingo-pod's path below the home folder in capitals, as a student might type it: ~/WORK/KINGO-POD/KINGO-POD
UP="$HOME/$(printf '%s' "${KINGO_DIR#"$HOME"/}" | tr '[:lower:]' '[:upper:]')"
[ -d "$UP" ] && [ -d "$HOME/library" ] || fail "this disk tells capitals from small letters ($UP): the students' Macs do not, so the checks below would prove nothing"
mac_refuses "is in kingo-pod" --write "$UP"
mac_refuses "is in kingo-pod" --write "$UP/SETUP"
mac_refuses "holds kingo-pod" --write "$(dirname "$UP")"
mac_refuses "is too wide" --read "$HOME/library"
mkdir -p "$HOME/Library/LaunchAgents"
mac_refuses "is in ~/Library/LaunchAgents" --write "$HOME/LIBRARY/LaunchAgents"
mac_refuses "is too wide" --read "$HOME/DOCUMENTS"
mac_refuses "is too wide" --in "$HOME/library"
mac_refuses "holds kingo-pod" --in "$(dirname "$UP")"
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$UP/setup") || fail "kingo claude --in <kingo-pod in capitals>/setup did not get as far as the start of Claude Code"
has "$dry" "This folder is in kingo-pod: Claude Code starts for the course" || { show "$dry" 3; fail "kingo claude --in <kingo-pod in capitals>/setup does not start the course"; }
ok "names in other capitals: kingo-pod, a folder that holds it, ~/library, ~/LIBRARY/LaunchAgents and ~/DOCUMENTS are refused; kingo-pod/setup starts the course"
out=$( ( cd "$OWN" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_TMPDIR="$CFG/tmp" TMPDIR="$CFG/tmp" NONO_NO_SAVE_PROMPT=1 \
    "$NONO_BIN" run --silent --profile kingo-claude-base --allow-cwd --read "$KINGO_DIR/setup/claude" --read "$NOTES" --allow "$OUT2" -- \
    sh -c 'cat "$1/note.txt"; ( : >> "$1/x.txt" ) 2>/dev/null && echo WROTE-READ; ( : >> "$2/y.txt" ) 2>/dev/null && echo WROTE-WRITE' sh "$NOTES" "$OUT2" ) 2>&1 || true )
has "$out" notes-probe || { show "$out" 12; fail "with --read, the sandbox cannot read the folder"; }
if has "$out" WROTE-READ; then fail "with --read, the sandbox can write in the folder"; fi
has "$out" WROTE-WRITE || { show "$out" 12; fail "with --write (nono --allow), the sandbox cannot write in the folder"; }
rm -rf "$NOTES" "$OUT2"
ok "--read and --write: kingo gives both folders to nono and Claude Code; the sandbox reads the one and writes the other"
# --key on a Mac: the profile of the key, which nono must take
KP="$HOME/.config/nono/profiles/kingo-claude-key-base-thesis.json"
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$OWN" --key thesis) || fail "kingo claude --in --key did not get as far as the start of Claude Code"
has "$dry" "nono run --silent --profile kingo-claude-key-base-thesis --allow-cwd --read $KINGO_DIR/setup/claude -- claude --settings $HOME/.kingo-claude/settings-in.json" \
  || { show "$dry" 3; fail "kingo claude --in --key does not start nono with the profile of the key"; }
"$NONO_BIN" profile validate "$KP" > "$CFG/tmp/validate-key.log" 2>&1 || { show "$(cat "$CFG/tmp/validate-key.log")" 8; fail "nono does not take the profile of --key"; }
ok "--key on a Mac: kingo starts nono with the profile of the key, and nono takes it"
# --key --provider on a Mac: the profile for Anthropic's API, which nono must take
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$OWN" --key api --provider anthropic --model claude-sonnet-5-5) || fail "kingo claude --in --key --provider anthropic did not get as far as the start of Claude Code"
has "$dry" "nono run --silent --profile kingo-claude-key-base-api --allow-cwd " || { show "$dry" 3; fail "kingo claude --in --key --provider does not start nono with the profile of the key"; }
has "$dry" "The model: claude-sonnet-5-5 (kept with \"api\"; --model changes it)" || { show "$dry" 3; fail "--model next to --key does not name the model of the key"; }
"$NONO_BIN" profile validate "$(dirname "$KP")/kingo-claude-key-base-api.json" > "$CFG/tmp/validate-key.log" 2>&1 || { show "$(cat "$CFG/tmp/validate-key.log")" 8; fail "nono does not take the profile of --key --provider anthropic"; }
rm -f "$HOME/.config/kingo/key-api.conf"
ok "--key --provider on a Mac: kingo keeps the model with the name, and nono takes the profile for Anthropic's API"

out=$(in_sandbox sh -c 'if ( : >> "$1" ) 2>/dev/null; then echo WROTE; else echo refused; fi' sh "$KINGO_DIR/shared/own-probe.txt")
has "$out" refused || { show "$out" 12; fail "with the course profile alone, the sandbox can already write in shared"; }
cp "$KINGO_DIR/setup/claude/my-nono-profile.example.json" "$MINE"
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude) || fail "kingo claude did not start with the example of my-nono-profile.json"
has "$dry" "nono run --silent --profile kingo-claude-mine --allow-cwd --read $KINGO_DIR -- " || { show "$dry" 3; fail "kingo does not start nono with the student's profile"; }
PROFILE=kingo-claude-mine
out=$(in_sandbox sh -c 'for f in "$@"; do if ( : >> "$f" ) 2>/dev/null; then echo "WROTE $f"; else echo "refused $f"; fi; done; echo "n8n=${N8N_BASE_URL:+set}"' sh \
  "$KINGO_DIR/shared/own-probe.txt" "$KINGO_DIR/own-probe.txt" "$MINE")
PROFILE=kingo-claude
show "$(printf '%s\n' "$out" | grep -E '^(WROTE|refused|n8n=)')" 5
has "$out" "WROTE $KINGO_DIR/shared/own-probe.txt" || { show "$out" 20; fail "with the example profile, the sandbox still cannot write in shared"; }
[ "$(printf '%s\n' "$out" | grep -c '^refused ')" = 2 ] || fail "with the example profile, the sandbox can write kingo-pod or the profile itself"
has "$out" "n8n=set" || fail "with the example profile, the route to n8n of the course profile is gone"
rm -f "$MINE" "$KINGO_DIR/shared/own-probe.txt"
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude) || fail "kingo claude did not start after the profile was removed"
ok "the example of my-nono-profile.json lets the sandbox write in shared, and kingo-pod and the profile itself stay closed"

# kingo claude --login on a Mac. No login can be made here: that needs an account. What is checked: what kingo
# would start; that only the profile of the login step may open the browser; kingo's steps with a stand-in for
# nono; what the real nono gives with the profiles of the login; and that their network is as closed as before.
say "kingo claude --login on a Mac: what it would start"
TPL="$KINGO_DIR/setup/claude"; LCFG="$HOME/.kingo-claude-login"; STORE="$HOME/.local/state/nono/oauth-capture"; PROF="$HOME/.config/nono/profiles"
mkdir -p "$LCFG/tmp" "$LCFG.lock" "$STORE"
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --login) || fail "kingo claude --login did not get as far as the start of Claude Code"
show "$dry" 3
has "$dry" "nono run --silent --profile kingo-claude-login-course --allow-cwd --read $KINGO_DIR -- claude --add-dir=$KINGO_DIR --settings $TPL/settings-login.json --permission-mode default" \
  || fail "kingo claude --login would not start Claude Code with the course profile of the login and the settings of the login"
if has "$dry" " CLAUDE_CODE_MAX_CONTEXT_TOKENS "; then fail "kingo claude --login tells Claude Code the context size of the course's model"; fi
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --login --in "$OWN") || fail "kingo claude --login --in did not get as far as the start of Claude Code"
has "$dry" "nono run --silent --profile kingo-claude-login --allow-cwd --read $TPL -- claude --settings $HOME/.kingo-claude-login/settings-in.json --permission-mode default --append-system-prompt You were started with" \
  || { show "$dry" 3; fail "kingo claude --login --in would not start Claude Code with the profile of the login and its own settings"; }
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude logout) || fail "kingo claude logout did not get as far as the logout"
has "$dry" "nono run --profile kingo-claude-login --allow-cwd -- claude auth logout" || { show "$dry" 3; fail "kingo claude logout would not log out inside the sandbox of the login"; }
for p in kingo-claude-core kingo-claude-base kingo-claude-course kingo-claude kingo-claude-login kingo-claude-login-course kingo-claude-login-open; do
  "$NONO_BIN" profile validate "$PROF/$p.json" > "$CFG/tmp/validate.log" 2>&1 || { show "$(cat "$CFG/tmp/validate.log")" 8; fail "nono does not take the profile $p"; }
done
ok "the course with the login, a folder of one's own with the login, the logout; nono takes the seven profiles"

say "only the login step may open the browser"
out=$( ( cd "$LCFG/tmp" && "$NONO_BIN" run --dry-run --profile kingo-claude-login-open --allow-cwd --allow-launch-services -- claude auth login --claudeai ) 2>&1 ) \
  || { show "$out" 8; fail "nono does not take the profile of the login step with --allow-launch-services"; }
for p in kingo-claude-login kingo-claude-login-course kingo-claude kingo-claude-base; do
  if ( cd "$LCFG/tmp" && "$NONO_BIN" run --dry-run --profile "$p" --allow-cwd --allow-launch-services -- true ) >/dev/null 2>&1; then
    fail "with the profile $p, a session could be started with the right to open pages in the browser"
  fi
done
ok "nono takes --allow-launch-services with kingo-claude-login-open, and with no profile of a session"

say "the steps of kingo around the login, with a stand-in for nono"
FH="$CFG/tmp/login-home"; CRED="$FH/.kingo-claude-login/.credentials.json"
rm -rf "$FH"; mkdir -p "$FH/projects/thesis" "$FH/.local/share/kingo/nono/$(sed -n 's/^CLAUDE_NONO_VERSION=//p' "$KINGO_DIR/kingo")"
cp "$HERE/fake_nono.sh" "$FH/.local/share/kingo/nono/$(sed -n 's/^CLAUDE_NONO_VERSION=//p' "$KINGO_DIR/kingo")/nono"
chmod +x "$FH"/.local/share/kingo/nono/*/nono
step() { # <what the stand-in leaves at a login> <arguments of kingo>
  local login=$1; shift
  ( cd "$KINGO_DIR" && HOME="$FH" XDG_CONFIG_HOME="" KINGO_CLAUDE_NO_BROWSER=1 STUB_LOGIN="$login" \
      python3 -c 'import pty, sys; pty.spawn(sys.argv[1:])' ./kingo "$@" < /dev/null 2>&1 | tr -d '\r' ) || true
}
out=$(step phantom claude --login --in "$FH/projects/thesis")
show "$(printf '%s\n' "$out" | grep -v '^STUB  ')" 6
has "$out" "STUB nono run --profile kingo-claude-login-open --allow-cwd --allow-launch-services -- claude auth login --claudeai" \
  || { show "$out" 30; fail "on a Mac, kingo does not run the login with the profile that may open the browser"; }
has "$out" "Logged in." || { show "$out" 30; fail "kingo does not take a login that nono kept outside the sandbox"; }
sess=$(printf '%s\n' "$out" | awk '/^STUB nono run .*--read /{f=1} f')
has "$sess" "STUB nono run --silent --profile kingo-claude-login --allow-cwd --read $TPL -- claude --settings $FH/.kingo-claude-login/settings-in.json" \
  || { show "$out" 30; fail "after the login, kingo does not start the session with the profile of the login"; }
if has "$sess" "allow-launch-services"; then fail "the session after the login may open pages in the browser"; fi
for p in "CLAUDE_CODE_DISABLE_ARTIFACT=1" "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1" "DISABLE_TELEMETRY=1" "DISABLE_ERROR_REPORTING=1" \
         "CLAUDE_CODE_MAX_CONTEXT_TOKENS=unset" "CLAUDE_CONFIG_DIR=$FH/.kingo-claude-login" "GIT_CONFIG_NOSYSTEM=1" "NONO_NO_SAVE_PROMPT=1" "PATH starts with $TPL/bin"; do
  has "$sess" "STUB   $p" || { show "$sess" 16; fail "the start of the session does not get: $p"; }
done
out=$(step real claude --login --in "$FH/projects/thesis")
if has "$out" "auth login"; then show "$out" 30; fail "kingo asks for the login again although one is there"; fi
out=$(step none claude logout)
has "$out" "Logged out" || { show "$out" 30; fail "kingo claude logout does not say that it logged out"; }
[ ! -e "$CRED" ] || fail "after kingo claude logout the login is still in the config folder"
out=$(step real claude --login --in "$FH/projects/thesis")
has "$out" "nono did not keep this login outside the sandbox" || { show "$out" 30; fail "kingo took a login that is not nono's stand-in"; }
if has "$out" "--read "; then show "$out" 30; fail "kingo started a session with a login that is not nono's stand-in"; fi
[ ! -e "$CRED" ] || fail "a login that is not nono's stand-in stayed in the config folder"
rm -rf "$FH"
ok "the login with the browser profile, the session without it and with kingo's variables; logout; a login that nono did not capture is deleted"

say "the sandbox of the login: the model not through OpenRouter, the course (and OpenRouter for the flows' models) only with the course, nono's store stays outside"
# in_login <profile> <folder> <what nono may read> command ...
in_login() {
  local profile=$1 where=$2 reads=$3; shift 3
  ( cd "$where" &&
    CLAUDE_CONFIG_DIR="$LCFG" CLAUDE_CODE_TMPDIR="$LCFG/tmp" TMPDIR="$LCFG/tmp" NONO_NO_SAVE_PROMPT=1 GIT_CONFIG_NOSYSTEM=1 \
    PGHOST=127.0.0.1 PGPORT=5432 PGUSER=student PGPASSWORD=placeholder PGDATABASE=classroom \
    PATH="$TPL/bin:$PATH" KINGO_BROWSER="$BROWSER_BIN" \
      "$NONO_BIN" run --silent --profile "$profile" --allow-cwd --read "$reads" -- "$@" ) 2>&1 || true
}
MARK="mark-$$-$(date +%s)"
# ci-probe.txt: can its text be read? A second file, which no command below names: can the folder be listed?
printf 'store-%s\n' "$MARK" > "$STORE/ci-probe.txt"
: > "$STORE/listed-$MARK"
printf 'login-folder-%s\n' "$MARK" > "$LCFG/marker.txt"
PROBE='echo "base=${ANTHROPIC_BASE_URL:-none} token=${ANTHROPIC_AUTH_TOKEN:-none} proxy=${HTTPS_PROXY:+set} ca=${NODE_EXTRA_CA_CERTS:+set} n8n=${N8N_BASE_URL:+set} langflow=${LANGFLOW_BASE_URL:+set} openrouter=${OPENROUTER_BASE_URL:+set} pg=${PGHOST:-none}"; cat "$1" 2>&1; ls "$(dirname "$1")" 2>&1; for f in "$2/probe" "$3/probe" ./probe-here; do if ( : >> "$f" ) 2>/dev/null; then echo "WROTE $f"; else echo "refused $f"; fi; done'
out=$(in_login kingo-claude-login "$OWN" "$TPL" sh -c "$PROBE" sh "$STORE/ci-probe.txt" "$CFG" "$LCFG")
show "$(printf '%s\n' "$out" | grep -E '^(base=|WROTE|refused)')" 5
has "$out" "base=none token=none proxy=set ca=set n8n= langflow= openrouter= pg=none" || { show "$out" 20; fail "the profile of the login: a way to OpenRouter or something of the course is there, or nono's proxy and certificate are not"; }
if has "$out" "store-$MARK" || has "$out" "listed-$MARK"; then fail "the sandbox of the login can read nono's store of the real tokens"; fi
has "$out" "refused $CFG/probe" || fail "the sandbox of the login can write in the config folder of the OpenRouter way"
has "$out" "WROTE $LCFG/probe" || fail "the sandbox of the login cannot write in its own config folder"
has "$out" "WROTE ./probe-here" || fail "the sandbox of the login cannot write in the folder it starts in"
out=$(in_login kingo-claude-login-course "$DIR" "$KINGO_DIR" sh -c "$PROBE" sh "$STORE/ci-probe.txt" "$CFG" "$LCFG")
show "$(printf '%s\n' "$out" | grep -E '^(base=|WROTE|refused)')" 5
has "$out" "base=none token=none proxy=set ca=set n8n=set langflow=set openrouter=set pg=127.0.0.1" || { show "$out" 20; fail "the course profile of the login: the model goes through OpenRouter, or n8n, Langflow, OpenRouter for the flows' models or PostgreSQL are not there"; }
if has "$out" "store-$MARK" || has "$out" "listed-$MARK"; then fail "the sandbox of the login, with the course, can read nono's store of the real tokens"; fi
rm -f "$DIR/probe-here"
out=$(in_sandbox sh -c 'cat "$1" 2>&1; cat "$2" 2>&1; ls "$(dirname "$2")" 2>&1' sh "$LCFG/marker.txt" "$STORE/ci-probe.txt")
if has "$out" "$MARK"; then fail "the sandbox of the OpenRouter way can read the config folder of the login, or nono's store"; fi
ok "login: the model not through OpenRouter, nono's proxy and certificate, its own config folder; the course's routes only with the course; the store is closed"

# A new session of Claude Code asks an address on platform.claude.com at its start. That is the host of the token
# address: nono reads all traffic to it and lets through only what has a route. Without a route, nono answers 502
# and Claude Code ends with "Unable to connect to Anthropic services" (Frank's Mac, 14 Nov 2026).
say "through nono's proxy, the login's sandbox reaches the other addresses on Anthropic's login host"
HELLO='for u in https://platform.claude.com/v1/oauth/hello https://api.anthropic.com/api/hello; do c=000; for i in 1 2 3; do c=$(curl -s -o /dev/null -m 30 --cacert "$NODE_EXTRA_CA_CERTS" -w "%{http_code}" "$u"); [ "$c" = 000 ] || break; sleep 3; done; echo "code=$c $u"; done'
# the comparison: a copy of the profile of the login without platform.claude.com among the hosts with a route
sed 's|"api_hosts": \["https://api.anthropic.com", "https://platform.claude.com"\]|"api_hosts": ["https://api.anthropic.com"]|' "$PROF/kingo-claude-login.json" > "$PROF/kingo-claude-login-ci.json"
if grep -q '"https://platform.claude.com"\]' "$PROF/kingo-claude-login-ci.json"; then fail "the copy of the profile still has the route for platform.claude.com"; fi
out=$(in_login kingo-claude-login-ci "$OWN" "$TPL" sh -c "$HELLO" | grep '^code=' || true)
show "$out" 2
has "$out" "code=502 https://platform.claude.com/" || fail "without the route, nono does not answer 502 for platform.claude.com: the check below would prove nothing"
rm -f "$PROF/kingo-claude-login-ci.json"
out=$(in_login kingo-claude-login "$OWN" "$TPL" sh -c "$HELLO" | grep '^code=' || true)
show "$out" 2
[ "$(printf '%s\n' "$out" | grep -c '^code=')" = 2 ] || fail "the probe for Anthropic's hosts did not run in the login's sandbox"
if has "$out" "code=502 " || has "$out" "code=000 "; then fail "the login's sandbox does not reach Anthropic's login host or its API through nono's proxy"; fi
ok "with the profile of the login both hosts answer; without the route for platform.claude.com nono answers 502"

# On a Mac, nono's rules for the network are what keeps a program in the sandbox from Unix sockets (Docker, Podman)
# and from the ports of this machine. The OpenRouter way has them through its key route. The login must have them too.
say "the network of the login's sandbox: no port of this machine and no Unix socket without nono's proxy"
PORT=18790; WORD="outside-word-$$"
python3 "$HERE/probe_server.py" "$PORT" "$OWN/probe.sock" "$WORD" &
SRV=$!
for i in $(seq 1 20); do curl -s -m 2 "http://127.0.0.1:$PORT/" 2>/dev/null | grep -q "$WORD" && break; sleep 0.5; done
out="tcp=$(curl -s -m 5 "http://127.0.0.1:$PORT/" 2>/dev/null | head -c 60) unix=$(curl -s -m 5 --unix-socket "$OWN/probe.sock" http://localhost/ 2>/dev/null | head -c 60)"
[ "$out" = "tcp=$WORD unix=$WORD" ] || { kill "$SRV" 2>/dev/null || true; fail "outside the sandbox the server does not answer ($out): the check would prove nothing"; }
NET='echo "tcp=$(curl -s -m 5 --noproxy "*" "http://127.0.0.1:$1/" 2>/dev/null | head -c 60)"; echo "unix=$(curl -s -m 5 --noproxy "*" --unix-socket "$2" http://localhost/ 2>/dev/null | head -c 60)"'
for p in kingo-claude-base kingo-claude-login kingo-claude-login-course; do
  out=$(in_login "$p" "$OWN" "$TPL" sh -c "$NET" sh "$PORT" "$OWN/probe.sock" | grep -E '^(tcp|unix)=' | tr '\n' ' ')
  echo "         | $p: $out"
  if has "$out" "$WORD"; then kill "$SRV" 2>/dev/null || true; fail "with the profile $p, a program in the sandbox reaches a server on this machine without nono's proxy"; fi
done
kill "$SRV" 2>/dev/null || true; wait "$SRV" 2>/dev/null || true
ok "neither the OpenRouter way nor the login reaches the port or the Unix socket"

PROFILE=kingo-claude
out=$(in_sandbox look look-cv.html)
has "$out" "in 1 picture(s)" || { show "$out" 30; fail "the last picture, for the upload, did not come"; }

printf '\nAll checks of look on a Mac passed.\n'
