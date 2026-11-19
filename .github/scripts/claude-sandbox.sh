#!/usr/bin/env bash
# CI for `kingo claude` under Linux, and so under Windows (WSL2).
#
# nono keeps a program in the sandbox away from files, but under Linux not away from Unix sockets. Docker, Podman's
# API socket and the systemd user manager listen on such sockets, outside the sandbox. So `kingo claude` starts
# Claude Code through setup/claude/no_unix_sockets.py, called "the lock" below.
#
#   claude-sandbox.sh lock      the lock by itself
#   claude-sandbox.sh sandbox   inside nono with the course profile: Docker, Podman, the systemd user manager
#   claude-sandbox.sh claude    one turn of Claude Code inside nono, with a stand-in for the model (fake_model.py)
#                               also: the result of a command holds no lines of bash about its startup files
#   claude-sandbox.sh session   a session of Claude Code in a terminal, as a student has it (pty_session.py)
#   claude-sandbox.sh leave     the end of a session in a terminal: nono does not ask to change the profile
#   claude-sandbox.sh look      look page.html inside nono under the lock: kingo gets the browser, pictures come out;
#                               clickthrough fills in a form and opens a page of the internet; its pages cannot reach a
#                               service on this machine by http or WebSocket, whatever the script does (its own
#                               routes, a copy of Playwright of its own, the other ways of Playwright's API)
#   claude-sandbox.sh own       kingo claude --in <folder>, my-nono-profile.json, and git inside the sandbox
#   claude-sandbox.sh login     kingo claude --login: the profiles, kingo's steps around the login, the sandbox
#   claude-sandbox.sh fresh     a fresh Ubuntu in a container: the packages that kingo names are enough for the browser
#
# Each way out is tried twice. Without the lock it must work, or the check would prove nothing. With the lock it
# must not work.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KINGO_DIR=$(cd "$HERE/../.." && pwd)
LOCK=(/usr/bin/python3 -I "$KINGO_DIR/setup/claude/no_unix_sockets.py")   # as in kingo
DOCKER_SOCK=/var/run/docker.sock
CFG="$HOME/.kingo-claude"
OUTSIDE="$HOME/outside"            # a folder the sandbox does not grant
SECRET="outside-$$-$(date +%s)"

