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
  has "$dry" "-- /usr/bin/python3 -I $KINGO_DIR/setup/claude/no_unix_sockets.py claude --add-dir $KINGO_DIR --permission-mode default" \
    || fail "under Linux, kingo claude would start Claude Code without the lock"
  ok "kingo claude starts Claude Code through the lock, and has written the nono profile"
  # The variables that kingo sets for nono and Claude Code: the dry run names them, from the list that the start
  # exports. kingo_env below sets the same ones. (On 14 Nov 2026 five of them no longer reached Claude Code, and
  # no check saw it: the checks here looked at lines of kingo, not at what a start gets.)
  local v vars
  vars=" $(printf '%s\n' "$dry" | sed -n 's/^  variables: //p')"
  for v in CLAUDE_CODE_DISABLE_ARTIFACT CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC DISABLE_TELEMETRY DISABLE_ERROR_REPORTING \
           CLAUDE_CODE_MAX_CONTEXT_TOKENS CLAUDE_CONFIG_DIR CLAUDE_CODE_TMPDIR TMPDIR PATH KINGO_BROWSER \
           GIT_CONFIG_NOSYSTEM NONO_NO_SAVE_PROMPT PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE; do
    has "$vars" " $v " || fail "kingo claude does not set the variable $v for the start"
  done
  grep -q '^  export "\${envs\[@\]}"$' "$KINGO_DIR/kingo" \
    || fail "kingo claude does not hand the variables that the dry run names to nono"
  ok "kingo claude sets its variables for the start: NONO_NO_SAVE_PROMPT, GIT_CONFIG_NOSYSTEM, those against telemetry, the PATH for look, PostgreSQL"
  # nono: the one that kingo downloaded (./kingo claude nono, in the workflow), and no other
  grep -q '^  exec "\$nono" run --profile "\$profile" --allow-cwd --read "\$reads" -- "\$@"$' "$KINGO_DIR/kingo" \
    || fail "kingo claude does not start its own nono with the line this script copies"
  has "$dry" "  nono run --profile kingo-claude --allow-cwd --read $KINGO_DIR -- " \
    || fail "for the course, kingo claude would not start nono with the course profile and read access to kingo-pod"
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
    NONO_NO_SAVE_PROMPT=1 GIT_CONFIG_NOSYSTEM=1 \
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

