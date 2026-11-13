#!/usr/bin/env bash
# CI for `kingo claude` under Linux, and so under Windows (WSL2).
#
# nono keeps a program in the sandbox away from files, but under Linux not away from Unix sockets. Docker, Podman's
# API socket and the systemd user manager listen on such sockets, outside the sandbox. So `kingo claude` starts
# Claude Code through setup/claude/no_unix_sockets.py, called "the lock" below.
#
#   claude-sandbox.sh lock      the lock by itself
#   claude-sandbox.sh sandbox   inside nono with the course profile: Docker, Podman, the systemd user manager
#   claude-sandbox.sh claude    Claude Code itself inside nono, with a stand-in for the model (fake_model.py)
#
# Each way out is tried twice. Without the lock it must work, or the check would prove nothing. With the lock it
# must not work.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KINGO_DIR=$(cd "$HERE/../.." && pwd)
LOCK=(/usr/bin/python3 "$KINGO_DIR/setup/claude/no_unix_sockets.py")
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
  has "$dry" "-- /usr/bin/python3 $KINGO_DIR/setup/claude/no_unix_sockets.py claude --add-dir $KINGO_DIR --permission-mode default" \
    || fail "under Linux, kingo claude would start Claude Code without the lock"
  ok "kingo claude starts Claude Code through the lock, and has written the nono profile"
}

# in_sandbox command ...: run it as kingo claude runs Claude Code; prints its output and nono's
in_sandbox() {
  ( cd "$KINGO_DIR/claude" &&
    CLAUDE_CODE_DISABLE_ARTIFACT=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1 \
    CLAUDE_CODE_MAX_CONTEXT_TOKENS=200000 \
    CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_TMPDIR="$CFG/tmp" TMPDIR="$CFG/tmp" \
    PGHOST=127.0.0.1 PGPORT=5432 PGUSER=student PGPASSWORD=placeholder PGDATABASE=classroom \
      timeout 180 nono run --profile kingo-claude --allow-cwd --read "$KINGO_DIR" -- "$@" 2>&1 ) || true
}

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
# One turn of the real Claude Code, started as kingo claude starts it: inside nono, with the course profile and the
# course settings. Only the model is a stand-in: fake_model.py takes OpenRouter's place in the profile, asks Claude
# Code to run one command with its Bash tool, and notes what comes back. The command is the way out through Docker.
part_claude() {
  local port=18765 profile="$HOME/.config/nono/profiles/kingo-claude.json" probe out log pid i

  say "what kingo claude would start"
  prepare
  sed -i "s|https://openrouter.ai/api|http://127.0.0.1:$port|" "$profile"
  grep -q "\"upstream\": \"http://127.0.0.1:$port\"" "$profile" || fail "the nono profile has no line for OpenRouter that the stand-in could take"
  ok "in the nono profile, the stand-in takes OpenRouter's place"
  docker pull -q alpine >/dev/null
  probe="docker run --rm --network none -v $OUTSIDE:/h:ro alpine cat /h/secret.txt; echo the-command-ended"

  # turn <log> command ...: one turn; the command and its arguments start Claude Code inside the sandbox
  turn() {
    log=$1; shift
    : > "$log"
    /usr/bin/python3 "$HERE/fake_model.py" "$port" "$log" "$probe" &
    pid=$!
    for i in $(seq 1 20); do curl -s -m 2 -o /dev/null "http://127.0.0.1:$port/ready" && break; sleep 0.5; done
    out=$(in_sandbox "$@" --add-dir "$KINGO_DIR" --dangerously-skip-permissions -p "Run the probe." < /dev/null)
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    /usr/bin/python3 - "$log" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    e = json.loads(line)
    if e.get("method") == "POST":
        print("         | request: %s; model %s; %s tools; key %r; results %r" % (
            e.get("kind"), e.get("model"), e.get("tools"), e.get("key"), [r[:90] for r in e.get("results", [])]))
PY
  }
  results() { /usr/bin/python3 -c 'import json, sys; print("\n".join(r for l in open(sys.argv[1]) for r in json.loads(l).get("results", [])))' "$1"; }

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
}

case "${1:-}" in
  lock)    part_lock ;;
  sandbox) part_sandbox ;;
  claude)  part_claude ;;
  *) echo "usage: claude-sandbox.sh lock|sandbox|claude"; exit 2 ;;
esac
printf '\nAll checks of "%s" passed.\n' "$1"