say()  { printf '\n── %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
show() { printf '%s\n' "$1" | tail -n "${2:-6}" | sed 's/^/         | /'; }
fail() { printf '   FAIL  %s\n' "$*"; exit 1; }
has()  { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
# try <seconds> command ...: its output, stdout and stderr, whatever the exit code
try()  { local t=$1; shift; timeout "$t" "$@" 2>&1 || true; }

# ── the lock by itself ───────────────────────────────────────────────────────
part_lock() {
  local rc out

  say "the lock starts a program and hands back its exit code"
  "${LOCK[@]}" true || fail "true did not run under the lock"
  rc=0; "${LOCK[@]}" sh -c 'exit 7' || rc=$?
  [ "$rc" = 7 ] || fail "exit code 7 came back as $rc"
  rc=0; "${LOCK[@]}" /no/such/program 2>/dev/null || rc=$?
  [ "$rc" = 127 ] || fail "a program that is not there gave exit code $rc, not 127"
  ok "true; exit code 7; a program that is not there"

  say "the calls without the lock, as a comparison"
  /usr/bin/python3 "$HERE/probe_calls.py" --unlocked || fail "the comparison is not as expected"

  say "the same calls under the lock"
  "${LOCK[@]}" /usr/bin/python3 "$HERE/probe_calls.py" || fail "the lock does not refuse what it should, or it refuses too much"

  say "two programs further down"
  "${LOCK[@]}" sh -c "sh -c '/usr/bin/python3 \"$HERE/probe_calls.py\"'" >/dev/null || fail "a grandchild is not under the lock"
  ok "a grandchild is under the lock too"
  out=$(try 20 "${LOCK[@]}" "${LOCK[@]}" sh -c 'echo twice-$((6*7))')
  has "$out" twice-42 || { show "$out"; fail "the lock does not start under itself"; }
  ok "the lock starts under itself"

  say "the network still works under the lock: a name of the internet, a page over HTTPS"
  out=$(try 30 getent hosts github.com)
  [ -n "$out" ] || fail "without the lock the name github.com does not resolve here: the check below would prove nothing"
  out=$(try 30 "${LOCK[@]}" getent hosts github.com)
  [ -n "$out" ] || fail "under the lock the name github.com does not resolve"
  out=$(try 40 "${LOCK[@]}" curl -s -m 20 -o /dev/null -w 'https=%{http_code}' https://github.com)
  has "$out" https=200 || { show "$out"; fail "under the lock curl did not get a page over HTTPS"; }
  ok "github.com resolves, and curl gets the page"

  if [ "$(uname -m)" = x86_64 ] && command -v gcc >/dev/null 2>&1; then
    say "a call in the 32-bit convention (int 0x80), where socket has another number"
    local dir; dir=$(mktemp -d)
    gcc -O0 -o "$dir/int80" "$HERE/probe_int80.c" || fail "probe_int80.c did not compile"
    out=$(try 10 "$dir/int80")
    case "$out" in
      int80-socket=-38) ok "this kernel takes no 32-bit calls at all: nothing to check" ;;
      int80-socket=-*)  fail "without the lock the 32-bit call failed in an unexpected way ($out)" ;;
      int80-socket=*)
        out=$(try 10 "${LOCK[@]}" "$dir/int80")
        [ "$out" = int80-socket=-38 ] || fail "under the lock a 32-bit call was not refused ($out)"
        ok "without the lock it makes a Unix socket; under the lock it is refused as not there" ;;
      *) show "$out"; fail "the 32-bit probe printed nothing usable" ;;
    esac
    rm -rf "$dir"
  fi

  say "Docker's socket: curl, the docker command, Node.js"
  out=$(try 20 curl -s -m 5 -o /dev/null -w 'ping=%{http_code}' --unix-socket "$DOCKER_SOCK" http://d/_ping)
  has "$out" ping=200 || { show "$out"; fail "without the lock Docker does not answer: the checks below would prove nothing"; }
  out=$(try 20 "${LOCK[@]}" curl -s -m 5 -o /dev/null -w 'ping=%{http_code}' --unix-socket "$DOCKER_SOCK" http://d/_ping)
  if has "$out" ping=200; then fail "curl reached Docker under the lock"; fi
  ok "curl: an answer without the lock, none with it ($out)"

  out=$(try 30 docker version --format 'server-runs-on-{{.Server.Os}}')
  has "$out" server-runs-on-linux || { show "$out"; fail "without the lock the docker command does not reach the daemon"; }
  out=$(try 30 "${LOCK[@]}" docker version --format 'server-runs-on-{{.Server.Os}}')
  if has "$out" server-runs-on-linux; then fail "the docker command reached the daemon under the lock"; fi
  ok "docker version: the daemon answers without the lock, not with it"
  show "$out" 2

  if command -v node >/dev/null 2>&1; then
    out=$(try 30 node "$HERE/probe_node.js" "$DOCKER_SOCK")
    has "$out" "children run; CONNECTED" || { show "$out"; fail "without the lock Node.js did not reach Docker's socket"; }
    out=$(try 30 "${LOCK[@]}" node "$HERE/probe_node.js" "$DOCKER_SOCK")
    has "$out" "children run; refused with EPERM" || { show "$out"; fail "under the lock Node.js should start children and be refused the socket"; }
    ok "Node.js ($(node --version)): it starts children under the lock, and the socket is refused"
  else
    ok "no Node.js on this machine: skipped"
  fi
}

# ── inside nono, with the course profile ─────────────────────────────────────
# What kingo claude does before it starts Claude Code, without the stack and without real keys.
prepare() {
  local k dry
  mkdir -p "$HOME/.config/kingo" "$OUTSIDE"
  chmod 700 "$HOME/.config/kingo"
  for k in openrouter n8n langflow; do ( umask 077; printf 'ci-placeholder' > "$HOME/.config/kingo/$k.key" ); done
  printf '%s\n' "$SECRET" > "$OUTSIDE/secret.txt"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude) || fail "kingo claude did not get as far as the start of Claude Code"
  show "$dry" 3
  has "$dry" "-- /usr/bin/python3 -I $KINGO_DIR/setup/claude/no_unix_sockets.py claude --add-dir=$KINGO_DIR --permission-mode default" \
    || fail "under Linux, kingo claude would start Claude Code without the lock"
  ok "kingo claude starts Claude Code through the lock, and has written the nono profile"
  # The variables that kingo sets for nono and Claude Code: the dry run names them, from the list that the start
  # exports. kingo_env below sets the same ones. (On 14 Nov 2026 five of them no longer reached Claude Code, and
  # no check saw it: the checks here looked at lines of kingo, not at what a start gets.)
  local v vars
  vars=" $(printf '%s\n' "$dry" | sed -n 's/^  variables: //p')"
  for v in CLAUDE_CODE_DISABLE_ARTIFACT CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC DISABLE_TELEMETRY DISABLE_ERROR_REPORTING \
           CLAUDE_CODE_MAX_CONTEXT_TOKENS CLAUDE_CONFIG_DIR CLAUDE_CODE_TMPDIR TMPDIR PATH KINGO_BROWSER KINGO_NODE KINGO_PLAYWRIGHT \
           KINGO_DEV_PORT KINGO_POD_PORTS \
           GIT_CONFIG_NOSYSTEM NONO_NO_SAVE_PROMPT PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE; do
    has "$vars" " $v " || fail "kingo claude does not set the variable $v for the start"
  done
  grep -q '^  export "\${envs\[@\]}"$' "$KINGO_DIR/kingo" \
    || fail "kingo claude does not hand the variables that the dry run names to nono"
  ok "kingo claude sets its variables for the start: NONO_NO_SAVE_PROMPT, GIT_CONFIG_NOSYSTEM, those against telemetry, the PATH for look, PostgreSQL"
  # nono: the one that kingo downloaded (./kingo claude nono, in the workflow), and no other
  grep -q '^  exec "\$nono" run \${quiet\[@\]+"\${quiet\[@\]}"} --profile "\$profile" --allow-cwd --read "\$reads" \${more_nono\[@\]+"\${more_nono\[@\]}"} -- "\$@"$' "$KINGO_DIR/kingo" \
    || fail "kingo claude does not start its own nono with the line this script copies"
  has "$dry" "  nono run --silent --profile kingo-claude --allow-cwd --read $KINGO_DIR -- " \
    || fail "for the course, kingo claude would not start nono with the course profile and read access to kingo-pod"
  NONO_BIN=$(ls "$HOME"/.local/share/kingo/nono/*/nono 2>/dev/null | head -n 1 || true)
  [ -x "$NONO_BIN" ] || fail "kingo's nono is not in ~/.local/share/kingo/nono (the workflow runs ./kingo claude nono first)"
  [ "$(command -v nono)" = "$NONO_BIN" ] || fail "this script would run $(command -v nono), not the nono that kingo downloaded ($NONO_BIN)"
  grep -q "^CLAUDE_NONO_VERSION=$("$NONO_BIN" --version | sed -n 's/^nono \([0-9.]*\).*/\1/p')\$" "$KINGO_DIR/kingo" \
    || fail "the nono that kingo downloaded says another version than kingo names: $("$NONO_BIN" --version)"
  ok "nono is the one kingo downloaded: $("$NONO_BIN" --version | head -n 1)"
  has "$dry" "--append-system-prompt When you have written or changed an HTML page, look at it" \
    || fail "kingo claude does not tell Claude Code how to look at a page"
  has "$dry" "run it with: clickthrough <script.cjs>" || fail "kingo claude does not tell Claude Code how to try a page with clickthrough"
  ok "kingo claude puts look on the PATH, says where the browser is, and tells Claude Code how to look at a page"
  # The ports of kingo-pod, which clickthrough --dev refuses: kingo takes them from its service table. clickthrough keeps a list
  # of its own for a start without kingo, and kingo_env below another; both must be kingo's.
  local pods list
  pods=$(printf '%s\n' "$dry" | sed -n 's/^  ports: .*KINGO_POD_PORTS=//p' | tr ' ' '\n' | grep . | sort -n | tr '\n' ' ')
  [ -n "$pods" ] || fail "the dry run does not name the ports of kingo-pod"
  for list in "$(sed -n 's/.*KINGO_POD_PORTS:-\([0-9 ]*\)}.*/\1/p' "$KINGO_DIR/setup/claude/bin/clickthrough" | head -n 1)" \
              "$(sed -n 's/.*KINGO_POD_PORTS="\([0-9 ]*\)".*/\1/p' "$HERE/claude-sandbox.sh" | head -n 1)"; do
    [ "$(printf '%s\n' $list | sort -n | tr '\n' ' ')" = "$pods" ] \
      || fail "a list of the ports of kingo-pod is not kingo's: '$list'; kingo says: $pods"
  done
  ok "the ports of kingo-pod in clickthrough and in this script are kingo's: $pods"
}

# kingo_env command ...: run it in the course folder with the variables that kingo claude sets for Claude Code
kingo_env() {
  ( cd "$KINGO_DIR/claude" &&
    CLAUDE_CODE_DISABLE_ARTIFACT=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1 \
    CLAUDE_CODE_MAX_CONTEXT_TOKENS=200000 \
    CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_TMPDIR="$CFG/tmp" TMPDIR="$CFG/tmp" \
    PGHOST=127.0.0.1 PGPORT=5432 PGUSER=student PGPASSWORD=placeholder PGDATABASE=classroom \
    NONO_NO_SAVE_PROMPT=1 GIT_CONFIG_NOSYSTEM=1 \
    PATH="$KINGO_DIR/setup/claude/bin:$PATH" KINGO_BROWSER="$BROWSER_BIN" KINGO_NODE="$NODE_BIN" KINGO_PLAYWRIGHT="$PW_DIR" \
    KINGO_DEV_PORT=5173 KINGO_POD_PORTS="5432 5678 5679 7860 8888 8000 4040 3000 8978 6333 6334" \
      "$@" )
}
SANDBOX=(nono run --silent --profile kingo-claude --allow-cwd --read "$KINGO_DIR" --)   # the line of kingo claude
BROWSER_BIN=""                      # where kingo put the browser; part_look fills it in
NODE_BIN="" PW_DIR=""               # where kingo put Node.js and playwright-core, for clickthrough; part_look fills them in

# clickthrough_block <where> command ...: a listener on the runner stands for n8n; the pages of clickthrough_block.js try to reach it
# by http and by WebSocket (setup/claude/clickthrough-setup.js closes both). curl reaches it first, or the check proves nothing.
clickthrough_block() {
  local where=$1 port=18765 log="$CFG/tmp/clickthrough-listener.log" out pid; shift
  mkdir -p "$CFG/tmp"; : > "$log"
  /usr/bin/python3 "$HERE/clickthrough_listener.py" "$port" "$log" & pid=$!
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
  /usr/bin/python3 "$HERE/clickthrough_devserver.py" "$port" "$log" > /dev/null & pid=$!
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
  /usr/bin/python3 "$HERE/clickthrough_devserver.py" 5173 "$log" > /dev/null & dpid=$!
  /usr/bin/python3 "$HERE/clickthrough_listener.py" 18765 "$llog" & lpid=$!
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
  local where=$1 d="$KINGO_DIR/claude/copy" port=18765 log="$CFG/tmp/clickthrough-copy-listener.log" out pid w; shift
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
  /usr/bin/python3 "$HERE/clickthrough_listener.py" "$port" "$log" & pid=$!
  sleep 1
  out=$("$@" "$d/clickthrough_block.js" "$port" "$HERE/clickthrough_shop.html" https://github.com/ own 2>&1) || true
  sleep 2; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  rm -rf "$d"
  has "$out" BLOCK-DONE || { show "$out" 20; fail "$where, clickthrough_block.js next to a copy of Playwright did not finish"; }
  ! grep -q '^ARRIVED' "$log" || { show "$(cat "$log")" 12; fail "$where, next to a copy of Playwright of its own, a page reached a service on this machine"; }
  has "$out" "BLOCK-GOTO clickthrough opens https pages and files" || { show "$out" 20; fail "$where, next to a copy of Playwright, page.goto on an http address did not stop with clickthrough's words"; }
  ok "$where: next to a copy of Playwright of its own, require and import by name get kingo's, the copy by its path is refused, and no page reached the listener"
}
# clickthrough_ways <where> command ...: the other ways of Playwright's API past the locks (clickthrough_ways.js). Each stops
# with clickthrough's words, and nothing connects to the listener.
clickthrough_ways() {
  local where=$1 port=18765 log="$CFG/tmp/clickthrough-ways-listener.log" out pid n; shift
  mkdir -p "$CFG/tmp"; : > "$log"
  /usr/bin/python3 "$HERE/clickthrough_listener.py" "$port" "$log" & pid=$!
  sleep 1
  out=$("$@" "$HERE/clickthrough_ways.js" "$port" "$HERE/clickthrough_shop.html" 2>&1) || true
  sleep 2; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  has "$out" WAYS-DONE || { show "$out" 24; fail "$where, clickthrough_ways.js did not finish"; }
  n=$(printf '%s\n' "$out" | grep -c '^WAYS .* refused clickthrough' || true)
  [ "$n" = 15 ] || { show "$(printf '%s\n' "$out" | grep '^WAYS')" 24; fail "$where, $n of the 15 other ways were refused"; }
  ! grep -q . "$log" || { show "$(cat "$log")" 8; fail "$where, a page connected to the listener (a context with a proxy of its own, or ignoreDefaultArgs)"; }
  ok "$where: 15 other ways refused (launchServer, connect, connectOverCDP, bind, newBrowserCDPSession, firefox, webkit, clientCertificates twice, six arguments for Chrome); nothing connected to the listener"
}
NONO_BIN=""                         # kingo's nono; prepare fills it in

# in_sandbox command ...: run it as kingo claude runs Claude Code; prints its output and nono's.
# WITHOUT_SHLVL=1 takes the variable SHLVL away before nono starts, as a comparison (see part_claude).
WITHOUT_SHLVL=""
in_sandbox() { kingo_env timeout 180 env ${WITHOUT_SHLVL:+-u SHLVL} "${SANDBOX[@]}" "$@" 2>&1 || true; }

# way_out <name> <text that only comes out when the way works> command ...
way_out() {
  local name=$1 proof=$2 out; shift 2
  out=$(in_sandbox "$@")
  has "$out" "$proof" || { show "$out" 12; fail "$name: without the lock this way out does not work here, so the check would prove nothing"; }
  ok "$name, without the lock: it works (this is the gap)"
  out=$(in_sandbox "${LOCK[@]}" "$@")
  if has "$out" "$proof"; then show "$out" 12; fail "$name: it still works with the lock"; fi
  ok "$name, with the lock: it does not work"
  show "$out" 3
}

# The course's part of the course folder (Frank, 18 Nov 2026): every start writes the part of AGENTS.md above
# "# Your team's rules" and the facts in info-for-ai/ anew. The team's part stays, and a file that had changed is
# kept as it was, in backups/course-files/. A file without the heading stays as it is.
course_files() {
  local dir="$KINGO_DIR/claude" tpl="$KINGO_DIR/setup/claude" saved="$KINGO_DIR/backups/course-files" t dry f rule
  rule="TEAM-RULE-$$: answer in Korean when the customer writes Korean."
  cf_start() { dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude 2>&1) || { show "$dry" 6; fail "kingo claude stopped: $1"; }; }
  cf_part() { head -n "$((t - 1))" "$1"; }

  say "the course folder: kingo writes the course's part of AGENTS.md and info-for-ai/, the team's rules stay"
  t=$(grep -n -m 1 "^# Your team's rules\$" "$tpl/AGENTS.md" | cut -d: -f1)
  [ -n "$t" ] || fail "setup/claude/AGENTS.md has no heading \"# Your team's rules\""
  cmp -s "$tpl/AGENTS.md" "$dir/AGENTS.md" || fail "the first start did not write AGENTS.md as the template is"
  for f in kingo-pod.md langflow.md n8n.md; do
    cmp -s "$tpl/info-for-ai/$f" "$dir/info-for-ai/$f" || fail "the first start did not write info-for-ai/$f"
    grep -q "^- .*: @info-for-ai/$f\$" "$dir/AGENTS.md" || fail "AGENTS.md does not load info-for-ai/$f"
  done
  [ ! -d "$saved" ] || fail "a new course folder made copies in backups/course-files/"
  ok "a new course folder: AGENTS.md as the template, which loads the three files in info-for-ai/"

  cp "$dir/AGENTS.md" "$dir/AGENTS.ci-before"
  { cf_part "$dir/AGENTS.md"; echo "A line that someone added above the heading."; echo "# Your team's rules"; echo
    echo "$rule"; } > "$dir/AGENTS.ci-new"
  mv "$dir/AGENTS.ci-new" "$dir/AGENTS.md"
  echo "A fact that Claude Code added." >> "$dir/info-for-ai/n8n.md"
  cf_start "after AGENTS.md and info-for-ai/n8n.md were changed"
  has "$dry" "kingo wrote the course's part of your course folder anew: AGENTS.md above \"# Your team's rules\", info-for-ai/n8n.md." \
    || { show "$dry" 6; fail "kingo did not say which files it wrote anew"; }
  has "$dry" "1 line above \"# Your team's rules\" was not kingo's: kingo moved it below the heading" \
    || { show "$dry" 6; fail "kingo did not say that it moved the line of the team's below the heading"; }
  [ "$(cf_part "$dir/AGENTS.md")" = "$(cf_part "$tpl/AGENTS.md")" ] || fail "the course's part of AGENTS.md is not the template's"
  grep -qxF "$rule" "$dir/AGENTS.md" || fail "the team's rules are gone from AGENTS.md"
  tail -n +"$t" "$dir/AGENTS.md" | grep -qxF "A line that someone added above the heading." \
    || { show "$(tail -n +"$t" "$dir/AGENTS.md")" 8; fail "the line above the heading did not move below it"; }
  cmp -s "$tpl/info-for-ai/n8n.md" "$dir/info-for-ai/n8n.md" || fail "info-for-ai/n8n.md was not written anew"
  [ "$(ls -1 "$saved" | wc -l)" = 1 ] || fail "kingo kept $(ls -1 "$saved" | wc -l) copies, not one"
  grep -q "A line that someone added above the heading." "$saved"/*/AGENTS.md || fail "the copy of AGENTS.md is not the file as it was"
  grep -q "A fact that Claude Code added." "$saved"/*/info-for-ai/n8n.md || fail "the copy of info-for-ai/n8n.md is not the file as it was"
  ok "a line above the heading moves below it, a line in a fact file goes, the team's rules stay, the files as they were are in backups/course-files/"

  # A line that an older template had above the heading is kingo's: it goes, it does not move.
  local old
  old=$(LC_ALL=C sort -u "$tpl/agents-course-lines.txt" \
    | LC_ALL=C comm -23 - <(cf_part "$tpl/AGENTS.md" | sed 's/[[:space:]]*$//' | grep -v '^$' | LC_ALL=C sort -u) | head -n 1)
  [ -n "$old" ] || fail "agents-course-lines.txt has no line of an older template to try"
  cp "$dir/AGENTS.md" "$dir/AGENTS.ci-moved"
  { cf_part "$dir/AGENTS.md"; printf '%s\n' "$old"; tail -n +"$t" "$dir/AGENTS.md"; } > "$dir/AGENTS.ci-new"
  mv "$dir/AGENTS.ci-new" "$dir/AGENTS.md"
  sleep 1
  cf_start "with a line of an older template above the heading"
  if has "$dry" "was not kingo's" || has "$dry" "were not kingo's"; then show "$dry" 6; fail "kingo moved a line of an older template"; fi
  cmp -s "$dir/AGENTS.md" "$dir/AGENTS.ci-moved" || fail "the line of an older template did not go"
  rm -f "$dir/AGENTS.ci-moved"
  # Every line that the template has above the heading is in agents-course-lines.txt (.github/scripts/agents-course-lines.sh)
  local miss
  miss=$(cf_part "$tpl/AGENTS.md" | sed 's/[[:space:]]*$//' | grep -v '^$' | LC_ALL=C sort -u | LC_ALL=C comm -23 - <(LC_ALL=C sort -u "$tpl/agents-course-lines.txt"))
  [ -z "$miss" ] || { show "$miss" 5; fail "lines of setup/claude/AGENTS.md are not in agents-course-lines.txt: run .github/scripts/agents-course-lines.sh"; }
  ok "a line of an older template above the heading goes and does not move; every line of the template is in agents-course-lines.txt"

  local copies
  copies=$(ls -1 "$saved" | wc -l)
  cf_start "a second time"
  if has "$dry" "kingo wrote the course's part"; then show "$dry" 6; fail "kingo wrote the course's part anew, though nothing had changed"; fi
  [ "$(ls -1 "$saved" | wc -l)" = "$copies" ] || fail "kingo kept a copy, though nothing had changed"
  ok "nothing changed: nothing written, nothing said, no copy"

  # Notepad on Windows: a CR at the end of every line, and the heading typed again with ’
  sleep 1
  sed -i -e 's/$/\r/' -e "s/^# Your team's rules\\r\$/# Your team’s rules\\r/" "$dir/AGENTS.md"
  grep -q "^# Your team’s rules"$'\r'"\$" "$dir/AGENTS.md" || fail "the test file has no heading with ’ and a CR"
  cf_start "with a file from Notepad"
  [ "$(cf_part "$dir/AGENTS.md")" = "$(cf_part "$tpl/AGENTS.md")" ] || fail "with CRs, the course's part is not the template's"
  grep -qxF "$rule"$'\r' "$dir/AGENTS.md" || fail "with CRs, the team's rules are gone"
  ok "a file from Notepad (a CR at every line, ’ in the heading): the course's part is written, the team's part stays"

  grep -v "team.s rules" "$dir/AGENTS.md" > "$dir/AGENTS.ci-new" && mv "$dir/AGENTS.ci-new" "$dir/AGENTS.md"
  cp "$dir/AGENTS.md" "$dir/AGENTS.ci-none"
  cf_start "with an AGENTS.md without the heading"
  has "$dry" "has no heading \"# Your team's rules\", so kingo left the file as it is" || { show "$dry" 6; fail "kingo did not say why it left AGENTS.md"; }
  cmp -s "$dir/AGENTS.md" "$dir/AGENTS.ci-none" || fail "kingo changed an AGENTS.md without the heading"
  ok "without the heading, AGENTS.md stays as it is, and kingo says why"

  mv "$dir/AGENTS.ci-before" "$dir/AGENTS.md"; rm -f "$dir/AGENTS.ci-none"; rm -rf "$saved"
  cf_start "with the template's AGENTS.md again"

  # Claude Code's memory: memory/ until 1.4.21, memory-of-ai/ since (Frank, 18 Nov 2026). A course folder of that
  # time: the line of the old template in settings.json, and a note in memory/.
  say "the course folder: Claude Code's memory moves from memory/ to memory-of-ai/"
  grep -q "\"autoMemoryDirectory\": \"$KINGO_DIR/claude/memory-of-ai\"," "$dir/.claude/settings.json" \
    || fail "a new course folder does not keep Claude Code's memory in memory-of-ai/"
  sed -i "s|/claude/memory-of-ai\"|/claude/memory\"|" "$dir/.claude/settings.json"
  rm -rf "$dir/memory-of-ai"; mkdir -p "$dir/memory"; echo "- a note of $$" > "$dir/memory/MEMORY.md"
  cf_start "with the memory in memory/"
  has "$dry" "kingo moved Claude Code's memory from claude/memory/ to claude/memory-of-ai/." || { show "$dry" 6; fail "kingo did not say that it moved the memory"; }
  grep -qxF -- "- a note of $$" "$dir/memory-of-ai/MEMORY.md" || fail "the note is not in memory-of-ai/"
  [ ! -e "$dir/memory" ] || fail "memory/ is still there"
  grep -q "\"autoMemoryDirectory\": \"$KINGO_DIR/claude/memory-of-ai\"," "$dir/.claude/settings.json" \
    || { show "$(grep autoMemory "$dir/.claude/settings.json")" 2; fail "settings.json does not name memory-of-ai/"; }
  cf_start "a second time, after the move"
  if has "$dry" "Claude Code's memory"; then show "$dry" 6; fail "kingo moved the memory again"; fi
  rm -rf "$dir/memory-of-ai"
  ok "a course folder from before: the note moves to memory-of-ai/, settings.json names it, the next start does nothing"
}

part_sandbox() {
  local out leak="$KINGO_DIR/claude/leak.txt" psock pid i

  say "what kingo claude would start"
  prepare
  course_files

  say "the sandbox runs a program, lets it read kingo-pod and keeps other files away"
  out=$(in_sandbox sh -c 'echo inside-$((6*7))')
  has "$out" inside-42 || { show "$out" 30; fail "nono did not run a program with the course profile"; }
  # nono itself says nothing (--silent): no banner, and no report with "Fix flags" at the end. Without --silent it does,
  # or this check would prove nothing. An error of nono still shows.
  if has "$out" "Capabilities" || has "$out" "Fix flags" || has "$out" "Sandbox denial"; then show "$out" 30; fail "nono, started as kingo claude starts it, still shows its banner or its report"; fi
  out=$(kingo_env timeout 180 nono run --profile kingo-claude --allow-cwd --read "$KINGO_DIR" -- sh -c 'echo loud-$((6*7))' 2>&1 || true)
  has "$out" loud-42 && has "$out" "Capabilities" || { show "$out" 30; fail "without --silent, nono shows no banner: the check of --silent proves nothing"; }
  out=$(kingo_env timeout 60 nono run --silent --profile kingo-claude-no-such-profile --allow-cwd --read "$KINGO_DIR" -- true 2>&1 || true)
  [ -n "$out" ] || fail "with --silent, nono says nothing about a profile that is not there"
  out=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 KINGO_CLAUDE_LOUD=1 ./kingo claude 2>&1) || { show "$out" 6; fail "kingo claude with KINGO_CLAUDE_LOUD=1 did not get as far as the start"; }
  has "$out" "  nono run --profile kingo-claude --allow-cwd --read $KINGO_DIR -- " || { show "$out" 6; fail "KINGO_CLAUDE_LOUD=1 does not take --silent away"; }
  ok "nono is silent as kingo claude starts it (no banner, no report), says so when a profile is missing, and KINGO_CLAUDE_LOUD=1 brings its output back"
  # The auto-compact window that kingo sets for the context of a key (./kingo claude key add <name> --context).
  out=$(export CLAUDE_CODE_AUTO_COMPACT_WINDOW=131072 KINGO_CI_NOT_NAMED=1; in_sandbox sh -c 'echo "window=${CLAUDE_CODE_AUTO_COMPACT_WINDOW-unset} other=${KINGO_CI_NOT_NAMED-unset}"')
  has "$out" "window=131072 other=unset" || { show "$out" 8; fail "the profile does not let the auto-compact window through, or it lets a variable through that it does not name"; }
  ok "the profile lets the auto-compact window of a key through, and no variable that it does not name"
  out=$(in_sandbox cat "$KINGO_DIR/VERSION")
  has "$out" "$(cat "$KINGO_DIR/VERSION")" || { show "$out" 12; fail "kingo-pod cannot be read in the sandbox"; }
  out=$(in_sandbox cat "$OUTSIDE/secret.txt")
  if has "$out" "$SECRET"; then fail "a program in the sandbox read a file outside directly: that is the profile, not a socket"; fi
  ok "a program runs; it reads kingo-pod; a file outside is refused"
  out=$(in_sandbox "${LOCK[@]}" sh -c 'echo locked-$((6*7))')
  has "$out" locked-42 || { show "$out" 30; fail "the lock does not start inside the sandbox"; }
  ok "the lock starts inside the sandbox"

  say "Docker: a container that mounts the folder outside"
  docker pull -q alpine >/dev/null
  way_out "Docker" "$SECRET" docker run --rm --network none -v "$OUTSIDE:/h:ro" alpine cat /h/secret.txt

  say "Podman's API socket, which setup-linux.sh turns on"
  psock="$XDG_RUNTIME_DIR/podman/podman.sock"
  if ! curl -s -m 5 -o /dev/null --unix-socket "$psock" http://d/_ping 2>/dev/null; then
    mkdir -p "$(dirname "$psock")"
    podman system service --time=0 "unix://$psock" >/dev/null 2>&1 &
    pid=$!
    for i in $(seq 1 30); do curl -s -m 2 -o /dev/null --unix-socket "$psock" http://d/_ping 2>/dev/null && break; sleep 1; done
  fi
  out=$(try 20 curl -s -m 5 -o /dev/null -w 'ping=%{http_code}' --unix-socket "$psock" http://d/_ping)
  has "$out" ping=200 || { show "$out"; fail "Podman's API socket does not answer outside the sandbox"; }
  podman pull -q docker.io/library/alpine >/dev/null
  way_out "Podman, a ping" ping=200 curl -s -m 5 -o /dev/null -w 'ping=%{http_code}' --unix-socket "$psock" http://d/_ping
  way_out "Podman, a container that mounts the folder outside" "$SECRET" \
    docker -H "unix://$psock" run --rm --network none -v "$OUTSIDE:/h:ro" docker.io/library/alpine cat /h/secret.txt
  if [ -n "${pid:-}" ]; then kill "$pid" 2>/dev/null || true; fi

  say "the systemd user manager"
  timeout 60 systemd-run --user --wait --collect -q true \
    || fail "no systemd user manager answers outside the sandbox: the check below would prove nothing"
  # The proof is a file: the command that systemd starts runs outside the sandbox, reads the file outside and
  # writes it into the course folder.
  rm -f "$leak"
  out=$(in_sandbox systemd-run --user --wait --collect -q /bin/sh -c "cat '$OUTSIDE/secret.txt' > '$leak'")
  if [ -f "$leak" ] && has "$(cat "$leak")" "$SECRET"; then
    ok "systemd, without the lock: a command started through it runs outside the sandbox and reads the file (this is the gap)"
  else
    show "$out" 12; fail "systemd: without the lock this way out does not work here, so the check would prove nothing"
  fi
  rm -f "$leak"
  out=$(in_sandbox "${LOCK[@]}" systemd-run --user --wait --collect -q /bin/sh -c "cat '$OUTSIDE/secret.txt' > '$leak'")
  if [ -f "$leak" ]; then show "$out" 12; fail "systemd: it still works with the lock"; fi
  ok "systemd, with the lock: it does not work"
  show "$out" 3

  # The dev port goes into the profile as a number: 08080 would be no JSON there, and nono would not start.
  say "the dev port: a number, never a port of kingo-pod"
  local dry
  dry=$(cd "$KINGO_DIR" && KINGO_DEV_PORT=08080 KINGO_CLAUDE_DRY_RUN=1 ./kingo claude 2>&1) || { show "$dry" 4; fail "kingo claude stopped at KINGO_DEV_PORT=08080"; }
  { has "$dry" "KINGO_DEV_PORT=08080 is not a port number" && has "$dry" "ports: KINGO_DEV_PORT=5173 "; } \
    || { show "$dry" 4; fail "KINGO_DEV_PORT=08080 did not fall back to 5173 with a warning"; }
  nono profile validate "$HOME/.config/nono/profiles/kingo-claude.json" > "$CFG/tmp/validate.log" 2>&1 \
    || { show "$(cat "$CFG/tmp/validate.log")" 6; fail "after KINGO_DEV_PORT=08080, nono does not take the profile"; }
  grep -q '"open_port": \[5173\]' "$HOME/.config/nono/profiles/kingo-claude-core.json" || fail "after KINGO_DEV_PORT=08080, the profile does not open 5173"
  dry=$(cd "$KINGO_DIR" && KINGO_DEV_PORT=5678 KINGO_CLAUDE_DRY_RUN=1 ./kingo claude 2>&1) || { show "$dry" 4; fail "kingo claude stopped at KINGO_DEV_PORT=5678"; }
  { has "$dry" "KINGO_DEV_PORT=5678 is a port of kingo-pod" && has "$dry" "ports: KINGO_DEV_PORT=5173 "; } \
    || { show "$dry" 4; fail "KINGO_DEV_PORT=5678, n8n's port, did not fall back to 5173 with a warning"; }
  dry=$(cd "$KINGO_DIR" && KINGO_PORT_N8N=5173 KINGO_PORT_LANGFLOW=5174 KINGO_CLAUDE_DRY_RUN=1 ./kingo claude 2>&1) || { show "$dry" 4; fail "kingo claude stopped with n8n on 5173"; }
  has "$dry" "ports: KINGO_DEV_PORT=5175 " || { show "$dry" 4; fail "with n8n on 5173 and Langflow on 5174, the dev port is not 5175"; }
  ok "08080 falls back to 5173 and nono takes the profile; 5678 is n8n's; with n8n on 5173 and Langflow on 5174 it is 5175"
  (cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude > /dev/null) || fail "kingo claude did not write the profile of the course again"
}

# ── Claude Code itself ───────────────────────────────────────────────────────
# The real Claude Code, started as kingo claude starts it: inside nono, with the course profile and the course
# settings. Only the model is a stand-in: fake_model.py takes OpenRouter's place in the profile, asks Claude Code to
# run one command with its Bash tool, and notes what comes back. The command is the way out through Docker.
MODEL_PORT=18765
MODEL_PID=""

stand_in() {  # prepare, and put the stand-in where OpenRouter is in the nono profile
  local profile="$HOME/.config/nono/profiles/kingo-claude-base.json"   # the course profile extends this one
  say "what kingo claude would start"
  prepare
  sed -i "s|https://openrouter.ai/api|http://127.0.0.1:$MODEL_PORT|" "$profile"
  grep -q "\"upstream\": \"http://127.0.0.1:$MODEL_PORT\"" "$profile" \
    || fail "the nono profile has no line for OpenRouter that the stand-in could take"
  ok "in the nono profile, the stand-in takes OpenRouter's place"
  docker pull -q alpine >/dev/null
  PROBE="docker run --rm --network none -v $OUTSIDE:/h:ro alpine cat /h/secret.txt; echo the-command-ended"
}

model_start() {  # model_start <log>
  local i
  : > "$1"
  /usr/bin/python3 "$HERE/fake_model.py" "$MODEL_PORT" "$1" "$PROBE" &
  MODEL_PID=$!
  for i in $(seq 1 20); do curl -s -m 2 -o /dev/null "http://127.0.0.1:$MODEL_PORT/ready" && return 0; sleep 0.5; done
  fail "the stand-in for the model did not start"
}

model_stop() {  # model_stop <log>: stop it and print what it was asked
  kill "$MODEL_PID" 2>/dev/null || true
  wait "$MODEL_PID" 2>/dev/null || true
  /usr/bin/python3 - "$1" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    e = json.loads(line)
    if e.get("method") == "POST":
        print("         | request: %s; model %s; %s tools; results %r" % (
            e.get("kind"), e.get("model"), e.get("tools"), [r[:90] for r in e.get("results", [])]))
PY
}

# results <log>: the text of the tool results that Claude Code sent back
results() { /usr/bin/python3 -c 'import json, sys; print("\n".join(r for l in open(sys.argv[1]) for r in json.loads(l).get("results", [])))' "$1"; }

part_claude() {
  local out log

  stand_in
  # turn <log> command ...: one turn without a terminal; the command and its arguments start Claude Code in the sandbox
  turn() {
    log=$1; shift
    model_start "$log"
    out=$(in_sandbox "$@" --add-dir "$KINGO_DIR" --dangerously-skip-permissions -p "Run the probe." < /dev/null)
    model_stop "$log"
  }

  say "Claude Code without the lock: its Bash tool reaches Docker (this is the gap)"
  turn "$CFG/tmp/model-plain.jsonl" claude
  has "$out" KINGO-PROBE-DONE || { show "$out" 40; fail "Claude Code did not finish a turn inside nono, even without the lock"; }
  has "$(results "$log")" the-command-ended || { show "$out" 40; fail "Claude Code did not run the command of the stand-in"; }
  has "$(cat "$log")" '"key": "Bearer ci-placeholder"' || fail "nono's proxy did not put the key from ~/.config/kingo into the request"
  has "$(results "$log")" "$SECRET" || { show "$(results "$log")" 12; fail "without the lock the file did not come out through Claude Code's Bash tool: the check would prove nothing"; }
  ok "the turn finished; the key came from nono's proxy; the file outside came back in the tool result"

  say "Claude Code with the lock, as kingo claude starts it"
  turn "$CFG/tmp/model-locked.jsonl" "${LOCK[@]}" claude
  has "$out" KINGO-PROBE-DONE || { show "$out" 40; fail "Claude Code did not finish a turn under the lock"; }
  has "$(results "$log")" the-command-ended || { show "$out" 40; fail "under the lock Claude Code did not run the command of the stand-in"; }
  if has "$(results "$log")" "$SECRET"; then fail "with the lock the file still came out through Claude Code's Bash tool"; fi
  ok "the turn finished, the Bash tool ran the command, and the file outside did not come back"
  show "$(results "$log")" 4
  # bash reads its startup files when it takes itself for the first shell of a remote login: no SHLVL, and its
  # input is a socket, which is how Claude Code starts it. The sandbox refuses the files, and bash says so.
  if has "$(results "$log")" bashrc; then
    fail "the result of the command starts with lines of bash about its startup files: SHLVL did not reach Claude Code"
  fi
  ok "the result holds no line of bash about its startup files"

  say "the same turn without the variable SHLVL, which the nono profile lets through for this"
  WITHOUT_SHLVL=1
  turn "$CFG/tmp/model-no-shlvl.jsonl" "${LOCK[@]}" claude
  WITHOUT_SHLVL=""
  has "$out" KINGO-PROBE-DONE || { show "$out" 40; fail "Claude Code did not finish a turn without SHLVL"; }
  if has "$(results "$log")" "bashrc: Permission denied"; then
    ok "without SHLVL the lines are back, before what the command printed: this is what SHLVL in the profile is for"
  else
    ok "without SHLVL the lines do not show either: SHLVL in the profile may no longer be needed"
  fi
  show "$(results "$log" | head -n 3)" 3
}

# ── a session in a terminal ──────────────────────────────────────────────────
# What a student does at the first ./kingo claude under Linux: the start screens, a prompt, yes to the command.
# The command line is the one kingo claude runs, with the lock. pty_session.py plays the student and keeps every
# screen; the model is the stand-in again.
need_pyte() {
  /usr/bin/python3 -c 'import pyte' 2>/dev/null \
    || /usr/bin/python3 -m pip install --user --break-system-packages -q pyte 2>/dev/null \
    || sudo apt-get install -y -q python3-pyte >/dev/null \
    || fail "pyte, which pty_session.py needs, could not be installed"
  /usr/bin/python3 -c 'import pyte' || fail "pyte, which pty_session.py needs, is not there"
}

part_session() {
  local log="$CFG/tmp/model-session.jsonl" screens="$CFG/tmp/session-screens.txt" rc=0

  stand_in
  need_pyte

  say "a first session: theme, security notes, trust in the folder, a prompt, yes to the command"
  model_start "$log"
  kingo_env timeout 300 /usr/bin/python3 "$HERE/pty_session.py" "$HERE/session_steps.json" "$screens" \
    "${SANDBOX[@]}" "${LOCK[@]}" claude --add-dir "$KINGO_DIR" --permission-mode default || rc=$?
  model_stop "$log"
  echo "         the last screen:"
  awk '/^===== /{buf=""} {buf=buf"\n"$0} END{print buf}' "$screens" | grep -v '^$' | cut -c1-150 | sed 's/^/         | /'
  if [ "$rc" != 0 ]; then
    echo "         all screens:"; sed 's/^/         | /' "$screens" | cut -c1-170
    fail "the session did not get to the model's last words"
  fi
  has "$(results "$log")" the-command-ended || fail "in the session Claude Code did not run the command of the stand-in"
  if has "$(results "$log")" "$SECRET"; then fail "in the session the file outside came out through Claude Code's Bash tool"; fi
  ok "the session went through, the Bash tool ran the command after the yes, and the file outside did not come back"
  show "$(results "$log")" 4
}

# ── the end of a session ─────────────────────────────────────────────────────
# When a program in a terminal ends and the sandbox refused something on the way, nono asks whether to put that into
# the profile: a list under "Review denied paths", or one line that ends with "[Enter] skip". kingo claude writes the
# profile again at every start, so it starts nono with NONO_NO_SAVE_PROMPT=1, and nono does not ask. Tried twice
# here, in a terminal: without the variable, as a comparison, and with it. The program reads the file outside, which
# the sandbox refuses, and ends.

# leave <screens> [env arguments ...]: -> "asked", "ended" or "stuck"
leave() {
  local screens=$1 steps="$CFG/tmp/leave-steps.json" rc=0; shift
  printf '%s\n' '{"until": ["Review denied paths", "[Enter] skip"], "seconds": 60, "steps": []}' > "$steps"
  kingo_env timeout 120 env "$@" /usr/bin/python3 "$HERE/pty_session.py" "$steps" "$screens" \
    "${SANDBOX[@]}" "${LOCK[@]}" sh -c "cat '$OUTSIDE/secret.txt'; echo the-program-ended" >/dev/null || rc=$?
  if [ "$rc" = 0 ]; then echo asked
  elif grep -q '^===== the program ended' "$screens"; then echo ended
  else echo stuck; fi
}

part_leave() {
  local plain="$CFG/tmp/leave-plain.txt" quiet="$CFG/tmp/leave-quiet.txt" got

  say "what kingo claude would start"
  prepare
  need_pyte

  say "without the variable, as a comparison"
  got=$(leave "$plain" -u NONO_NO_SAVE_PROMPT)
  sed 's/^/         | /' "$plain" | cut -c1-170 | tail -n 25
  has "$(cat "$plain")" the-program-ended || fail "the program did not run in the terminal"
  if has "$(cat "$plain")" "$SECRET"; then fail "the program read the file outside"; fi
  case "$got" in
    asked) ok "nono asks whether to change the profile (this is the question that students got)" ;;
    ended) ok "this nono does not ask here, even without the variable: the run below proves less" ;;
    *)     fail "the program did not end, and nono's question did not come" ;;
  esac

  say "with NONO_NO_SAVE_PROMPT=1, as kingo claude starts nono"
  got=$(leave "$quiet")
  sed 's/^/         | /' "$quiet" | cut -c1-170 | tail -n 25
  has "$(cat "$quiet")" the-program-ended || fail "the program did not run in the terminal"
  if has "$(cat "$quiet")" "$SECRET"; then fail "the program read the file outside"; fi
  [ "$got" = ended ] || fail "nono still asks, or the program did not end ($got)"
  ok "the program ends, and nono does not ask"
}

