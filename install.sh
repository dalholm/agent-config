#!/usr/bin/env bash
#
# install.sh — wire this repo into every agent harness via symlinks.
#
# AGENTS.md is the single source of truth. We symlink each harness's global
# instruction file to it, so the content is identical everywhere and you only ever
# edit AGENTS.md. Existing files are backed up first.
#
# It also bootstraps the tools the config assumes: it installs Pi, Node/npm and the
# pi-hermes-memory extension if they're missing.
#
# Usage:
#   ./install.sh             # do it
#   ./install.sh --dry-run   # show what would happen, change nothing
#   ./install.sh --no-bootstrap   # symlinks/hook only; never install external tools
#
set -euo pipefail

DRY_RUN=0
BOOTSTRAP=1
for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=1 ;;
    --no-bootstrap) BOOTSTRAP=0 ;;
  esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

say()  { printf '%s\n' "$*"; }
run()  { if [ "$DRY_RUN" = 1 ]; then say "  would: $*"; else eval "$*"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

# A freshly-installed pi (and friends) land in ~/.local/bin — put it on PATH so later
# steps in this same run can see them without the user opening a new shell.
export PATH="$HOME/.local/bin:$PATH"

# link <target> <linkpath>
link() {
  local target="$1" link="$2" dir
  dir="$(dirname "$link")"
  run "mkdir -p '$dir'"
  if [ -L "$link" ] && [ "$(readlink "$link" 2>/dev/null)" = "$target" ]; then
    say "  ok (already linked): $link"
    return
  fi
  if [ -e "$link" ] || [ -L "$link" ]; then
    say "  backing up existing: $link -> $link.bak-$STAMP"
    run "mv '$link' '$link.bak-$STAMP'"
  fi
  run "ln -sfn '$target' '$link'"
  if [ "$DRY_RUN" = 1 ]; then say "  (would link) $link -> $target"; else say "  linked: $link -> $target"; fi
}

say "Repo: $REPO"
[ "$DRY_RUN" = 1 ] && say "(dry run — no changes)"
[ "$BOOTSTRAP" = 0 ] && say "(--no-bootstrap — symlinks/hook only, no tool installs)"
say ""

if [ "$BOOTSTRAP" = 1 ]; then
  say "Tools (install if missing):"

  # Node/npm — needed for the pi-hermes-memory npm extension.
  if have node && have npm; then
    say "  ok: node/npm present"
  elif have brew; then
    say "  node/npm missing — installing via Homebrew"
    run "brew install node"
  else
    say "  node/npm missing and Homebrew not found — install Node manually: https://nodejs.org"
  fi

  # Pi — the coding agent itself (separate from the hermes-memory extension below).
  if have pi; then
    say "  ok: pi present"
  else
    say "  pi missing — installing via pi.dev"
    run "curl -fsSL https://pi.dev/install.sh | sh"
    have pi && say "  pi installed" || say "  pi installed — open a new shell if 'pi' isn't found yet"
  fi
  say ""
fi

say "Instruction files (all -> AGENTS.md):"
link "$REPO/AGENTS.md" "$HOME/.claude/CLAUDE.md"
link "$REPO/AGENTS.md" "$HOME/.gemini/GEMINI.md"
link "$REPO/AGENTS.md" "$HOME/.codex/AGENTS.md"
say ""

say "Claude Code skills:"
for skill in "$REPO"/skills/*/; do
  [ -d "$skill" ] || continue
  name="$(basename "$skill")"
  link "${skill%/}" "$HOME/.claude/skills/$name"
done
say ""

say "Claude Code hook (UserPromptSubmit):"
HOOK="$REPO/hooks/router-reminder.sh"
run "chmod +x '$HOOK'"
SETTINGS="$HOME/.claude/settings.json"
if command -v jq >/dev/null 2>&1; then
  run "mkdir -p '$HOME/.claude'"
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: merge UserPromptSubmit hook into $SETTINGS (via jq)"
  else
    [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
    if jq -e --arg c "$HOOK" \
        '[.. | objects | .command? // empty] | index($c)' "$SETTINGS" >/dev/null 2>&1; then
      say "  ok (hook already present): $SETTINGS"
    else
      tmp="$(mktemp)"
      jq --arg c "$HOOK" '
        .hooks //= {} |
        .hooks.UserPromptSubmit //= [] |
        .hooks.UserPromptSubmit += [ { "hooks": [ { "type": "command", "command": $c } ] } ]
      ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
      say "  merged hook into: $SETTINGS"
    fi
  fi
else
  say "  jq not found — add this hook manually to $SETTINGS"
  say "  (see hooks/settings-snippet.json; set command to: $HOOK)"
fi
say ""

say "Pi:"
# Configs live at fixed paths under ~/.pi/agent; symlink them out so editing in the
# repo is live. models.json defines local providers (LM Studio); hermes config drives
# persistent memory.
link "$REPO/pi/models.json" "$HOME/.pi/agent/models.json"
link "$REPO/pi/hermes-memory-config.json" "$HOME/.pi/agent/hermes-memory-config.json"
# Data dir is redirected into the repo via memoryDir in the config — just ensure it exists.
run "mkdir -p '$REPO/pi/memory/skills' '$REPO/pi/memory/projects-memory'"
if have pi; then
  if pi list 2>/dev/null | grep -q 'pi-hermes-memory'; then
    say "  ok (extension already installed)"
  elif [ "$BOOTSTRAP" = 1 ]; then
    say "  installing extension: pi install npm:pi-hermes-memory"
    run "pi install npm:pi-hermes-memory"
  else
    say "  extension not installed — run: pi install npm:pi-hermes-memory"
  fi
else
  say "  pi not found on PATH — open a new shell, then: pi install npm:pi-hermes-memory"
fi

# Additional Pi extensions. Quality gates (lens/simplify), model-tiered subagents,
# research (web-access), MCP bridge, interactive prompts (ask-user/goal), and
# robustness for local LM Studio runs (lean-ctx/retry/handoff-rebase). See pi/README.md
# for why each is here. Same idempotent pattern as hermes-memory above.
PI_PACKAGES="pi-subagents pi-lens pi-lean-ctx pi-web-access pi-goal pi-ask-user pi-simplify pi-mcp-adapter pi-retry pi-handoff-rebase"
if have pi; then
  for pkg in $PI_PACKAGES; do
    if pi list 2>/dev/null | grep -q "$pkg"; then
      say "  ok (extension already installed): $pkg"
    elif [ "$BOOTSTRAP" = 1 ]; then
      say "  installing extension: pi install npm:$pkg"
      run "pi install npm:$pkg"
    else
      say "  extension not installed — run: pi install npm:$pkg"
    fi
  done
else
  say "  pi not on PATH — open a new shell, then install each: $PI_PACKAGES"
fi
say ""
say "Done. Restart your agent so it re-reads global config."
say "First Pi run: '/memory-index-sessions' to index past sessions for search."
