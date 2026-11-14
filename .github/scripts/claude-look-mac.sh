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
# pictures and a PDF inside nono with the course profile and waits for scripts; under a copy of the profile without
# the rule, look falls back to one program and says so.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KINGO_DIR=$(cd "$HERE/../.." && pwd)
CFG="$HOME/.kingo-claude"
DIR="$KINGO_DIR/claude"
PROFILE=kingo-claude
MODE=""                            # KINGO_BROWSER_MODE; kingo claude sets none
NONO_BIN=""

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
      "$NONO_BIN" run --profile "$PROFILE" --allow-cwd --read "$KINGO_DIR" -- "$@" ) 2>&1 || true
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

say "kingo gets its own nono"
if command -v nono >/dev/null 2>&1; then echo "         | on the PATH of this job: $(command -v nono)"; fi
out=$(cd "$KINGO_DIR" && ./kingo claude nono 2>&1) || { show "$out" 8; fail "kingo claude nono failed"; }
show "$out" 3
NONO_BIN=$(ls "$HOME"/.local/share/kingo/nono/*/nono 2>/dev/null | head -n 1)
[ -x "$NONO_BIN" ] || fail "kingo's nono is not in ~/.local/share/kingo/nono"
grep -q "^CLAUDE_NONO_VERSION=$("$NONO_BIN" --version | sed -n 's/^nono \([0-9.]*\).*/\1/p')\$" "$KINGO_DIR/kingo" \
  || fail "the nono that kingo downloaded says another version than kingo names: $("$NONO_BIN" --version)"
"$NONO_BIN" profile validate "$HOME/.config/nono/profiles/kingo-claude.json" > "$CFG/tmp/validate.log" 2>&1 \
  || { show "$(cat "$CFG/tmp/validate.log")" 6; fail "nono does not take the course profile"; }
grep -q 'allow mach-register (global-name-prefix .*org.chromium.Chromium.MachPortRendezvousServer\.' "$HOME/.config/nono/profiles/kingo-claude-base.json" \
  || fail "the base profile, which the course profile extends, has no rule for Chrome's Mach service"
ok "nono is the one kingo downloaded ($("$NONO_BIN" --version | head -n 1)), and it takes the course profile"

say "kingo gets the browser"
out=$(cd "$KINGO_DIR" && ./kingo claude browser 2>&1) || { show "$out" 8; fail "kingo claude browser failed"; }
show "$out" 3
BROWSER_BIN=$(find "$HOME/.local/share/kingo/browsers" -type f -name chrome-headless-shell 2>/dev/null | head -n 1)
[ -x "$BROWSER_BIN" ] || fail "the browser is not in ~/.local/share/kingo/browsers"
[ ! -e "$CFG/browsers" ] || fail "there is a browser in $CFG, a folder the sandbox can write"
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

# kingo starts nono and the browser outside the sandbox. A program inside must not be able to swap them.
say "the sandbox cannot change what kingo downloaded"
out=$(in_sandbox sh -c 'for f in "$@"; do if ( : >> "$f" ) 2>/dev/null; then echo "WROTE $f"; else echo "refused $f"; fi; done' sh \
  "$DIR/look-write-probe" "$BROWSER_BIN" "$(dirname "$BROWSER_BIN")/new-file" "$NONO_BIN" "$(dirname "$NONO_BIN")/new-file" \
  "$HOME/.local/share/kingo/new-file")
show "$(printf '%s\n' "$out" | grep -E '^(WROTE|refused) ')" 6
has "$out" "WROTE $DIR/look-write-probe" || { show "$out" 20; fail "the probe proves nothing: it could not write in the course folder either"; }
[ "$(printf '%s\n' "$out" | grep -c '^refused ')" = 5 ] || fail "a program in the sandbox can write where kingo keeps nono or the browser"
rm -f "$DIR/look-write-probe"
ok "inside the sandbox, the browser, nono and their folders cannot be written"

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
# the rule is in the base profile, and nothing else is in its list: a copy of the base profile with an empty list
COPY="$CFG/tmp/kingo-claude-base-without-mach-rule.json"
python3 - "$HOME/.config/nono/profiles/kingo-claude-base.json" "$COPY" <<'PYTHON'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
new, n = re.subn(r'\n\s*"\(allow mach-register [^\n]*"\n', "\n", text)
assert n == 1, n
open(sys.argv[2], "w", encoding="utf-8").write(new)
PYTHON
if grep -q 'allow mach-register' "$COPY"; then fail "the copy of the profile still has the rule"; fi
"$NONO_BIN" profile validate "$COPY" > "$CFG/tmp/validate.log" 2>&1 || { show "$(cat "$CFG/tmp/validate.log")" 6; fail "nono does not take the copy of the profile"; }
PROFILE="$COPY"
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
for d in / "$HOME" "$HOME/Documents" "$HOME/Library" "$KINGO_DIR" "$(dirname "$KINGO_DIR")"; do
  if out=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$d" 2>&1); then show "$out" 3; fail "kingo claude --in took the folder $d"; fi
done
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in "$OWN") || fail "kingo claude --in did not get as far as the start of Claude Code"
has "$dry" "nono run --profile kingo-claude-base --allow-cwd --read $KINGO_DIR/setup/claude -- claude --settings $KINGO_DIR/setup/claude/settings-in.json --permission-mode default --append-system-prompt You were started with" \
  || { show "$dry" 3; fail "kingo claude --in would not start Claude Code with the base profile and its own settings"; }
