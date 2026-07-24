#!/usr/bin/env bash
#
# uninstall.sh — remove the wiring created by install.sh.
#
# Default mode is conservative: remove symlinks/config entries that point at this repo
# and reset permissive agent settings. It does not uninstall external tools (Node, Pi)
# or delete repo-owned memory data.
#
# Usage:
#   ./uninstall.sh                         # remove repo wiring
#   ./uninstall.sh --dry-run               # show what would happen, change nothing
#   ./uninstall.sh --keep-permissions      # do not reset approval/sandbox settings
#
set -euo pipefail

DRY_RUN=0
KEEP_PERMISSIONS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --keep-permissions) KEEP_PERMISSIONS=1 ;;
    *)
      printf 'Unknown argument: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$REPO/hooks/router-reminder.sh"

say() { printf '%s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
run() {
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: $*"
  else
    eval "$*"
  fi
}

remove_repo_symlink() {
  local path="$1" target
  if [ ! -L "$path" ]; then
    [ -e "$path" ] && say "  keep (not a symlink): $path"
    return 0
  fi
  target="$(readlink "$path" 2>/dev/null || true)"
  case "$target" in
    "$REPO"|"$REPO"/*)
      run "rm -f '$path'"
      say "  removed: $path"
      ;;
    *)
      say "  keep (points elsewhere): $path -> $target"
      ;;
  esac
}

remove_file_if_repo_owned() {
  local path="$1"
  [ -e "$path" ] || return 0
  if grep -Fq "$REPO" "$path" 2>/dev/null; then
    run "rm -f '$path'"
    say "  removed: $path"
  else
    say "  keep (does not reference this repo): $path"
  fi
}

say "Repo: $REPO"
[ "$DRY_RUN" = 1 ] && say "(dry run — no changes)"
say ""

say "Instruction symlinks:"
remove_repo_symlink "$HOME/.claude/CLAUDE.md"
remove_repo_symlink "$HOME/.gemini/GEMINI.md"
remove_repo_symlink "$HOME/.codex/AGENTS.md"
say ""

say "Skill symlinks:"
for skill in "$REPO"/skills/*/; do
  [ -d "$skill" ] || continue
  name="$(basename "$skill")"
  remove_repo_symlink "$HOME/.claude/skills/$name"
  remove_repo_symlink "$HOME/.codex/skills/$name"
done
say ""

say "Claude hook:"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if have jq && [ -f "$CLAUDE_SETTINGS" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: remove UserPromptSubmit hook command $HOOK from $CLAUDE_SETTINGS"
  else
    tmp="$(mktemp)"
    jq --arg hook "$HOOK" '
      if .hooks.UserPromptSubmit then
        .hooks.UserPromptSubmit |=
          map(
            .hooks = ((.hooks // []) | map(select(.command != $hook)))
          )
          | .hooks.UserPromptSubmit |= map(select((.hooks // []) | length > 0))
          | if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end
          | if (.hooks | length) == 0 then del(.hooks) else . end
      else
        .
      end
    ' "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
    say "  removed hook from: $CLAUDE_SETTINGS"
  fi
else
  say "  skipped (jq or $CLAUDE_SETTINGS missing)"
fi
say ""

say "Pi config:"
remove_repo_symlink "$HOME/.pi/agent/AGENTS.md"
remove_repo_symlink "$HOME/.pi/agent/models.json"
remove_repo_symlink "$HOME/.pi/agent/extensions"
remove_repo_symlink "$HOME/.pi/agent/themes"
remove_repo_symlink "$HOME/.pi/agent/skills"
PI_SETTINGS="$HOME/.pi/agent/settings.json"
if have jq && [ -f "$PI_SETTINGS" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: remove $REPO/skills from skills[] and reset the repo theme in $PI_SETTINGS"
  else
    tmp="$(mktemp)"
    jq --arg skills "$REPO/skills" '
      if .skills then
        .skills |= map(select(. != $skills))
        | if (.skills | length) == 0 then del(.skills) else . end
      else
        .
      end |
      if .theme == "github-dark-default" then .theme = "dark" else . end
    ' "$PI_SETTINGS" > "$tmp" && mv "$tmp" "$PI_SETTINGS"
    say "  removed repo skills dir and reset repo theme in: $PI_SETTINGS"
  fi
fi
say ""

if [ "$KEEP_PERMISSIONS" = 0 ]; then
  say "Permissions reset to safer defaults:"
  OPENCODE_SETTINGS="$HOME/.config/opencode/opencode.jsonc"
  if have jq && [ -f "$CLAUDE_SETTINGS" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say "  would: set Claude permissions.defaultMode=default"
    else
      tmp="$(mktemp)"
      jq '.permissions = (.permissions // {}) | .permissions.defaultMode = "default"' \
        "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
      say "  claude: permissions.defaultMode = default"
    fi
  fi

  CODEX_CONFIG="$HOME/.codex/config.toml"
  if [ -f "$CODEX_CONFIG" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say "  would: set Codex approval_policy=on-request, sandbox_mode=workspace-write"
    else
      tmp="$(mktemp)"
      {
        printf 'approval_policy = "on-request"\nsandbox_mode = "workspace-write"\n\n'
        awk '!/^(approval_policy|sandbox_mode)[[:space:]]*=/' "$CODEX_CONFIG"
      } > "$tmp"
      mv "$tmp" "$CODEX_CONFIG"
      say "  codex: approval_policy=on-request, sandbox_mode=workspace-write"
    fi
  fi

  if have jq && [ -f "$OPENCODE_SETTINGS" ] && jq -e . "$OPENCODE_SETTINGS" >/dev/null 2>&1; then
    if [ "$DRY_RUN" = 1 ]; then
      say "  would: set OpenCode permission edit/bash/webfetch=ask"
    else
      tmp="$(mktemp)"
      jq '.permission = ((.permission // {}) + {edit:"ask",bash:"ask",webfetch:"ask"})' \
        "$OPENCODE_SETTINGS" > "$tmp" && mv "$tmp" "$OPENCODE_SETTINGS"
      say "  opencode: permission edit/bash/webfetch = ask"
    fi
  fi

  if have jq && [ -f "$PI_SETTINGS" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say "  would: set Pi defaultProjectTrust=ask"
    else
      tmp="$(mktemp)"
      jq '.defaultProjectTrust = "ask"' "$PI_SETTINGS" > "$tmp" && mv "$tmp" "$PI_SETTINGS"
      say "  pi: defaultProjectTrust = ask"
    fi
  fi
else
  say "Permissions: kept unchanged (--keep-permissions)"
fi
say ""

say "Kept:"
say "  repo data: $REPO"
say "  Pi auth, sessions, and runtime data under: $HOME/.pi/agent"
say "  backup files (*.bak-*) created by install.sh"
say ""
say "Done. Restart agent sessions so they re-read config."
