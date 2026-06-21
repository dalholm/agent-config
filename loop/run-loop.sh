#!/usr/bin/env bash
# run-loop.sh — run ONE cycle of the autonomous task loop.
#
# Manual trigger for now: just run `./run-loop.sh` whenever you want the agent to
# pick up the next task from "Auto Tasks.md". Wire it to a schedule later with the
# launchd plist next to this file (see README.md).
#
# It feeds loop-prompt.md to pi as a one-shot, non-interactive run. pi inherits your
# AGENTS.md, skills (router/oracle/goal-watcher) and the loop-guard extension, so the
# whole T3 autonomous machinery applies.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_FILE="$SCRIPT_DIR/loop-prompt.md"
RESULT_FILE="$SCRIPT_DIR/.cycle-result.json"   # builder writes this; chat log reads it
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# ── Single-instance lock ──────────────────────────────────────────────────────
# Never run two cycles at once. A task can take far longer than the 15-min schedule;
# every tick that fires while a cycle is still running must skip, NOT start the task
# again. (launchd already won't run two copies of the same job, but this also covers a
# manual ./run-loop.sh racing the scheduled one.) macOS has no flock(1), so we use an
# atomic mkdir lock with stale-PID recovery for crashed runs.
LOCK_DIR="$SCRIPT_DIR/.loop.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [ -f "$LOCK_DIR/pid" ] && kill -0 "$(cat "$LOCK_DIR/pid" 2>/dev/null)" 2>/dev/null; then
    echo "[$(date)] cycle already running (pid $(cat "$LOCK_DIR/pid")); skipping this tick." \
      >> "$LOG_DIR/skips.log"
    exit 0
  fi
  echo "[$(date)] stale lock (dead pid); reclaiming." >> "$LOG_DIR/skips.log"
  rm -rf "$LOCK_DIR"; mkdir "$LOCK_DIR" || { echo "lock acquire failed" >&2; exit 1; }
fi
echo "$$" > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT
# ──────────────────────────────────────────────────────────────────────────────

STAMP="$(date +%Y-%m-%dT%H-%M-%S)"
LOG_FILE="$LOG_DIR/cycle-$STAMP.log"

# Flags verified against pi's official CLI reference:
#   -p / --print          → non-interactive: print response and exit (one-shot cycle)
#   --model <provider/id> → pin the model (custom providers from ~/.pi/agent/models.json)
#   message arg           → the prompt text (we pass the whole loop-prompt as the message)
MODEL="lmstudio/qwen/qwen3.6-35b-a3b"   # BUILDER model — load it in LM Studio first
# The preference-oracle is NOT pinned here. The oracle runs on a cloud coding CLI
# (Claude, falling back to Codex) via loop/ask-oracle.sh -> loop/ask-cli-helper.sh — a
# genuinely independent voice, separate from the local builder model. No second local
# model needed; just make sure `claude` (and/or `codex`) is installed and logged in.

# Autonomy guards that REPLACE loop-guard for the loop:
#  - LOOP_GUARD_OFF=1 disables loop-guard's hard "terminate until /loopguard reset" (it
#    mistakes legitimate repeated cargo builds for a loop and kills the cycle half-done).
#  - MAX_CYCLE_SECONDS is a deterministic wall-clock cap: a cycle that runs past it is
#    killed, so a genuinely runaway pi can't grind forever. Tune to your longest build.
export LOOP_GUARD_OFF=1
MAX_CYCLE_SECONDS="${MAX_CYCLE_SECONDS:-2700}"   # 45 min

# Background watchdog: kill pi if a cycle runs past the wall-clock cap.
_watchdog() {
  local pid=$1
  ( sleep "$MAX_CYCLE_SECONDS"
    if kill -0 "$pid" 2>/dev/null; then
      echo "[$(date)] cycle exceeded ${MAX_CYCLE_SECONDS}s — terminating pi." >>"$LOG_FILE"
      kill -TERM "$pid" 2>/dev/null; sleep 10; kill -KILL "$pid" 2>/dev/null
    fi ) &
  local wd=$!
  wait "$pid" 2>/dev/null
  kill "$wd" 2>/dev/null || true
}

