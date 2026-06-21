#!/usr/bin/env bash
# ask-cli-helper.sh — the loop's "stronger model" helper, running on a cloud coding CLI.
#
# Sends a prompt to a CLI agent and prints its answer to stdout. Two uses:
#   (a) the preference-oracle's brain — called by ask-oracle.sh (replaces local gemma).
#   (b) the "stronger model" rung of the BLOCKED protocol — the builder calls this
#       directly when local reasoning dead-ends, BEFORE escalating to the human.
#
# Order: try Claude CLI first, fall back to Codex CLI. There is NO local fallback by
# design — if neither CLI answers, this exits non-zero so the caller treats it as a
# BLOCKED and escalates to the human (that is the human gate).
#
# Every call is recorded to the chat transcript (logs/conversations.jsonl) via conv-log.sh:
# one "question" message (builder → channel) and one "answer" message (cli → builder).
#
# Usage:
#   ./ask-cli-helper.sh "<prompt>"
#   HELPER_CLI=claude ./ask-cli-helper.sh "<prompt>"   # force Claude only
#   HELPER_CLI=codex  ./ask-cli-helper.sh "<prompt>"   # force Codex only
#
# Env knobs:
#   HELPER_CLI       auto (default) | claude | codex
#   HELPER_CHANNEL   stronger-model (default) | oracle   — who the builder is talking to
#   HELPER_MODE      consult (default, READ-ONLY advice) | build (WRITE — can edit the
#                    repo, run tools, and commit). build is the loop's last-ditch rescue:
#                    a strong CLI actually finishes a task the local builder stalled on.
#   CLAUDE_BIN       claude   (override path/name)
#   CODEX_BIN        codex    (override path/name)
#   HELPER_TIMEOUT   per-call wall-clock cap in seconds (default 300 consult / 2700 build)
#
# NOTE: the exact CLI flags below are the only harness-specific bit. Verify them once
# against your installed versions (`claude --help`, `codex --help`) and adjust if needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVLOG="$SCRIPT_DIR/conv-log.sh"

# Resolve claude/codex (and pi/node) under a minimal launchd/cron PATH. See ensure-path.sh.
# shellcheck source=ensure-path.sh
. "$SCRIPT_DIR/ensure-path.sh"

PROMPT="${1:-}"
if [ -z "$PROMPT" ]; then
  echo "usage: ask-cli-helper.sh \"<prompt>\"" >&2
  exit 2
fi

CHANNEL="${HELPER_CHANNEL:-stronger-model}"
MODE="${HELPER_MODE:-consult}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CODEX_BIN="${CODEX_BIN:-codex}"
# build cycles run a full task (edit + test + commit) so they need the cycle-length cap,
# not the short consult cap.
if [ "$MODE" = "build" ]; then TIMEOUT_SECS="${HELPER_TIMEOUT:-2700}"
else TIMEOUT_SECS="${HELPER_TIMEOUT:-300}"; fi

_have() { command -v "$1" >/dev/null 2>&1; }
_log()  { printf '%s' "$2" | "$CONVLOG" "$1" "$3" "$4" - 2>/dev/null || true; }

# Wrap a command in a wall-clock cap if timeout/gtimeout exists (portable on macOS).
_cap() {
  local t; t="$(command -v timeout || command -v gtimeout || true)"
  if [ -n "$t" ]; then "$t" -k 10 "${TIMEOUT_SECS}s" "$@"; else "$@"; fi
}

# Claude Code, headless:
#   -p / --print     run non-interactively, print the result, exit.
#   consult mode     --allowedTools "Read Grep Glob" — read-only; the oracle may read
#                    preferences.md / specs but must never modify the repo.
#   build mode       --permission-mode bypassPermissions — full write access so the rescue
#                    can edit, run tests, and commit. (Verify both flag names for your build.)
run_claude() {
  _have "$CLAUDE_BIN" || return 127
  # Feed the prompt via stdin: claude's --allowedTools / --permission-mode are variadic
  # and otherwise swallow a positional prompt ("Input must be provided ... when using
  # --print"). stdin sidesteps that entirely.
  if [ "$MODE" = "build" ]; then
    printf '%s' "$PROMPT" | _cap "$CLAUDE_BIN" -p --permission-mode bypassPermissions
  else
    printf '%s' "$PROMPT" | _cap "$CLAUDE_BIN" -p --allowedTools "Read Grep Glob"
  fi
}

# Codex CLI, headless:
#   exec                       non-interactive subcommand.
#   --sandbox read-only        consult: read to reason, can't write to the repo.
#   --sandbox workspace-write  build: can edit the repo, run tools, and commit.
run_codex() {
  _have "$CODEX_BIN" || return 127
  if [ "$MODE" = "build" ]; then
    _cap "$CODEX_BIN" exec --sandbox workspace-write "$PROMPT"
  else
    _cap "$CODEX_BIN" exec --sandbox read-only "$PROMPT"
  fi
}

# Record the outgoing question (builder → oracle/stronger-model).
_log "builder" "$PROMPT" "$CHANNEL" "question"

RESPONSE=""; ANSWER_CLI="none"
get_answer() {
  case "${HELPER_CLI:-auto}" in
    claude) if RESPONSE="$(run_claude)"; then ANSWER_CLI="claude"; return 0; fi; return 1 ;;
    codex)  if RESPONSE="$(run_codex)";  then ANSWER_CLI="codex";  return 0; fi; return 1 ;;
    auto)
      if RESPONSE="$(run_claude)"; then ANSWER_CLI="claude"; return 0; fi
      echo "[ask-cli-helper] claude unavailable or failed → falling back to codex" >&2
      if RESPONSE="$(run_codex)"; then ANSWER_CLI="codex"; return 0; fi
      return 1 ;;
    *) echo "[ask-cli-helper] unknown HELPER_CLI: ${HELPER_CLI}" >&2; exit 2 ;;
  esac
}

if get_answer; then
  _log "$ANSWER_CLI" "$RESPONSE" "builder" "answer"
  printf '%s\n' "$RESPONSE"
  exit 0
else
  _log "$CHANNEL" "(no answer — both claude and codex unavailable/failed → BLOCK)" "builder" "answer"
  echo "[ask-cli-helper] both claude and codex failed — no answer (caller should BLOCK)" >&2
  exit 1
fi