# ── look: Claude sees the pages it writes ────────────────────────────────────
# kingo claude gets a browser without a window on its first start and puts setup/claude/bin/look on the PATH.
# look page.html makes pictures of the whole page, part by part. Here: kingo gets the browser, and look runs inside
# nono with the course profile and under the lock, by itself and from the Bash tool of the real Claude Code.
part_look() {
  local out line dir="$KINGO_DIR/claude" log="$CFG/tmp/model-look.jsonl" n

  stand_in

  say "kingo gets the browser"
  out=$(cd "$KINGO_DIR" && ./kingo claude browser 2>&1) || {
    show "$out" 6
    line=$(printf '%s\n' "$out" | sed -n 's/^ *\(sudo apt-get install -y .*\)$/\1/p')
    [ -n "$line" ] || fail "kingo claude browser failed and named no packages"
    sudo apt-get update -q >/dev/null
    $line >/dev/null || fail "the line that kingo named did not install: $line"
    out=$(cd "$KINGO_DIR" && ./kingo claude browser 2>&1) || { show "$out" 6; fail "the browser does not run after the packages that kingo named"; }
  }
  show "$out" 3
  BROWSER_BIN=$(find "$HOME/.local/share/kingo/browsers" -type f -name chrome-headless-shell 2>/dev/null | head -n 1 || true)
  [ -x "$BROWSER_BIN" ] || fail "the browser is not where kingo says it is: $BROWSER_BIN"
  [ ! -e "$CFG/browsers" ] || fail "there is a browser in $CFG, a folder the sandbox can write"
  ok "the browser is there: $BROWSER_BIN"
  NODE_BIN=$(ls "$HOME"/.local/share/kingo/node/*/node 2>/dev/null | head -n 1 || true)
  PW_DIR=$(ls -d "$HOME"/.local/share/kingo/playwright/*/ 2>/dev/null | head -n 1 || true); PW_DIR=${PW_DIR%/}
  [ -x "$NODE_BIN" ] || fail "kingo claude browser did not get Node.js into ~/.local/share/kingo/node"
  [ -f "$PW_DIR/node_modules/playwright-core/package.json" ] || fail "kingo claude browser did not get playwright-core into ~/.local/share/kingo/playwright"
  ok "Node.js $("$NODE_BIN" --version) and playwright-core $(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$PW_DIR/node_modules/playwright-core/package.json" | head -n 1), for clickthrough"
  out=$(cd "$KINGO_DIR" && ./kingo claude browser 2>&1) || fail "a second kingo claude browser failed"
  if has "$out" "Getting a browser"; then fail "a second kingo claude browser downloaded it again"; fi
  if has "$out" "Getting Node.js" || has "$out" "Getting playwright-core"; then fail "a second kingo claude browser downloaded Node.js or playwright-core again"; fi
  ok "a second kingo claude browser downloads nothing"

  cat > "$dir/look-cv.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Probe</title>
<style>body{font-family:sans-serif;margin:40px}h1{color:#1a4d8f}.bar{height:60px;background:linear-gradient(90deg,#e4572e,#f3a712,#76b041)}
.cols{display:flex;gap:20px;margin-top:20px}.cols div{flex:1;border:1px solid #888;padding:10px}</style></head>
<body><h1>Curriculum Vitae</h1><div class="bar"></div>
<div class="cols"><div><b>Education</b><br>MBA, 2026</div><div><b>Experience</b><br>Analyst, 2021 to 2025</div></div>
</body></html>
HTML
  # 400 pixels at first; half a second later a script makes the page 3000 pixels high
  cat > "$dir/look-late.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;font-family:sans-serif}
.first{height:400px;background:linear-gradient(#e4572e,#76b041)}</style></head>
<body><div class="first">first</div><div id="more"></div>
<script>setTimeout(function () { var d = document.getElementById('more'); d.style.height = '2600px';
  d.style.background = 'linear-gradient(#1a4d8f,#f3a712)'; d.textContent = 'late'; }, 500)</script></body></html>
HTML
  rm -rf "$dir/look"

  # pictures <how many> <name>: so many pictures of that page are there, and each shows something
  pictures() {
    local i
    for i in $(seq 1 "$1"); do
      /usr/bin/python3 "$HERE/png_check.py" "$dir/look/$2-$i.png" | sed 's/^/         | /' \
        || fail "look/$2-$i.png is missing or shows nothing"
    done
    [ ! -e "$dir/look/$2-$(( $1 + 1 )).png" ] || fail "there are more than $1 pictures of $2"
  }

  # kingo starts nono and the browser outside the sandbox. A program inside must not be able to swap them.
  say "the sandbox cannot change what kingo downloaded"
  out=$(in_sandbox "${LOCK[@]}" sh -c 'for f in "$@"; do if ( : >> "$f" ) 2>/dev/null; then echo "WROTE $f"; else echo "refused $f"; fi; done' sh \
    "$dir/look-write-probe" "$BROWSER_BIN" "$(dirname "$BROWSER_BIN")/new-file" "$NONO_BIN" "$(dirname "$NONO_BIN")/new-file" \
    "$HOME/.local/share/kingo/new-file" "$NODE_BIN" "$(dirname "$NODE_BIN")/new-file" \
    "$PW_DIR/node_modules/playwright-core/package.json" "$PW_DIR/new-file")
  show "$(printf '%s\n' "$out" | grep -E '^(WROTE|refused) ')" 10
  has "$out" "WROTE $dir/look-write-probe" || fail "the probe proves nothing: it could not write in the course folder either"
  [ "$(printf '%s\n' "$out" | grep -c '^refused ')" = 9 ] || fail "a program in the sandbox can write where kingo keeps nono, the browser, Node.js or playwright-core"
  rm -f "$dir/look-write-probe"
  ok "inside the sandbox, the browser, nono, Node.js, playwright-core and their folders cannot be written"

  # A font that the user installed: the browser must draw its letters, not boxes. Reports, and fails only on boxes.
  say "a font that the user installed (~/.local/share/fonts)"
  mkdir -p "$HOME/.local/share/fonts"
  if curl -fsSL -m 60 -o "$HOME/.local/share/fonts/Pacifico-Regular.ttf" https://raw.githubusercontent.com/google/fonts/main/ofl/pacifico/Pacifico-Regular.ttf; then
    fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true
    glyphs() { sed -n 's/.*<title>GLYPHS=\([^<]*\)<.*/\1/p' | head -n 1; }
    out=$("$BROWSER_BIN" --headless --no-sandbox --disable-gpu --virtual-time-budget=3000 --user-data-dir="$CFG/tmp/font-outside" --dump-dom "file://$HERE/font_check.html#Pacifico" 2>/dev/null | glyphs)
    echo "         | outside the sandbox: ${out:-nothing}"
    if [ "$out" = "Pacifico:own" ]; then
      out=$(in_sandbox "${LOCK[@]}" "$BROWSER_BIN" --headless --no-sandbox --disable-gpu --virtual-time-budget=3000 --user-data-dir="$CFG/tmp/font-inside" --dump-dom "file://$HERE/font_check.html#Pacifico" | glyphs)
      echo "         | inside the sandbox:  ${out:-nothing}"
      [ "$out" != "Pacifico:boxes" ] || fail "inside the sandbox, a font that the user installed is drawn as boxes"
      [ "$out" = "Pacifico:own" ] && ok "the browser draws the user's font inside the sandbox" \
        || echo "   RESULT  inside the sandbox the user's font is not drawn with its own letters: ${out:-nothing}"
    else
      echo "   RESULT  the font did not arrive in the browser outside the sandbox either: nothing to compare"
    fi
  else
    echo "   RESULT  the font could not be downloaded: not checked"
  fi

  say "look inside nono, under the lock: a short page"
  out=$(in_sandbox "${LOCK[@]}" look look-cv.html)
  has "$out" "in 1 picture(s)" || { show "$out" 12; fail "look made no picture of a short page"; }
  pictures 1 look-cv
  ok "one picture, and it shows something"

  say "a page that a script makes longer after it has loaded"
  out=$(in_sandbox "${LOCK[@]}" look look-late.html)
  has "$out" "is 1000 x 3000 pixels, in 3 picture(s)" || { show "$out" 12; fail "look did not wait for the script, or did not cut the page into 3 pictures"; }
  pictures 3 look-late
  ok "look waited for the script: 3000 pixels, three pictures"

  say "a narrow window, and the page as it prints"
  out=$(in_sandbox "${LOCK[@]}" look look-cv.html --width 600)
  has "$out" "is 600 x" || { show "$out" 12; fail "look --width 600 did not make a picture 600 wide"; }
  /usr/bin/python3 "$HERE/png_check.py" "$dir/look/look-cv-1.png" | grep -q ": 600 x " || fail "the picture is not 600 pixels wide"
  out=$(in_sandbox "${LOCK[@]}" look look-cv.html --pdf)
  [ "$(head -c 4 "$dir/look/look-cv.pdf" 2>/dev/null)" = "%PDF" ] || { show "$out" 12; fail "look --pdf made no PDF"; }
  ok "600 pixels wide; a PDF of $(wc -c < "$dir/look/look-cv.pdf") bytes"

  # clickthrough: a script as Claude would write it fills in a form and sends it; then a page of the internet, through
  # nono's proxy
  say "clickthrough inside nono, under the lock: a form is filled in and sent, and a page of the internet comes"
  out=$(in_sandbox "${LOCK[@]}" clickthrough "$HERE/clickthrough_check.js" "$HERE/clickthrough_shop.html" look/clickthrough-shop.png https://github.com/)
  show "$(printf '%s\n' "$out" | grep '^CLICKTHROUGH-')" 3
  has "$out" "CLICKTHROUGH-SAID Thank you, Mina: 1 Coffee" || { show "$out" 20; fail "clickthrough did not fill in and send the form inside the sandbox"; }
  /usr/bin/python3 "$HERE/png_check.py" "$dir/look/clickthrough-shop.png" | sed 's/^/         | /' || fail "clickthrough made no picture of the page"
  printf '%s\n' "$out" | grep '^CLICKTHROUGH-TITLE ' | grep -q GitHub || { show "$out" 20; fail "clickthrough did not get a page of the internet inside the sandbox"; }
  ok "clickthrough filled in the form, read the answer, made a picture, and opened github.com"

  # Outside nono and without a proxy, a direct connection to 127.0.0.1 works, as under WSL2 inside nono; inside nono a
  # page could go through nono's proxy, which lets the laptop's own addresses through when the network is open.
  say "clickthrough: a page cannot reach a service on this machine by http or WebSocket"
  clickthrough_block "outside nono, without a proxy" kingo_env bash "$KINGO_DIR/setup/claude/bin/clickthrough"
  clickthrough_block "inside nono, under the lock" in_sandbox "${LOCK[@]}" clickthrough

  # clickthrough --dev: the student's dev server on this laptop (kingo opens KINGO_DEV_PORT, 5173, in the profile).
  say "clickthrough --dev 5173: the dev server's page works, and nothing else opens"
  grep -q '"open_port": \[5173\]' "$HOME/.config/nono/profiles/kingo-claude-core.json" \
    || fail "kingo did not open the dev port 5173 in the core profile (open_port)"
  out=$(in_sandbox "${LOCK[@]}" clickthrough --dev 5678 "$HERE/clickthrough_dev.js")
  has "$out" "is a port of kingo-pod" || { show "$out" 6; fail "clickthrough --dev 5678 did not refuse n8n's port"; }
  out=$(in_sandbox "${LOCK[@]}" clickthrough --dev 5174 "$HERE/clickthrough_dev.js")
  has "$out" "the sandbox opens port 5173 for a dev server" || { show "$out" 6; fail "clickthrough --dev 5174 did not say which port the sandbox opens"; }
  ok "clickthrough --dev refuses n8n's port, and names the one port the sandbox opens"
  clickthrough_dev "outside nono, without a proxy (as under WSL2)" kingo_env bash "$KINGO_DIR/setup/claude/bin/clickthrough"
  clickthrough_dev "inside nono, under the lock" in_sandbox "${LOCK[@]}" clickthrough
  clickthrough_block "inside nono, under the lock, with --dev 5173" in_sandbox "${LOCK[@]}" clickthrough --dev 5173
  clickthrough_dev_inside in_sandbox "${LOCK[@]}"

  # Whatever the script does (setup/claude/clickthrough-setup.js): the locks hold for every way of Playwright's API.
  say "clickthrough: the locks hold, whatever the script does (its own routes, a copy of Playwright of its own, other ways)"
  clickthrough_routes "outside nono, without a proxy" kingo_env bash "$KINGO_DIR/setup/claude/bin/clickthrough"
  clickthrough_routes "inside nono, under the lock" in_sandbox "${LOCK[@]}" clickthrough
  clickthrough_copy "outside nono, without a proxy" kingo_env bash "$KINGO_DIR/setup/claude/bin/clickthrough"
  clickthrough_copy "inside nono, under the lock" in_sandbox "${LOCK[@]}" clickthrough
  clickthrough_ways "outside nono, without a proxy" kingo_env bash "$KINGO_DIR/setup/claude/bin/clickthrough"
  clickthrough_ways "inside nono, under the lock" in_sandbox "${LOCK[@]}" clickthrough

  say "clickthrough in a Vite project, where a .js is an ES module; and --dev without leading zeros"
  mkdir -p "$dir/vite"; printf '{ "name": "a-vite-project", "type": "module" }\n' > "$dir/vite/package.json"
  cp "$HERE/clickthrough_check.js" "$dir/vite/try.js"; cp "$HERE/clickthrough_check.js" "$dir/vite/try.cjs"
  out=$(in_sandbox "${LOCK[@]}" clickthrough vite/try.js "$HERE/clickthrough_shop.html" look/vite.png)
  has "$out" "Write the script as a .cjs file" || { show "$out" 6; fail "clickthrough did not stop at a .js in a project of type module, or did not say to write a .cjs"; }
  out=$(in_sandbox "${LOCK[@]}" clickthrough vite/try.cjs "$HERE/clickthrough_shop.html" look/vite.png)
  has "$out" "CLICKTHROUGH-SAID Thank you, Mina: 1 Coffee" || { show "$out" 12; fail "clickthrough did not run the .cjs in a project of type module"; }
  rm -rf "$dir/vite"
  out=$(in_sandbox "${LOCK[@]}" clickthrough --dev 05678 "$HERE/clickthrough_dev.js")
  has "$out" "a number without leading zeros" || { show "$out" 6; fail "clickthrough --dev 05678 did not refuse the leading zero"; }
  ok "in a project of type module clickthrough asks for a .cjs, and the .cjs runs; --dev 05678 is refused"

  say "the real Claude Code runs look with its Bash tool"
  PROBE="look look-cv.html; echo the-command-ended"
  rm -rf "$dir/look"
  model_start "$log"
  out=$(in_sandbox "${LOCK[@]}" claude --add-dir "$KINGO_DIR" --dangerously-skip-permissions -p "Run the probe." < /dev/null)
  model_stop "$log"
  has "$out" KINGO-PROBE-DONE || { show "$out" 40; fail "Claude Code did not finish the turn"; }
  has "$(results "$log")" "in 1 picture(s)" || { show "$(results "$log")" 12; fail "look did not run from Claude Code's Bash tool"; }
  pictures 1 look-cv
  ok "look is on the PATH of the Bash tool, and the picture is there"
  show "$(results "$log")" 4
}

# ── a fresh Ubuntu ───────────────────────────────────────────────────────────
# The runner has many packages that a new Ubuntu under Windows (WSL) does not have. In a container of the same
# Ubuntu version with nothing but curl and python3: kingo names the packages the browser needs, they install, and
# then the browser makes a picture. No nono here: this is about the packages.
part_fresh() {
  local image
  image="ubuntu:$(. /etc/os-release && echo "$VERSION_ID")"
  say "a fresh $image"
  docker run --rm -v "$KINGO_DIR:/k:ro" "$image" bash -c '
    set -eu
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q >/dev/null && apt-get install -y -q curl ca-certificates python3 >/dev/null
    cd /k
    # The download of Node.js fails here (a curl that refuses nodejs.org): kingo still names the packages of the system.
    mkdir -p /tmp/nocurl
    printf "#!/bin/sh\ncase \"\$*\" in *nodejs.org*) echo \"curl: (6) not nodejs.org, for this check\" >&2; exit 6 ;; esac\nexec /usr/bin/curl \"\$@\"\n" > /tmp/nocurl/curl
    chmod +x /tmp/nocurl/curl
    if out=$(PATH=/tmp/nocurl:$PATH ./kingo claude browser 2>&1); then echo "$out"; echo "FRESH: nothing was missing, which a fresh Ubuntu cannot be"; exit 1; fi
    echo "$out" | tail -n 6
    case "$out" in *"download of Node.js did not work"*) ;; *) echo "FRESH: the download of Node.js did not fail, so this check proves nothing"; exit 1 ;; esac
    line=$(printf "%s\n" "$out" | sed -n "s/^ *sudo \(apt-get install -y .*\)$/\1/p")
    [ -n "$line" ] || { echo "FRESH: without Node.js, kingo named no packages"; exit 1; }
    mkdir /w && cd /w
    printf "<!doctype html><meta charset=utf-8><h1 style=\"color:#1a4d8f\">Curriculum Vitae 이력서</h1><p>Hello</p>" > page.html
    # look, before the packages are there: it must say what the student shall do, not only that it failed
    if out=$(bash /k/setup/claude/bin/look page.html 2>&1); then echo "$out"; echo "FRESH: look made a picture without the packages"; exit 1; fi
    echo "$out" | tail -n 2 | cut -c1-200
    case "$out" in *"./kingo claude browser"*) ;; *) echo "FRESH: without the packages, look does not name ./kingo claude browser"; exit 1 ;; esac
    cd /k
    # in a terminal kingo asks. "n": nothing is installed, and the line is named
    in_terminal() { printf "%s\n" "$1" | python3 -c "import pty, sys; pty.spawn(sys.argv[1:])" ./kingo claude browser 2>&1 | tr -d "\r" || true; }
    out=$(in_terminal n)
    case "$out" in *"Install them now?"*"not installed"*"apt-get install -y "*) ;; *) echo "$out" | tail -n 8; echo "FRESH: after a no, kingo does not name the line"; exit 1 ;; esac
    if ./kingo claude browser >/dev/null 2>&1; then echo "FRESH: after a no the packages are there"; exit 1; fi
    # "y": kingo installs them itself (here as root, so without sudo)
    out=$(in_terminal y)
    echo "$out" | grep -E "Install them now|Installed\.|WARN|ready" | cut -c1-200
    case "$out" in *"Install them now?"*"Installed. Claude can look at pages now."*) ;; *) echo "$out" | tail -n 12; echo "FRESH: after a yes, kingo did not install the packages"; exit 1 ;; esac
    ./kingo claude browser
    cd /w
    bash /k/setup/claude/bin/look page.html
    python3 /k/.github/scripts/png_check.py look/page-1.png
    # clickthrough: Node.js and playwright-core came with ./kingo claude browser
    out=$(bash /k/setup/claude/bin/clickthrough /k/.github/scripts/clickthrough_check.js /k/.github/scripts/clickthrough_shop.html look/clickthrough.png 2>&1) \
      || { echo "$out" | tail -n 8; echo "FRESH: clickthrough did not run"; exit 1; }
    case "$out" in *"CLICKTHROUGH-SAID Thank you, Mina: 1 Coffee"*) echo "$out" | grep "^CLICKTHROUGH-" ;; *) echo "$out" | tail -n 8; echo "FRESH: clickthrough did not fill in the form"; exit 1 ;; esac
    python3 /k/.github/scripts/png_check.py look/clickthrough.png
  ' || fail "on a fresh $image the browser does not run with the packages that kingo names"
  ok "kingo named the missing packages, also when the download of Node.js failed; look said what to do, kingo installed them after a yes, the browser made a picture, and clickthrough filled in a form"
}

