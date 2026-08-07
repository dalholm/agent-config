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
GUARD_HOOK="$REPO/hooks/deny-dangerous.sh"

say() { printf '%s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
safety_profile_field() {
  local harness="$1" field="$2" resolved
  resolved="$(
    node "$REPO/scripts/agent-safety.mjs" profile \
      --profile safe \
      --harness "$harness" \
      --format json
  )"
  node -e '
  const profile = JSON.parse(process.argv[1]);
  const value = profile[process.argv[2]];
  if (typeof value !== "string" && typeof value !== "boolean") {
    throw new Error(`missing scalar profile field ${process.argv[2]}`);
  }
  process.stdout.write(String(value));
  ' "$resolved" "$field"
}
run() {
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: $*"
  else
    eval "$*"
  fi
}

HERMES_COORDINATOR_HOMES=()
add_hermes_coordinator_home() {
  local candidate="$1" resolved existing
  if ! resolved="$(
    HOME="$HOME" HERMES_HOME="$candidate" \
      node "$REPO/scripts/resolve-hermes-home.mjs" 2>/dev/null
  )"; then
    say "  keep (Hermes home is unavailable or unsafe): $candidate"
    return 0
  fi
  if [ "${#HERMES_COORDINATOR_HOMES[@]}" -gt 0 ]; then
    for existing in "${HERMES_COORDINATOR_HOMES[@]}"; do
      [ "$existing" = "$resolved" ] && return 0
    done
  fi
  HERMES_COORDINATOR_HOMES+=("$resolved")
}

