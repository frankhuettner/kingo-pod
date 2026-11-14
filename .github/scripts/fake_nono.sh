#!/bin/bash
# CI: a stand-in for nono, for the steps that kingo itself takes around the login of `kingo claude --login`
# (claude-sandbox.sh login). It starts nothing. It says what it was started with, and for `claude auth login` it
# leaves what STUB_LOGIN names in Claude Code's config folder:
#   phantom   a login as nono leaves it: both tokens are stand-ins
#   real      a login that nono did not capture: tokens in the form of Anthropic's own (made up here, good for nothing)
#   none      no login
[ "${1:-}" = --version ] && { echo "nono 0.0.0 (stand-in)"; exit 0; }
[ "${1:-}" = profile ] && exit 0
echo "STUB nono $*" | cut -c1-600
for v in CLAUDE_CODE_DISABLE_ARTIFACT CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC DISABLE_TELEMETRY DISABLE_ERROR_REPORTING \
         CLAUDE_CODE_MAX_CONTEXT_TOKENS CLAUDE_CONFIG_DIR TMPDIR GIT_CONFIG_NOSYSTEM NONO_NO_SAVE_PROMPT KINGO_BROWSER; do
  eval "x=\${$v-unset}"; echo "STUB   $v=$x"
done
echo "STUB   PATH starts with ${PATH%%:*}"
hex=abababababababababababababababababababababababababababababababab
case "$*" in
  *"claude auth login"*)
    case "${STUB_LOGIN:-none}" in
      phantom) printf '{"claudeAiOauth":{"accessToken":"sk-ant-oat01-%s","refreshToken":"nono_%s","expiresAt":1}}' "$hex" "$hex" > "$CLAUDE_CONFIG_DIR/.credentials.json" ;;
      real)    printf '{"claudeAiOauth":{"accessToken":"sk-ant-oat01-MADE-UP_for-the-CI_AbCdEf0123456789AbCdEf0123456789AbCdEf0123456789AbCdEf0123456789AbCdEf-AA","refreshToken":"sk-ant-ort01-MADE-UP_for-the-CI_AbCdEf0123456789"}}' > "$CLAUDE_CONFIG_DIR/.credentials.json" ;;
    esac ;;
esac
exit 0
