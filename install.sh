#!/usr/bin/env bash
#
# install.sh — wire this repo into every agent harness via symlinks.
#
# AGENTS.md is the single source of truth. We symlink each harness's global
# instruction file to it, so the content is identical everywhere and you only ever
# edit AGENTS.md. Existing files are backed up first.
#
# It also bootstraps the tools the config assumes: it installs Pi, Node/npm and the
# pi-hermes-memory extension if they're missing, and sets up Superpowers per harness
# (scripted for OpenCode/Pi, printed as slash-command steps for Claude Code/Codex).
#
# Usage:
#   ./install.sh             # do it
#   ./install.sh --dry-run   # show what would happen, change nothing
#   ./install.sh --no-bootstrap   # symlinks/hook only; never install external tools
#   ./install.sh --safe-profile   # keep harness permission prompts/sandboxing enabled
#
set -euo pipefail

DRY_RUN=0
BOOTSTRAP=1
PERMISSION_PROFILE="auto-approve"
for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=1 ;;
    --no-bootstrap)  BOOTSTRAP=0 ;;
    --safe-profile)  PERMISSION_PROFILE="safe" ;;
    --auto-approve)  PERMISSION_PROFILE="auto-approve" ;;
    *)
      printf 'Unknown argument: %s\n' "$arg" >&2
      exit 2
      ;;
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

# pi_install <spec> <label> — install a Pi extension, non-fatal on failure so one bad
# package (404, network) doesn't abort the whole run under `set -e`.
pi_install() {
  if [ "$DRY_RUN" = 1 ]; then say "  would: pi install $1"; return; fi
  say "  installing extension: pi install $1"
  pi install "$1" || say "  ! failed: $2 (skipped — check the name / registry)"
}

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

# render <template> <dest>
render() {
  local template="$1" dest="$2" dir tmp
  dir="$(dirname "$dest")"
  run "mkdir -p '$dir'"
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: render $template -> $dest with REPO=$REPO"
    return
  fi
  tmp="$(mktemp)"
  awk -v repo="$REPO" '{ gsub(/__REPO__/, repo); print }' "$template" > "$tmp"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    say "  ok (already rendered): $dest"
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    say "  backing up existing: $dest -> $dest.bak-$STAMP"
    mv "$dest" "$dest.bak-$STAMP"
  fi
  mv "$tmp" "$dest"
  say "  rendered: $dest"
}

# set_toml_keys <file> <approval_policy> <sandbox_mode>
set_toml_keys() {
  local file="$1" approval="$2" sandbox="$3" dir tmp
  dir="$(dirname "$file")"
  run "mkdir -p '$dir'"
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: set approval_policy=$approval, sandbox_mode=$sandbox in $file"
    return
  fi
  tmp="$(mktemp)"
  {
    printf 'approval_policy = "%s"\nsandbox_mode = "%s"\n\n' "$approval" "$sandbox"
    if [ -f "$file" ]; then
      awk '!/^(approval_policy|sandbox_mode)[[:space:]]*=/' "$file"
    fi
  } > "$tmp"
  mv "$tmp" "$file"
}

say "Repo: $REPO"
[ "$DRY_RUN" = 1 ] && say "(dry run — no changes)"
[ "$BOOTSTRAP" = 0 ] && say "(--no-bootstrap — symlinks/hook only, no tool installs)"
say "(permission profile: $PERMISSION_PROFILE)"
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

say "Obsidian spec vault:"
# Specs/plans live in the Obsidian vault (AGENTS.md §8). Ensure the folder exists so
# agents can write into it; AGENTS.md (symlinked above) tells Claude/Gemini/Codex, and
# pi/memory/USER.md tells Pi.
SPECS="$HOME/Documents/Obsidian/dalholm/Projekt/Specs"
run "mkdir -p '$SPECS'"
say "  ensured: $SPECS"
say ""

say "Claude Code skills:"
for skill in "$REPO"/skills/*/; do
  [ -d "$skill" ] || continue
  name="$(basename "$skill")"
  link "${skill%/}" "$HOME/.claude/skills/$name"
done
say ""

say "Codex skills:"
for skill in "$REPO"/skills/*/; do
  [ -d "$skill" ] || continue
  name="$(basename "$skill")"
  link "${skill%/}" "$HOME/.codex/skills/$name"
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
# Configs live at fixed paths under ~/.pi/agent. models.json can be symlinked; the
# hermes config is rendered at install time so memoryDir follows this repo checkout.
link "$REPO/pi/models.json" "$HOME/.pi/agent/models.json"
render "$REPO/pi/hermes-memory-config.json" "$HOME/.pi/agent/hermes-memory-config.json"
# Data dir is redirected into the repo via memoryDir in the config — just ensure it exists.
run "mkdir -p '$REPO/pi/memory/skills' '$REPO/pi/memory/projects-memory'"
# Register our skills/ dir with Pi so the same skills trigger as in Claude Code — most
# importantly complexity-router, which decides whether/how much a task goes through
# Superpowers. Pi loads description-based skills from settings.json "skills"[]; point it
# at the repo (same source Claude uses, no copy). Idempotent, append only if absent.
if have jq; then
  PIS="$HOME/.pi/agent/settings.json"
  run "mkdir -p '$HOME/.pi/agent'"
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: add $REPO/skills to \"skills\"[] in $PIS"
  else
    [ -f "$PIS" ] || echo '{}' > "$PIS"
    tmp="$(mktemp)"
    jq --arg p "$REPO/skills" 'if (.skills // [] | index($p)) then . else .skills = ((.skills // []) + [$p]) end' \
      "$PIS" > "$tmp" && mv "$tmp" "$PIS"
    say "  pi: registered skills dir in \"skills\"[] ($REPO/skills)"
  fi