# ── a folder of one's own, one's own profile, and git ────────────────────────
# kingo claude --in <folder> starts Claude Code with the base profile in a folder that is not the course folder.
# my-nono-profile.json adds to the course profile. And git must work in both places: it is how a student keeps
# versions of what Claude Code writes.
part_own() {
  local out dry d dir="$HOME/projects/thesis" log="$CFG/tmp/model-own.jsonl" mine="$KINGO_DIR/my-nono-profile.json"
  local base=(nono run --silent --profile kingo-claude-base --allow-cwd --read "$KINGO_DIR/setup/claude" --)
  # in_folder command ...: run it as kingo claude --in runs Claude Code, in the folder
  in_folder() {
    ( cd "$dir" &&
      CLAUDE_CODE_DISABLE_ARTIFACT=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1 \
      CLAUDE_CODE_MAX_CONTEXT_TOKENS=200000 \
      CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_TMPDIR="$CFG/tmp" TMPDIR="$CFG/tmp" \
      NONO_NO_SAVE_PROMPT=1 GIT_CONFIG_NOSYSTEM=1 \
      PATH="$KINGO_DIR/setup/claude/bin:$PATH" KINGO_BROWSER="$BROWSER_BIN" \
        timeout 180 "${base[@]}" "$@" ) 2>&1 || true
  }
  # versions <text of the run>: the run made two commits and tidied the repository
  GIT='git init -q . && git add -A && git -c user.name=ci -c user.email=ci@example.com commit -q -m one && echo more >> git-probe.txt && git -c user.name=ci -c user.email=ci@example.com commit -q -a -m two && git gc -q && echo "commits=$(git log --oneline | wc -l | tr -d " ")"'

  prepare
  rm -rf "$dir" "$mine"; mkdir -p "$dir" "$HOME/Documents"

  say "kingo claude --in: the folders it does not take"
  # refuses <why> <arguments of kingo claude>: kingo stops, and for that reason (a stop for another reason, early in
  # kingo, would pass a check of the stop alone)
  refuses() {
    local why=$1; shift
    if out=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude "$@" 2>&1); then show "$out" 3; fail "kingo claude $* did not stop"; fi
    has "$out" "$why" || { show "$out" 3; fail "kingo claude $* stopped, but not because: $why"; }
    printf '         | %s\n' "$(printf '%s\n' "$out" | tail -n 1 | cut -c1-140)"
  }
  # kingo-pod and a folder in it are not refused: they start the course (claude-shortcuts.sh in checks that).
  refuses "takes a folder inside your home folder" --in /
  refuses "not the home folder itself" --in "$HOME"
  refuses "is too wide" --in "$HOME/Documents"
  refuses "is a hidden folder" --in "$HOME/.config"
  refuses "is a Windows folder" --in /mnt/c/Users/someone
  refuses "holds kingo-pod" --in "$(dirname "$KINGO_DIR")"
  refuses "there is no folder" --in "$HOME/no-such-folder"
  ok "it refuses /, the home folder, Documents, a hidden folder, a Windows folder, a folder that holds kingo-pod, a folder that is not there, and says why"

  say "kingo claude --in: what it would start"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$dir") || fail "kingo claude --in did not get as far as the start of Claude Code"
  show "$dry" 2
  has "$dry" "nono run --silent --profile kingo-claude-base --allow-cwd --read $KINGO_DIR/setup/claude -- /usr/bin/python3 -I $KINGO_DIR/setup/claude/no_unix_sockets.py claude --settings $HOME/.kingo-claude/settings-in.json --permission-mode default --append-system-prompt You were started with" \
    || fail "kingo claude --in would not start Claude Code with the base profile, under the lock, with its own settings"
  [ -z "$(ls -A "$dir")" ] || fail "kingo put a file into the folder: $(ls -A "$dir")"
  # The settings are kingo's template with one line more: Claude Code's memory in memory-of-ai/ of the folder.
  [ "$(grep -v autoMemoryDirectory "$HOME/.kingo-claude/settings-in.json")" = "$(cat "$KINGO_DIR/setup/claude/settings-in.json")" ] \
    || fail "the settings of kingo claude --in are not the template's with the line for the memory"
  grep -qxF "  \"autoMemoryDirectory\": \"$dir/memory-of-ai\"," "$HOME/.kingo-claude/settings-in.json" \
    || { show "$(cat "$HOME/.kingo-claude/settings-in.json")" 5; fail "with --in, Claude Code's memory does not go into memory-of-ai/ of the folder"; }
  ok "the base profile, the lock, settings from kingo-pod with the memory in memory-of-ai/ of the folder, and no file in the folder"
  # What Claude Code is told there: no n8n, and nothing for the user's own terminal (CLAUDE_IN_HINT forbids that)
  if has "$dry" 'N8N_BASE_URL'; then fail "kingo claude --in tells Claude Code about n8n, which is not there"; fi
  if has "$dry" "in their own terminal (npm run dev)"; then fail "kingo claude --in asks Claude Code to send the user to their own terminal, which CLAUDE_IN_HINT forbids"; fi
  has "$dry" "run it with: clickthrough <script.cjs>" || fail "kingo claude --in does not tell Claude Code about clickthrough"
  has "$dry" "Start the dev server yourself (npm run dev), on that port." || fail "under Linux, kingo claude --in does not tell Claude Code to start the dev server itself"
  ok "kingo claude --in names no n8n, and Claude starts the dev server itself"

  # --read and --write: more folders for one start (Frank, 18 Nov 2026). kingo checks them as it checks --in, gives
  # them to nono (--read, --allow) and to Claude Code (--add-dir), and names them; the shortcut kc passes them on.
  # Before stand_in below: a dry run writes the profiles again, and so takes the stand-in out of them.
  say "kingo claude --read and --write: the folders it does not take, and what it would start"
  local notes="$HOME/projects/notes" out2="$HOME/projects/out" base_before
  rm -rf "$notes" "$out2"; mkdir -p "$notes" "$out2" "$KINGO_DIR/shared" "$KINGO_DIR/backups"
  printf 'notes-probe-%s\n' "$$" > "$notes/note.txt"
  refuses "takes a folder inside your home folder" --read /
  refuses "not the home folder itself" --read "$HOME"
  refuses "is too wide" --read "$HOME/Documents"
  refuses "is a hidden folder" --read "$HOME/.config"
  refuses "is a Windows folder" --read /mnt/c/Users/someone
  refuses "there is no folder" --read "$HOME/no-such-folder"
  refuses "is in kingo-pod" --write "$KINGO_DIR"
  refuses "is in kingo-pod" --write "$KINGO_DIR/setup"
  refuses "is in kingo-pod" --write "$KINGO_DIR/backups"
  refuses "holds kingo-pod" --write "$(dirname "$KINGO_DIR")"
  # no folder, and nothing as the folder: not the folder kingo was started in (the review of 18 Nov 2026)
  refuses "needs a folder" --read
  refuses "needs a folder" --read=
  refuses "needs a folder" --write ""
  ok "--read refuses what --in refuses; --write takes nothing of kingo-pod but shared, and no folder that holds kingo-pod; nothing is no folder"
  # In --read=~/notes no shell puts in the home folder: kingo does.
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude "--read=~/projects/notes") || fail "kingo claude --read=~/projects/notes did not get as far as the start of Claude Code"
  has "$dry" "--read $KINGO_DIR --read $notes -- " || { show "$dry" 3; fail "in --read=~/projects/notes, kingo does not put the home folder in for ~"; }
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --read "$notes" --write "$KINGO_DIR/shared") || fail "kingo claude --read --write did not get as far as the start of Claude Code"
  show "$dry" 4
  has "$dry" "nono run --silent --profile kingo-claude --allow-cwd --read $KINGO_DIR --read $notes --allow $KINGO_DIR/shared -- " || fail "kingo does not give nono the two folders"
  has "$dry" "claude --add-dir=$KINGO_DIR --add-dir=$notes --add-dir=$KINGO_DIR/shared --permission-mode default" || fail "kingo does not give Claude Code the two folders"
  has "$dry" "Claude Code may also read this folder, and not change it: $notes" || fail "kingo does not name the folder to read"
  has "$dry" "You may also read these, and not change them: $notes. You may also read and change these: $KINGO_DIR/shared." \
    || fail "kingo does not tell Claude Code about the two folders"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --read "$notes") || fail "kc <folder> --read did not get as far as the start of Claude Code"
  has "$dry" "nono run --silent --profile kingo-claude-base --allow-cwd --read $KINGO_DIR/setup/claude --read $notes -- " || { show "$dry" 3; fail "kc <folder> --read does not give nono the folder"; }
  has "$dry" "claude --settings $HOME/.kingo-claude/settings-in.json --add-dir=$notes --permission-mode default --append-system-prompt You were started with" \
    || { show "$dry" 3; fail "kc <folder> --read does not give Claude Code the folder"; }
  has "$dry" "/add-dir and a yes to a request for permission do not open a folder outside the sandbox" || fail "the text for --in does not say that /add-dir does not open the sandbox"
  ok "the folders go to nono and to Claude Code, and kingo names them: with the course, and with kc <folder>"

  # The second review of 18 Nov 2026: no folder with commands for --write and --in (a curl put into ~/bin got the
  # keys from kingo); no folder where a link puts the keys and settings of programs (~/.config in ~/dotfiles/config);
  # shared/ as a link is where it leads; Library as a whole; kingo-pod for --read in a folder of one's own, where it
  # is closed; --in "" and --in=; an option in place of a folder; kingo's options before the folder of kc.
  say "kingo claude --in, --read and --write: commands, links, Library, kingo-pod, and the words around the folder"
  mkdir -p "$HOME/bin" "$HOME/projects/tools/bin" "$HOME/Library/notes"
  refuses "is a folder where your terminal finds its commands" --write "$HOME/bin"
  refuses "is a folder where your terminal finds its commands" --in "$HOME/bin"
  ( PATH="$HOME/projects/tools/bin:$PATH"; refuses "holds $HOME/projects/tools/bin, a folder where your terminal finds its commands" --write "$HOME/projects/tools" )
  ( PATH="$HOME/projects/tools/bin:$PATH"; cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --read "$HOME/projects/tools" > /dev/null ) \
    || fail "kingo claude --read did not take a folder with commands in it, which it only reads"
  # Library as a whole is too wide; a folder in it is the student's choice (Frank, 18 Nov 2026), but not LaunchAgents
  # for --write: its programs start at login, outside the sandbox
  mkdir -p "$HOME/Library/LaunchAgents"
  refuses "is too wide" --read "$HOME/Library"
  (cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --read "$HOME/Library/notes" > /dev/null) \
    || fail "kingo claude --read did not take a folder in Library, which the student chose"
  refuses "is in ~/Library/LaunchAgents" --write "$HOME/Library/LaunchAgents"
  rmdir "$HOME/bin" 2>/dev/null || true; rm -rf "$HOME/projects/tools" "$HOME/Library"
  local fh="$CFG/tmp/dotfiles-home"
  rm -rf "$fh"; mkdir -p "$fh/dotfiles/config/kingo" "$fh/dotfiles/zsh" "$fh/projects/x"; ln -s dotfiles/config "$fh/.config"
  : > "$fh/dotfiles/zsh/zshrc"; ln -s dotfiles/zsh/zshrc "$fh/.zshrc"
  for d in "$fh/dotfiles" "$fh/dotfiles/config/kingo" "$fh/dotfiles/zsh"; do
    if out=$(cd "$KINGO_DIR" && HOME="$fh" KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --read "$d" 2>&1); then show "$out" 3; fail "with ~/.config and ~/.zshrc in ~/dotfiles, kingo claude --read took $d"; fi
    has "$out" "where kingo or another program keeps its keys and settings" || { show "$out" 3; fail "kingo claude --read $d stopped, but not for the keys and settings"; }
    printf '         | %s\n' "$(printf '%s\n' "$out" | tail -n 1 | cut -c1-140)"
  done
  rm -rf "$fh"
  mv "$KINGO_DIR/shared" "$KINGO_DIR/shared.ci"; ln -s "$HOME" "$KINGO_DIR/shared"
  refuses "not the home folder itself" --write "$KINGO_DIR/shared"
  refuses "is a hidden folder" --read "$KINGO_DIR/shared/.config"
  rm "$KINGO_DIR/shared"; mv "$KINGO_DIR/shared.ci" "$KINGO_DIR/shared"
  refuses "holds kingo-pod" --in "$dir" --read "$(dirname "$KINGO_DIR")"
  refuses "is in kingo-pod" --in "$dir" --read "$KINGO_DIR/backups"
  (cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --read "$(dirname "$KINGO_DIR")" > /dev/null) \
    || fail "in the course, kingo claude --read did not take a folder that holds kingo-pod, which the course reads anyway"
  refuses "needs a folder" --in ""
  refuses "needs a folder, not --login" --in "$dir" --read --login
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude "--in=$dir") || fail "kingo claude --in=<folder> did not get as far as the start of Claude Code"
  has "$dry" "nono run --silent --profile kingo-claude-base --allow-cwd --read $KINGO_DIR/setup/claude -- " || { show "$dry" 3; fail "kingo claude --in=<folder> did not start in the folder"; }
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc --read "$notes" "$dir") || fail "kc --read <folder> <folder> did not get as far as the start of Claude Code"
  has "$dry" "nono run --silent --profile kingo-claude-base --allow-cwd --read $KINGO_DIR/setup/claude --read $notes -- " || { show "$dry" 3; fail "kc --read <folder> <folder> did not start in the folder"; }
  ok "commands, links to keys, shared as a link, Library and LaunchAgents, kingo-pod in a folder of one's own, --in \"\", --in=, an option for a folder, and kc --read <folder> <folder>"

  # The line for a new start that Claude Code gets: this start's own, with one --read more (the review: a fixed
  # "kc --read <folder>" dropped --login, ky and the folders of the start).
  say "kingo claude: the line for a new start with one more folder"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --read "$notes")
  has "$dry" "starts you again with this line, which keeps what this start has: kc $dir --read $notes --read <that folder> (without the short commands, in kingo-pod: ./kingo claude --in $dir --read $notes --read <that folder>)" \
    || { show "$dry" 3; fail "kc <folder> --read does not give Claude Code the line for a new start with its folders"; }
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kyl)
  has "$dry" "starts you again with this line, which keeps what this start has: kyl --read <that folder> (without the short commands, in kingo-pod: ./kingo yolo --login --read <that folder>)" \
    || { show "$dry" 3; fail "kyl does not give Claude Code the line for a new start with yolo and the login"; }
  if ls "$HOME/.config/nono/profiles" | grep -q '\.json\.[0-9]*$'; then fail "kingo left a part of a profile in ~/.config/nono/profiles"; fi
  ok "the line keeps the folder, the folders of --read, ky and the login; no part of a profile is left"

  say "kingo claude --read and --write, in the sandbox"
  base_before=("${base[@]}")
  base=(nono run --silent --profile kingo-claude-base --allow-cwd --read "$KINGO_DIR/setup/claude" --read "$notes" --allow "$out2" --)
  out=$(in_folder "${LOCK[@]}" sh -c 'cat "$1/note.txt"; ( : >> "$1/x.txt" ) 2>/dev/null && echo WROTE-READ; ( : >> "$2/y.txt" ) 2>/dev/null && echo WROTE-WRITE; cat "$3" 2>&1' sh "$notes" "$out2" "$OUTSIDE/secret.txt")
  base=("${base_before[@]}")
  show "$out" 4
  has "$out" "notes-probe-$$" || { show "$out" 12; fail "with --read, the sandbox cannot read the folder"; }
  if has "$out" WROTE-READ; then fail "with --read, the sandbox can write in the folder"; fi
  has "$out" WROTE-WRITE || { show "$out" 12; fail "with --write (nono --allow), the sandbox cannot write in the folder"; }
  if has "$out" "$SECRET"; then fail "with --read and --write, a file outside both folders was read"; fi
  rm -rf "$notes" "$out2"
  ok "it reads the folder of --read and cannot write there, writes in the folder of --write, and still reads nothing outside"

  say "my-nono-profile.json: the student's own additions to the sandbox of the course"
  out=$(in_sandbox "${LOCK[@]}" sh -c 'if ( : >> "$1" ) 2>/dev/null; then echo WROTE; else echo refused; fi' sh "$KINGO_DIR/shared/own-probe.txt")
  has "$out" refused || { show "$out" 12; fail "with the course profile alone, the sandbox can already write in shared: the check below would prove nothing"; }
  sed 's/"extends": "kingo-claude",/"extends": "default",/' "$KINGO_DIR/setup/claude/my-nono-profile.example.json" > "$mine"
  if out=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude 2>&1); then show "$out" 3; fail "kingo took a profile that does not extend the course profile"; fi
  ok "a profile that does not extend the course profile: kingo does not start"
  cp "$KINGO_DIR/setup/claude/my-nono-profile.example.json" "$mine"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude) || fail "kingo claude did not start with the example of my-nono-profile.json"
  has "$dry" "nono run --silent --profile kingo-claude-mine --allow-cwd --read $KINGO_DIR -- " || { show "$dry" 3; fail "kingo does not start nono with the student's profile"; }
  nono profile validate "$HOME/.config/nono/profiles/kingo-claude-mine.json" > "$CFG/tmp/validate.log" 2>&1 \
    || { show "$(cat "$CFG/tmp/validate.log")" 8; fail "nono does not take the example of my-nono-profile.json"; }
  out=$(kingo_env timeout 180 nono run --silent --profile kingo-claude-mine --allow-cwd --read "$KINGO_DIR" -- "${LOCK[@]}" \
    sh -c 'for f in "$@"; do if ( : >> "$f" ) 2>/dev/null; then echo "WROTE $f"; else echo "refused $f"; fi; done; echo "pg=$PGHOST n8n=${N8N_BASE_URL:+set}"' sh \
    "$KINGO_DIR/shared/own-probe.txt" "$KINGO_DIR/own-probe.txt" "$mine" "$OUTSIDE/own-probe.txt" 2>&1 || true)
  show "$(printf '%s\n' "$out" | grep -E '^(WROTE|refused|pg=)')" 6
  has "$out" "WROTE $KINGO_DIR/shared/own-probe.txt" || { show "$out" 20; fail "with the example profile, the sandbox still cannot write in shared"; }
  [ "$(printf '%s\n' "$out" | grep -c '^refused ')" = 3 ] || fail "with the example profile, the sandbox can write more than shared (kingo-pod, the profile itself, or a folder outside)"
  has "$out" "pg=127.0.0.1 n8n=set" || fail "with the example profile, what the course profile gives is gone (PostgreSQL, n8n)"
  rm -f "$mine" "$KINGO_DIR/shared/own-probe.txt"
  ok "the example lets Claude Code write in shared and nowhere else new; kingo-pod and the profile itself stay closed"

  stand_in      # writes the profiles again (my-nono-profile.json is gone) and puts the stand-in into the base profile
  [ ! -e "$HOME/.config/nono/profiles/kingo-claude-mine.json" ] || fail "kingo left the student's profile behind after the file was removed"

  say "the course profile is the base profile plus the course"
  out=$(in_sandbox "${LOCK[@]}" sh -c 'echo "pg=$PGHOST/$PGDATABASE n8n=${N8N_BASE_URL:+set} langflow=${LANGFLOW_BASE_URL:+set} openrouter=${OPENROUTER_BASE_URL:+set}/${OPENROUTER_API_KEY:+set} model=${ANTHROPIC_BASE_URL:+set}"')
  has "$out" "pg=127.0.0.1/classroom n8n=set langflow=set openrouter=set/set model=set" || { show "$out" 12; fail "the course profile lost a route or the variables for PostgreSQL"; }
  ok "course: PostgreSQL, n8n, Langflow, OpenRouter for the flows' models, and the model are there"

  say "in a folder of one's own, with the base profile"
  out=$(in_folder "${LOCK[@]}" sh -c 'echo "pg=$PGHOST n8n=${N8N_BASE_URL:-none} openrouter=${OPENROUTER_BASE_URL:-none} model=${ANTHROPIC_BASE_URL:+set}"; : >> here.txt && echo WROTE-HERE; head -n 1 "$1/setup/claude/README.md"; cat "$1/VERSION" 2>&1; cat "$2" 2>&1; ( : >> "$1/setup/claude/x" ) 2>/dev/null && echo WROTE-KINGO' sh "$KINGO_DIR" "$OUTSIDE/secret.txt")
  has "$out" "pg= n8n=none openrouter=none model=set" || { show "$out" 12; fail "the base profile has something of the course in it, or lost the way to the model"; }
  has "$out" WROTE-HERE || { show "$out" 12; fail "Claude Code could not write in its folder"; }
  has "$out" "# How \`kingo claude\` differs" || { show "$out" 12; fail "setup/claude cannot be read: look and the settings are there"; }
  if has "$out" "$(cat "$KINGO_DIR/VERSION")"; then fail "the rest of kingo-pod can be read from a folder of one's own"; fi
  if has "$out" "$SECRET"; then fail "a file outside the folder was read"; fi
  if has "$out" WROTE-KINGO; then fail "setup/claude can be written from a folder of one's own"; fi
  ok "it writes in the folder, reads setup/claude, and neither the rest of kingo-pod nor a file outside; nothing of the course"

  say "git keeps versions: in the folder, and in the course folder"
  # Without GIT_CONFIG_NOSYSTEM, git stops where the system has an /etc/gitconfig, which the sandbox refuses.
  if [ -e /etc/gitconfig ]; then
    out=$(in_folder "${LOCK[@]}" env -u GIT_CONFIG_NOSYSTEM sh -c 'git init -q probe-repo 2>&1; cd probe-repo && git -c user.name=ci -c user.email=ci@example.com commit -q --allow-empty -m x 2>&1; echo "commit-exit=$?"')
    rm -rf "$dir/probe-repo"
    printf '         | this machine has an /etc/gitconfig; without the variable: %s\n' "$(printf '%s\n' "$out" | grep -E 'commit-exit=|fatal' | tr '\n' ' ' | cut -c1-150)"
  fi
  printf 'first\n' > "$dir/git-probe.txt"
  out=$(in_folder "${LOCK[@]}" sh -c "$GIT")
  has "$out" "commits=2" || { show "$out" 20; fail "git does not work in a folder of one's own inside the sandbox"; }
  rm -rf "$KINGO_DIR/claude/.git"; printf 'first\n' > "$KINGO_DIR/claude/git-probe.txt"
  out=$(in_sandbox "${LOCK[@]}" sh -c "$GIT")
  has "$out" "commits=2" || { show "$out" 20; fail "git does not work in the course folder inside the sandbox"; }
  [ -z "$(cd "$KINGO_DIR" && git status --porcelain -- claude)" ] || fail "kingo-pod's own git sees the repository in the course folder"
  rm -rf "$KINGO_DIR/claude/.git" "$KINGO_DIR/claude/git-probe.txt"
  ok "git init, two commits and git gc work in both; kingo-pod's own git does not see the course folder's repository"

  say "the real Claude Code in a folder of one's own, with the settings from the command line"
  PROBE="pwd; echo made > made-by-claude.txt; echo the-command-ended"
  model_start "$log"
  out=$(in_folder "${LOCK[@]}" claude --settings "$KINGO_DIR/setup/claude/settings-in.json" --dangerously-skip-permissions -p "Run the probe." < /dev/null)
  model_stop "$log"
  has "$out" KINGO-PROBE-DONE || { show "$out" 40; fail "Claude Code did not finish the turn in a folder of one's own"; }
  has "$(results "$log")" "$dir" || { show "$(results "$log")" 12; fail "the Bash tool did not run in the folder"; }
  [ -s "$dir/made-by-claude.txt" ] || fail "the Bash tool did not write in the folder"
  /usr/bin/python3 - "$log" <<'PYTHON' || fail "Claude Code did not ask for the course's model: the settings from the command line did not count"
import json, sys
models = {json.loads(line).get("model") for line in open(sys.argv[1]) if json.loads(line).get("method") == "POST"}
print("         | models asked for: %s" % ", ".join(sorted(str(m) for m in models)))
sys.exit(0 if models == {"z-ai/glm-5.3-flash"} else 1)
PYTHON
  ok "Claude Code works in the folder and asks for the model that settings-in.json names"

  # Another provider for the model. The student's profile gives the route "anthropic" again, with another address,
  # another key file and another header; nono takes the student's entry in place of the base profile's. The
  # settings of the course folder name the model. Here the other provider is the stand-in, asked with x-api-key.
  say "my-nono-profile.json: another provider for the model, with a key of its own"
  local settings="$KINGO_DIR/claude/.claude/settings.json" other="$HOME/.config/kingo/other.key" log2="$CFG/tmp/model-other.jsonl"
  ( umask 077; printf 'other-provider-key' > "$other" )
  cat > "$mine" <<EOF
{
  "extends": "kingo-claude",
  "meta": { "name": "kingo-claude-mine", "version": "1", "description": "another provider for the model" },
  "network": {
    "custom_credentials": {
      "anthropic": {
        "upstream": "http://127.0.0.1:$MODEL_PORT",
        "credential_key": "file://__KEYS_DIR__/other.key",
        "env_var": "ANTHROPIC_API_KEY",
        "inject_header": "x-api-key",
        "credential_format": "{}"
      }
    }
  }
}
EOF
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude) || fail "kingo claude did not start with a profile that names another provider"
  grep -q '"upstream": "https://openrouter.ai/api"' "$HOME/.config/nono/profiles/kingo-claude-base.json" \
    || fail "the base profile does not name OpenRouter: the run below would not show that the student's profile wins"
  cp "$settings" "$settings.before"
  /usr/bin/python3 - "$settings" <<'PYTHON'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
env = data["env"]
env.pop("ANTHROPIC_API_KEY")                       # the course blanks it; the other provider's route sets it
for name in list(env):
    if name == "ANTHROPIC_MODEL" or name.endswith("_MODEL"):
        env[name] = "other-model"