# Run pi with a wall-clock cap. Two modes:
#   STREAM=1 → no redirect: pi inherits the terminal (e.g. a tmux pane = a real TTY) and
#              streams token-by-token live. Used by watch-cycle.sh; tmux pipe-pane logs.
#   default  → output to the per-cycle log (watch with tail -f or the dashboard).
# Portable: prefers timeout/gtimeout, else a background kill via _watchdog.
run_pi() {
  local to; to="$(command -v timeout || command -v gtimeout || true)"
  local cmd=(pi -p --model "$MODEL" "$(cat "$PROMPT_FILE")")
  [ -n "$to" ] && cmd=("$to" -k 10 "${MAX_CYCLE_SECONDS}s" "${cmd[@]}")
  if [ "${STREAM:-0}" = 1 ]; then
    if [ -n "$to" ]; then "${cmd[@]}"; else "${cmd[@]}" & _watchdog $!; fi
  else
    if [ -n "$to" ]; then "${cmd[@]}" >>"$LOG_FILE" 2>&1
    else "${cmd[@]}" >>"$LOG_FILE" 2>&1 & _watchdog $!; fi
  fi
}

echo "[$(date)] loop cycle start" | tee -a "$LOG_FILE"

if ! command -v pi >/dev/null 2>&1; then
  echo "ERROR: 'pi' not found on PATH. Open an interactive shell or fix PATH in the" \
       "launchd plist (launchd has a minimal PATH)." | tee -a "$LOG_FILE"
  exit 127
fi

# ── Deterministic claim ───────────────────────────────────────────────────────
# The shell (not the flaky local model) moves the top Queue task into In progress
# BEFORE pi runs, so a forgetful or crashed cycle can NEVER leave it as a re-pickable
# `- [ ]` that the next tick restarts from scratch. Prints the task id, or NONE.
CLAIMED="$(python3 "$SCRIPT_DIR/claim-task.sh" "$$" 2>>"$LOG_FILE")"
if [ "$CLAIMED" = "NONE" ] || [ -z "$CLAIMED" ]; then
  echo "[$(date)] nothing to do — Queue empty and nothing in progress." | tee -a "$LOG_FILE"
  exit 0
fi
echo "[$(date)] claimed task: $CLAIMED" | tee -a "$LOG_FILE"

# claim-task.sh wrote who should execute this cycle: "local" (the pi builder) or "rescue"
# (the strong cloud CLI with write access — last-ditch after the local builder stalled).
CYCLE_MODE="$(cat "$SCRIPT_DIR/.claim-mode" 2>/dev/null || echo local)"

# Chat transcript: record the kickoff — the instruction prompt the loop hands the builder.
# (This is "the autonomous starting a chat with instructions" shown in the dashboard.)
{ cat "$PROMPT_FILE"; printf '\n\n[cycle instruction — claimed task: %s]\n' "$CLAIMED"; } \
  | "$SCRIPT_DIR/conv-log.sh" "loop" "builder" "instruction" - || true

# Clear any stale result file so a cycle that crashes without writing one can't be
# mis-completed from a previous cycle's leftover (complete-task.sh keys off this file).
rm -f "$RESULT_FILE"

# Run one cycle on the claimed task (output → log; watch with `tail -f` or the dashboard).
# Last-ditch rescue: if the local builder has already stalled this task its allotted times,
# claim-task.sh flips the mode to "rescue" and we hand the SAME cycle prompt to the strong
# cloud CLI in write mode — it can actually finish (edit, test, commit) instead of advise.
# It writes the same .cycle-result.json, so completion below is identical for both paths.
if [ "$CYCLE_MODE" = "rescue" ]; then
  echo "[$(date)] RESCUE: local builder stalled — handing cycle to strong CLI (build mode)." \
    | tee -a "$LOG_FILE"
  HELPER_MODE=build HELPER_TIMEOUT="$MAX_CYCLE_SECONDS" HELPER_CHANNEL=stronger-model \
    "$SCRIPT_DIR/ask-cli-helper.sh" "$(cat "$PROMPT_FILE")" >>"$LOG_FILE" 2>&1 \
    || echo "[$(date)] rescue CLI exited non-zero; result file (if any) decides." >>"$LOG_FILE"
else
  run_pi
fi

# Chat transcript: record the builder's reply — its structured result (or a crash note).
if [ -f "$RESULT_FILE" ]; then
  cat "$RESULT_FILE"
else
  printf '(no result file — builder crashed or was blocked mid-cycle; see cycle log)'
fi | "$SCRIPT_DIR/conv-log.sh" "builder" "loop" "result" - || true

# ── Deterministic completion ──────────────────────────────────────────────────
# The agent wrote loop/.cycle-result.json (done/blocked) and did NOT edit the task
# list structure itself. The shell does all markdown surgery + the merge to main, so
# the local model can never scramble its own state file. No result file = crashed
# mid-cycle → task stays in In progress and resumes next cycle.
python3 "$SCRIPT_DIR/complete-task.sh" "$CLAIMED" 2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] loop cycle end ($CLAIMED) — log: $LOG_FILE" | tee -a "$LOG_FILE"