fi
if have pi; then
  if pi list 2>/dev/null | grep -q 'pi-hermes-memory'; then
    say "  ok (extension already installed)"
  elif [ "$BOOTSTRAP" = 1 ]; then
    pi_install "npm:pi-hermes-memory" "pi-hermes-memory"
  else
    say "  extension not installed — run: pi install npm:pi-hermes-memory"
  fi
else
  say "  pi not found on PATH — open a new shell, then: pi install npm:pi-hermes-memory"
fi

# Additional Pi extensions. Quality gates (lens/simplify), model-tiered subagents,
# research (web-access), MCP bridge, interactive prompts (ask-user/goal), and
# robustness for local LM Studio runs (lean-ctx/handoff-rebase). See pi/README.md
# for why each is here. Same idempotent pattern as hermes-memory above.
PI_PACKAGES="pi-subagents pi-lens pi-lean-ctx pi-web-access pi-goal pi-ask-user pi-simplify pi-mcp-adapter pi-handoff-rebase"
if have pi; then
  for pkg in $PI_PACKAGES; do
    if pi list 2>/dev/null | grep -q "$pkg"; then
      say "  ok (extension already installed): $pkg"
    elif [ "$BOOTSTRAP" = 1 ]; then
      pi_install "npm:$pkg" "$pkg"
    else
      say "  extension not installed — run: pi install npm:$pkg"
    fi
  done
else
  say "  pi not on PATH — open a new shell, then install each: $PI_PACKAGES"
fi
say ""

say "Superpowers (cross-harness skills framework):"
# Superpowers supports many harnesses. OpenCode (a config edit) and Pi (a CLI command)
# can be scripted; Claude Code and Codex install via in-session slash commands, so for
# those we just print the steps.

# OpenCode: add the plugin to opencode.jsonc's plugin[] array (idempotent).
SP_OC="superpowers@git+https://github.com/obra/superpowers.git"
OCJ="$HOME/.config/opencode/opencode.jsonc"
if have jq && [ -f "$OCJ" ]; then
  if grep -q 'obra/superpowers' "$OCJ"; then
    say "  ok (opencode: superpowers already in plugin[])"
  elif [ "$DRY_RUN" = 1 ]; then
    say "  would: add superpowers to plugin[] in $OCJ"
  elif jq -e . "$OCJ" >/dev/null 2>&1; then
    tmp="$(mktemp)"
    jq --arg p "$SP_OC" '.plugin = ((.plugin // []) + [$p])' "$OCJ" > "$tmp" && mv "$tmp" "$OCJ"
    say "  opencode: added superpowers to plugin[]"
  else
    say "  opencode: $OCJ has comments jq can't parse — add \"$SP_OC\" to plugin[] manually"
  fi
fi

# Pi: install from git (network op — gated behind bootstrap like the other installs).
if have pi; then
  if pi list 2>/dev/null | grep -q 'superpowers'; then
    say "  ok (pi: superpowers already installed)"
  elif [ "$BOOTSTRAP" = 1 ]; then
    pi_install "git:github.com/obra/superpowers" "superpowers"
  else
    say "  pi: run 'pi install git:github.com/obra/superpowers'"
  fi
else
  say "  pi: not on PATH yet — later run 'pi install git:github.com/obra/superpowers'"
fi

# Claude Code + Codex: in-session slash commands — can't be scripted from a shell.
if grep -q 'superpowers' "$HOME/.claude/plugins/known_marketplaces.json" 2>/dev/null; then
  say "  ok (claude: superpowers marketplace already added)"
else
  say "  claude — run in a Claude Code session:"
  say "    /plugin marketplace add obra/superpowers-marketplace"
  say "    /plugin install superpowers@superpowers-marketplace"
fi
say "  codex — run in a Codex CLI session: /plugins  (search 'superpowers' -> Install)"
say ""