json.dump(data, open(sys.argv[1], "w", encoding="utf-8"), indent=2)
PYTHON
  PROBE='echo "key-in-sandbox=$ANTHROPIC_API_KEY token-in-sandbox=${ANTHROPIC_AUTH_TOKEN:-none}"; echo the-command-ended'
  model_start "$log2"
  out=$(kingo_env timeout 180 nono run --silent --profile kingo-claude-mine --allow-cwd --read "$KINGO_DIR" -- "${LOCK[@]}" \
    claude --add-dir "$KINGO_DIR" --dangerously-skip-permissions -p "Run the probe." < /dev/null 2>&1 || true)
  model_stop "$log2"
  mv "$settings.before" "$settings"; rm -f "$mine" "$other"
  has "$out" KINGO-PROBE-DONE || { show "$out" 40; fail "Claude Code did not finish the turn with the other provider"; }
  /usr/bin/python3 - "$log2" <<'PYTHON' || fail "the request to the other provider did not carry its key in x-api-key, or not the model of the settings"
import json, sys
posts = [e for e in map(json.loads, open(sys.argv[1])) if e.get("method") == "POST" and e.get("kind") not in ("count", "unknown")]
seen = sorted({(e.get("model"), e.get("key_header"), e.get("key")) for e in posts})
for model, header, key in seen:
    print("         | model %s, header %s, key %s" % (model, header, key))
sys.exit(0 if seen == [("other-model", "x-api-key", "other-provider-key")] else 1)
PYTHON
  if has "$(results "$log2")" "other-provider-key"; then fail "the key of the other provider is readable inside the sandbox"; fi
  has "$(results "$log2")" "token-in-sandbox=none" || { show "$(results "$log2")" 6; fail "the token of the base profile's route is still set inside the sandbox"; }
  show "$(results "$log2")" 2
  ok "the other provider gets its own key in x-api-key and the model of the settings; inside the sandbox the key is a stand-in"

  # --key <name>: Claude Code's model paid with another OpenRouter key (Frank, 18 Nov 2026). kingo writes a profile
  # kingo-claude-key-<course|base|mine>-<name>, which extends the profile of the start and gives the route of the
  # model again, with that key's file. Here the route goes to the stand-in, which says which key came.
  say "kingo claude --key: another OpenRouter key for the model"
  local pd="$HOME/.config/nono/profiles" kp kf="$HOME/.config/kingo/openrouter-thesis.key" log3="$CFG/tmp/model-key.jsonl" n
  for n in "" "Big" "../x" "-x" "thesis-" "a_b"; do
    refuses "takes a name of small letters, digits and -" --key "$n"
  done
  refuses "a name of at most 32 letters" --key "$(printf '%033d' 0 | tr 0 a)"
  refuses "needs a name for the key" --key
  refuses "Take one of the two" --login --key thesis
  ok "--key refuses an empty name, capitals, a path, a name that starts or ends with -, a long name, no name, and --login"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --key thesis) || fail "kingo claude --key did not get as far as the start of Claude Code"
  has "$dry" "nono run --silent --profile kingo-claude-key-course-thesis --allow-cwd --read $KINGO_DIR -- " || { show "$dry" 3; fail "kingo claude --key does not start nono with the profile of the key"; }
  has "$dry" "Claude Code's model is paid with your OpenRouter key \"thesis\": $kf" || fail "kingo claude --key does not say which key pays"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --key thesis) || fail "kc <folder> --key did not get as far as the start of Claude Code"
  has "$dry" "nono run --silent --profile kingo-claude-key-base-thesis --allow-cwd --read $KINGO_DIR/setup/claude -- " || { show "$dry" 3; fail "kc <folder> --key does not start nono with the profile of the key"; }
  cp "$KINGO_DIR/setup/claude/my-nono-profile.example.json" "$mine"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --key thesis) || fail "kingo claude --key did not start with the example of my-nono-profile.json"
  has "$dry" "nono run --silent --profile kingo-claude-key-mine-thesis --allow-cwd --read $KINGO_DIR -- " || { show "$dry" 3; fail "with my-nono-profile.json, kingo claude --key does not start nono with the profile of the key"; }
  # Each profile of the key is the profile of its start, but for the file of the model's route: as nono itself sees
  # them (the manifest), every other route stays (n8n, Langflow, the flows' OpenRouter), and the model's route is the
  # base profile's in every field but the file. So the copy of the route in kingo cannot fall behind unseen.
  for n in course:kingo-claude base:kingo-claude-base mine:kingo-claude-mine; do
    kp="$pd/kingo-claude-key-${n%%:*}-thesis.json"
    [ -s "$kp" ] || fail "kingo did not write the profile of the key at $kp"
    nono profile validate "$kp" > "$CFG/tmp/validate-key.log" 2>&1 || { show "$(cat "$CFG/tmp/validate-key.log")" 8; fail "nono does not take the profile of the key that extends ${n#*:}"; }
    /usr/bin/python3 - "${n#*:}" "kingo-claude-key-${n%%:*}-thesis" "$kf" <<'PYTHON' || fail "the profile of the key that extends ${n#*:} is not its parent but for the key's file"
import json, subprocess, sys
parent, child, keyfile = sys.argv[1:]
def routes(profile):
    out = subprocess.run(["nono", "profile", "show", "--format", "manifest", profile], capture_output=True, text=True, check=True).stdout
    return {c["name"]: c for c in json.loads(out)["credentials"]}
a, b = routes(parent), routes(child)
want = dict(a.pop("anthropic", {}), source="file://" + keyfile)
model = b.pop("anthropic", {})
print("         | %s: %s; the model: %s" % (child, ", ".join("%s %s" % (k, "kept" if a.get(k) == b.get(k) else "CHANGED") for k in sorted(set(a) | set(b))) or "no other route",
      "the parent's route with the key's file" if model == want else "%s, not %s" % (model, want)))
sys.exit(0 if a == b and model == want else 1)
PYTHON
  done
  # A my-nono-profile.json that names another provider for the model, on one line or without quotes: --key is refused,
  # and before any key is asked for (the review of 18 Nov 2026: a test of whole lines missed both)
  printf '{ "extends": "kingo-claude", "meta": { "name": "kingo-claude-mine", "version": "1" }, "network": { "custom_credentials": { "anthropic": { "upstream": "https://api.example.com", "credential_key": "file://__KEYS_DIR__/x.key", "env_var": "ANTHROPIC_API_KEY", "inject_header": "x-api-key", "credential_format": "{}" } } } }\n' > "$mine"
  refuses "names another provider for the model (\"anthropic\"), and --key" --key thesis
  refuses "names another provider for the model (\"anthropic\"), and --login" --login
  sed 's/"anthropic":/anthropic:/' "$mine" > "$mine.json5" && mv "$mine.json5" "$mine"
  refuses "names another provider for the model (\"anthropic\"), and --key" --key thesis
  rm -f "$mine"
  # written whole: kingo writes a profile of the key under another name and then moves it (mv), so no part of one is left
  if ls "$pd" | grep -q '^kingo-claude-key-.*\.json\.'; then fail "kingo left a part of a profile of the key in $pd"; fi
  ok "three profiles of the key, one for each start: each is its parent but for the file of the model's route; nono takes them"
  # kc takes --key before the folder too, and the line for a new start keeps the key
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc --key thesis "$dir") || fail "kc --key thesis <folder> did not get as far as the start of Claude Code"
  has "$dry" "nono run --silent --profile kingo-claude-key-base-thesis --allow-cwd --read $KINGO_DIR/setup/claude -- " || { show "$dry" 3; fail "kc --key thesis <folder> did not start in the folder with the key"; }
  has "$dry" "starts you again with this line, which keeps what this start has: kc $dir --key thesis --read <that folder> (without the short commands, in kingo-pod: ./kingo claude --in $dir --key thesis --read <that folder>)" \
    || { show "$dry" 3; fail "the line for a new start does not keep --key"; }
  ok "kc --key thesis <folder> starts in the folder, and the line for a new start keeps the key"

  # The key itself, as a start finds it: kingo asks for it in a terminal only, and checks it at OpenRouter. A key that
  # OpenRouter refuses is deleted, that one and no other. Here a curl that answers OpenRouter's check with 401.
  local fake="$CFG/tmp/fake-curl" before
  mkdir -p "$fake"
  cat > "$fake/curl" <<'SH'
#!/bin/sh
case "$*" in *openrouter.ai/api/v1/key*) cat > /dev/null; printf 401; exit 0 ;; esac
exec /usr/bin/curl "$@"
SH
  chmod +x "$fake/curl"
  rm -f "$kf"
  if out=$(cd "$KINGO_DIR" && PATH="$fake:$PATH" ./kingo claude --in "$dir" --key thesis < /dev/null 2>&1); then show "$out" 3; fail "kingo claude --key started without the key and without a terminal to ask for it"; fi
  has "$out" "needs the OpenRouter key \"thesis\". Run it in a terminal" || { show "$out" 3; fail "without a terminal, kingo claude --key does not say that it must ask for the key"; }
  ( umask 077; printf 'refused-key' > "$kf" )
  before=$(cat "$HOME/.config/kingo/openrouter.key")
  if out=$(cd "$KINGO_DIR" && PATH="$fake:$PATH" ./kingo claude --in "$dir" --key thesis < /dev/null 2>&1); then show "$out" 3; fail "kingo claude --key started with a key that OpenRouter refused"; fi
  has "$out" "OpenRouter did not accept the key \"thesis\", and kingo deleted it" || { show "$out" 3; fail "kingo claude --key does not say that OpenRouter refused the key"; }
  [ ! -e "$kf" ] || fail "kingo kept the key that OpenRouter refused"
  [ "$(cat "$HOME/.config/kingo/openrouter.key")" = "$before" ] || fail "for a refused key of --key, kingo changed the key without a name"
  if has "$out" "Paste your OpenRouter key"; then fail "with --in and --key, kingo asked for the key without a name"; fi
  ok "the key of --key: asked for in a terminal only; refused by OpenRouter, it is deleted, and no other key"

  # A start in a folder of one's own with --key needs that key only: here the key without a name is gone.
  ( umask 077; printf 'thesis-key' > "$kf" )
  kp="$pd/kingo-claude-key-base-thesis.json"
  sed -i "s|https://openrouter.ai/api|http://127.0.0.1:$MODEL_PORT|" "$kp"
  mv "$HOME/.config/kingo/openrouter.key" "$CFG/tmp/openrouter.key.away"
  PROBE='echo "token-in-sandbox=$ANTHROPIC_AUTH_TOKEN"; echo the-command-ended'
  base_before=("${base[@]}")
  base=(nono run --silent --profile kingo-claude-key-base-thesis --allow-cwd --read "$KINGO_DIR/setup/claude" --)
  model_start "$log3"
  out=$(in_folder "${LOCK[@]}" claude --settings "$KINGO_DIR/setup/claude/settings-in.json" --dangerously-skip-permissions -p "Run the probe." < /dev/null)
  model_stop "$log3"
  base=("${base_before[@]}")
  mv "$CFG/tmp/openrouter.key.away" "$HOME/.config/kingo/openrouter.key"
  has "$out" KINGO-PROBE-DONE || { show "$out" 40; fail "Claude Code did not finish the turn with the profile of --key, without the key without a name"; }
  /usr/bin/python3 - "$log3" <<'PYTHON' || fail "the requests to the model did not carry the key of --key"
import json, sys
posts = [e for e in map(json.loads, open(sys.argv[1])) if e.get("method") == "POST" and e.get("kind") not in ("count", "unknown")]
seen = sorted({(e.get("key_header"), e.get("key")) for e in posts})
for header, key in seen:
    print("         | header %s, key %s" % (header, key))
sys.exit(0 if seen == [("authorization", "Bearer thesis-key")] else 1)
PYTHON
  if has "$(results "$log3")" "thesis-key"; then fail "the key of --key is readable inside the sandbox"; fi
  rm -f "$kf"
  ok "the model gets the key of --key, also without the key without a name; inside the sandbox it is a stand-in"

  # --key <name> --provider <provider> [--model <ID>]: the key of a name for another provider (Frank, 19 Nov 2026:
  # "beliebig, z.b. auch local"). kingo keeps the provider and the model with the name, writes the route of the model
  # for that provider, and the settings with that model. Checked here: what kingo refuses; what it keeps; the route as
  # nono sees it; and with the real Claude Code and the stand-in for the model, which key comes in which header, and
  # which model is asked for.
  say "kingo claude --key --provider: Anthropic's API, Ollama, or the address of a provider"
  local kd="$HOME/.config/kingo" set4 log4="$CFG/tmp/model-provider.jsonl"
  refuses "goes with --key <name>" --provider anthropic
  refuses "needs a provider" --key api --provider
  for n in "ftp://x" "http://example.com" "http://127.0.0.2:8000" "https://" "https://a b" "https://x:9z" "anthropic2" 'https://x/$(id)' "https://user@x.y" "HTTPS://x.y" "https://https://x.y" "https://x.y:"; do
    refuses "kingo claude --provider" --key bad --provider "$n" --model m
  done
  refuses "needs a model too" --key bad --provider ollama
  refuses "needs a model too" --key bad --provider https://api.example.com/anthropic
  refuses "takes the ID of a model" --key bad --provider ollama --model 'a"b'
  refuses "takes the ID of a model" --key bad --provider ollama --model 'a|b'
  refuses "needs the ID of a model" --key bad --provider ollama --model
  [ ! -e "$kd/key-bad.conf" ] || { show "$(cat "$kd/key-bad.conf")" 3; fail "a start that kingo refused left a file for the key"; }
  ok "--provider refuses: no --key, no provider, an address that is not https (or http on this laptop), a letter that is not of an address, the scheme twice, a : without a port; no model, or one with a letter that is not of an ID"

  # Anthropic's API, in a folder of one's own
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --key api --provider anthropic) || fail "kc <folder> --key api --provider anthropic did not get as far as the start of Claude Code"
  has "$dry" "nono run --silent --profile kingo-claude-key-base-api --allow-cwd --read $KINGO_DIR/setup/claude -- " || { show "$dry" 4; fail "--provider anthropic does not start nono with the profile of the key"; }
  has "$dry" "Claude Code's model comes from Anthropic's API, paid with your key \"api\": $kd/key-api.key" || { show "$dry" 4; fail "--provider anthropic does not say where the model comes from"; }
  has "$dry" "The model: Claude Code picks one of Anthropic's" || { show "$dry" 4; fail "--provider anthropic without --model does not say who picks the model"; }
  if has "$dry" CLAUDE_CODE_MAX_CONTEXT_TOKENS; then fail "with Anthropic's API, kingo still tells Claude Code the size of the course model's context"; fi
  [ "$(cat "$kd/key-api.conf")" = "$(printf 'provider=anthropic\nmodel=')" ] || { show "$(cat "$kd/key-api.conf")" 3; fail "kingo did not keep the provider with the name"; }
  [ "$(stat -c %a "$kd/key-api.conf")" = 600 ] || fail "the file with the provider of the key is readable for others"
  set4=$(printf '%s\n' "$dry" | sed -n 's/.* claude --settings \([^ ]*\) .*/\1/p' | head -n 1)
  [ -s "$set4" ] || { show "$dry" 4; fail "kingo did not write settings for the key"; }
  /usr/bin/python3 - "$set4" "$dir" <<'PYTHON' || fail "the settings for Anthropic's API are not the settings of a folder of one's own without the lines that name a model"
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
env = data["env"]
models = sorted(k for k in env if k.endswith("_MODEL"))
print("         | lines that name a model: %s; ANTHROPIC_API_KEY=%r; memory in %s" % (models or "none", env.get("ANTHROPIC_API_KEY"), data.get("autoMemoryDirectory")))
sys.exit(0 if not models and env.get("ANTHROPIC_API_KEY") == "" and data.get("autoMemoryDirectory") == sys.argv[2] + "/memory-of-ai"
         and data.get("disableRemoteControl") is True and env.get("DISABLE_TELEMETRY") == "1" else 1)
PYTHON
  kp="$pd/kingo-claude-key-base-api.json"
  nono profile validate "$kp" > "$CFG/tmp/validate-key.log" 2>&1 || { show "$(cat "$CFG/tmp/validate-key.log")" 8; fail "nono does not take the profile of the key for Anthropic's API"; }
  /usr/bin/python3 - kingo-claude-key-base-api "$kd/key-api.key" <<'PYTHON' || fail "the route of the model for Anthropic's API is not: api.anthropic.com, the key in Authorization: Bearer, a stand-in in ANTHROPIC_AUTH_TOKEN"
import json, subprocess, sys
out = subprocess.run(["nono", "profile", "show", "--format", "manifest", sys.argv[1]], capture_output=True, text=True, check=True).stdout
routes = {c["name"]: c for c in json.loads(out[out.index("{"):])["credentials"]}
r = routes.get("anthropic", {})
print("         | routes: %s; the model: %s, %s: %s, stand-in in %s" % (", ".join(sorted(routes)), r.get("upstream"), r.get("inject", {}).get("header"), r.get("inject", {}).get("format"), r.get("env_var")))
sys.exit(0 if list(routes) == ["anthropic"] and r.get("upstream") == "https://api.anthropic.com" and r.get("inject") == {"format": "Bearer {}", "header": "Authorization", "mode": "header"}
         and r.get("env_var") == "ANTHROPIC_AUTH_TOKEN" and r.get("source") == "file://" + sys.argv[2] else 1)
PYTHON
  # the next start needs only the name; --model is kept too, and names the first model only
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --key api) || fail "kc <folder> --key api did not start with the provider that kingo kept"
  has "$dry" "Claude Code's model comes from Anthropic's API" || { show "$dry" 4; fail "the next start with --key api forgot the provider"; }
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc --key api --model claude-sonnet-5-5 "$dir") || fail "kc --key api --model <ID> <folder> did not get as far as the start of Claude Code"
  has "$dry" "The model: claude-sonnet-5-5 (kept with \"api\"; --model changes it)" || { show "$dry" 4; fail "--model next to --key does not name the model of the key"; }
  if has "$(printf '%s\n' "$dry" | grep '^  nono run ')" " --model"; then show "$dry" 4; fail "--model next to --key went on to Claude Code as well"; fi
  [ "$(cat "$kd/key-api.conf")" = "$(printf 'provider=anthropic\nmodel=claude-sonnet-5-5')" ] || fail "kingo did not keep the model with the name"
  /usr/bin/python3 - "$set4" <<'PYTHON' || fail "with --model, the settings for Anthropic's API do not name that model, and that one only"
import json, sys
env = json.load(open(sys.argv[1], encoding="utf-8"))["env"]
models = {k: v for k, v in env.items() if k.endswith("_MODEL")}
print("         | %s" % models)
sys.exit(0 if models == {"ANTHROPIC_MODEL": "claude-sonnet-5-5"} else 1)
PYTHON
  # the course: settings for the command line, which rank above the settings of the course folder
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --key api) || fail "kingo claude --key api did not get as far as the start of Claude Code"
  has "$dry" "nono run --silent --profile kingo-claude-key-course-api --allow-cwd --read $KINGO_DIR -- " || { show "$dry" 4; fail "in the course, --key api does not start nono with the profile of the key"; }
  has "$dry" " claude --add-dir=$KINGO_DIR --settings $CFG/settings-key-api.json " || { show "$dry" 4; fail "in the course, the key of a name with a model does not bring its settings"; }
  /usr/bin/python3 - "$CFG/settings-key-api.json" <<'PYTHON' || fail "in the course, the settings of the key do not name its model and blank the other five"
import json, sys
env = json.load(open(sys.argv[1], encoding="utf-8"))["env"]
print("         | %s" % env)
sys.exit(0 if env.pop("ANTHROPIC_MODEL") == "claude-sonnet-5-5" and len(env) == 5 and set(env.values()) == {""} else 1)
PYTHON
  # The effort: medium for a provider by its address, in the course and with --in, so that a model that takes no
  # high gets a level it takes; none for Anthropic's API, whose models Claude Code knows (Frank, 20 Nov 2026).
  ( cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo key add eff --provider https://llm.example.com --model qwen3.8 > /dev/null ) || fail "kingo key add eff failed"
  ( umask 077; printf 'eff-key' > "$kd/key-eff.key" )
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --key eff) || { show "$dry" 4; fail "kingo claude --key eff did not get as far as the start of Claude Code"; }
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$dir" --key eff) || { show "$dry" 4; fail "kingo claude --in --key eff did not get as far as the start of Claude Code"; }
  /usr/bin/python3 - "$CFG/settings-key-eff.json" "$CFG"/settings-in-key-eff-*.json "$CFG/settings-key-api.json" <<'PYTHON' || fail "the settings of a key do not set the effort medium for a provider by its address, or set one for Anthropic's API"
import json, sys
course, own, api = (json.load(open(p, encoding="utf-8")) for p in sys.argv[1:4])
print("         | effort: course %r, own folder %r, Anthropic's API %r" % (course.get("effortLevel"), own.get("effortLevel"), api.get("effortLevel")))
sys.exit(0 if course.get("effortLevel") == own.get("effortLevel") == "medium" and "effortLevel" not in api else 1)
PYTHON
  ( cd "$KINGO_DIR" && ./kingo key remove eff > /dev/null ) || fail "kingo key remove eff failed"
  # a name stays with its provider once it has a key, and an OpenRouter key of before stays one
  ( umask 077; printf 'api-key-of-the-name' > "$kd/key-api.key" )
  refuses "The key \"api\" is for Anthropic's API, not for Ollama on this laptop" --key api --provider ollama --model m
  ( umask 077; printf 'thesis-key' > "$kf" )
  refuses "The key \"thesis\" is for OpenRouter, not for Anthropic's API" --key thesis --provider anthropic
  rm -f "$kf"
  # --model without --key is Claude Code's own option, as before
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --model opus) || fail "kc <folder> --model opus did not get as far as the start of Claude Code"
  has "$(printf '%s\n' "$dry" | grep '^  nono run ')" " --model opus" || { show "$dry" 4; fail "--model without --key no longer goes on to Claude Code"; }
  ok "Anthropic's API: kingo keeps the provider and the model with the name; the route is api.anthropic.com with the key in Authorization: Bearer; the settings name no model, or the first only"

  # The real Claude Code with that route and those settings; the stand-in takes Anthropic's place and says what came.
  # The key comes in Authorization: Bearer and nothing in x-api-key: Anthropic's API refuses a request that carries a
  # credential in both.
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --key api) || fail "kc <folder> --key api did not write its profile again"
  sed -i "s|https://api.anthropic.com|http://127.0.0.1:$MODEL_PORT|" "$kp"
  grep -q "\"upstream\": \"http://127.0.0.1:$MODEL_PORT\"" "$kp" || fail "the profile of the key has no line for Anthropic's API that the stand-in could take"
  PROBE='echo "token-in-sandbox=$ANTHROPIC_AUTH_TOKEN key-in-sandbox=${ANTHROPIC_API_KEY:-none}"; echo the-command-ended'
  base_before=("${base[@]}")
  base=(nono run --silent --profile kingo-claude-key-base-api --allow-cwd --read "$KINGO_DIR/setup/claude" --)
  model_start "$log4"
  out=$(in_folder "${LOCK[@]}" claude --settings "$set4" --dangerously-skip-permissions -p "Run the probe." < /dev/null)
  model_stop "$log4"
  base=("${base_before[@]}")
  has "$out" KINGO-PROBE-DONE || { show "$out" 40; fail "Claude Code did not finish the turn with the route for Anthropic's API"; }
  /usr/bin/python3 - "$log4" <<'PYTHON' || fail "the requests for Anthropic's API did not carry the key in Authorization: Bearer and nothing in x-api-key, or not the model of the key"
