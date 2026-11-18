#!/usr/bin/env bash
# CI for Claude Code started from the folder you are in, under Linux and on a Mac.
#
#   claude-shortcuts.sh in          kingo claude --in with a folder named from where you are (--in ., --in thesis);
#                                   --in in kingo-pod starts the course and says so in one line; --in ~ and a folder
#                                   that holds kingo-pod are refused
#   claude-shortcuts.sh shortcuts   ./kingo shortcuts with zsh and with bash: the choice (named, or typed in a
#                                   terminal), the block in the startup file, a second run, a name that is taken,
#                                   remove, refresh (a block of an older kingo), and in a new shell that reads the
#                                   file: kc alone (the course), kc . and kc <folder> (that folder), ky, kcl, kyl, kingo
#
# Every check has a home folder of its own (mktemp -d) and runs kingo claude as a dry run (KINGO_CLAUDE_DRY_RUN=1):
# nothing starts, and no file of the real home folder is touched. Needs Claude Code on the PATH (the dry run looks for
# it), python3 for a terminal (pty_answer.py), and /bin/zsh and /bin/bash.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
KINGO_DIR=$(cd "$HERE/../.." && pwd -P)
KINGO="$KINGO_DIR/kingo"
START="# >>> kingo shortcuts >>>"
END="# <<< kingo shortcuts <<<"

say()  { printf '\n── %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
show() { printf '%s\n' "$1" | tail -n "${2:-6}" | cut -c1-200 | sed 's/^/         | /'; }
fail() { printf '   FAIL  %s\n' "$*"; exit 1; }
has()  { case "$1" in *"$2"*) return 0 ;; esac; return 1; }
# brief <output of a dry run>: its lines that say where and how Claude Code would start
brief() { show "$(printf '%s\n' "$1" | grep -E '^(This folder|dry run|  nono run)' | sed "s|$KINGO_DIR|<kingo-pod>|g; s|${HOME_SHOWN:-/nonexistent}|<home>|g")" 4; }

# fresh_home: a home folder of its own, with ~/projects/thesis in it; prints its path
fresh_home() {
  local h; h=$(cd "$(mktemp -d)" && pwd -P)
  mkdir -p "$h/projects/thesis"
  printf '%s' "$h"
}
# k <home> <folder> argument ...: ./kingo from that folder, with that home folder, as a dry run; stdout and stderr
k() {
  local h=$1 from=$2; shift 2
  ( cd "$from" && env -u XDG_CONFIG_HOME -u ZDOTDIR HOME="$h" KINGO_CLAUDE_DRY_RUN=1 "$KINGO" "$@" ) 2>&1
}