# ── a folder of one's own, one's own profile, and git ────────────────────────
# kingo claude --in <folder> starts Claude Code with the base profile in a folder that is not the course folder.
# my-nono-profile.json adds to the course profile. And git must work in both places: it is how a student keeps
# versions of what Claude Code writes.
part_own() {
  local out dry d dir="$HOME/projects/thesis" log="$CFG/tmp/model-own.jsonl" mine="$KINGO_DIR/my-nono-profile.json"
  local base=(nono run --profile kingo-claude-base --allow-cwd --read "$KINGO_DIR/setup/claude" --)
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
  for d in / "$HOME" "$HOME/Documents" "$HOME/.config" /mnt/c/Users/someone "$KINGO_DIR" "$KINGO_DIR/shared" "$(dirname "$KINGO_DIR")" "$HOME/no-such-folder"; do
    if out=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$d" 2>&1); then show "$out" 3; fail "kingo claude --in took the folder $d"; fi
    printf '         | %s\n' "$(printf '%s\n' "$out" | tail -n 1 | cut -c1-140)"
  done
  ok "it refuses /, the home folder, Documents, a hidden folder, a Windows folder, kingo-pod, a folder that holds kingo-pod, a folder that is not there"

  say "kingo claude --in: what it would start"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$dir") || fail "kingo claude --in did not get as far as the start of Claude Code"
  show "$dry" 2
  has "$dry" "nono run --profile kingo-claude-base --allow-cwd --read $KINGO_DIR/setup/claude -- /usr/bin/python3 -I $KINGO_DIR/setup/claude/no_unix_sockets.py claude --settings $KINGO_DIR/setup/claude/settings-in.json --permission-mode default --append-system-prompt You were started with" \
    || fail "kingo claude --in would not start Claude Code with the base profile, under the lock, with its own settings"
  [ -z "$(ls -A "$dir")" ] || fail "kingo put a file into the folder: $(ls -A "$dir")"
  ok "the base profile, the lock, settings from kingo-pod, and no file in the folder"

  say "my-nono-profile.json: the student's own additions to the sandbox of the course"
  out=$(in_sandbox "${LOCK[@]}" sh -c 'if ( : >> "$1" ) 2>/dev/null; then echo WROTE; else echo refused; fi' sh "$KINGO_DIR/shared/own-probe.txt")
  has "$out" refused || { show "$out" 12; fail "with the course profile alone, the sandbox can already write in shared: the check below would prove nothing"; }
  sed 's/"extends": "kingo-claude",/"extends": "default",/' "$KINGO_DIR/setup/claude/my-nono-profile.example.json" > "$mine"
  if out=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude 2>&1); then show "$out" 3; fail "kingo took a profile that does not extend the course profile"; fi
  ok "a profile that does not extend the course profile: kingo does not start"
  cp "$KINGO_DIR/setup/claude/my-nono-profile.example.json" "$mine"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude) || fail "kingo claude did not start with the example of my-nono-profile.json"
  has "$dry" "nono run --profile kingo-claude-mine --allow-cwd --read $KINGO_DIR -- " || { show "$dry" 3; fail "kingo does not start nono with the student's profile"; }
  nono profile validate "$HOME/.config/nono/profiles/kingo-claude-mine.json" > "$CFG/tmp/validate.log" 2>&1 \
    || { show "$(cat "$CFG/tmp/validate.log")" 8; fail "nono does not take the example of my-nono-profile.json"; }
  out=$(kingo_env timeout 180 nono run --profile kingo-claude-mine --allow-cwd --read "$KINGO_DIR" -- "${LOCK[@]}" \
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
  out=$(in_sandbox "${LOCK[@]}" sh -c 'echo "pg=$PGHOST/$PGDATABASE n8n=${N8N_BASE_URL:+set} langflow=${LANGFLOW_BASE_URL:+set} model=${ANTHROPIC_BASE_URL:+set}"')
  has "$out" "pg=127.0.0.1/classroom n8n=set langflow=set model=set" || { show "$out" 12; fail "the course profile lost a route or the variables for PostgreSQL"; }
  ok "course: PostgreSQL, n8n, Langflow and the model are there"

  say "in a folder of one's own, with the base profile"
  out=$(in_folder "${LOCK[@]}" sh -c 'echo "pg=$PGHOST n8n=${N8N_BASE_URL:-none} model=${ANTHROPIC_BASE_URL:+set}"; : >> here.txt && echo WROTE-HERE; head -n 1 "$1/setup/claude/README.md"; cat "$1/VERSION" 2>&1; cat "$2" 2>&1; ( : >> "$1/setup/claude/x" ) 2>/dev/null && echo WROTE-KINGO' sh "$KINGO_DIR" "$OUTSIDE/secret.txt")
  has "$out" "pg= n8n=none model=set" || { show "$out" 12; fail "the base profile has something of the course in it, or lost the way to the model"; }
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
  out=$(kingo_env timeout 180 nono run --profile kingo-claude-mine --allow-cwd --read "$KINGO_DIR" -- "${LOCK[@]}" \
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
        timeout 180 nono run --profile "$profile" --allow-cwd --read "$reads" -- "${LOCK[@]}" "$@" ) 2>&1 || true
  }

  say "what kingo claude would start"
  prepare
  rm -rf "$dir" "$mine"; mkdir -p "$dir" "$lcfg/tmp" "$lcfg.lock" "$store"

  say "kingo claude --login: what it would start"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --login) || fail "kingo claude --login did not get as far as the start of Claude Code"
  show "$dry" 3
  has "$dry" "nono run --profile kingo-claude-login-course --allow-cwd --read $KINGO_DIR -- /usr/bin/python3 -I $tpl/no_unix_sockets.py claude --add-dir $KINGO_DIR --settings $tpl/settings-login.json --permission-mode default" \
    || fail "kingo claude --login would not start Claude Code with the course profile of the login, under the lock, with the settings of the login"
  vars=" $(printf '%s\n' "$dry" | sed -n 's/^  variables: //p')"
  has "$vars" " PGHOST " || fail "kingo claude --login does not set the variables for PostgreSQL"
  if has "$vars" " CLAUDE_CODE_MAX_CONTEXT_TOKENS "; then fail "kingo claude --login tells Claude Code the context size of the course's model"; fi
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --login --in "$dir") || fail "kingo claude --login --in did not get as far as the start of Claude Code"
  has "$dry" "nono run --profile kingo-claude-login --allow-cwd --read $tpl -- /usr/bin/python3 -I $tpl/no_unix_sockets.py claude --settings $tpl/settings-in-login.json --permission-mode default --append-system-prompt You were started with" \
    || { show "$dry" 3; fail "kingo claude --login --in would not start Claude Code with the profile of the login and its own settings"; }
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo yolo --in "$dir" --login) || fail "kingo yolo --in --login did not get as far as the start of Claude Code"
  has "$dry" "nono run --profile kingo-claude-login --allow-cwd --read $tpl -- " || { show "$dry" 3; fail "kingo does not find --login after --in"; }
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude logout) || fail "kingo claude logout did not get as far as the logout"
  has "$dry" "nono run --profile kingo-claude-login --allow-cwd -- claude auth logout" || { show "$dry" 3; fail "kingo claude logout would not log out inside the sandbox of the login"; }
  ok "the course with the login, a folder of one's own with the login, and the logout"

  say "kingo claude --login with the student's own profile"
  cp "$tpl/my-nono-profile.example.json" "$mine"
  dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --login) || fail "kingo claude --login did not start with the example of my-nono-profile.json"
  has "$dry" "nono run --profile kingo-claude-mine --allow-cwd --read $KINGO_DIR -- " || { show "$dry" 3; fail "with --login, kingo does not start nono with the student's profile"; }
  grep -q '^  "extends": "kingo-claude-login-course",$' "$prof/kingo-claude-mine.json" \
    || fail "with --login, the student's profile does not extend the course profile of the login"
  nono profile validate "$prof/kingo-claude-mine.json" > "$CFG/tmp/validate.log" 2>&1 \
    || { show "$(cat "$CFG/tmp/validate.log")" 8; fail "nono does not take the student's profile on top of the login"; }
  out=$(in_login kingo-claude-mine "$KINGO_DIR/claude" "$KINGO_DIR" sh -c 'echo "base=${ANTHROPIC_BASE_URL:-none} n8n=${N8N_BASE_URL:+set}"; if ( : >> "$1" ) 2>/dev/null; then echo WROTE; else echo refused; fi' sh "$KINGO_DIR/shared/own-probe.txt")
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

  out=$(step phantom claude --login --in "$fh/projects/thesis")
  show "$(printf '%s\n' "$out" | grep -v '^STUB  ')" 6
  has "$out" "STUB nono run --profile kingo-claude-login --allow-cwd -- /usr/bin/python3 -I $tpl/no_unix_sockets.py claude auth login --claudeai" \
    || { show "$out" 30; fail "without a login, kingo does not run the login inside the sandbox, under the lock"; }
  has "$out" "Logged in." || { show "$out" 30; fail "kingo does not take a login that nono kept outside the sandbox"; }
  sess=$(session_of "$out")
  has "$sess" "STUB nono run --profile kingo-claude-login --allow-cwd --read $tpl -- /usr/bin/python3 -I $tpl/no_unix_sockets.py claude --settings $tpl/settings-in-login.json" \
    || { show "$out" 30; fail "after the login, kingo does not start the session"; }
  for p in "CLAUDE_CODE_DISABLE_ARTIFACT=1" "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1" "DISABLE_TELEMETRY=1" "DISABLE_ERROR_REPORTING=1" \
           "CLAUDE_CODE_MAX_CONTEXT_TOKENS=unset" "CLAUDE_CONFIG_DIR=$fh/.kingo-claude-login" "TMPDIR=$fh/.kingo-claude-login/tmp" \
           "GIT_CONFIG_NOSYSTEM=1" "NONO_NO_SAVE_PROMPT=1" "PATH starts with $tpl/bin"; do
    has "$sess" "STUB   $p" || { show "$sess" 16; fail "the start of the session does not get: $p"; }
  done
  ok "no login: kingo runs the login in the sandbox, takes nono's stand-ins, and starts the session with its variables"

  out=$(step none claude --login --in "$fh/projects/thesis")
  if has "$out" "auth login"; then show "$out" 30; fail "kingo asks for the login again although one is there"; fi
  has "$(session_of "$out")" "STUB nono run --profile kingo-claude-login " || { show "$out" 30; fail "with a login, kingo does not start the session"; }
  ok "a login is there: kingo starts the session and does not ask again"

  out=$(step none claude logout)
  has "$out" "STUB nono run --profile kingo-claude-login --allow-cwd -- /usr/bin/python3 -I $tpl/no_unix_sockets.py claude auth logout" || { show "$out" 30; fail "kingo claude logout does not log out inside the sandbox"; }
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
  say "the sandbox of the login: no way to OpenRouter, the course only with the course, nono's store stays outside"
  printf 'store-%s\n' "$SECRET" > "$store/ci-probe.txt"
  printf 'login-folder-%s\n' "$SECRET" > "$lcfg/marker.txt"
  local probe='echo "base=${ANTHROPIC_BASE_URL:-none} token=${ANTHROPIC_AUTH_TOKEN:-none} proxy=${HTTPS_PROXY:+set} ca=${NODE_EXTRA_CA_CERTS:+set} n8n=${N8N_BASE_URL:+set} langflow=${LANGFLOW_BASE_URL:+set} pg=${PGHOST:-none}"; cat "$1" 2>&1; ls "$(dirname "$1")" 2>&1; for f in "$2/probe" "$3/probe" ./probe-here; do if ( : >> "$f" ) 2>/dev/null; then echo "WROTE $f"; else echo "refused $f"; fi; done'
  out=$(in_login kingo-claude-login "$dir" "$tpl" sh -c "$probe" sh "$store/ci-probe.txt" "$CFG" "$lcfg")
  show "$(printf '%s\n' "$out" | grep -E '^(base=|WROTE|refused)')" 5
  has "$out" "base=none token=none proxy=set ca=set n8n= langflow= pg=none" || { show "$out" 20; fail "the profile of the login: a way to OpenRouter or something of the course is there, or nono's proxy and certificate are not"; }
  if has "$out" "store-$SECRET" || has "$out" "ci-probe.txt"; then fail "the sandbox of the login can read nono's store of the real tokens"; fi
  has "$out" "refused $CFG/probe" || fail "the sandbox of the login can write in the config folder of the OpenRouter way"
  has "$out" "WROTE $lcfg/probe" || fail "the sandbox of the login cannot write in its own config folder"
  has "$out" "WROTE ./probe-here" || fail "the sandbox of the login cannot write in the folder it starts in"
  out=$(in_login kingo-claude-login-course "$KINGO_DIR/claude" "$KINGO_DIR" sh -c "$probe" sh "$store/ci-probe.txt" "$CFG" "$lcfg")
  show "$(printf '%s\n' "$out" | grep -E '^(base=|WROTE|refused)')" 5
  has "$out" "base=none token=none proxy=set ca=set n8n=set langflow=set pg=127.0.0.1" || { show "$out" 20; fail "the course profile of the login: a way to OpenRouter is there, or n8n, Langflow or PostgreSQL are not"; }
  if has "$out" "store-$SECRET" || has "$out" "ci-probe.txt"; then fail "the sandbox of the login, with the course, can read nono's store of the real tokens"; fi
  rm -f "$KINGO_DIR/claude/probe-here"
  out=$(in_sandbox "${LOCK[@]}" sh -c 'cat "$1" 2>&1; cat "$2" 2>&1' sh "$lcfg/marker.txt" "$store/ci-probe.txt")
  if has "$out" "$SECRET"; then fail "the sandbox of the OpenRouter way can read the config folder of the login, or nono's store"; fi
  ok "login: no OpenRouter, nono's proxy and certificate, its own config folder; the course's routes only with the course; the store is closed"

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