import json, sys
posts = [e for e in map(json.loads, open(sys.argv[1])) if e.get("method") == "POST" and e.get("kind") not in ("count", "unknown")]
seen = sorted({(e.get("model"), e.get("xkey"), e.get("auth")) for e in posts})
for model, xkey, auth in seen:
    print("         | model %s, x-api-key %r, Authorization %r" % (model, xkey, auth))
# The first model is the key's. Claude Code may ask one of Anthropic's small models for a side task: the settings
# name the first model only, as Claude Code knows Anthropic's others itself.
models = {m for m, _, _ in seen}
sys.exit(0 if seen and {(x, a) for _, x, a in seen} == {("", "Bearer api-key-of-the-name")} and "claude-sonnet-5-5" in models
         and all(str(m).startswith("claude-") for m in models) else 1)
PYTHON
  if has "$(results "$log4")" "api-key-of-the-name"; then fail "the key for Anthropic's API is readable inside the sandbox"; fi
  has "$(results "$log4")" "key-in-sandbox=none" || { show "$(results "$log4")" 6; fail "ANTHROPIC_API_KEY is set inside the sandbox: Claude Code would ask whether to use it"; }
  show "$(results "$log4")" 2
  ok "Anthropic's API: the model gets the key in Authorization: Bearer and nothing in x-api-key, and is asked for the model of the key; inside the sandbox the key is a stand-in"

  # The address of a provider: here the stand-in itself, on this laptop. No file is changed by hand: the profile and
  # the settings are kingo's as they are. The key goes out in Authorization: Bearer, and all six lines name the model.
  ( umask 077; printf 'gateway-key' > "$kd/key-gw.key" )
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --key gw --provider "http://localhost:$MODEL_PORT/" --model other/model:8b) || fail "kc <folder> --key gw --provider <address> did not get as far as the start of Claude Code"
  has "$dry" "Claude Code's model comes from http://127.0.0.1:$MODEL_PORT, with your key \"gw\": $kd/key-gw.key" || { show "$dry" 4; fail "--provider <address> does not say where the model comes from"; }
  has "$dry" CLAUDE_CODE_MAX_CONTEXT_TOKENS || fail "with the address of a provider, kingo no longer tells Claude Code the size of the context"
  set4=$(printf '%s\n' "$dry" | sed -n 's/.* claude --settings \([^ ]*\) .*/\1/p' | head -n 1)
  nono profile validate "$pd/kingo-claude-key-base-gw.json" > "$CFG/tmp/validate-key.log" 2>&1 || { show "$(cat "$CFG/tmp/validate-key.log")" 8; fail "nono does not take the profile of the key for the address of a provider"; }
  PROBE='echo "token-in-sandbox=$ANTHROPIC_AUTH_TOKEN"; echo the-command-ended'
  base=(nono run --silent --profile kingo-claude-key-base-gw --allow-cwd --read "$KINGO_DIR/setup/claude" --)
  model_start "$log4"
  out=$(in_folder "${LOCK[@]}" claude --settings "$set4" --dangerously-skip-permissions -p "Run the probe." < /dev/null)
  model_stop "$log4"
  base=("${base_before[@]}")
  has "$out" KINGO-PROBE-DONE || { show "$out" 40; fail "Claude Code did not finish the turn with the address of a provider"; }
  /usr/bin/python3 - "$log4" <<'PYTHON' || fail "the requests to the address of the provider did not carry its key in Authorization: Bearer, or not the model of the key"
import json, sys
posts = [e for e in map(json.loads, open(sys.argv[1])) if e.get("method") == "POST" and e.get("kind") not in ("count", "unknown")]
seen = sorted({(e.get("model"), e.get("auth"), e.get("xkey")) for e in posts})
for model, auth, xkey in seen:
    print("         | model %s, Authorization %r, x-api-key %r" % (model, auth, xkey))
sys.exit(0 if seen == [("other/model:8b", "Bearer gateway-key", "")] else 1)
PYTHON
  if has "$(results "$log4")" "gateway-key"; then fail "the key for the address of a provider is readable inside the sandbox"; fi
  ok "the address of a provider: the model gets the key of the name in Authorization: Bearer, and every request asks for the model of the key"

  # Ollama: a model on this laptop, no key. kingo writes a word into the key file, and stops when Ollama does not
  # answer. Here nothing listens on Ollama's port.
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --key local --provider ollama --model qwen3.5) || fail "kc <folder> --key local --provider ollama did not get as far as the start of Claude Code"
  has "$dry" "Claude Code's model comes from Ollama on this laptop (\"local\")." || { show "$dry" 4; fail "--provider ollama does not say where the model comes from"; }
  grep -q '"upstream": "http://127.0.0.1:11434"' "$pd/kingo-claude-key-base-local.json" || fail "the route for Ollama does not go to 127.0.0.1:11434"
  nono profile validate "$pd/kingo-claude-key-base-local.json" > "$CFG/tmp/validate-key.log" 2>&1 || { show "$(cat "$CFG/tmp/validate-key.log")" 8; fail "nono does not take the profile of the key for Ollama"; }
  if curl -s -m 2 -o /dev/null http://127.0.0.1:11434/api/version; then
    printf '         | something answers on 127.0.0.1:11434 here: the start without Ollama is not checked\n'
  else
    if out=$(cd "$KINGO_DIR" && KINGO_CLAUDE_NO_BROWSER=1 ./kingo claude --in "$dir" --key local < /dev/null 2>&1); then show "$out" 3; fail "kingo claude started for Ollama, and Ollama does not run"; fi
    has "$out" "Ollama does not answer on this laptop" || { show "$out" 3; fail "kingo does not say that Ollama does not answer"; }
    if has "$out" "Paste"; then show "$out" 3; fail "for Ollama, kingo asked for a key"; fi
    [ "$(cat "$kd/key-local.key")" = ollama ] || fail "for Ollama, kingo did not write the word that stands for a key"
  fi
  rm -f "$kd"/key-api.* "$kd"/key-gw.* "$kd"/key-local.*
  ok "Ollama: the route goes to 127.0.0.1:11434 without asking for a key, and kingo stops when Ollama does not answer"

  # ./kingo claude key add|list|remove (Frank, 19 Nov 2026: "dann kann man key verwaltung und project laden trennen"):
  # the keys apart from a start. Checked here: what the three refuse; what add keeps (the address without /v1, the
  # context, the certificate) and what a start makes of it; that list shows no key; that add puts another key in the
  # place of the first one, and of a name's, only when the provider accepts it (typed through a terminal of its own,
  # with_terminal.py); that remove takes the whole name and no other; and one turn of the real Claude Code to a
  # provider that signs with a certificate of its own.
  say "kingo claude key: add, list, remove; the context of a model; a certificate of the provider's own"
  local tls="$CFG/tmp/tls" log5="$CFG/tmp/model-tls.jsonl" set5 first_before i
  kk() { ( cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude key "$@" 2>&1 ); }
  # none_left <file or pattern> ...: not one of them is there. Each on its own: ls with three patterns fails as soon
  # as one matches nothing, and so said "nothing left" while two kinds of files were (the review of 19 Nov 2026).
  none_left() { local f; for f in "$@"; do [ ! -e "$f" ] || return 1; done; }
  mkdir -p "$tls"
  # a root, and a certificate for localhost that it signs: what a server at work or in a lab has
  { openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tls/root.key" -out "$tls/root.crt" -subj "/CN=kingo CI root" -days 2 \
    && openssl req -newkey rsa:2048 -nodes -keyout "$tls/server.key" -out "$tls/server.csr" -subj "/CN=localhost" \
    && printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' > "$tls/server.ext" \
    && openssl x509 -req -in "$tls/server.csr" -CA "$tls/root.crt" -CAkey "$tls/root.key" -CAcreateserial -out "$tls/server.crt" -days 2 -extfile "$tls/server.ext"
  } > "$tls/openssl.log" 2>&1 || { show "$(cat "$tls/openssl.log")" 8; fail "openssl did not make the certificates of the stand-in"; }
  cat "$tls/root.crt" "$tls/root.key" > "$tls/both.pem"
  printf 'no certificate\n' > "$tls/text.txt"

  refuses "takes add, list or remove" key bogus
  refuses "asks its questions in a terminal only" key add
  refuses "needs a name for the key" key add --provider anthropic
  refuses "takes a name of small letters" key add Thesis
  refuses "takes one name, not two" key add a b
  refuses "does not take --in" key add a --in "$dir"
  refuses "needs a model too" key add a --provider ollama
  refuses "takes a number of tokens from 32000 to 10000000" key add a --context 64
  refuses "takes a number of tokens from 32000 to 10000000" key add a --context 131072k
  refuses "takes a number of tokens from 32000 to 10000000" key add a --context 13107
  refuses "--context is for the other providers" key add a --provider anthropic --context 100000
  refuses "is for a provider by its address" key add a --provider anthropic --ca "$tls/root.crt"
  refuses "holds a private key" key add a --provider https://llm.example.com --model m --ca "$tls/both.pem"
  refuses "takes a certificate as text (PEM)" key add a --provider https://llm.example.com --model m --ca "$tls/text.txt"
  refuses "there is no file that kingo can read" key add a --provider https://llm.example.com --model m --ca "$tls/none.crt"
  refuses "takes nothing else" key add --first a
  refuses "takes a name. For your first OpenRouter key" key remove --first
  refuses "There is no key with the name nothere" key remove nothere
  refuses "belongs to the key, not to one start" --in "$dir" --key a --context 5000
  refuses "belongs to the key, not to one start" --key a --ca=x
  ls "$kd"/key-a.* > /dev/null 2>&1 && fail "a line that kingo claude key add refused left a file for the name"
  ok "key add, list and remove refuse: an unknown word, no name or two, a context that is no number of tokens, a certificate for a provider that needs none, with a private key, or that is none; a start refuses --context and --ca"

  # add: the address loses /v1, and kingo keeps the provider, the model, the context and the certificate
  out=$(kk add spark --provider "https://localhost:$MODEL_PORT/v1/" --model spark/model --context 131072 --ca "$tls/root.crt") \
    || { show "$out" 6; fail "kingo claude key add did not take a provider by its address, with a context and a certificate"; }
  has "$out" "kingo left out /v1 at the end of the address" || { show "$out" 6; fail "kingo claude key add does not say that it left out /v1"; }
  [ "$(cat "$kd/key-spark.conf")" = "$(printf 'provider=https://localhost:%s\nmodel=spark/model\ncontext=131072' "$MODEL_PORT")" ] \
    || { show "$(cat "$kd/key-spark.conf")" 4; fail "kingo claude key add did not keep the address without /v1, the model and the context"; }
  [ "$(stat -c %a "$kd/key-spark.conf")" = 600 ] && [ "$(stat -c %a "$kd/key-spark.crt")" = 600 ] || fail "what kingo claude key add keeps is readable for others"
  cmp -s "$tls/root.crt" "$kd/key-spark.crt" || fail "kingo claude key add did not keep the certificate as it was given"
  out=$(kk add spark2 --provider "https://localhost:$MODEL_PORT/v1/messages" --model m) || { show "$out" 4; fail "kingo claude key add did not take an address that ends in /v1/messages"; }
  grep -qx "provider=https://localhost:$MODEL_PORT" "$kd/key-spark2.conf" || fail "kingo claude key add did not leave out /v1/messages at the end of an address"
  ( umask 077; printf 'spark-key' > "$kd/key-spark.key" )   # the dry run asks for no key
  out=$(kk add spark --context 100000) || { show "$out" 4; fail "kingo claude key add did not change the context of a name that is there"; }
  [ "$(cat "$kd/key-spark.conf")" = "$(printf 'provider=https://localhost:%s\nmodel=spark/model\ncontext=100000' "$MODEL_PORT")" ] || fail "a new context changed more than the context"
  [ -s "$kd/key-spark.crt" ] && [ "$(cat "$kd/key-spark.key")" = spark-key ] || fail "a new context took the certificate or the key of the name away"
  out=$(kk add spark --context 131072) || fail "kingo claude key add did not set the context again"
  if out=$(kk add spark --provider anthropic); then show "$out" 3; fail "kingo claude key add gave a name that has a key another provider"; fi
  has "$out" "Or delete this name first:  ./kingo key remove spark" || { show "$out" 3; fail "for a name of another provider, kingo does not name key remove"; }
  ok "key add keeps the address without /v1, the model, the context and the certificate, for the owner only; a new context changes nothing else"

  # list: every name with what kingo keeps for it, and no key
  out=$(kk list) || { show "$out" 6; fail "kingo claude key list failed"; }
  has "$out" "(first)    OpenRouter, the course's model. It has no name" || { show "$out" 8; fail "kingo claude key list does not show the first key"; }
  has "$out" "spark      https://localhost:$MODEL_PORT, model spark/model, 131072 tokens of context, with your certificate" || { show "$out" 8; fail "kingo claude key list does not say what kingo keeps for a name"; }
  has "$out" "spark2     https://localhost:$MODEL_PORT, model m. No key yet" || { show "$out" 8; fail "kingo claude key list does not say that a name has no key yet"; }
  if has "$out" spark-key || has "$out" "$(cat "$kd/openrouter.key")"; then fail "kingo claude key list shows a key"; fi
  show "$out" 5
  ok "key list shows each name with its provider, model, context and certificate, and never a key"

  # a start with that name: the context goes to Claude Code in place of the 200000, and nono gets the certificate
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --key spark) || fail "kc <folder> --key spark did not get as far as the start of Claude Code"
  has "$dry" "The model holds 131072 tokens, as you said" || { show "$dry" 6; fail "a start does not say the context of the key"; }
  has "$dry" "context: CLAUDE_CODE_MAX_CONTEXT_TOKENS=131072" || { show "$dry" 6; fail "the context of the key does not go to Claude Code"; }
  has "$dry" "context: CLAUDE_CODE_AUTO_COMPACT_WINDOW=131072" || { show "$dry" 6; fail "the context of the key does not go to Claude Code as its auto-compact window too"; }
  has "$dry" "kingo trusts the certificate that you gave: $kd/key-spark.crt" || { show "$dry" 6; fail "a start does not say that kingo trusts the certificate of the key"; }
  grep -q "\"tls_ca\": \"$kd/key-spark.crt\"" "$pd/kingo-claude-key-base-spark.json" || { show "$(cat "$pd/kingo-claude-key-base-spark.json")" 20; fail "the profile of the key does not give nono the certificate"; }
  nono profile validate "$pd/kingo-claude-key-base-spark.json" > "$CFG/tmp/validate-key.log" 2>&1 || { show "$(cat "$CFG/tmp/validate-key.log")" 8; fail "nono does not take the profile of a key with a certificate"; }
  set5=$(printf '%s\n' "$dry" | sed -n 's/.* claude --settings \([^ ]*\) .*/\1/p' | head -n 1)
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --key plain) || fail "kc <folder> --key plain did not get as far as the start of Claude Code"
  has "$dry" "context: CLAUDE_CODE_MAX_CONTEXT_TOKENS=200000" || { show "$dry" 6; fail "without a context of its own, a key no longer gets the 200000"; }
  if has "$dry" CLAUDE_CODE_AUTO_COMPACT_WINDOW; then show "$dry" 6; fail "a key without a context of its own gets an auto-compact window"; fi
  if grep -q tls_ca "$pd/kingo-claude-key-base-plain.json"; then fail "a key without a certificate got one in its profile"; fi
  ok "a start with the name: its context in place of the 200000, and its certificate in the route that nono reads"

  # The real Claude Code to a provider that signs with a certificate of its own: the stand-in, over https, with the
  # certificate that the root above signed. This machine does not trust it by itself; nono does, from the profile.
  PROBE='echo "token-in-sandbox=$ANTHROPIC_AUTH_TOKEN window-in-sandbox=${CLAUDE_CODE_AUTO_COMPACT_WINDOW-unset}"; echo the-command-ended'
  : > "$log5"
  /usr/bin/python3 "$HERE/fake_model.py" "$MODEL_PORT" "$log5" "$PROBE" "$tls/server.crt" "$tls/server.key" &
  MODEL_PID=$!
  for i in $(seq 1 20); do curl -s -m 2 -o /dev/null --cacert "$tls/root.crt" "https://localhost:$MODEL_PORT/ready" && break; sleep 0.5; done
  curl -s -m 2 -o /dev/null --cacert "$tls/root.crt" "https://localhost:$MODEL_PORT/ready" || fail "the stand-in with a certificate of its own did not start"
  if curl -s -m 2 -o /dev/null "https://localhost:$MODEL_PORT/ready"; then fail "this machine trusts the certificate of the stand-in without being given the root: the turn would prove nothing"; fi
  base_before=("${base[@]}")
  base=(nono run --silent --profile kingo-claude-key-base-spark --allow-cwd --read "$KINGO_DIR/setup/claude" --)
  # with the auto-compact window of the key, as a start with --key spark sets it (in_folder sets the rest)
  out=$(export CLAUDE_CODE_AUTO_COMPACT_WINDOW=131072; in_folder "${LOCK[@]}" claude --settings "$set5" --dangerously-skip-permissions -p "Run the probe." < /dev/null)
  model_stop "$log5"
  base=("${base_before[@]}")
  has "$out" KINGO-PROBE-DONE || { show "$out" 40; fail "Claude Code did not finish the turn with a provider that signs with a certificate of its own"; }
  /usr/bin/python3 - "$log5" <<'PYTHON' || fail "the requests to the provider with its own certificate did not carry the key of the name, or not its model"
import json, sys
posts = [e for e in map(json.loads, open(sys.argv[1])) if e.get("method") == "POST" and e.get("kind") not in ("count", "unknown")]
seen = sorted({(e.get("model"), e.get("auth"), e.get("xkey")) for e in posts})
for model, auth, xkey in seen:
    print("         | model %s, Authorization %r, x-api-key %r" % (model, auth, xkey))
sys.exit(0 if seen == [("spark/model", "Bearer spark-key", "")] else 1)
PYTHON
  if has "$(results "$log5")" "spark-key"; then fail "the key for the provider with its own certificate is readable inside the sandbox"; fi
  has "$(results "$log5")" "window-in-sandbox=131072" || { show "$(results "$log5")" 6; fail "the auto-compact window of a key does not reach Claude Code through the profile of the key"; }
  if has "$out" "100k minimum" || has "$out" "1M maximum" || has "$out" "isn't a usable size"; then show "$out" 12; fail "Claude Code warns about the auto-compact window that kingo sets"; fi
  ok "a provider with a certificate of its own: nono trusts it from the profile, and the model gets the key and the model of the name"

  # The keys that are typed: kingo asks in a terminal only, so the CI gives it one (with_terminal.py). A curl that
  # answers the check of a key with the code in a file stands for OpenRouter and Anthropic.
  local fake2="$CFG/tmp/fake-curl-code" term="$HERE/with_terminal.py"
  mkdir -p "$fake2"
  cat > "$fake2/curl" <<'SH'