# ── kingo claude --in, from the folder you are in ────────────────────────────
part_in() {
  local h out d
  h=$(fresh_home)

  say "kingo claude --in .: the folder you are in"
  out=$(k "$h" "$h/projects/thesis" claude --in .) || { show "$out" 4; fail "kingo claude --in . did not take the folder it was started in"; }
  HOME_SHOWN=$h brief "$out"
  has "$out" "dry run — would start in $h/projects/thesis:" || { show "$out" 6; fail "kingo claude --in . would not start in the folder it was started in"; }
  has "$out" "nono run --profile kingo-claude-base --allow-cwd --read $KINGO_DIR/setup/claude -- " \
    || { show "$out" 6; fail "kingo claude --in . would not start with the base profile, which reads only setup/claude"; }
  out=$(k "$h" "$h/projects/thesis" yolo --in .) || { show "$out" 4; fail "kingo yolo --in . did not take the folder it was started in"; }
  has "$out" "dry run — would start in $h/projects/thesis:" || { show "$out" 6; fail "kingo yolo --in . would not start in the folder it was started in"; }
  has "$out" "--dangerously-skip-permissions" || fail "kingo yolo --in . would start Claude Code with requests for permission"
  ok "kingo claude --in . and kingo yolo --in . take the folder they are started in"

  say "kingo claude --in thesis: a folder named from where you are"
  for d in thesis ./thesis/ ../projects/thesis; do
    out=$(k "$h" "$h/projects" claude --in "$d") || { show "$out" 4; fail "kingo claude --in $d from ~/projects did not take ~/projects/thesis"; }
    has "$out" "dry run — would start in $h/projects/thesis:" || { show "$out" 6; fail "kingo claude --in $d from ~/projects would not start in ~/projects/thesis"; }
  done
  out=$(k "$h" "$h/projects/thesis" claude --in ../thesis) || { show "$out" 4; fail "kingo claude --in ../thesis did not take the folder"; }
  has "$out" "dry run — would start in $h/projects/thesis:" || { show "$out" 6; fail "kingo claude --in ../thesis would not start in ~/projects/thesis"; }
  if out=$(k "$h" "$h/projects" claude --in nothing-here); then show "$out" 3; fail "kingo claude --in took a folder that is not there"; fi
  has "$out" "$h/projects/nothing-here" || { show "$out" 3; fail "for a folder that is not there, kingo does not name it with the folder it was started in"; }
  show "$out" 1
  ok "thesis, ./thesis/, ../projects/thesis from ~/projects, ../thesis from thesis; a folder that is not there is named in full"

  say "kingo claude --in . in kingo-pod: Claude Code starts for the course, and says so"
  for d in "$KINGO_DIR" "$KINGO_DIR/shared" "$KINGO_DIR/setup/claude"; do
    out=$(k "$h" "$d" claude --in .) || { show "$out" 4; fail "kingo claude --in . in $d did not start the course"; }
    has "$out" "This folder is in kingo-pod: Claude Code starts for the course, in $(basename "$KINGO_DIR")/claude." \
      || { show "$out" 6; fail "kingo claude --in . in $d does not say that it starts the course"; }
    has "$out" "dry run — would start in $KINGO_DIR/claude:" || { show "$out" 6; fail "kingo claude --in . in $d would not start in kingo-pod/claude"; }
    has "$out" "nono run --profile kingo-claude --allow-cwd --read $KINGO_DIR -- " || { show "$out" 6; fail "kingo claude --in . in $d would not start with the course profile"; }
    has "$out" "claude --add-dir=$KINGO_DIR " || { show "$out" 6; fail "kingo claude --in . in $d would not start Claude Code as ./kingo claude does"; }
    if has "$out" "is kingo-pod or a folder in it"; then fail "kingo claude --in . in $d still refuses kingo-pod"; fi
  done
  HOME_SHOWN=$h brief "$out"
  out=$(k "$h" "$h/projects" claude --in "$KINGO_DIR/shared") || { show "$out" 4; fail "kingo claude --in kingo-pod/shared did not start the course"; }
  has "$out" "dry run — would start in $KINGO_DIR/claude:" || { show "$out" 6; fail "kingo claude --in kingo-pod/shared, by its full path, would not start the course"; }
  out=$(k "$h" "$KINGO_DIR" claude --login --in .) || { show "$out" 4; fail "kingo claude --login --in . in kingo-pod did not start the course"; }
  has "$out" "nono run --profile kingo-claude-login-course --allow-cwd --read $KINGO_DIR -- " \
    || { show "$out" 6; fail "kingo claude --login --in . in kingo-pod would not start the course with the login"; }
  out=$(k "$h" "$KINGO_DIR/shared" yolo --in .) || { show "$out" 4; fail "kingo yolo --in . in kingo-pod/shared did not start the course"; }
  has "$out" "--dangerously-skip-permissions" || fail "kingo yolo --in . in kingo-pod would start the course with requests for permission"
  ok "kingo-pod, shared, setup/claude, a full path, with --login, with yolo: the course in kingo-pod/claude, with the line that says so"

  say "kingo claude --in ~, and a folder that holds kingo-pod: refused"
  for d in "$h" ..; do
    if out=$(k "$h" "$h/projects" claude --in "$d"); then show "$out" 3; fail "kingo claude --in $d from ~/projects took the home folder"; fi
  done
  if out=$(k "$h" "$h" claude --in .); then show "$out" 3; fail "kingo claude --in . took the home folder"; fi
  has "$out" "not the home folder itself" || { show "$out" 3; fail "kingo claude --in . in the home folder does not say why it refuses"; }
  show "$out" 1
  # a kingo-pod inside the home folder, as on a student's laptop: the folder above it holds it
  mkdir -p "$h/box/kingo-pod"
  cp -R "$KINGO" "$KINGO_DIR/.env" "$KINGO_DIR/VERSION" "$KINGO_DIR/setup" "$h/box/kingo-pod/"
  if out=$( (cd "$h/box/kingo-pod" && env -u XDG_CONFIG_HOME -u ZDOTDIR HOME="$h" KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in ..) 2>&1 ); then
    show "$out" 3; fail "kingo claude --in .. in kingo-pod took the folder that holds kingo-pod"
  fi
  has "$out" "holds kingo-pod" || { show "$out" 3; fail "kingo claude --in .. in kingo-pod does not say that the folder holds kingo-pod"; }
  show "$out" 1
  out=$( (cd "$h/box/kingo-pod" && env -u XDG_CONFIG_HOME -u ZDOTDIR HOME="$h" KINGO_CLAUDE_DRY_RUN=1 ./kingo claude --in .) 2>&1 ) \
    || { show "$out" 4; fail "kingo claude --in . in a kingo-pod inside the home folder did not start the course"; }
  has "$out" "dry run — would start in $h/box/kingo-pod/claude:" || { show "$out" 6; fail "kingo claude --in . in a kingo-pod inside the home folder would not start in its claude folder"; }
  ok "the home folder (by name, as ., as ..) and the folder that holds kingo-pod are refused; in that kingo-pod, --in . is the course"
  rm -rf "$h"
}