[ -z "$(ls -A "$OWN")" ] || fail "kingo put a file into the folder"
out=$( ( cd "$OWN" && CLAUDE_CONFIG_DIR="$CFG" CLAUDE_CODE_TMPDIR="$CFG/tmp" TMPDIR="$CFG/tmp" NONO_NO_SAVE_PROMPT=1 GIT_CONFIG_NOSYSTEM=1 \
    PATH="$KINGO_DIR/setup/claude/bin:$PATH" KINGO_BROWSER="$BROWSER_BIN" \
    "$NONO_BIN" run --profile kingo-claude-base --allow-cwd --read "$KINGO_DIR/setup/claude" -- \
    sh -c 'echo "n8n=${N8N_BASE_URL:-none} model=${ANTHROPIC_BASE_URL:+set}"; : >> here.txt && echo WROTE-HERE; cat "$1/VERSION" 2>&1; ( : >> "$1/setup/claude/x" ) 2>/dev/null && echo WROTE-KINGO; cp "$1/setup/claude/README.md" page.md && look "$2" | head -n 1; git init -q . && git add -A && git -c user.name=ci -c user.email=ci@example.com commit -q -m one && echo "commits=$(git log --oneline | wc -l | tr -d " ")"' \
    sh "$KINGO_DIR" "$DIR/look-cv.html" ) 2>&1 || true )
has "$out" "n8n=none model=set" || { show "$out" 20; fail "the base profile has something of the course in it, or lost the way to the model"; }
has "$out" WROTE-HERE || { show "$out" 20; fail "the sandbox could not write in the folder"; }
if has "$out" "$(cat "$KINGO_DIR/VERSION")"; then fail "the rest of kingo-pod can be read from a folder of one's own"; fi
if has "$out" WROTE-KINGO; then fail "setup/claude can be written from a folder of one's own"; fi
has "$out" "commits=1" || { show "$out" 20; fail "git does not work in the folder inside the sandbox"; }
ok "in a folder of one's own: it writes there, reads setup/claude and not the rest of kingo-pod, nothing of the course, git works"

out=$(in_sandbox sh -c 'if ( : >> "$1" ) 2>/dev/null; then echo WROTE; else echo refused; fi' sh "$KINGO_DIR/shared/own-probe.txt")
has "$out" refused || { show "$out" 12; fail "with the course profile alone, the sandbox can already write in shared"; }
cp "$KINGO_DIR/setup/claude/my-nono-profile.example.json" "$MINE"
dry=$(cd "$KINGO_DIR" && KINGO_CLAUDE_DRY_RUN=1 ./kingo claude) || fail "kingo claude did not start with the example of my-nono-profile.json"
has "$dry" "nono run --profile kingo-claude-mine --allow-cwd --read $KINGO_DIR -- " || { show "$dry" 3; fail "kingo does not start nono with the student's profile"; }
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

PROFILE=kingo-claude
out=$(in_sandbox look look-cv.html)
has "$out" "in 1 picture(s)" || { show "$out" 30; fail "the last picture, for the upload, did not come"; }

printf '\nAll checks of look on a Mac passed.\n'