#!/bin/sh
case "$*" in *openrouter.ai/api/v1/key*|*api.anthropic.com/v1/models*) cat > /dev/null; cat "$(dirname "$0")/code"; exit 0 ;; esac
exec /usr/bin/curl "$@"
SH
  chmod +x "$fake2/curl"
  typed() { # typed <code> <answer> <what comes after kingo claude key>: in a terminal, with the answer typed once
    local answer=$2; printf '%s' "$1" > "$fake2/code"; shift 2
    ( cd "$KINGO_DIR" && PATH="$fake2:$PATH" /usr/bin/python3 "$term" "$answer" ./kingo claude key "$@" 2>&1 )
  }
  first_before=$(cat "$kd/openrouter.key")
  if out=$(cd "$KINGO_DIR" && ./kingo claude key add --first < /dev/null 2>&1); then show "$out" 3; fail "kingo claude key add --first went on without a terminal"; fi
  has "$out" "Run it in a terminal" || { show "$out" 3; fail "without a terminal, key add --first does not say that it must ask for the key"; }
  for n in 401 000; do
    if out=$(typed "$n" first-key-new add --first); then show "$out" 4; fail "key add --first took a key that OpenRouter answered with $n"; fi
    has "$out" "your first key is as it was" || { show "$out" 4; fail "key add --first does not say that the first key is as it was (HTTP $n)"; }
    [ "$(cat "$kd/openrouter.key")" = "$first_before" ] || fail "key add --first changed the first key, and OpenRouter answered with $n"
  done
  out=$(typed 200 first-key-new add --first) || { show "$out" 4; fail "key add --first did not take a key that OpenRouter accepted"; }
  [ "$(cat "$kd/openrouter.key")" = first-key-new ] && [ "$(stat -c %a "$kd/openrouter.key")" = 600 ] || fail "key add --first did not put the new key in the place of the first one, for the owner only"
  if has "$out" first-key-new; then show "$out" 4; fail "kingo showed the key that was typed"; fi
  ( umask 077; printf '%s' "$first_before" > "$kd/openrouter.key" )   # the first key of this run, as it was
  ok "key add --first: the first key stays until OpenRouter has accepted the new one, and the typed key is not shown"

  out=$(typed 200 web-key-1 add website) || { show "$out" 4; fail "key add did not take a new name with a key that OpenRouter accepted"; }
  has "$out" "Paste the OpenRouter key \"website\"" || { show "$out" 4; fail "key add does not ask for the key of a new name"; }
  [ "$(cat "$kd/openrouter-website.key")" = web-key-1 ] || fail "key add did not keep the key of a new name"
  out=$(typed 200 '' add website) || { show "$out" 4; fail "key add failed for a name that is there, with Enter alone"; }
  has "$out" "The key is as it was." && [ "$(cat "$kd/openrouter-website.key")" = web-key-1 ] || { show "$out" 4; fail "Enter alone did not keep the key of the name"; }
  if out=$(typed 403 web-key-2 add website); then show "$out" 4; fail "key add put a key that OpenRouter refused in the place of a name's key"; fi
  has "$out" "the key \"website\" is as it was" && [ "$(cat "$kd/openrouter-website.key")" = web-key-1 ] || { show "$out" 4; fail "a refused new key changed the key of the name"; }
  out=$(typed 200 web-key-3 add website --model other/model) || { show "$out" 4; fail "key add did not put an accepted key in the place of a name's key"; }
  [ "$(cat "$kd/openrouter-website.key")" = web-key-3 ] && [ "$(cat "$kd/key-website.conf")" = "$(printf 'provider=openrouter\nmodel=other/model')" ] || fail "key add did not keep the new key and the new model of the name"
  out=$(typed 200 api-key-1 add api --provider anthropic --model sonnet) || { show "$out" 4; fail "key add did not take a name for Anthropic's API"; }
  if out=$(typed 400 api-key-2 add api); then show "$out" 4; fail "key add put a key that Anthropic answered with 400 in the place of a name's key"; fi
  has "$out" "probably not made for one workspace" && [ "$(cat "$kd/key-api.key")" = api-key-1 ] || { show "$out" 4; fail "a new key for Anthropic that got 400 changed the key of the name"; }
  ok "key add for a name: a new name is asked for its key; for a name that is there, Enter keeps the key, and another key takes its place only when the provider accepts it"

  # kingo key add with nothing after it asks its questions, one by one, and asks again after an answer that the line
  # would refuse (Frank, 20 Nov 2026); kingo key is kingo claude key. pty_answer.py --all types one answer per
  # question, and fails when an answer is left over.
  asked() { # asked <code> <answer> ... -- <command>: in a terminal, the answers typed one by one
    printf '%s' "$1" > "$fake2/code"; shift
    ( cd "$KINGO_DIR" && PATH="$fake2:$PATH" /usr/bin/python3 "$HERE/pty_answer.py" --all 60 "$@" 2>&1 )
  }
  out=$(asked 200 "Bad Name" wiz 7 4 ftp://x "https://llm.example.com/v1" "" big-model 1000 "64,000" wiz-key -- ./kingo key add) \
    || { show "$out" 12; fail "kingo key add did not take a provider by its address from its questions"; }
  for t in "A name of small letters, digits and -" "Type one number, from 1 to 4." "An address that starts with https://" "kingo left out /v1 at the end of the address" \
           "This provider needs the name of a model." "A number from 32000 to 10000000" "Start Claude Code with it:  kc <folder> --key wiz"; do
    has "$out" "$t" || { show "$out" 24; fail "kingo key add with its questions does not say: $t"; }
  done
  [ "$(cat "$kd/key-wiz.conf")" = "$(printf 'provider=https://llm.example.com\nmodel=big-model\ncontext=64000')" ] \
    || { show "$(cat "$kd/key-wiz.conf")" 4; fail "kingo key add did not keep the answers to its questions"; }
  [ "$(cat "$kd/key-wiz.key")" = wiz-key ] && [ "$(stat -c %a "$kd/key-wiz.key")" = 600 ] || fail "kingo key add did not keep the typed key, for the owner only"
  if has "$out" wiz-key; then show "$out" 24; fail "kingo key add showed the key that was typed"; fi
  out=$(asked 200 wiz2 2 sk-ant-pasted-too-early sonnet api-key-w -- ./kingo key add) || { show "$out" 12; fail "kingo key add did not take Anthropic's API from its questions"; }
  grep -qx provider=anthropic "$kd/key-wiz2.conf" && grep -qx model=sonnet "$kd/key-wiz2.conf" && [ "$(cat "$kd/key-wiz2.key")" = api-key-w ] \
    || fail "kingo key add did not keep Anthropic's API, the model and the key from its questions"
  has "$out" "That looks like a key, not the name of a model." && ! grep -q sk-ant-pasted "$kd/key-wiz2.conf" || { show "$out" 12; fail "kingo key add took a key, pasted at the question for the model, as the model"; }
  if out=$(asked 401 wiz3 1 "" bad-key -- ./kingo key add); then show "$out" 12; fail "kingo key add kept a key that OpenRouter refused"; fi
  none_left "$kd"/openrouter-wiz3.key "$kd"/key-wiz3.* || fail "kingo key add left a file for a key that OpenRouter refused"
  out=$(asked 200 wiz other/model "" -- ./kingo key add) || { show "$out" 12; fail "kingo key add failed for a name that is there"; }
  has "$out" "kingo keeps this name already:" && grep -qx model=other/model "$kd/key-wiz.conf" && [ "$(cat "$kd/key-wiz.key")" = wiz-key ] \
    || { show "$out" 12; fail "kingo key add with its questions did not change the model of a name that is there, or lost its key"; }
  if out=$(cd "$KINGO_DIR" && ./kingo key add < /dev/null 2>&1); then show "$out" 3; fail "kingo key add went on without a terminal and without a name"; fi
  has "$out" "asks its questions in a terminal only" || { show "$out" 3; fail "without a terminal, kingo key add does not say how to give it all in the line"; }
  out=$(asked 200 "" -- ./kingo key remove) || { show "$out" 12; fail "kingo key remove with Enter alone failed"; }
  has "$out" "kingo deleted nothing." && [ -s "$kd/key-wiz.key" ] || { show "$out" 12; fail "kingo key remove with Enter alone deleted something"; }
  out=$(asked 200 wiz -- ./kingo key remove) || { show "$out" 12; fail "kingo key remove did not take a name from its question"; }
  none_left "$kd"/key-wiz.* || fail "kingo key remove with its question left something of the name"
  ( cd "$KINGO_DIR" && ./kingo key remove wiz2 > /dev/null ) || fail "kingo key remove wiz2 failed"
  out=$(cd "$KINGO_DIR" && ./kingo key list 2>&1) || { show "$out" 6; fail "kingo key list failed"; }
  has "$out" "(first)    OpenRouter, the course's model." || { show "$out" 6; fail "kingo key list does not show the first key"; }
  # What the review of 20 Nov 2026 found in the questions, one case each.
  # The address at the question for the provider, and a key at the question for the model; then an http:// address.
  out=$(asked 200 direct "https://llm.example.com" "0123456789abcdef0123456789abcdef.AbCdEfGhIjKlMnOp" m "" dkey -- ./kingo key add) \
    || { show "$out" 16; fail "kingo key add failed with an address at the question for the provider"; }
  has "$out" "That looks like a key, not the name of a model." || { show "$out" 16; fail "kingo key add took a key of hex, a dot and letters as the model"; }
  grep -qx provider=https://llm.example.com "$kd/key-direct.conf" && grep -qx model=m "$kd/key-direct.conf" \
    || { show "$out" 16; fail "kingo key add did not take an address typed at the question for the provider"; }
  if has "$out" "dkey"; then show "$out" 16; fail "kingo key add showed the key that was typed"; fi
  ( cd "$KINGO_DIR" && ./kingo key remove direct > /dev/null ) || fail "kingo key remove direct failed"
  out=$(asked 200 wrong 4 "http://llm.example.com" "https://llm.example.com" m "" wkey -- ./kingo key add) || { show "$out" 16; fail "kingo key add did not go on after an address that it cannot use"; }
  has "$out" "  kingo cannot use this address. kingo takes http:// only for a server on this laptop" && ! has "$out" "ERROR:" || { show "$out" 16; fail "kingo key add says ERROR and names --provider for an address in its questions"; }
  ( cd "$KINGO_DIR" && ./kingo key remove wrong > /dev/null ) || fail "kingo key remove wrong failed"
  # A provider that refused the key leaves the name without a key: the next round asks for the provider again.
  if out=$(asked 401 oops 2 sonnet bad-key -- ./kingo key add); then show "$out" 12; fail "kingo key add kept a key that Anthropic refused"; fi
  out=$(asked 200 oops 1 "" good-key -- ./kingo key add) || { show "$out" 12; fail "kingo key add did not let a name without a key change its provider"; }
  has "$out" "no key for it yet. It asks everything again." && [ "$(cat "$kd/openrouter-oops.key")" = good-key ] && none_left "$kd"/key-oops.* \
    || { show "$out" 12; fail "a name whose key Anthropic refused could not become an OpenRouter key"; }
  ( cd "$KINGO_DIR" && ./kingo key remove oops > /dev/null ) || fail "kingo key remove oops failed"
  # A laptop that never started kingo claude has no folder for the keys yet.
  local fresh; fresh=$(mktemp -d "$CFG/tmp/fresh-home.XXXXXX")
  out=$(printf 200 > "$fake2/code"; cd "$KINGO_DIR" && HOME="$fresh" PATH="$fake2:$PATH" /usr/bin/python3 "$HERE/pty_answer.py" --all 60 thesis 1 "" fresh-key -- ./kingo key add 2>&1) \
    || { show "$out" 12; fail "kingo key add failed on a laptop without ~/.config/kingo"; }
  [ "$(cat "$fresh/.config/kingo/openrouter-thesis.key")" = fresh-key ] && [ "$(stat -c %a "$fresh/.config/kingo")" = 700 ] \
    || { show "$out" 12; fail "kingo key add lost an accepted key on a laptop without ~/.config/kingo"; }
  rm -rf "$fresh"
  # kingo key remove asks again after a name that is not there.
  ( cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo key add again --provider https://llm.example.com --model m > /dev/null ) || fail "kingo key add again failed"
  out=$(asked 200 Again nosuch again -- ./kingo key remove) || { show "$out" 12; fail "kingo key remove did not ask again after a name that is not there"; }
  has "$out" "There is no key with the name nosuch. Type one of the names above." && none_left "$kd"/key-again.* || { show "$out" 12; fail "kingo key remove did not delete the name after a wrong one"; }
  ok "kingo key add asks its questions in a terminal, asks again after a wrong answer, keeps the answers and the key unseen, and refuses a key that the provider refused; kingo key remove asks which name"

  # What the review of 19 Nov 2026 found in 1.4.27, one case each.
  # A name without a key that turns into plain OpenRouter leaves no file of the provider before.
  kk add turn --provider https://llm.example.com --model big > /dev/null || fail "kingo claude key add did not take the name turn"
  out=$(kk add turn --provider openrouter) || { show "$out" 4; fail "kingo claude key add did not give a name without a key to OpenRouter"; }
  [ ! -e "$kd/key-turn.conf" ] || { show "$(cat "$kd/key-turn.conf")" 3; fail "a name that turned to OpenRouter kept the file of its provider before"; }
  # --ca by a name, from the folder the person is in (kingo itself works in kingo-pod)
  out=$(cd "$tls" && KINGO_CLAUDE_DRY_RUN=1 "$KINGO_DIR/kingo" claude key add rel --provider https://llm.example.com --model m --ca root.crt 2>&1) \
    || { show "$out" 4; fail "kingo claude key add --ca did not find a file named from the folder one is in"; }
  cmp -s "$tls/root.crt" "$kd/key-rel.crt" || fail "kingo claude key add --ca did not keep the file named from the folder one is in"
  # a file that someone changed by hand, with a key under the name: the key goes to no provider that kingo cannot name
  ( umask 077; printf 'provider=ht!tp\nmodel=m\n' > "$kd/key-hand.conf"; printf 'hand-key' > "$kd/key-hand.key" )
  refuses "names a provider that kingo does not take, and the name has a key" key add hand --provider https://new.example.com --model m
  refuses "names a provider that kingo does not take, and the name has a key" --in "$dir" --key hand --provider anthropic
  [ "$(cat "$kd/key-hand.key")" = hand-key ] && [ "$(cat "$kd/key-hand.conf")" = "$(printf 'provider=ht!tp\nmodel=m')" ] || fail "kingo changed a name whose provider it cannot read"
  # a start that stops, here for a folder that is not there, leaves the name as it was
  kk add cert --provider https://llm.example.com --model m --context 131072 --ca "$tls/root.crt" > /dev/null || fail "kingo claude key add did not take the name cert"
  before=$(cat "$kd/key-cert.conf")
  refuses "there is no folder" --in "$HOME/no-such-folder" --key cert --provider https://other.example.com --model x
  [ "$(cat "$kd/key-cert.conf")" = "$before" ] && [ -s "$kd/key-cert.crt" ] || fail "a start that stopped changed what kingo keeps for the name"
  # an address that 1.4.26 kept with /v1 at its end: kingo says that it leaves it out from now on
  ( umask 077; printf 'provider=https://old.example.com/v1\nmodel=m\n' > "$kd/key-old.conf" )
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --key old) || fail "kc <folder> --key old did not get as far as the start of Claude Code"
  has "$dry" "kingo keeps the address of \"old\" without /v1 at its end from now on" || { show "$dry" 5; fail "kingo changed an address that it kept, and did not say so"; }
  grep -qx 'provider=https://old.example.com' "$kd/key-old.conf" || fail "kingo did not keep the address without /v1"
  # A context for one of Anthropic's models behind an address. Claude Code keeps its own size for such a model, so
  # the number goes to it as the auto-compact window too, which is 100000 to 1000000 tokens. Outside that range
  # kingo sets no window (Claude Code would warn at every start), and says that the number may change nothing.
  out=$(kk add gwc --provider https://gateway.example.com --model claude-sonnet-5 --context 200000) || { show "$out" 4; fail "kingo claude key add did not take a context for a model of Anthropic behind an address"; }
  if has "$out" "may change nothing"; then show "$out" 4; fail "kingo says that a context of 200000 may change nothing for a model of Anthropic, while the auto-compact window carries it"; fi
  for n in 200000 100000 1000000; do
    [ "$n" = 200000 ] || out=$(kk add gwc --context "$n") || { show "$out" 4; fail "kingo claude key add did not take the context $n"; }
    dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --key gwc) || fail "kc <folder> --key gwc did not get as far as the start of Claude Code"
    has "$dry" "context: CLAUDE_CODE_MAX_CONTEXT_TOKENS=$n" && has "$dry" "context: CLAUDE_CODE_AUTO_COMPACT_WINDOW=$n" || { show "$dry" 6; fail "the context $n of a key does not go to Claude Code in both variables"; }
  done
  for n in 64000 99999 1000001; do
    out=$(kk add gwc --context "$n") || { show "$out" 4; fail "kingo claude key add did not take the context $n"; }
    has "$out" "--context $n may change nothing" || { show "$out" 4; fail "kingo does not say that the context $n may change nothing for a model of Anthropic"; }
    dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --key gwc) || fail "kc <folder> --key gwc did not get as far as the start of Claude Code"
    has "$dry" "context: CLAUDE_CODE_MAX_CONTEXT_TOKENS=$n" || { show "$dry" 6; fail "the context $n of a key does not go to Claude Code"; }
    if has "$dry" CLAUDE_CODE_AUTO_COMPACT_WINDOW; then show "$dry" 6; fail "kingo sets an auto-compact window of $n, which Claude Code does not take"; fi
  done
  # a name with a key, no terminal, and a provider that answers 401: the key stays (a start would delete it)
  printf 401 > "$fake2/code"
  ( umask 077; printf 'kept-key' > "$kd/openrouter-keep.key" )
  out=$(cd "$KINGO_DIR" && PATH="$fake2:$PATH" ./kingo claude key add keep --context 131072 < /dev/null 2>&1) || { show "$out" 4; fail "kingo claude key add failed for a name with a key, without a terminal"; }
  [ "$(cat "$kd/openrouter-keep.key")" = kept-key ] || fail "kingo claude key add lost the key of a name, and no other key took its place"
  grep -qx 'context=131072' "$kd/key-keep.conf" || fail "kingo claude key add without a terminal did not keep the context"
  # key add for Ollama starts nothing, so Ollama need not run
  if curl -s -m 2 -o /dev/null http://127.0.0.1:11434/api/version; then
    printf '         | something answers on 127.0.0.1:11434 here: key add without Ollama is not checked\n'
  else
    out=$(cd "$KINGO_DIR" && ./kingo claude key add local --provider ollama --model qwen3.5 < /dev/null 2>&1) || { show "$out" 4; fail "kingo claude key add stopped because Ollama does not run"; }
    has "$out" "Ollama does not answer on this laptop right now" && has "$out" "local      Ollama on this laptop, model qwen3.5 (no key)" || { show "$out" 5; fail "kingo claude key add for Ollama does not say that Ollama does not answer, or not what it keeps"; }
  fi
  for n in turn rel hand cert old gwc keep local; do
    if [ -n "$(ls "$kd" | grep -E "^(key|openrouter)-$n[.]" || true)" ]; then kk remove "$n" > /dev/null || fail "kingo claude key remove $n failed"; fi
  done
  ok "the review of 19 Nov: no file of a provider before; --ca from the folder one is in; no key to a provider that kingo cannot read; a start that stops changes nothing; /v1 in a kept address is said; without a terminal the key stays; key add needs no running Ollama"

  # remove: the whole name, with what kingo wrote for it, and nothing of another name
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo kc "$dir" --key spark2) || fail "kc <folder> --key spark2 did not get as far as the start of Claude Code"
  ls "$CFG"/settings-in-key-spark-*.json "$CFG"/settings-in-key-spark2-*.json > /dev/null 2>&1 || fail "the settings of the two names are not both there before remove"
  out=$(kk remove spark) || { show "$out" 4; fail "kingo claude key remove failed"; }
  has "$out" "kingo deleted the key \"spark\" from this laptop" || { show "$out" 4; fail "kingo claude key remove does not say what it deleted"; }
  none_left "$kd"/key-spark.* "$pd"/kingo-claude-key-*-spark.json "$CFG"/settings-in-key-spark-[0-9]*.json || fail "kingo claude key remove left something of the name"
  [ -s "$kd/key-spark2.conf" ] && [ -s "$pd/kingo-claude-key-base-spark2.json" ] && ls "$CFG"/settings-in-key-spark2-*.json > /dev/null 2>&1 \
    || fail "kingo claude key remove spark took something of spark2"
  [ "$(cat "$kd/openrouter.key")" = "$first_before" ] || fail "kingo claude key remove changed the first key"
  out=$(kk list)
  if has "$out" "  spark  "; then show "$out" 8; fail "kingo claude key list still shows a name that was removed"; fi
  for n in spark2 website api; do kk remove "$n" > /dev/null || fail "kingo claude key remove $n failed"; done
  rm -f "$kd"/key-plain.* "$pd"/kingo-claude-key-*-plain.json
  [ -z "$(ls "$kd" | grep -E '^(key|openrouter)-(spark|spark2|website|api|plain|turn|rel|hand|cert|old|gwc|keep|local)[.]' || true)" ] || { show "$(ls "$kd")" 8; fail "after the removes, kingo still keeps a file of a name"; }
  ok "key remove takes the key, the provider, the model, the certificate, the settings and the profiles of that name, and nothing of another"
}