collect_hermes_coordinator_homes() {
  local candidate
  if ! have node; then
    say "  keep (node unavailable; cannot validate Hermes homes)"
    return 0
  fi
  if [ -n "${HERMES_HOME:-}" ]; then
    add_hermes_coordinator_home "$HERMES_HOME"
  fi
  for candidate in "$HOME/.hermes" "$HOME/.hermes/profiles"/*; do
    [ -d "$candidate" ] || continue
    add_hermes_coordinator_home "$candidate"
  done
}

# Resolve the safe state before removing any enforcement. If the authority cannot be
# loaded, fail closed and leave the existing installation untouched.
if [ "$KEEP_PERMISSIONS" = 0 ]; then
  CLAUDE_MODE="$(safety_profile_field claude permissionMode)"
  CODEX_APPROVAL="$(safety_profile_field codex approvalPolicy)"
  CODEX_SANDBOX="$(safety_profile_field codex sandbox)"
  OPENCODE_PERMISSION="$(safety_profile_field opencode permission)"
  PI_TRUST="$(safety_profile_field pi projectTrust)"
  if ! have jq && {
    [ -f "$HOME/.claude/settings.json" ] ||
      [ -f "$HOME/.config/opencode/opencode.jsonc" ] ||
      [ -f "$HOME/.pi/agent/settings.json" ]
  }; then
    say "Cannot reset permissive JSON settings without jq; nothing was removed."
    exit 2
  fi
  if have jq; then
    for settings_file in \
      "$HOME/.claude/settings.json" \
      "$HOME/.config/opencode/opencode.jsonc" \
      "$HOME/.pi/agent/settings.json"; do
      [ -f "$settings_file" ] || continue
      if ! jq -e . "$settings_file" >/dev/null 2>&1; then
        say "Cannot safely reset $settings_file; nothing was removed."
        exit 2
      fi
    done
  fi
fi

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
remove_repo_symlink "$HOME/.config/opencode/AGENTS.md"
say ""

say "Provider-independent model routing:"
remove_repo_symlink "$HOME/.config/agent-config/model-routing.json"
remove_repo_symlink "$HOME/.local/bin/agent-model-route"
say ""

say "Safety authority:"
remove_repo_symlink "$HOME/.config/agent-config/safety-policy.json"
remove_repo_symlink "$HOME/.local/bin/agent-safety"
say ""

say "Hermes development coordinator:"
collect_hermes_coordinator_homes
if [ "${#HERMES_COORDINATOR_HOMES[@]}" -gt 0 ]; then
  for coordinator_home in "${HERMES_COORDINATOR_HOMES[@]}"; do
    HERMES_SOUL_ARGS=(--action remove --soul "$coordinator_home/SOUL.md")
    [ "$DRY_RUN" = 1 ] && HERMES_SOUL_ARGS+=(--dry-run)
    if ! node "$REPO/scripts/manage-hermes-soul.mjs" "${HERMES_SOUL_ARGS[@]}"; then
      say "  keep (could not safely update coordinator SOUL): $coordinator_home/SOUL.md"
    fi
  done
fi
say ""

say "Skill symlinks:"
for skill in "$REPO"/skills/*/; do
  [ -d "$skill" ] || continue
  name="$(basename "$skill")"
  remove_repo_symlink "$HOME/.claude/skills/$name"
  remove_repo_symlink "$HOME/.codex/skills/$name"
  remove_repo_symlink "$HOME/.hermes/skills/$name"
  if [ "${#HERMES_COORDINATOR_HOMES[@]}" -gt 0 ]; then
    for coordinator_home in "${HERMES_COORDINATOR_HOMES[@]}"; do
      remove_repo_symlink "$coordinator_home/skills/$name"
    done
  fi
done
say ""

say "Claude hook:"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if have jq && [ -f "$CLAUDE_SETTINGS" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    say "  would: remove UserPromptSubmit hook command $HOOK from $CLAUDE_SETTINGS"
    say "  would: remove PreToolUse hook command $GUARD_HOOK from $CLAUDE_SETTINGS"
  else
    tmp="$(mktemp)"
    jq --arg hook "$HOOK" --arg guard "$GUARD_HOOK" '
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
      end |
      if .hooks.PreToolUse then
        .hooks.PreToolUse |=
          map(
            .hooks = ((.hooks // []) | map(select(.command != $guard)))
          )
          | .hooks.PreToolUse |= map(select((.hooks // []) | length > 0))
          | if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end
          | if (.hooks | length) == 0 then del(.hooks) else . end
      else
        .
      end
    ' "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
    say "  removed repo hooks from: $CLAUDE_SETTINGS"
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
remove_repo_symlink "$HOME/.pi/agent/node_modules"
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
      say "  would: set Claude permissions.defaultMode=$CLAUDE_MODE"
    else
      tmp="$(mktemp)"
      jq --arg mode "$CLAUDE_MODE" \
        '.permissions = (.permissions // {}) | .permissions.defaultMode = $mode' \
        "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"
      say "  claude: permissions.defaultMode = $CLAUDE_MODE"
    fi
  fi

  CODEX_CONFIG="$HOME/.codex/config.toml"
  if [ -f "$CODEX_CONFIG" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say "  would: set Codex approval_policy=$CODEX_APPROVAL, sandbox_mode=$CODEX_SANDBOX"
    else
      tmp="$(mktemp)"
      {
        printf 'approval_policy = "%s"\nsandbox_mode = "%s"\n\n' \
          "$CODEX_APPROVAL" "$CODEX_SANDBOX"
        awk '!/^(approval_policy|sandbox_mode)[[:space:]]*=/' "$CODEX_CONFIG"
      } > "$tmp"
      mv "$tmp" "$CODEX_CONFIG"
      say "  codex: approval_policy=$CODEX_APPROVAL, sandbox_mode=$CODEX_SANDBOX"
    fi
  fi

  if have jq && [ -f "$OPENCODE_SETTINGS" ] && jq -e . "$OPENCODE_SETTINGS" >/dev/null 2>&1; then
    if [ "$DRY_RUN" = 1 ]; then
      say "  would: set OpenCode permission edit/bash/webfetch=$OPENCODE_PERMISSION"
    else
      tmp="$(mktemp)"
      jq --arg permission "$OPENCODE_PERMISSION" \
        '.permission = ((.permission // {}) + {edit:$permission,bash:$permission,webfetch:$permission})' \
        "$OPENCODE_SETTINGS" > "$tmp" && mv "$tmp" "$OPENCODE_SETTINGS"
      say "  opencode: permission edit/bash/webfetch = $OPENCODE_PERMISSION"
    fi
  fi

  if have jq && [ -f "$PI_SETTINGS" ]; then
    if [ "$DRY_RUN" = 1 ]; then
      say "  would: set Pi defaultProjectTrust=$PI_TRUST"
    else
      tmp="$(mktemp)"
      jq --arg trust "$PI_TRUST" '.defaultProjectTrust = $trust' \
        "$PI_SETTINGS" > "$tmp" && mv "$tmp" "$PI_SETTINGS"
      say "  pi: defaultProjectTrust = $PI_TRUST"
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