# ── ./kingo shortcuts ────────────────────────────────────────────────────────
# outside <file>: the file without the block of kingo shortcuts
outside() { awk -v s="$START" -v e="$END" '$0 == s {b = 1} !b {print} $0 == e {b = 0}' "$1"; }
# blocks <file>: how many blocks it has
blocks() { grep -cxF "$START" "$1" || true; }
# names <file>: the names of the functions in the block, in their order
names() { sed -n 's/^  function \([a-z]*\) {.*/\1/p' "$1" | tr '\n' ' ' | sed 's/ $//'; }

shortcuts_with() {
  local sh=$1 name=${1##*/} h rc out n login=""
  [ -x "$sh" ] || fail "$sh is not there"
  [ "$(uname -s)" = Darwin ] && login=-l       # a terminal on a Mac starts a login shell; under Linux a terminal does not
  h=$(fresh_home)
  case "$name" in
    zsh)  rc="$h/.zshrc" ;;
    bash) rc="$h/.bashrc"; [ "$(uname -s)" = Darwin ] && rc="$h/.bash_profile" ;;
  esac
  # s argument ...: ./kingo shortcuts with this shell and home folder, without a terminal
  s() { ( cd "$h/projects" && env -u XDG_CONFIG_HOME -u ZDOTDIR HOME="$h" SHELL="$sh" KINGO_CLAUDE_DRY_RUN=1 PATH="$h/bin:$PATH" "$KINGO" shortcuts "$@" ) < /dev/null 2>&1; }
  # t answer ... [-- argument ...]: the same in a terminal, with these answers typed
  t() {
    local a=() x
    while [ $# -gt 0 ] && [ "$1" != -- ]; do a+=("$1"); shift; done
    [ $# = 0 ] || shift
    ( cd "$h/projects" && env -u XDG_CONFIG_HOME -u ZDOTDIR HOME="$h" SHELL="$sh" KINGO_CLAUDE_DRY_RUN=1 PATH="$h/bin:$PATH" TERM=dumb \
        python3 "$HERE/pty_answer.py" 60 ${a[@]+"${a[@]}"} -- "$KINGO" shortcuts "$@" ) < /dev/null 2>&1
  }
  # new_shell <folder> <command>: a new shell, as a new terminal starts it, which reads the startup file
  new_shell() { ( cd "$1" && env -u XDG_CONFIG_HOME -u ZDOTDIR HOME="$h" SHELL="$sh" KINGO_CLAUDE_DRY_RUN=1 "$sh" +m $login -i -c "$2" ) < /dev/null 2>&1; }
  mkdir -p "$h/bin"
  printf '# my own line\nexport MY_OWN=1\n' > "$rc"
  cp "$rc" "$h/rc.before"

  say "$name: without a terminal and without names, kingo shortcuts stops and says why"
  if out=$(s); then show "$out" 4; fail "kingo shortcuts went on without a terminal and without names"; fi
  has "$out" "Run it in a terminal" || { show "$out" 4; fail "kingo shortcuts does not say that it needs a terminal"; }
  cmp -s "$rc" "$h/rc.before" || fail "kingo shortcuts changed $rc although it stopped"
  show "$out" 1
  ok "it stops, and the file is as it was"

  say "$name: names on the command line"
  out=$(s kc ky kingo) || { show "$out" 8; fail "kingo shortcuts kc ky kingo failed"; }
  show "$out" 8
  [ "$(blocks "$rc")" = 1 ] || { show "$(cat "$rc")" 20; fail "the block is not in $rc once"; }
  [ "$(names "$rc")" = "kc ky kingo" ] || { show "$(cat "$rc")" 20; fail "the block has '$(names "$rc")', not 'kc ky kingo'"; }
  outside "$rc" | cmp -s - "$h/rc.before" || { show "$(cat "$rc")" 20; fail "kingo shortcuts changed more of $rc than its block"; }
  n=$(ls "$rc".kingo-backup-* 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" = 1 ] || fail "there is not one copy of $rc from before ($n)"
  cmp -s "$rc".kingo-backup-* "$h/rc.before" || fail "the copy of $rc is not the file as it was before"
  has "$out" "Written to" || fail "kingo shortcuts does not say what it wrote"
  has "$out" "source " || fail "kingo shortcuts does not say how the shortcuts work in this terminal"
  grep -qxF "  function kc { '$KINGO' kc \"\$@\"; }" "$rc" || { show "$(cat "$rc")" 20; fail "kc does not call kingo kc by kingo's full path"; }
  out=$(s kc ky kingo) || { show "$out" 8; fail "kingo shortcuts kc ky kingo failed the second time"; }
  [ "$(ls "$rc".kingo-backup-* | wc -l | tr -d ' ')" = 1 ] || fail "a run that changes nothing made a copy of $rc"
  if out=$(s kc nonsense); then show "$out" 3; fail "kingo shortcuts took a name it does not know"; fi
  ok "the block holds kc, ky and kingo, calls kingo by its full path, and nothing else in the file changed; a copy from before"

  say "$name: in a terminal, Enter takes all; a second run replaces the block"
  out=$(t "") || { show "$out" 12; fail "kingo shortcuts in a terminal, Enter, failed"; }
  show "$out" 14
  has "$out" "1  kc" || fail "the list does not show kc with its number"
  has "$out" "5  kingo" || fail "the list does not show kingo with its number"
  [ "$(blocks "$rc")" = 1 ] || { show "$(cat "$rc")" 20; fail "after a second run, the block is not in $rc once"; }
  [ "$(names "$rc")" = "kc kcl ky kyl kingo" ] || { show "$(cat "$rc")" 20; fail "Enter gave '$(names "$rc")', not all five"; }
  outside "$rc" | cmp -s - "$h/rc.before" || fail "the second run changed more of $rc than its block"
  out=$(t "2 4") || { show "$out" 12; fail "kingo shortcuts in a terminal, 2 4, failed"; }
  [ "$(names "$rc")" = "kcl kyl" ] || { show "$(cat "$rc")" 20; fail "2 4 gave '$(names "$rc")', not kcl kyl"; }
  out=$(t "9" "kc, 3") || { show "$out" 12; fail "kingo shortcuts in a terminal, 9 and then kc, 3, failed"; }
  has "$out" "9 is not on the list" || { show "$out" 12; fail "kingo shortcuts does not say that 9 is not on the list"; }
  [ "$(names "$rc")" = "kc ky" ] || { show "$(cat "$rc")" 20; fail "kc, 3 gave '$(names "$rc")', not kc ky"; }
  [ "$(blocks "$rc")" = 1 ] || fail "after four runs, the block is not in $rc once"
  ok "Enter: all five; 2 4: kcl and kyl; 9 is refused and asked again; names and commas work; always one block"

  say "$name: kc, ky, kcl, kyl and kingo in a new shell that reads $(basename "$rc")"
  out=$(t "") || { show "$out" 12; fail "kingo shortcuts in a terminal, Enter, failed"; }
  # Frank, 18 Nov 2026: "kc started kingo claude im kingopod/claude ordner, kc . im ordner wo man ist; kc pfad in einem
  # anderen ordner"
  out=$(new_shell "$h/projects/thesis" kc)
  has "$out" "dry run — would start in $KINGO_DIR/claude:" || { show "$out" 8; fail "kc alone would not start the course"; }
  has "$out" "--profile kingo-claude " || { show "$out" 8; fail "kc alone would not start with the course profile"; }
  HOME_SHOWN=$h brief "$out"
  out=$(new_shell "$h/projects/thesis" 'kc .')
  has "$out" "dry run — would start in $h/projects/thesis:" || { show "$out" 8; fail "kc . would not start Claude Code in the folder it is in"; }
  has "$out" "--profile kingo-claude-base " || { show "$out" 8; fail "kc . would not start with the base profile"; }
  HOME_SHOWN=$h brief "$out"
  out=$(new_shell "$h/projects" 'kc thesis')
  has "$out" "dry run — would start in $h/projects/thesis:" || { show "$out" 8; fail "kc thesis in ~/projects would not start in ~/projects/thesis"; }
  out=$(new_shell / "kc $h/projects/thesis")
  has "$out" "dry run — would start in $h/projects/thesis:" || { show "$out" 8; fail "kc with the full path of a folder would not start there"; }
  out=$(new_shell "$h/projects/thesis" 'kc nowhere; echo "kc-exit=$?"')
  has "$out" "there is no folder" || { show "$out" 8; fail "kc with a folder that is not there does not say so"; }
  has "$out" "kc-exit=1" || { show "$out" 8; fail "kc with a folder that is not there did not stop with exit code 1"; }
  if has "$out" "dry run — would start"; then show "$out" 8; fail "kc with a folder that is not there would start Claude Code"; fi
  out=$(new_shell "$KINGO_DIR/shared" 'kc .')
  has "$out" "This folder is in kingo-pod: Claude Code starts for the course" || { show "$out" 8; fail "kc . in kingo-pod does not say that it starts the course"; }
  has "$out" "dry run — would start in $KINGO_DIR/claude:" || { show "$out" 8; fail "kc . in kingo-pod would not start the course"; }
  out=$(new_shell "$h/projects/thesis" 'ky --model probe-model')
  has "$out" "dry run — would start in $KINGO_DIR/claude:" || { show "$out" 8; fail "ky with an option first would not start the course"; }
  has "$out" "--dangerously-skip-permissions" || { show "$out" 8; fail "ky would start Claude Code with requests for permission"; }
  has "$out" "--model probe-model" || { show "$out" 8; fail "ky does not pass on what comes after it"; }
  out=$(new_shell "$h/projects/thesis" 'ky . --model probe-model')
  has "$out" "dry run — would start in $h/projects/thesis:" || { show "$out" 8; fail "ky . with an option would not start in the folder"; }
  has "$out" "--model probe-model" || { show "$out" 8; fail "ky . does not pass on what comes after the folder"; }
  out=$(new_shell "$h/projects/thesis" kcl)
  has "$out" "--profile kingo-claude-login-course " || { show "$out" 8; fail "kcl alone would not start the course with the login"; }
  out=$(new_shell "$h/projects/thesis" 'kcl .')
  has "$out" "--profile kingo-claude-login " || { show "$out" 8; fail "kcl . would not start with the login"; }
  out=$(new_shell "$h/projects/thesis" 'kyl .')
  has "$out" "--profile kingo-claude-login " || { show "$out" 8; fail "kyl . would not start with the login"; }
  has "$out" "--dangerously-skip-permissions" || { show "$out" 8; fail "kyl would start Claude Code with requests for permission"; }
  out=$(new_shell / 'kingo version')
  has "$out" "$(cat "$KINGO_DIR/VERSION")" || { show "$out" 8; fail "kingo version from / does not run kingo"; }
  ok "kc alone: the course; kc ., kc thesis, kc with a full path: that folder, and not one that is not there; kc . in kingo-pod: the course; ky with an option first: the course, after a folder: there; kcl, kcl ., kyl ., and kingo version from /"

  say "$name: a block of an older kingo, written anew by ./kingo shortcuts refresh, which ./kingo update runs"
  local q="'$KINGO'"
  { cat "$h/rc.before"
    printf '%s\n' "$START" "# Made by ./kingo shortcuts, which replaces these lines when it runs again. To take them out:  $q shortcuts remove" \
      'if [ -z "${KINGO_SHORTCUTS_SKIP:-}" ]; then' "  unalias kc ky 2>/dev/null" "  function kc { $q claude --in . \"\$@\"; }" \
      "  function ky { $q yolo --in . \"\$@\"; }" "fi" "$END"; } > "$rc"
  rm -f "$rc".kingo-backup-*
  out=$(s refresh) || { show "$out" 6; fail "kingo shortcuts refresh failed"; }
  show "$out" 4
  has "$out" "are written anew for this kingo-pod: kc ky." || { show "$out" 6; fail "kingo shortcuts refresh does not say that it wrote the block anew"; }
  [ "$(names "$rc")" = "kc ky" ] || { show "$(cat "$rc")" 20; fail "refresh changed the names: '$(names "$rc")'"; }
  grep -qxF "  function kc { '$KINGO' kc \"\$@\"; }" "$rc" || { show "$(cat "$rc")" 20; fail "after refresh, kc does not call kingo kc"; }
  if grep -qF "claude --in ." "$rc"; then show "$(cat "$rc")" 20; fail "after refresh, the old kc is still in the file"; fi
  outside "$rc" | cmp -s - "$h/rc.before" || { show "$(cat "$rc")" 20; fail "refresh changed more of the file than its block"; }
  [ "$(ls "$rc".kingo-backup-* | wc -l | tr -d ' ')" = 1 ] || fail "refresh did not keep one copy of the file"
  out=$(new_shell "$h/projects/thesis" kc)
  has "$out" "dry run — would start in $KINGO_DIR/claude:" || { show "$out" 8; fail "after refresh, kc alone does not start the course"; }
  out=$(s refresh) || { show "$out" 6; fail "a second refresh failed"; }
  [ -z "$out" ] || { show "$out" 4; fail "a second refresh said something, though nothing had changed"; }
  [ "$(ls "$rc".kingo-backup-* | wc -l | tr -d ' ')" = 1 ] || fail "a second refresh made a copy"
  grep -q '^  shortcuts_refresh || true$' "$KINGO_DIR/kingo" || fail "./kingo update does not run the refresh"
  ok "the old block gets kc and ky anew, which call kingo kc and ky; nothing else changes, a copy first; a second refresh does nothing; ./kingo update runs it"

  say "$name: a name that means something already, in a startup file that asks a question"
  # zsh's compinit asks one, in the terminal, when it finds insecure directories: kingo's check of the names must not
  # wait for it (it waited 10 seconds and missed the alias), show it, or take the student's keys. The question is
  # asked only in that check (KINGO_SHORTCUTS_SKIP), so a new shell of this test does not wait for it either.
  case "$name" in
    zsh)  ask='[ -z "${KINGO_SHORTCUTS_SKIP:-}" ] || read -q "?Ignore insecure directories and continue [y] or abort compinit [n]? " || true' ;;
    bash) ask='[ -z "${KINGO_SHORTCUTS_SKIP:-}" ] || read -r -p "Ignore insecure directories and continue [y] or abort compinit [n]? " _ < /dev/tty || true' ;;
  esac
  { printf "alias kc='echo mine'\n"; printf '%s\n' "$ask"; cat "$h/rc.before"; } > "$h/rc.alias"
  cp "$h/rc.alias" "$rc"
  printf '#!/bin/sh\necho my-kyl\n' > "$h/bin/kyl"; chmod +x "$h/bin/kyl"
  out=$(s kc ky kyl) || { show "$out" 8; fail "kingo shortcuts kc ky kyl failed with a name that is taken"; }
  show "$out" 6
  has "$out" "kc already means something in your terminal" || { show "$out" 8; fail "kingo shortcuts does not say that kc is an alias already"; }
  has "$out" "kyl already means something in your terminal" || { show "$out" 8; fail "kingo shortcuts does not say that kyl is a command already"; }
  has "$out" "left kc out" || { show "$out" 8; fail "without a terminal, kingo shortcuts does not say that it left kc out"; }
  [ "$(names "$rc")" = "ky" ] || { show "$(cat "$rc")" 20; fail "without a terminal, the names that are taken went in: '$(names "$rc")'"; }
  out=$(t "1 3" "" -- ) || { show "$out" 12; fail "kingo shortcuts in a terminal, 1 3 and Enter, failed"; }
  if has "$out" "did not answer within"; then show "$out" 12; fail "in a terminal, kingo's check of the names waited for the question of the startup file"; fi
  if has "$out" "Ignore insecure directories"; then show "$out" 12; fail "the question of the startup file showed in the student's terminal"; fi
  has "$out" "Kept yours" || { show "$out" 12; fail "Enter at the question does not keep the student's kc"; }
  [ "$(names "$rc")" = "ky" ] || { show "$(cat "$rc")" 20; fail "Enter at the question wrote kc: '$(names "$rc")'"; }
  out=$(new_shell "$h/projects/thesis" kc)
  has "$out" mine || { show "$out" 8; fail "the student's own kc is gone, though they kept it"; }
  out=$(t "1 3" "yes") || { show "$out" 12; fail "kingo shortcuts in a terminal, 1 3 and yes, failed"; }
  [ "$(names "$rc")" = "kc ky" ] || { show "$(cat "$rc")" 20; fail "yes at the question did not write kc: '$(names "$rc")'"; }
  out=$(new_shell "$h/projects/thesis" 'kc .')
  has "$out" "dry run — would start in $h/projects/thesis:" || { show "$out" 8; fail "after yes, kc in a new shell is not kingo's (the alias still wins)"; }
  out=$(s kc ky) || { show "$out" 8; fail "kingo shortcuts kc ky failed once kingo's kc is in"; }
  if has "$out" "kc already means"; then show "$out" 6; fail "kingo asks again for a kc that the student took with yes before"; fi
  [ "$(names "$rc")" = "kc ky" ] || { show "$(cat "$rc")" 20; fail "a second run without a terminal dropped the kc that the student took with yes: '$(names "$rc")'"; }
  rm -f "$h/bin/kyl"
  ok "an alias and a command are named; a question in the startup file neither waits nor shows; without a terminal they stay out; Enter keeps the student's; yes takes kingo's, which then wins and is not asked again"

  say "$name: remove"
  out=$(s remove) || { show "$out" 6; fail "kingo shortcuts remove failed"; }
  show "$out" 3
  [ "$(blocks "$rc")" = 0 ] || { show "$(cat "$rc")" 20; fail "kingo shortcuts remove left the block in $rc"; }
  cmp -s "$rc" "$h/rc.alias" || { show "$(cat "$rc")" 20; fail "after remove, $rc is not the file it was before the shortcuts"; }
  out=$(new_shell "$h/projects/thesis" 'ky; echo "ky-exit=$?"')
  has "$out" "ky-exit=127" || { show "$out" 6; fail "after remove, ky still works in a new shell"; }
  cp "$rc" "$h/rc.after"
  out=$(s remove) || { show "$out" 6; fail "kingo shortcuts remove failed when there is nothing to take out"; }
  has "$out" "no shortcuts" || { show "$out" 4; fail "kingo shortcuts remove does not say that there is nothing to take out"; }
  cmp -s "$rc" "$h/rc.after" || fail "kingo shortcuts remove changed $rc although there was nothing to take out"
  ok "the block is out, the file is as it was before it, ky is gone in a new shell; a second remove changes nothing"

  say "$name: a startup file that takes longer than 10 seconds"
  { printf "alias kc='echo mine'\nkyl() { echo my-kyl; }\n"; printf '[ -z "${KINGO_SHORTCUTS_SKIP:-}" ] || sleep 25\n'; cat "$h/rc.before"; } > "$rc"
  out=$(s kc ky kyl) || { show "$out" 8; fail "kingo shortcuts kc ky kyl failed with a slow startup file"; }
  show "$out" 4
  has "$out" "did not answer within 10 seconds" || { show "$out" 8; fail "kingo does not say that the shell did not answer"; }
  has "$out" "kc already means something in your terminal: alias kc='echo mine'" || { show "$out" 8; fail "with a slow shell, kingo does not find the alias kc in the startup file"; }
  has "$out" "kyl already means something in your terminal: kyl()" || { show "$out" 8; fail "with a slow shell, kingo does not find the function kyl in the startup file"; }
  [ "$(names "$rc")" = "ky" ] || { show "$(cat "$rc")" 20; fail "with a slow shell, the names that are taken went in: '$(names "$rc")'"; }
  cp "$h/rc.after" "$rc"
  ok "the shell is not waited for; kingo finds the alias and the function in the startup file and leaves them out"

  say "$name: what kingo shortcuts does not change"
  printf '%s\n# a line that the student wrote\n' "$START" >> "$rc"; cp "$rc" "$h/rc.broken"
  if out=$(s kc); then show "$out" 4; fail "kingo shortcuts wrote into a file whose block is not whole"; fi
  has "$out" "kingo changed nothing" || { show "$out" 4; fail "kingo shortcuts does not say that it changed nothing"; }
  cmp -s "$rc" "$h/rc.broken" || fail "kingo shortcuts changed a file whose block is not whole"
  if out=$(s remove); then show "$out" 4; fail "kingo shortcuts remove took lines out of a file whose block is not whole"; fi
  cmp -s "$rc" "$h/rc.broken" || fail "kingo shortcuts remove changed a file whose block is not whole"
  if out=$( (cd "$h/projects" && env -u ZDOTDIR HOME="$h" SHELL=/bin/sh "$KINGO" shortcuts kc) < /dev/null 2>&1 ); then show "$out" 3; fail "kingo shortcuts wrote for /bin/sh"; fi
  has "$out" "zsh and bash" || { show "$out" 3; fail "for another shell, kingo shortcuts does not say which shells it knows"; }
  show "$out" 1
  # a startup file that is a link (dotfiles kept elsewhere) stays a link; one without a last newline gets the block on lines of its own
  rm -f "$rc"; mkdir -p "$h/dotfiles"; printf 'export LAST_LINE=1' > "$h/dotfiles/rc"; ln -s "$h/dotfiles/rc" "$rc"
  out=$(s kingo) || { show "$out" 6; fail "kingo shortcuts kingo failed with a startup file that is a link"; }
  [ -L "$rc" ] || fail "kingo shortcuts made the link $rc a file of its own"
  [ "$(names "$h/dotfiles/rc")" = kingo ] || { show "$(cat "$h/dotfiles/rc")" 12; fail "the block is not in the file the link points to"; }
  [ "$(head -n 1 "$h/dotfiles/rc")" = "export LAST_LINE=1" ] || { show "$(cat "$h/dotfiles/rc")" 12; fail "the last line of the file and the block ran together"; }
  ok "a block that is not whole, another shell, a link and a file without a last newline"
  rm -rf "$h"
}

