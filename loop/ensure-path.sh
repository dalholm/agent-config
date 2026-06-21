#!/usr/bin/env bash
# ensure-path.sh — make the loop's binaries resolvable under a minimal environment.
#
# Sourced by run-loop.sh and ask-cli-helper.sh so they behave the same whether launched
# from an interactive shell, from launchd/cron, or from any other non-interactive context
# that does NOT load nvm or the user's shell profile. Without this, `pi` (installed as an
# nvm-global npm package, and itself a `#!/usr/bin/env node` script, so it needs `node`
# too) and the native `claude`/`codex` CLIs in ~/.local/bin are invisible and the loop
# dies with "command not found".
#
# Idempotent and safe to source under `set -euo pipefail`. Override the nvm bin dir
# explicitly with PI_BIN_DIR if your pi lives somewhere non-standard.

_ensure_on_path() {
  case ":$PATH:" in
    *":$1:"*) ;;                          # already on PATH — leave it
    *) [ -d "$1" ] && PATH="$1:$PATH" ;;  # prepend only if the dir exists
  esac
  return 0                                # never fail the caller under `set -e`
}

# The nvm node bin that actually contains `pi` (newest, if several node versions have it).
# Resolving by "where pi lives" instead of a pinned version survives `nvm install <newer>`.
# That one directory covers BOTH `pi` and the `node` it shebangs to.
if [ -n "${PI_BIN_DIR:-}" ]; then
  _ensure_on_path "$PI_BIN_DIR"
else
  _pi_path="$(ls -d "$HOME"/.nvm/versions/node/*/bin/pi 2>/dev/null | sort -V | tail -1 || true)"
  if [ -n "$_pi_path" ]; then _ensure_on_path "$(dirname "$_pi_path")"; fi
fi

# Native claude / codex CLIs (the strong-model tier) live here, off launchd's minimal PATH.
_ensure_on_path "$HOME/.local/bin"

export PATH
