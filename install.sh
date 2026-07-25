#!/usr/bin/env bash
#
# install.sh — wire this repo into every agent harness via symlinks.
#
# AGENTS.md is the single source of truth. We symlink each harness's global
# instruction file to it, so the content is identical everywhere and you only ever
# edit AGENTS.md. Existing files are backed up first.
#
# It also bootstraps the tools the config assumes: it installs Pi and Node/npm if
# they're missing, then installs the dependencies for the repo-owned Pi extensions.
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

# link <target> <linkpath>
link() {
  local target="$1" link="$2" dir
  dir="$(dirname "$link")"
  run "mkdir -p '$dir'"
  if [ -L "$link" ] && [ "$(readlink "$link" 2>/dev/null)" = "$target" ]; then
    say "  ok (already linked): $link"
    return
  fi
  if [ -L "$link" ]; then
    run "rm '$link'"
  elif [ -e "$link" ]; then
    say "  backing up existing: $link -> $link.bak-$STAMP"
    run "mv '$link' '$link.bak-$STAMP'"
  fi
  run "ln -sfn '$target' '$link'"
  if [ "$DRY_RUN" = 1 ]; then say "  (would link) $link -> $target"; else say "  linked: $link -> $target"; fi
}

link_skills_to() {
  local dest="$1" root skill_md skill_dir name linkpath
  shift
  for root in "$@"; do
    [ -d "$root" ] || continue
    while IFS= read -r skill_md; do
      skill_dir="$(dirname "$skill_md")"
      name="$(basename "$skill_dir")"
      linkpath="$dest/$name"
      if [ -e "$linkpath" ] && [ ! -L "$linkpath" ]; then
        say "  skip collision: $name ($linkpath exists)"
        continue
      fi
      link "$skill_dir" "$linkpath"
    done < <(find "$root" -type f -name SKILL.md | sort)
  done
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

  # Node/npm — needed by the repo-owned Pi extensions.
  if have node && have npm; then
    say "  ok: node/npm present"
  elif have brew; then
    say "  node/npm missing — installing via Homebrew"
    run "brew install node"
  else
    say "  node/npm missing and Homebrew not found — install Node manually: https://nodejs.org"
  fi

  # Pi — keep the runtime aligned with the extension API version in pi/package.json.
  PI_REQUIRED_VERSION="$(node -p "require('$REPO/pi/package.json').dependencies['@earendil-works/pi-coding-agent'].replace(/^[^0-9]*/, '')" 2>/dev/null || true)"
  PI_CURRENT_VERSION="$(pi --version 2>/dev/null || true)"
  if [ -n "$PI_REQUIRED_VERSION" ] && [ "$PI_CURRENT_VERSION" = "$PI_REQUIRED_VERSION" ]; then
    say "  ok: pi $PI_CURRENT_VERSION present"
  elif have npm && [ -n "$PI_REQUIRED_VERSION" ]; then
    if [ -n "$PI_CURRENT_VERSION" ]; then
      say "  pi $PI_CURRENT_VERSION found — updating to $PI_REQUIRED_VERSION"
    else
      say "  pi missing — installing $PI_REQUIRED_VERSION"
    fi
    run "npm install --global '@earendil-works/pi-coding-agent@$PI_REQUIRED_VERSION'"
  else
    say "  could not determine/install the required Pi version — install @earendil-works/pi-coding-agent manually"
  fi
  say ""
fi

say "Instruction files (all -> AGENTS.md):"
link "$REPO/AGENTS.md" "$HOME/.claude/CLAUDE.md"
link "$REPO/AGENTS.md" "$HOME/.gemini/GEMINI.md"
link "$REPO/AGENTS.md" "$HOME/.codex/AGENTS.md"
say ""

say "Obsidian spec vault:"
# Specs/plans live in the Obsidian vault (AGENTS.md §7). Ensure the folder exists so
# agents can write into it; the shared AGENTS.md tells every harness, including Pi.
SPECS="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/dalholm/Projects/general/specs"
run "mkdir -p '$SPECS'"
say "  ensured: $SPECS"
say ""

say "Claude Code skills:"
link_skills_to "$HOME/.claude/skills" "$REPO/skills"
say ""

say "Codex skills:"
link_skills_to "$HOME/.codex/skills" "$REPO/skills"
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
link "$REPO/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
link "$REPO/pi/models.json" "$HOME/.pi/agent/models.json"
link "$REPO/pi/extensions" "$HOME/.pi/agent/extensions"
link "$REPO/pi/themes" "$HOME/.pi/agent/themes"
link "$REPO/pi/skills" "$HOME/.pi/agent/skills"
link "$REPO/pi/node_modules" "$HOME/.pi/agent/node_modules"

if [ "$BOOTSTRAP" = 1 ]; then
  if have npm; then
    run "npm install --prefix '$REPO/pi'"
  else
    say "  npm not found — install dependencies later: npm install --prefix '$REPO/pi'"
  fi
elif [ ! -d "$REPO/pi/node_modules" ]; then
  say "  dependencies missing — run: npm install --prefix '$REPO/pi'"
fi

# Register our skills dir with Pi so the same skills trigger as in Claude Code — most
# importantly complexity-router, which selects the workflow for each task. Pi loads
# description-based skills from settings.json "skills"[]; point it at the repo (same
# source Claude uses, no copy). Also select the repo-owned theme and remove packages
# from the retired Pi setup while preserving unrelated user packages.
if have jq; then
  PIS="$HOME/.pi/agent/settings.json"
  run "mkdir -p '$HOME/.pi/agent'"
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: register $REPO/skills, set theme=github-dark-default, and remove retired Pi packages in $PIS"
  else
    [ -f "$PIS" ] || echo '{}' > "$PIS"
    tmp="$(mktemp)"
    jq --arg p "$REPO/skills" --arg old "$HOME/develop/misc/skills/skills" '
      .skills = ((.skills // []) | map(select(. != $old))) |
      (if (.skills | index($p)) then . else .skills += [$p] end) |
      .theme = "github-dark-default" |
      if .packages then
        .packages |= map(select(
          . != "npm:pi-hermes-memory" and
          . != "npm:pi-subagents" and
          . != "npm:pi-lens" and
          . != "npm:pi-lean-ctx" and
          . != "npm:pi-web-access" and
          . != "npm:pi-goal" and
          . != "npm:pi-ask-user" and
          . != "npm:pi-simplify" and
          . != "npm:pi-mcp-adapter" and
          . != "npm:pi-handoff-rebase" and
          . != "git:github.com/obra/superpowers"
        ))
      else . end
    ' \
      "$PIS" > "$tmp" && mv "$tmp" "$PIS"
    say "  pi: registered shared skills, selected theme, and removed retired packages"
  fi
fi
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
say "Pi keeps auth, sessions, and other runtime state under ~/.pi/agent."
