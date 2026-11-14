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
#   claude-sandbox.sh look      look page.html inside nono under the lock: kingo gets the browser, pictures come out
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
  has "$dry" "-- /usr/bin/python3 -I $KINGO_DIR/setup/claude/no_unix_sockets.py claude --add-dir $KINGO_DIR --permission-mode default" \
    || fail "under Linux, kingo claude would start Claude Code without the lock"
  ok "kingo claude starts Claude Code through the lock, and has written the nono profile"
  grep -q '^  NONO_NO_SAVE_PROMPT=1 \\$' "$KINGO_DIR/kingo" \
    || fail "kingo claude does not start nono with NONO_NO_SAVE_PROMPT=1: nono would ask to change the profile when a session ends"
  ok "kingo claude starts nono with NONO_NO_SAVE_PROMPT=1"
  grep -q '^  PATH="\$tpl/bin:\$PATH" KINGO_BROWSER="\$(claude_browser_path)" \\$' "$KINGO_DIR/kingo" \
    || fail "kingo claude does not put look on the PATH or does not say where the browser is"
  # nono: the one that kingo downloaded (./kingo claude nono, in the workflow), and no other
  grep -q '^    exec "\$nono" run --profile kingo-claude --allow-cwd --read "\$KINGO_DIR" -- "\$@"$' "$KINGO_DIR/kingo" \
    || fail "kingo claude does not start its own nono with the line this script copies"
  NONO_BIN=$(ls "$HOME"/.local/share/kingo/nono/*/nono 2>/dev/null | head -n 1)
  [ -x "$NONO_BIN" ] || fail "kingo's nono is not in ~/.local/share/kingo/nono (the workflow runs ./kingo claude nono first)"
  [ "$(command -v nono)" = "$NONO_BIN" ] || fail "this script would run $(command -v nono), not the nono that kingo downloaded ($NONO_BIN)"
  grep -q "^CLAUDE_NONO_VERSION=$("$NONO_BIN" --version | sed -n 's/^nono \([0-9.]*\).*/\1/p')\$" "$KINGO_DIR/kingo" \
    || fail "the nono that kingo downloaded says another version than kingo names: $("$NONO_BIN" --version)"
  ok "nono is the one kingo downloaded: $("$NONO_BIN" --version | head -n 1)"
  has "$dry" "--append-system-prompt When you have written or changed an HTML page, look at it" \
    || fail "kingo claude does not tell Claude Code how to look at a page"
  ok "kingo claude puts look on the PATH, says where the browser is, and tells Claude Code how to look at a page"
}

# kingo_env command ...: run it in the course folder with the variables that kingo claude sets for Claude Code
kingo_env() {
  ( cd "$KINGO_DIR/claude" &&
    CLAUDE_CODE_DISABLE_ARTIFACT=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1 \
    CLAUDE_CODE_MAX_CONTEXT_TOKENS=200000 \
    CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_TMPDIR="$CFG/tmp" TMPDIR="$CFG/tmp" \
    PGHOST=127.0.0.1 PGPORT=5432 PGUSER=student PGPASSWORD=placeholder PGDATABASE=classroom \
    NONO_NO_SAVE_PROMPT=1 \
    PATH="$KINGO_DIR/setup/claude/bin:$PATH" KINGO_BROWSER="$BROWSER_BIN" \
      "$@" )
}
SANDBOX=(nono run --profile kingo-claude --allow-cwd --read "$KINGO_DIR" --)   # the line of kingo claude
BROWSER_BIN=""                      # where kingo put the browser; part_look fills it in
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

part_sandbox() {
  local out leak="$KINGO_DIR/claude/leak.txt" psock pid i

  say "what kingo claude would start"
  prepare

  say "the sandbox runs a program, lets it read kingo-pod and keeps other files away"
  out=$(in_sandbox sh -c 'echo inside-$((6*7))')
  has "$out" inside-42 || { show "$out" 30; fail "nono did not run a program with the course profile"; }
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
}

# ── Claude Code itself ───────────────────────────────────────────────────────
# The real Claude Code, started as kingo claude starts it: inside nono, with the course profile and the course
# settings. Only the model is a stand-in: fake_model.py takes OpenRouter's place in the profile, asks Claude Code to
# run one command with its Bash tool, and notes what comes back. The command is the way out through Docker.
MODEL_PORT=18765
MODEL_PID=""

stand_in() {  # prepare, and put the stand-in where OpenRouter is in the nono profile
  local profile="$HOME/.config/nono/profiles/kingo-claude.json"
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
  BROWSER_BIN=$(find "$HOME/.local/share/kingo/browsers" -type f -name chrome-headless-shell 2>/dev/null | head -n 1)
  [ -x "$BROWSER_BIN" ] || fail "the browser is not where kingo says it is: $BROWSER_BIN"
  [ ! -e "$CFG/browsers" ] || fail "there is a browser in $CFG, a folder the sandbox can write"
  ok "the browser is there: $BROWSER_BIN"
  out=$(cd "$KINGO_DIR" && ./kingo claude browser 2>&1) || fail "a second kingo claude browser failed"
  if has "$out" "Getting a browser"; then fail "a second kingo claude browser downloaded it again"; fi
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
    "$HOME/.local/share/kingo/new-file")
  show "$(printf '%s\n' "$out" | grep -E '^(WROTE|refused) ')" 6
  has "$out" "WROTE $dir/look-write-probe" || fail "the probe proves nothing: it could not write in the course folder either"
  [ "$(printf '%s\n' "$out" | grep -c '^refused ')" = 5 ] || fail "a program in the sandbox can write where kingo keeps nono or the browser"
  rm -f "$dir/look-write-probe"
  ok "inside the sandbox, the browser, nono and their folders cannot be written"

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
    if out=$(./kingo claude browser 2>&1); then echo "$out"; echo "FRESH: nothing was missing, which a fresh Ubuntu cannot be"; exit 1; fi
    echo "$out" | tail -n 4
    line=$(printf "%s\n" "$out" | sed -n "s/^ *sudo \(apt-get install -y .*\)$/\1/p")
    [ -n "$line" ] || { echo "FRESH: kingo named no packages"; exit 1; }
    $line >/dev/null
    ./kingo claude browser
    mkdir /w && cd /w
    printf "<!doctype html><meta charset=utf-8><h1 style=\"color:#1a4d8f\">Curriculum Vitae 이력서</h1><p>Hello</p>" > page.html
    bash /k/setup/claude/bin/look page.html
    python3 /k/.github/scripts/png_check.py look/page-1.png
  ' || fail "on a fresh $image the browser does not run with the packages that kingo names"
  ok "kingo named the missing packages, they installed, and the browser made a picture"
}

case "${1:-}" in
  look)    part_look ;;
  fresh)   part_fresh ;;
  leave)   part_leave ;;
  lock)    part_lock ;;
  sandbox) part_sandbox ;;
  claude)  part_claude ;;
  session) part_session ;;
  *) echo "usage: claude-sandbox.sh lock|sandbox|claude|session|leave|look|fresh"; exit 2 ;;
esac
printf '\nAll checks of "%s" passed.\n' "$1"
