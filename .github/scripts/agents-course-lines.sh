#!/usr/bin/env bash
# setup/claude/agents-course-lines.txt: every line that the course's part of AGENTS.md (above "# Your team's rules")
# had in a version of setup/claude/AGENTS.md that git knows, and has now. kingo claude reads it to tell kingo's lines
# from the team's: a line above the heading that is not in it, kingo moves below the heading (claude_course_theirs).
# Run this after a change of the template; the CI (claude-sandbox.sh sandbox) checks that the template's lines are in
# the file. It only adds: a line of an older template stays, so that kingo knows it in a course folder of that time.
set -euo pipefail
cd "$(dirname "$0")/../.."
out=setup/claude/agents-course-lines.txt
part() { # file: the lines above its heading
  local n
  n=$(LC_ALL=C grep -n -m 1 -i -E '^#[[:space:]]+your team.{1,3}s rules[[:space:]]*$' "$1" | cut -d: -f1 || true)
  if [ -n "$n" ]; then head -n "$((n - 1))" "$1"; else cat "$1"; fi
}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
{ [ ! -f "$out" ] || cat "$out"
  for c in $(git rev-list --all -- setup/claude/AGENTS.md); do
    git show "${c}:setup/claude/AGENTS.md" > "$tmp/v.md" && part "$tmp/v.md"
  done
  part setup/claude/AGENTS.md
} | sed -e 's/\r$//' -e 's/[[:space:]]*$//' | grep -v '^$' | LC_ALL=C sort -u > "$tmp/lines.txt"
cp "$tmp/lines.txt" "$out"
echo "$(wc -l < "$out" | tr -d ' ') lines in $out"