part_shortcuts() {
  local h out
  shortcuts_with /bin/zsh
  shortcuts_with /bin/bash
  if [ "$(uname -s)" = Darwin ]; then
    # bash on a Mac reads only the first of ~/.bash_profile, ~/.bash_login and ~/.profile. A ~/.bash_profile that kingo
    # makes would end the reading of ~/.profile, so it reads that one first.
    say "bash on a Mac with a ~/.profile and no ~/.bash_profile"
    h=$(fresh_home)
    printf 'export FROM_PROFILE=yes\n' > "$h/.profile"
    out=$( (cd "$h" && env -u ZDOTDIR HOME="$h" SHELL=/bin/bash "$KINGO" shortcuts kc) < /dev/null 2>&1 ) || { show "$out" 6; fail "kingo shortcuts kc failed"; }
    show "$out" 6
    [ -f "$h/.bash_profile" ] || fail "kingo shortcuts did not make ~/.bash_profile"
    out=$( (cd "$h/projects/thesis" && env -u ZDOTDIR HOME="$h" SHELL=/bin/bash KINGO_CLAUDE_DRY_RUN=1 /bin/bash +m -l -i -c 'echo "profile=$FROM_PROFILE"; kc .') < /dev/null 2>&1 )
    has "$out" "profile=yes" || { show "$out" 8; fail "with the new ~/.bash_profile, bash no longer reads ~/.profile"; }
    has "$out" "dry run — would start in $h/projects/thesis:" || { show "$out" 8; fail "kc . in a new login shell would not start in the folder"; }
    ok "kingo made ~/.bash_profile, which reads ~/.profile first; kc works"
    rm -rf "$h"
  fi
}

case "${1:-}" in
  in)        part_in ;;
  shortcuts) part_shortcuts ;;
  *) echo "usage: claude-shortcuts.sh in|shortcuts"; exit 2 ;;
esac
printf '\nAll checks of "%s" passed.\n' "$1"
