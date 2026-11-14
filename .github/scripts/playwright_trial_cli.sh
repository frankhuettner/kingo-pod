#!/usr/bin/env bash
# Playwright's CLI, as Claude Code would call it: one command per step, a browser that stays open in between.
#   playwright_trial_cli.sh <address of the page> [config file]
url=$1; cfg=${2:-}
pw() {  # one command of the CLI, stopped after a minute
  if command -v timeout >/dev/null 2>&1; then timeout -k 5 60 playwright-cli "$@" 2>&1
  else perl -e 'alarm shift; exec @ARGV' 60 playwright-cli "$@" 2>&1; fi
}
flat() { printf '%s' "$1" | tr '\n' '|' | cut -c1-700; }
out=$(pw open ${cfg:+--config "$cfg"} "$url")
case "$out" in *"Page Title: Order form"*) echo "   step  open: the page is open" ;;
  *) echo "CLI-RESULT failed: open: $(flat "$out")"; pw close >/dev/null; exit 1 ;; esac
snap=$(pw snapshot)
ref() { printf '%s\n' "$snap" | sed -n "s/.*$1.*\[ref=\([a-z0-9]*\)\].*/\1/p" | head -n 1; }
name=$(ref 'textbox "Name"'); product=$(ref 'combobox "Product"'); button=$(ref 'button "Order"')
if [ -z "$name" ] || [ -z "$product" ] || [ -z "$button" ]; then
  echo "CLI-RESULT failed: snapshot: $(flat "$snap")"; pw close >/dev/null; exit 1
fi
echo "   step  snapshot: $(printf '%s' "$snap" | wc -c | tr -d ' ') characters; the fields are $name, $product, $button"
pw fill "$name" Mina >/dev/null; pw select "$product" Coffee >/dev/null; pw click "$button" >/dev/null
after=$(pw snapshot)
shot=$(pw screenshot | sed -n 's/.*(\(.*\.png\)).*/\1/p' | head -n 1)
echo "   step  screenshot: ${shot:-none}"
pw close >/dev/null
case "$after" in
  *"Thank you, Mina: 1 Coffee"*) echo 'CLI-RESULT ok: the page answered "Thank you, Mina: 1 Coffee"' ;;
  *) echo "CLI-RESULT failed: after the click: $(flat "$after")"; exit 1 ;;
esac
