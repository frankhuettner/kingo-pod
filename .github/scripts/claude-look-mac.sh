#!/usr/bin/env bash
# CI for look on a Mac: does Claude see the pages it writes inside the sandbox of `kingo claude`?
#
#   claude-look-mac.sh
#
# On a Mac, nono's sandbox keeps two things from Chrome (found on 14 Nov 2026):
#   - the sleep and wake notices of the system (IOKit, RootDomainUserClient). Chrome 159 goes on without them;
#     older builds crash.
#   - registering a Mach service, which Chrome does for its helper programs. So kingo claude sets
#     KINGO_BROWSER_MODE=single there, and look starts Chrome as one program (--single-process).
# The checks: kingo gets the browser, and look makes pictures and a PDF inside nono with the course profile.
# Two trials after that report and fail nothing (lines that start with RESULT): Chrome with its helper programs
# under the course profile, and the same under a copy of the profile that has one rule more, for the Mach service.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KINGO_DIR=$(cd "$HERE/../.." && pwd)
CFG="$HOME/.kingo-claude"
DIR="$KINGO_DIR/claude"
PROFILE=kingo-claude
MODE=single

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
      nono run --profile "$PROFILE" --allow-cwd --read "$KINGO_DIR" -- "$@" ) 2>&1 || true
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
if has "$dry" no_unix_sockets.py; then fail "on a Mac, kingo claude would start Claude Code through the lock for Linux"; fi
ok "kingo claude tells Claude Code how to look at a page"

say "kingo gets the browser"
out=$(cd "$KINGO_DIR" && ./kingo claude browser 2>&1) || { show "$out" 8; fail "kingo claude browser failed"; }
show "$out" 3
BROWSER_BIN=$(find "$CFG/browsers" -type f -name chrome-headless-shell 2>/dev/null | head -n 1)
[ -x "$BROWSER_BIN" ] || fail "the browser is not in $CFG/browsers"
ok "the browser is there: $BROWSER_BIN"

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

say "look inside nono with the course profile, as kingo claude sets it up (one program)"
out=$(in_sandbox look look-cv.html)
has "$out" "in 1 picture(s)" || { show "$out" 30; fail "look made no picture of a short page"; }
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
n=$(printf '%s\n' "$out" | sed -n 's/.* in \([0-9]*\) picture(s).*/\1/p')
has "$out" "What a script adds later is not on them" || { show "$out" 30; fail "look does not say that it could not wait for scripts"; }
echo "   RESULT  one program, course profile: the page that grows later comes out in ${n:-no} picture(s) (3 would mean it waited)"

# ── the two trials ───────────────────────────────────────────────────────────
say "trial: Chrome with its helper programs under the course profile"
MODE=""
rm -rf "$DIR/look"
out=$(in_sandbox look look-late.html)
n=$(printf '%s\n' "$out" | sed -n 's/.* in \([0-9]*\) picture(s).*/\1/p')
echo "   RESULT  helper programs, course profile: ${n:-no} picture(s)"
show "$(printf '%s\n' "$out" | grep -E 'FATAL|mach-register|look:' | head -n 4)" 4

say "trial: the same under a copy of the profile with one rule more"
RULE='"(allow mach-register (global-name-prefix \"org.chromium.Chromium.MachPortRendezvousServer.\"))"'
COPY="$CFG/tmp/kingo-claude-with-mach-rule.json"
RULE="$RULE" awk '{ print } /"unsafe_macos_seatbelt_rules": \[/ { print "    " ENVIRON["RULE"] "," }' \
  "$HOME/.config/nono/profiles/kingo-claude.json" > "$COPY"
if nono profile validate "$COPY" > "$CFG/tmp/validate.log" 2>&1 && grep -q MachPortRendezvousServer "$COPY"; then
  PROFILE="$COPY"
  rm -rf "$DIR/look"
  out=$(in_sandbox look look-late.html)
  n=$(printf '%s\n' "$out" | sed -n 's/.* in \([0-9]*\) picture(s).*/\1/p')
  echo "   RESULT  helper programs, profile with the Mach rule: ${n:-no} picture(s) (3 means it waited for the script)"
  show "$(printf '%s\n' "$out" | grep -E 'FATAL|mach-register|look:|pixels' | head -n 4)" 4
  if [ "${n:-0}" -ge 1 ]; then python3 "$HERE/png_check.py" "$DIR"/look/look-late-*.png | sed 's/^/         | /' || true; fi
  out=$(in_sandbox look look-cv.html)
  echo "   RESULT  helper programs, profile with the Mach rule, short page: $(printf '%s\n' "$out" | sed -n 's/.* in \([0-9]*\) picture(s).*/\1/p' | head -n 1) picture(s)"
else
  echo "   RESULT  nono does not take the copy of the profile"; show "$(cat "$CFG/tmp/validate.log")" 4
fi

printf '\nAll checks of look on a Mac passed.\n'