say "Ponytail (minimal implementation layer):"
# Ponytail is kept separate from Superpowers: Superpowers controls process; Ponytail
# shapes implementation/review. The local AGENTS.md and skills/ponytail already provide
# instruction-level coverage. Install the upstream plugin where lifecycle hooks/commands
# are useful.
if have pi; then
  if pi list 2>/dev/null | grep -q 'ponytail'; then
    say "  ok (pi: ponytail already installed)"
  elif [ "$BOOTSTRAP" = 1 ]; then
    pi_install "git:github.com/DietrichGebert/ponytail" "ponytail"
  else
    say "  pi: run 'pi install git:github.com/DietrichGebert/ponytail'"
  fi
else
  say "  pi: not on PATH yet — later run 'pi install git:github.com/DietrichGebert/ponytail'"
fi
say "  claude — run in a Claude Code session:"
say "    /plugin marketplace add DietrichGebert/ponytail"
say "    /plugin install ponytail@ponytail"
say "  codex — run once, then install from /plugins and trust hooks:"
say "    codex plugin marketplace add DietrichGebert/ponytail"
say "    codex"
say ""

say "Permissions ($PERMISSION_PROFILE):"
# These configs hold machine state (theme/auth), so they can't be symlinked — we merge
# the permission keys for the chosen profile. Idempotent and reversible.

# Claude Code.
if have jq; then
  CSET="$HOME/.claude/settings.json"
  run "mkdir -p '$HOME/.claude'"
  if [ "$PERMISSION_PROFILE" = "safe" ]; then
    CLAUDE_MODE="default"
  else
    CLAUDE_MODE="bypassPermissions"
  fi
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: set permissions.defaultMode=$CLAUDE_MODE in $CSET"
  else
    [ -f "$CSET" ] || echo '{}' > "$CSET"
    tmp="$(mktemp)"
    jq --arg mode "$CLAUDE_MODE" '.permissions = (.permissions // {}) | .permissions.defaultMode = $mode' \
      "$CSET" > "$tmp" && mv "$tmp" "$CSET"
    say "  claude: permissions.defaultMode = $CLAUDE_MODE"
  fi
else
  say "  jq not found — set permissions.defaultMode manually in ~/.claude/settings.json"
fi

# Codex. These are top-level TOML keys, so they MUST precede any [table] header.
CXT="$HOME/.codex/config.toml"
if [ "$PERMISSION_PROFILE" = "safe" ]; then
  CODEX_APPROVAL="on-request"
  CODEX_SANDBOX="workspace-write"
else
  CODEX_APPROVAL="never"
  CODEX_SANDBOX="danger-full-access"
fi
set_toml_keys "$CXT" "$CODEX_APPROVAL" "$CODEX_SANDBOX"
say "  codex: approval_policy=$CODEX_APPROVAL, sandbox_mode=$CODEX_SANDBOX"

# OpenCode. opencode.jsonc is JSON-clean today; if comments are
# added later jq can't parse it, so we detect and fall back to a manual hint.
OCJ="$HOME/.config/opencode/opencode.jsonc"
if have jq && [ -f "$OCJ" ]; then
  if [ "$PERMISSION_PROFILE" = "safe" ]; then
    OPENCODE_PERMISSION="ask"
  else
    OPENCODE_PERMISSION="allow"
  fi
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: set permission.{edit,bash,webfetch}=$OPENCODE_PERMISSION in $OCJ"
  elif jq -e . "$OCJ" >/dev/null 2>&1; then
    tmp="$(mktemp)"
    jq --arg p "$OPENCODE_PERMISSION" '.permission = ((.permission // {}) + {edit:$p,bash:$p,webfetch:$p})' \
      "$OCJ" > "$tmp" && mv "$tmp" "$OCJ"
    say "  opencode: permission edit/bash/webfetch = $OPENCODE_PERMISSION"
  else
    say "  opencode: $OCJ has comments jq can't parse — set permission block manually"
  fi
else
  say "  opencode config not found (or no jq) — skipping"
fi

# Pi: project trust.
if have jq; then
  PIS="$HOME/.pi/agent/settings.json"
  run "mkdir -p '$HOME/.pi/agent'"
  if [ "$PERMISSION_PROFILE" = "safe" ]; then
    PI_TRUST="ask"
  else
    PI_TRUST="always"
  fi
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: set defaultProjectTrust=$PI_TRUST in $PIS"
  else
    [ -f "$PIS" ] || echo '{}' > "$PIS"
    tmp="$(mktemp)"
    jq --arg trust "$PI_TRUST" '.defaultProjectTrust = $trust' "$PIS" > "$tmp" && mv "$tmp" "$PIS"
    say "  pi: defaultProjectTrust = $PI_TRUST"
  fi
fi
say ""

say "Done. Restart your agent so it re-reads global config."
say "First Pi run: '/memory-index-sessions' to index past sessions for search."