# kingo claude --login: Claude Code with the student's Anthropic login in place of OpenRouter. No login can be made
# here: that needs an account. What is checked: what kingo would start; that nono takes the profiles; the steps of
# kingo around the login, with a stand-in for nono (fake_nono.sh); what the real nono gives with the profiles of
# the login; and that Claude Code asks for Anthropic's models when the settings of the login are on the command line.
part_login() {
  local out dry p vars sess a b dir="$HOME/projects/thesis" lcfg="$HOME/.kingo-claude-login" tpl="$KINGO_DIR/setup/claude"
  local store="$HOME/.local/state/nono/oauth-capture" mine="$KINGO_DIR/my-nono-profile.json" prof="$HOME/.config/nono/profiles"
  local port=18790 word="outside-word-$$" pid i log="$CFG/tmp/model-login.jsonl"
  # in_login <profile> <folder> <what nono may read> command ...: as kingo claude --login runs Claude Code
  in_login() {
    local profile=$1 where=$2 reads=$3; shift 3
    ( cd "$where" &&
      CLAUDE_CODE_DISABLE_ARTIFACT=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1 \
      CLAUDE_CONFIG_DIR="$lcfg" CLAUDE_CODE_TMPDIR="$lcfg/tmp" TMPDIR="$lcfg/tmp" \
      PGHOST=127.0.0.1 PGPORT=5432 PGUSER=student PGPASSWORD=placeholder PGDATABASE=classroom \
      NONO_NO_SAVE_PROMPT=1 GIT_CONFIG_NOSYSTEM=1 \
      PATH="$KINGO_DIR/setup/claude/bin:$PATH" KINGO_BROWSER="$BROWSER_BIN" \
        timeout 180 nono run --silent --profile "$profile" --allow-cwd --read "$reads" -- "${LOCK[@]}" "$@" ) 2>&1 || true
  }

  say "what kingo claude would start"
  prepare
  rm -rf "$dir" "$mine"; mkdir -p "$dir" "$lcfg/tmp" "$lcfg.lock" "$store"

  say "kingo claude --login: what it would start"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --login) || fail "kingo claude --login did not get as far as the start of Claude Code"
  show "$dry" 3
  has "$dry" "nono run --silent --profile kingo-claude-login-course --allow-cwd --read $KINGO_DIR -- /usr/bin/python3 -I $tpl/no_unix_sockets.py claude --add-dir=$KINGO_DIR --settings $tpl/settings-login.json --permission-mode default" \
    || fail "kingo claude --login would not start Claude Code with the course profile of the login, under the lock, with the settings of the login"
  vars=" $(printf '%s\n' "$dry" | sed -n 's/^  variables: //p')"
  has "$vars" " PGHOST " || fail "kingo claude --login does not set the variables for PostgreSQL"
  if has "$vars" " CLAUDE_CODE_MAX_CONTEXT_TOKENS "; then fail "kingo claude --login tells Claude Code the context size of the course's model"; fi
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --login --in "$dir") || fail "kingo claude --login --in did not get as far as the start of Claude Code"
  has "$dry" "nono run --silent --profile kingo-claude-login --allow-cwd --read $tpl -- /usr/bin/python3 -I $tpl/no_unix_sockets.py claude --settings $HOME/.kingo-claude-login/settings-in.json --permission-mode default --append-system-prompt You were started with" \
    || { show "$dry" 3; fail "kingo claude --login --in would not start Claude Code with the profile of the login and its own settings"; }
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo yolo --in "$dir" --login) || fail "kingo yolo --in --login did not get as far as the start of Claude Code"
  has "$dry" "nono run --silent --profile kingo-claude-login --allow-cwd --read $tpl -- " || { show "$dry" 3; fail "kingo does not find --login after --in"; }
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude logout) || fail "kingo claude logout did not get as far as the logout"
  has "$dry" "nono run --profile kingo-claude-login --allow-cwd -- claude auth logout" || { show "$dry" 3; fail "kingo claude logout would not log out inside the sandbox of the login"; }
  ok "the course with the login, a folder of one's own with the login, and the logout"

  say "kingo claude --login with the student's own profile"
  cp "$tpl/my-nono-profile.example.json" "$mine"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --login) || fail "kingo claude --login did not start with the example of my-nono-profile.json"
  # under a name of its own: a kc and a kcl at the same time must not take each other's copy (the review of 18 Nov 2026)
  has "$dry" "nono run --silent --profile kingo-claude-login-mine --allow-cwd --read $KINGO_DIR -- " || { show "$dry" 3; fail "with --login, kingo does not start nono with the student's profile"; }
  grep -q '^  "extends": "kingo-claude-login-course",$' "$prof/kingo-claude-login-mine.json" \
    || fail "with --login, the student's profile does not extend the course profile of the login"
  nono profile validate "$prof/kingo-claude-login-mine.json" > "$CFG/tmp/validate.log" 2>&1 \
    || { show "$(cat "$CFG/tmp/validate.log")" 8; fail "nono does not take the student's profile on top of the login"; }
  out=$(in_login kingo-claude-login-mine "$KINGO_DIR/claude" "$KINGO_DIR" sh -c 'echo "base=${ANTHROPIC_BASE_URL:-none} n8n=${N8N_BASE_URL:+set}"; if ( : >> "$1" ) 2>/dev/null; then echo WROTE; else echo refused; fi' sh "$KINGO_DIR/shared/own-probe.txt")
  has "$out" "base=none n8n=set" || { show "$out" 12; fail "the student's profile on top of the login: the way to OpenRouter is there, or n8n is gone"; }
  has "$out" WROTE || { show "$out" 12; fail "the student's profile on top of the login does not give shared"; }
  rm -f "$KINGO_DIR/shared/own-probe.txt"
  cat > "$mine" <<EOF
{
  "extends": "kingo-claude",
  "meta": { "name": "kingo-claude-mine", "version": "1", "description": "another provider for the model" },
  "network": {
    "custom_credentials": {
      "anthropic": {
        "upstream": "https://example.com",
        "credential_key": "file://__KEYS_DIR__/other.key",
        "env_var": "ANTHROPIC_API_KEY",
        "inject_header": "x-api-key",
        "credential_format": "{}"
      }
    }
  }
}
EOF
  if out=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --login 2>&1); then show "$out" 3; fail "kingo took --login together with a profile that names another provider"; fi
  rm -f "$mine"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude) || fail "kingo claude did not start after the profile was removed"
  ok "the example adds shared to the sandbox of the login; a profile with another provider and --login: kingo does not start"

  say "nono takes the seven profiles"
  for p in kingo-claude-core kingo-claude-base kingo-claude-course kingo-claude kingo-claude-login kingo-claude-login-course kingo-claude-login-open; do
    nono profile validate "$prof/$p.json" > "$CFG/tmp/validate.log" 2>&1 || { show "$(cat "$CFG/tmp/validate.log")" 8; fail "nono does not take the profile $p"; }
  done
  ok "core, base, course, kingo-claude, login, login-course, login-open"

  # kingo's own steps: a start of kingo in a terminal, in a home folder of its own, where "nono" is fake_nono.sh.
  say "the steps of kingo around the login, with a stand-in for nono"
  local fh="$CFG/tmp/login-home" cred
  cred="$fh/.kingo-claude-login/.credentials.json"
  rm -rf "$fh"; mkdir -p "$fh/projects/thesis" "$fh/.local/share/kingo/nono/$(sed -n 's/^CLAUDE_NONO_VERSION=//p' "$KINGO_DIR/kingo")"
  cp "$HERE/fake_nono.sh" "$fh/.local/share/kingo/nono/$(sed -n 's/^CLAUDE_NONO_VERSION=//p' "$KINGO_DIR/kingo")/nono"
  chmod +x "$fh"/.local/share/kingo/nono/*/nono
  # step <what the stand-in leaves at a login> <arguments of kingo>
  step() {
    local login=$1; shift
    ( cd "$KINGO_DIR" && HOME="$fh" XDG_CONFIG_HOME="" KINGO_CLAUDE_NO_BROWSER=1 STUB_LOGIN="$login" \
        timeout 120 /usr/bin/python3 -I -c 'import pty, sys; pty.spawn(sys.argv[1:])' ./kingo "$@" < /dev/null 2>&1 | tr -d '\r' ) || true
  }
  session_of() { printf '%s\n' "$1" | awk '/^STUB nono run .*--read /{f=1} f'; }

  # With an auto-compact window in the person's own terminal: the profile lets the variable through for the context
  # of a key, so kingo takes it away before every start (the variables of the session, below).
  out=$(export CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000; step phantom claude --login --in "$fh/projects/thesis")
  if has "$out" "CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000"; then show "$out" 30; fail "an auto-compact window from the person's own terminal reaches nono"; fi
  show "$(printf '%s\n' "$out" | grep -v '^STUB  ')" 6
  has "$out" "STUB nono run --profile kingo-claude-login --allow-cwd --read-file $tpl/no_unix_sockets.py -- /usr/bin/python3 -I $tpl/no_unix_sockets.py claude auth login --claudeai" \
    || { show "$out" 30; fail "without a login, kingo does not run the login inside the sandbox, under the lock"; }
  has "$out" "Logged in." || { show "$out" 30; fail "kingo does not take a login that nono kept outside the sandbox"; }
  sess=$(session_of "$out")
  has "$sess" "STUB nono run --silent --profile kingo-claude-login --allow-cwd --read $tpl -- /usr/bin/python3 -I $tpl/no_unix_sockets.py claude --settings $fh/.kingo-claude-login/settings-in.json" \
    || { show "$out" 30; fail "after the login, kingo does not start the session"; }
  for p in "CLAUDE_CODE_DISABLE_ARTIFACT=1" "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1" "DISABLE_TELEMETRY=1" "DISABLE_ERROR_REPORTING=1" \
           "CLAUDE_CODE_MAX_CONTEXT_TOKENS=unset" "CLAUDE_CODE_AUTO_COMPACT_WINDOW=unset" \
           "CLAUDE_CONFIG_DIR=$fh/.kingo-claude-login" "TMPDIR=$fh/.kingo-claude-login/tmp" \
           "GIT_CONFIG_NOSYSTEM=1" "NONO_NO_SAVE_PROMPT=1" "PATH starts with $tpl/bin"; do
    has "$sess" "STUB   $p" || { show "$sess" 16; fail "the start of the session does not get: $p"; }
  done
  ok "no login: kingo runs the login in the sandbox, takes nono's stand-ins, and starts the session with its variables"

  out=$(step none claude --login --in "$fh/projects/thesis")
  if has "$out" "auth login"; then show "$out" 30; fail "kingo asks for the login again although one is there"; fi
  has "$(session_of "$out")" "STUB nono run --silent --profile kingo-claude-login " || { show "$out" 30; fail "with a login, kingo does not start the session"; }
  ok "a login is there: kingo starts the session and does not ask again"

  # One session with --login at a time (nono issues 2087, 2299): a session that runs stops a second start and the
  # logout; a session that ended, or a number that now runs another program, does not.
  # The stand-in is a script, not a copy of sleep: since Ubuntu 25.10 sleep is
  # one program for all of coreutils that goes by its name, and a copy named
  # nono-session ends at once. A script's process carries the script's name.
  # sleep is not its last command, so sh cannot hand over the process to it.
  printf '#!/bin/sh\nsleep 300\nexit 0\n' > "$fh/nono-session"; chmod +x "$fh/nono-session"
  "$fh/nono-session" & pid=$!
  sleep 0.2
  [ "$(ps -p "$pid" -o comm= 2>/dev/null)" = nono-session ] || fail "the stand-in for a running session does not run as nono-session"
  echo "$pid" > "$fh/.kingo-claude-login.session"
  out=$(step none claude --login --in "$fh/projects/thesis")
  has "$out" "another ./kingo claude --login is running (process $pid)" || { show "$out" 30; fail "a second kingo claude --login started while one runs"; }
  if has "$out" "--read "; then show "$out" 30; fail "kingo started a second session with --login"; fi
  out=$(step none claude logout)
  has "$out" "so the logout does not start" || { show "$out" 30; fail "kingo claude logout ran while a session with --login runs"; }
  [ -s "$cred" ] || fail "the logout removed the login while a session with --login runs"
  # The script ends by itself once its sleep is gone, so the kill may find nothing.
  pkill -P "$pid" 2>/dev/null || true; kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
  out=$(step none claude --login --in "$fh/projects/thesis")
  has "$(session_of "$out")" "STUB nono run --silent --profile kingo-claude-login " || { show "$out" 30; fail "after the other session ended, kingo does not start one"; }
  sleep 300 & pid=$!
  echo "$pid" > "$fh/.kingo-claude-login.session"
  out=$(step none claude --login --in "$fh/projects/thesis")
  has "$(session_of "$out")" "STUB nono run --silent --profile kingo-claude-login " || { show "$out" 30; fail "a number that runs another program stopped kingo claude --login"; }
  kill "$pid"; wait "$pid" 2>/dev/null || true
  ok "one session with --login at a time: a running one stops a second start and the logout, an ended one does not"

  out=$(step none claude logout)
  has "$out" "STUB nono run --profile kingo-claude-login --allow-cwd --read-file $tpl/no_unix_sockets.py -- /usr/bin/python3 -I $tpl/no_unix_sockets.py claude auth logout" || { show "$out" 30; fail "kingo claude logout does not log out inside the sandbox"; }
  has "$out" "Logged out" || { show "$out" 30; fail "kingo claude logout does not say that it logged out"; }
  [ ! -e "$cred" ] || fail "after kingo claude logout the login is still in the config folder"
  out=$(step none claude logout)
  has "$out" "There is no login" || { show "$out" 30; fail "a second kingo claude logout does not say that there is no login"; }
  ok "logout: inside the sandbox, the login is gone from the config folder, and a second logout says so"

  out=$(step real claude --login --in "$fh/projects/thesis")
  has "$out" "nono did not keep this login outside the sandbox" || { show "$out" 30; fail "kingo took a login that is not nono's stand-in"; }
  if has "$out" "--read "; then show "$out" 30; fail "kingo started a session with a login that is not nono's stand-in"; fi
  [ ! -e "$cred" ] || fail "a login that is not nono's stand-in stayed in the config folder"
  ok "a login that nono did not capture: kingo logs out, deletes it, and starts no session"

  out=$(step none claude --login --in "$fh/projects/thesis")
  has "$out" "the login did not work" || { show "$out" 30; fail "kingo does not say that no login was made"; }
  if has "$out" "--read "; then show "$out" 30; fail "kingo started a session without a login"; fi
  ok "no login made: kingo says so and starts no session"

  printf '{"claudeAiOauth":{"accessToken":"sk-ant-oat01-MADE-UP_for-the-CI","refreshToken":"nono_abababababababababababababababababababababababababababababababab"}}' > "$cred"
  out=$(step phantom claude --login --in "$fh/projects/thesis")
  has "$out" "removed a login" || { show "$out" 30; fail "kingo kept a login in which one token is not nono's stand-in"; }
  has "$out" "Logged in." || { show "$out" 30; fail "after removing the login, kingo did not ask for a new one"; }
  ok "a login in the config folder with a token that is not nono's: kingo removes it and asks for the login"

  rm -f "$cred"
  out=$( ( cd "$KINGO_DIR" && HOME="$fh" XDG_CONFIG_HOME="" KINGO_CLAUDE_NO_BROWSER=1 ./kingo claude --login --in "$fh/projects/thesis" < /dev/null 2>&1 ) || true)
  has "$out" "Run it in a terminal" || { show "$out" 12; fail "without a terminal and without a login, kingo does not say what to do"; }
  ok "without a terminal: kingo says that the login needs one"
  rm -rf "$fh"

  # The real nono, with the profiles of the login. Its store of the real tokens is outside everything the sandbox gets.
  say "the sandbox of the login: the model not through OpenRouter, the course (and OpenRouter for the flows' models) only with the course, nono's store stays outside"
  # ci-probe.txt: can its text be read? A second file, which no command below names: can the folder be listed?
  printf 'store-%s\n' "$SECRET" > "$store/ci-probe.txt"
  : > "$store/listed-$SECRET"
  printf 'login-folder-%s\n' "$SECRET" > "$lcfg/marker.txt"
  local probe='echo "base=${ANTHROPIC_BASE_URL:-none} token=${ANTHROPIC_AUTH_TOKEN:-none} proxy=${HTTPS_PROXY:+set} ca=${NODE_EXTRA_CA_CERTS:+set} n8n=${N8N_BASE_URL:+set} langflow=${LANGFLOW_BASE_URL:+set} openrouter=${OPENROUTER_BASE_URL:+set} pg=${PGHOST:-none}"; cat "$1" 2>&1; ls "$(dirname "$1")" 2>&1; for f in "$2/probe" "$3/probe" ./probe-here; do if ( : >> "$f" ) 2>/dev/null; then echo "WROTE $f"; else echo "refused $f"; fi; done'
  out=$(in_login kingo-claude-login "$dir" "$tpl" sh -c "$probe" sh "$store/ci-probe.txt" "$CFG" "$lcfg")
  show "$(printf '%s\n' "$out" | grep -E '^(base=|WROTE|refused)')" 5
  has "$out" "base=none token=none proxy=set ca=set n8n= langflow= openrouter= pg=none" || { show "$out" 20; fail "the profile of the login: a way to OpenRouter or something of the course is there, or nono's proxy and certificate are not"; }
  if has "$out" "store-$SECRET" || has "$out" "listed-$SECRET"; then fail "the sandbox of the login can read nono's store of the real tokens"; fi
  has "$out" "refused $CFG/probe" || fail "the sandbox of the login can write in the config folder of the OpenRouter way"
  has "$out" "WROTE $lcfg/probe" || fail "the sandbox of the login cannot write in its own config folder"
  has "$out" "WROTE ./probe-here" || fail "the sandbox of the login cannot write in the folder it starts in"
  out=$(in_login kingo-claude-login-course "$KINGO_DIR/claude" "$KINGO_DIR" sh -c "$probe" sh "$store/ci-probe.txt" "$CFG" "$lcfg")
  show "$(printf '%s\n' "$out" | grep -E '^(base=|WROTE|refused)')" 5
  has "$out" "base=none token=none proxy=set ca=set n8n=set langflow=set openrouter=set pg=127.0.0.1" || { show "$out" 20; fail "the course profile of the login: the model goes through OpenRouter, or n8n, Langflow, OpenRouter for the flows' models or PostgreSQL are not there"; }
  if has "$out" "store-$SECRET" || has "$out" "listed-$SECRET"; then fail "the sandbox of the login, with the course, can read nono's store of the real tokens"; fi
  rm -f "$KINGO_DIR/claude/probe-here"
  out=$(in_sandbox "${LOCK[@]}" sh -c 'cat "$1" 2>&1; cat "$2" 2>&1; ls "$(dirname "$2")" 2>&1' sh "$lcfg/marker.txt" "$store/ci-probe.txt")
  if has "$out" "$SECRET"; then fail "the sandbox of the OpenRouter way can read the config folder of the login, or nono's store"; fi
  ok "login: the model not through OpenRouter, nono's proxy and certificate, its own config folder; the course's routes only with the course; the store is closed"

  # kingo itself, with the real nono and the real Claude Code. The checks above rebuild kingo's lines; here kingo
  # runs them. (On 14 Nov 2026 the login step could not read the lock under WSL2, and no check saw it: every
  # check here gave nono read access that kingo's login step did not.) Nobody logs in here: the step counts as
  # run when Claude Code shows the address for the login.
  say "kingo claude --login itself, with the real nono: its login step gets as far as the address for the login"
  rm -f "$lcfg/.credentials.json"
  # the comparison: kingo's login step as it was, without read access to the lock
  out=$( ( cd "$lcfg/tmp" && CLAUDE_CONFIG_DIR="$lcfg" NONO_NO_SAVE_PROMPT=1 \
             timeout 120 nono run --profile kingo-claude-login --allow-cwd -- /usr/bin/python3 -I "$tpl/no_unix_sockets.py" claude auth login --claudeai ) 2>&1 || true)
  has "$out" "no_unix_sockets.py': [Errno 13] Permission denied" \
    || { show "$out" 12; fail "without read access to the lock, the login step runs all the same: the check below would prove nothing"; }
  # real_kingo <seconds> <arguments of kingo>: kingo in a terminal, with this runner's home folder and kingo's nono
  real_kingo() {
    local t=$1; shift
    ( cd "$KINGO_DIR" && KINGO_CLAUDE_NO_BROWSER=1 \
        timeout "$t" /usr/bin/python3 -I -c 'import pty, sys; pty.spawn(sys.argv[1:])' ./kingo "$@" < /dev/null 2>&1 | tr -d '\r' ) || true
  }
  out=$(real_kingo 60 claude --login --in "$dir")
  pkill -f 'claude auth login' 2>/dev/null || true
  show "$(printf '%s\n' "$out" | grep -E 'Sign in|Paste code|ERROR|Permission denied' | cut -c1-110)" 4
  if has "$out" "can't open file"; then show "$out" 30; fail "kingo's login step cannot read the lock"; fi
  has "$out" "/oauth/authorize?" || { show "$out" 40; fail "kingo's login step did not get as far as the address for the login, inside the real sandbox"; }
  if has "$out" "Logged in."; then fail "kingo says that it is logged in, and nobody logged in"; fi
  [ ! -e "$lcfg/.credentials.json" ] || fail "kingo's login step left a login, and nobody logged in"
  ok "kingo's login step starts Claude Code through the lock, inside the real sandbox, and Claude Code shows the address"
  printf '{"claudeAiOauth":{"accessToken":"sk-ant-oat01-%s","refreshToken":"nono_%s","expiresAt":1}}' \
    abababababababababababababababababababababababababababababababab abababababababababababababababababababababababababababababababab > "$lcfg/.credentials.json"
  out=$(real_kingo 120 claude logout)
  show "$(printf '%s\n' "$out" | grep -E 'ogged out|ERROR|Permission denied' | cut -c1-110)" 4
  if has "$out" "can't open file" || has "$out" "Permission denied"; then show "$out" 30; fail "kingo claude logout cannot read the lock"; fi
  has "$out" "Logged out: ./kingo claude --login will ask" || { show "$out" 40; fail "kingo claude logout did not say that it logged out"; }
  [ ! -e "$lcfg/.credentials.json" ] || fail "after kingo claude logout the login is still in the config folder"
  ok "kingo claude logout runs inside the real sandbox too"

  say "the network of the login's sandbox is as closed as that of the OpenRouter way"
  /usr/bin/python3 "$HERE/probe_server.py" "$port" "$dir/probe.sock" "$word" &
  pid=$!
  for i in $(seq 1 20); do curl -s -m 2 "http://127.0.0.1:$port/" 2>/dev/null | grep -q "$word" && break; sleep 0.5; done
  out="tcp=$(curl -s -m 5 "http://127.0.0.1:$port/" 2>/dev/null | head -c 60) unix=$(curl -s -m 5 --unix-socket "$dir/probe.sock" http://localhost/ 2>/dev/null | head -c 60)"
  [ "$out" = "tcp=$word unix=$word" ] || { kill "$pid" 2>/dev/null || true; fail "outside the sandbox the server does not answer ($out): the check would prove nothing"; }
  local net='echo "tcp=$(curl -s -m 5 --noproxy "*" "http://127.0.0.1:$1/" 2>/dev/null | head -c 60)"; echo "unix=$(curl -s -m 5 --noproxy "*" --unix-socket "$2" http://localhost/ 2>/dev/null | head -c 60)"'
  a=$(in_login kingo-claude-base "$dir" "$tpl" sh -c "$net" sh "$port" "$dir/probe.sock" | grep -E '^(tcp|unix)=' | tr '\n' ' ')
  b=$(in_login kingo-claude-login "$dir" "$tpl" sh -c "$net" sh "$port" "$dir/probe.sock" | grep -E '^(tcp|unix)=' | tr '\n' ' ')
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
  echo "         | a server on this machine, asked without the proxy, from the OpenRouter way: $a"
  echo "         | a server on this machine, asked without the proxy, from the login:          $b"
  if has "$b" "unix=$word"; then fail "under the lock, the sandbox of the login reaches a Unix socket"; fi
  if has "$b" "tcp=$word" && ! has "$a" "tcp=$word"; then fail "the sandbox of the login reaches a port of this machine that the OpenRouter way does not reach"; fi
  ok "the login's sandbox reaches no more of this machine than the OpenRouter way"

  # A new session of Claude Code asks an address on platform.claude.com at its start. That is the host of the token
  # address: nono reads all traffic to it and lets through only what has a route. Without a route, nono answers
  # 502 and Claude Code ends with "Unable to connect to Anthropic services" (Frank's Mac, 14 Nov 2026).
  say "through nono's proxy, the login's sandbox reaches the other addresses on Anthropic's login host"
  local hello='for u in https://platform.claude.com/v1/oauth/hello https://api.anthropic.com/api/hello; do c=000; for i in 1 2 3; do c=$(curl -s -o /dev/null -m 30 --cacert "$NODE_EXTRA_CA_CERTS" -w "%{http_code}" "$u"); [ "$c" = 000 ] || break; sleep 3; done; echo "code=$c $u"; done'
  # the comparison: a copy of the profile of the login without platform.claude.com among the hosts with a route
  sed 's|"api_hosts": \["https://api.anthropic.com", "https://platform.claude.com"\]|"api_hosts": ["https://api.anthropic.com"]|' "$prof/kingo-claude-login.json" > "$prof/kingo-claude-login-ci.json"
  if grep -q '"https://platform.claude.com"\]' "$prof/kingo-claude-login-ci.json"; then fail "the copy of the profile still has the route for platform.claude.com"; fi
  out=$(in_login kingo-claude-login-ci "$dir" "$tpl" sh -c "$hello" | grep '^code=' || true)
  show "$out" 2
  has "$out" "code=502 https://platform.claude.com/" || fail "without the route, nono does not answer 502 for platform.claude.com: the check below would prove nothing"
  rm -f "$prof/kingo-claude-login-ci.json"
  out=$(in_login kingo-claude-login "$dir" "$tpl" sh -c "$hello" | grep '^code=' || true)
  show "$out" 2
  [ "$(printf '%s\n' "$out" | grep -c '^code=')" = 2 ] || fail "the probe for Anthropic's hosts did not run in the login's sandbox"
  if has "$out" "code=502 " || has "$out" "code=000 "; then fail "the login's sandbox does not reach Anthropic's login host or its API through nono's proxy"; fi
  ok "with the profile of the login both hosts answer; without the route for platform.claude.com nono answers 502"

  # The course folder's settings name the course's model. With --login, kingo puts settings-login.json on the
  # command line. Here Claude Code runs with them against the stand-in for the model, which notes what it is asked for.
  say "with the settings of the login, Claude Code asks for Anthropic's models, not for the course's"
  stand_in
  grep -q '"ANTHROPIC_MODEL": "z-ai/' "$KINGO_DIR/claude/.claude/settings.json" || fail "the course folder's settings do not name the course's model: the check would prove nothing"
  PROBE="echo the-command-ended"
  model_start "$log"
  out=$(in_sandbox "${LOCK[@]}" claude --add-dir "$KINGO_DIR" --settings "$tpl/settings-login.json" --dangerously-skip-permissions -p "Run the probe." < /dev/null)
  model_stop "$log"
  /usr/bin/python3 - "$log" <<'PYTHON' || { show "$out" 20; fail "with the settings of the login, Claude Code still asks for the course's model, or asked for nothing"; }
import json, sys
models = {json.loads(line).get("model") for line in open(sys.argv[1]) if json.loads(line).get("method") == "POST"}
print("         | models asked for: %s" % ", ".join(sorted(str(m) for m in models)))
sys.exit(0 if models and all(str(m).startswith("claude-") for m in models) else 1)
PYTHON
  ok "Claude Code asks for Anthropic's models"
}

case "${1:-}" in
  own)     part_own ;;
  login)   part_login ;;
  look)    part_look ;;
  fresh)   part_fresh ;;
  leave)   part_leave ;;
  lock)    part_lock ;;
  sandbox) part_sandbox ;;
  claude)  part_claude ;;
  session) part_session ;;
  *) echo "usage: claude-sandbox.sh lock|sandbox|claude|session|leave|look|own|login|fresh"; exit 2 ;;
esac
printf '\nAll checks of "%s" passed.\n' "$1"
