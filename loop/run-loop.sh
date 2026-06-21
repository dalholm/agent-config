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

# Make pi/node + the claude/codex CLIs resolvable even under launchd's minimal PATH (they
# live in nvm and ~/.local/bin, neither of which a non-interactive shell loads). Sourced
# early so the lock, claim, pi run, and ask-cli-helper child all inherit the fixed PATH.
# shellcheck source=ensure-path.sh
. "$SCRIPT_DIR/ensure-path.sh"

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
MODEL="lmstudio/qwen/qwen3.6-35b-a3b"   # BUILDER fallback — load it in LM Studio first.
# Per-task routing OVERRIDES this below: claim-task.sh resolves the task's `class:` tag
# against pi/models-routing.json and writes the chosen model to .claim-model. This pin is
# only used if routing wrote nothing (older claim / missing routing file).
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

# Let the builder read the spec/task notes that live in the Obsidian vault. pi's
# lean-ctx context layer sandboxes file reads to the project root (here agent-config),
# so ctx_read of the vault hard-fails ("path escapes project root") and the builder
# flails after specs it can't see. LEAN_CTX_EXTRA_ROOTS adds the vault's Projekt/ folder
# to lean-ctx's PathJail allow-list. Scoped to the loop only — other pi projects keep
# their tighter sandbox. ponytail: widen to the parent vault dir if specs ever link out.
export LEAN_CTX_EXTRA_ROOTS="${LEAN_CTX_EXTRA_ROOTS:-/Users/dalholm/Documents/Obsidian/dalholm/Projekt}"

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
  local msg; msg="$(cat "$PROMPT_FILE")"
  # Slice 2: if a senior junior-plan was cached for this task, append it to the builder's
  # message. Local models follow inline instructions far better than "go read this file".
  if [ -n "${PLAN_FILE:-}" ] && [ -s "${PLAN_FILE:-/nonexistent}" ]; then
    msg="$msg

---
## Junior plan for $CLAIMED — senior-written, FOLLOW IT
A stronger model wrote the plan and acceptance tests below. Implement TO those tests; they
are authoritative — do NOT modify or weaken them. Full copy on disk: $PLAN_FILE

$(cat "$PLAN_FILE")"
  fi
  local cmd=(pi -p --model "$MODEL" "$msg")
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
  echo "ERROR: 'pi' not found on PATH even after ensure-path.sh. Is pi installed as an" \
       "nvm-global package? Set PI_BIN_DIR to its bin dir, or reinstall with 'npm i -g pi'." \
       | tee -a "$LOG_FILE"
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
# Per-task builder model routed by claim-task.sh from the task's class. Fall back to the
# pin above if routing wrote nothing. (Only used for local cycles; rescue uses the CLI.)
CLAIMED_MODEL="$(cat "$SCRIPT_DIR/.claim-model" 2>/dev/null || true)"
[ -n "$CLAIMED_MODEL" ] && MODEL="$CLAIMED_MODEL"
echo "[$(date)] builder model: $MODEL (mode: $CYCLE_MODE)" | tee -a "$LOG_FILE"
# The claimed task's repo (if any). A strong-CLI build must run with cwd = this repo:
# codex's workspace-write sandbox only allows writes under cwd, so building from the loop
# dir would let codex read the spec vault but fail every write to the target repo.
CYCLE_REPO="$(cat "$SCRIPT_DIR/.claim-repo" 2>/dev/null || true)"
# The task's branch (claim-task.sh wrote it from the `Branch:` line). The shell owns all
# git: it checks this branch out before a strong build, because codex's sandbox makes .git
# read-only — it can neither create the branch nor commit.
CYCLE_BRANCH="$(cat "$SCRIPT_DIR/.claim-branch" 2>/dev/null || true)"

# Chat transcript: record the kickoff — the instruction prompt the loop hands the builder.
# (This is "the autonomous starting a chat with instructions" shown in the dashboard.)
{ cat "$PROMPT_FILE"; printf '\n\n[cycle instruction — claimed task: %s]\n' "$CLAIMED"; } \
  | "$SCRIPT_DIR/conv-log.sh" "loop" "builder" "instruction" - || true

# Clear any stale result file so a cycle that crashes without writing one can't be
# mis-completed from a previous cycle's leftover (complete-task.sh keys off this file).
rm -f "$RESULT_FILE"

# ── Slice 2: senior plan pre-step (local cycles only) ─────────────────────────
# A strong CLI decomposes the task into a small junior plan WITH its acceptance tests; the
# local builder then implements to it (run_pi appends it to the prompt). Cached in the vault
# (inside LEAN_CTX_EXTRA_ROOTS so the builder can read it) so a resume reuses the plan
# instead of re-paying for it. Rescue cycles skip this — the strong CLI builds directly.
PLAN_FILE=""
if [ "$CYCLE_MODE" = "local" ]; then
  PLAN_DIR="${LEAN_CTX_EXTRA_ROOTS%%:*}/Auto Plans"
  PLAN_FILE="$PLAN_DIR/$CLAIMED.md"
  mkdir -p "$PLAN_DIR"
  if [ ! -s "$PLAN_FILE" ]; then
    echo "[$(date)] Slice2: generating junior plan for $CLAIMED via the strong CLI…" \
      | tee -a "$LOG_FILE"
    PLAN_PROMPT="$(sed "s/__TASK__/$CLAIMED/g" "$SCRIPT_DIR/plan-prompt.md")"
    if HELPER_MODE=consult HELPER_CHANNEL=stronger-model \
         "$SCRIPT_DIR/ask-cli-helper.sh" "$PLAN_PROMPT" >"$PLAN_FILE.tmp" 2>>"$LOG_FILE" \
         && [ -s "$PLAN_FILE.tmp" ]; then
      mv "$PLAN_FILE.tmp" "$PLAN_FILE"
      echo "[$(date)] Slice2: plan cached at $PLAN_FILE" | tee -a "$LOG_FILE"
    else
      rm -f "$PLAN_FILE.tmp"; PLAN_FILE=""
      echo "[$(date)] Slice2: plan generation failed — builder runs without one." \
        | tee -a "$LOG_FILE"
    fi
  else
    echo "[$(date)] Slice2: reusing cached junior plan $PLAN_FILE" | tee -a "$LOG_FILE"
  fi
fi

# Run one cycle on the claimed task (output → log; watch with `tail -f` or the dashboard).
# Last-ditch rescue: if the local builder has already stalled this task its allotted times,
# claim-task.sh flips the mode to "rescue" and we hand the SAME cycle prompt to the strong
# cloud CLI in write mode — it can actually finish (edit, test, commit) instead of advise.
# It writes the same .cycle-result.json, so completion below is identical for both paths.
if [ "$CYCLE_MODE" = "rescue" ]; then
  # Build with cwd = the task's repo so codex's workspace-write sandbox can write it.
  # (It can still read the vault outside cwd.) Fall back to the loop dir for repo-less tasks.
  BUILD_CWD="$SCRIPT_DIR"; REPO_BUILD=0
  if [ -n "$CYCLE_REPO" ] && [ -d "$CYCLE_REPO" ]; then BUILD_CWD="$CYCLE_REPO"; REPO_BUILD=1; fi
  echo "[$(date)] RESCUE/STRONG: building with the strong CLI (codex) in $BUILD_CWD." \
    | tee -a "$LOG_FILE"
  # When cwd = the repo, codex is sandboxed to it: it CANNOT write the loop result file
  # (it lives outside the repo) or git-commit (.git is blocked). So it writes the result
  # INSIDE the repo and leaves the work uncommitted; finalize-strong-build.sh (after the
  # build, in this normal unsandboxed shell) relays the result out and commits. Repo-less
  # tasks keep cwd = the loop dir, so codex writes the result directly — nothing to commit.
  if [ "$REPO_BUILD" = 1 ]; then
    rm -f "$BUILD_CWD/.loop-result.json"
    # The shell owns git: check out the task branch NOW (codex's sandbox can't create it).
    # Reuse an existing branch (resume) or cut a fresh one from main; never build on main.
    BR="${CYCLE_BRANCH:-auto/$CLAIMED}"
    if git -C "$BUILD_CWD" rev-parse --verify -q "$BR" >/dev/null 2>&1; then
      git -C "$BUILD_CWD" checkout -q "$BR" 2>>"$LOG_FILE" \
        || echo "[$(date)] WARN: could not switch to existing branch $BR" >>"$LOG_FILE"
    else
      git -C "$BUILD_CWD" checkout -q main 2>>"$LOG_FILE" \
        && git -C "$BUILD_CWD" checkout -q -b "$BR" 2>>"$LOG_FILE" \
        || echo "[$(date)] WARN: could not create branch $BR from main" >>"$LOG_FILE"
    fi
    echo "[$(date)] strong build on branch: $(git -C "$BUILD_CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)" \
      | tee -a "$LOG_FILE"
    RESULT_INSTR="You are ALREADY on the task branch ($BR) — the loop runner checked it out for you. Do NOT run ANY git command (no branch/checkout/add/commit): the sandbox makes .git read-only and the runner owns all git (it commits your work and merges). Just edit files in this repo, and write your result JSON to ./.loop-result.json in the repo root (you cannot write outside this repo)."
  else
    RESULT_INSTR="Write your result JSON to $RESULT_FILE as usual."
  fi
  # The strong builder cannot spawn the oracle: the oracle is another cloud CLI, and a
  # nested codex/claude fails inside the build sandbox ("in-process app-server: Operation
  # not permitted"). So tell it to BE its own skeptical reviewer and gate on tests — not
  # call ask-oracle.sh. The hard gate (green tests before status:done) is what matters.
  STRONG_NOTE="

---
# STRONG-BUILD MODE (overrides the oracle steps above)
You ARE the strong cloud builder running this cycle directly. The separate oracle is
another cloud CLI that cannot be spawned inside your sandbox — loop/ask-oracle.sh and
loop/ask-cli-helper.sh WILL fail, and that is expected, NOT a BLOCK.
- Do NOT call the oracle for kickoff or sign-off; do not treat its absence as blocked.
- Be your own skeptical, YAGNI reviewer: build only what the Done-when and the spec's
  locked decisions require; never expand scope.
- The gate is real: write status:done ONLY after the actual gate is green (e.g. cargo test).
  If you cannot get it green, write status:blocked with a one-line reason.
- $RESULT_INSTR"
  # codex is the verified strong builder (reads the vault, writes the repo, runs tests).
  ( cd "$BUILD_CWD" && \
    HELPER_CLI="${RESCUE_CLI:-codex}" HELPER_MODE=build HELPER_TIMEOUT="$MAX_CYCLE_SECONDS" \
    HELPER_CHANNEL=stronger-model \
      "$SCRIPT_DIR/ask-cli-helper.sh" "$(cat "$PROMPT_FILE")$STRONG_NOTE" ) >>"$LOG_FILE" 2>&1 \
    || echo "[$(date)] rescue CLI exited non-zero; result file (if any) decides." >>"$LOG_FILE"
  # Bridge the sandboxed build back: relay the in-repo result out to $RESULT_FILE and commit
  # the work codex couldn't (it can't write outside cwd or touch .git). No-op for repo-less
  # builds (codex wrote the result directly) and when no result was produced (crash → resume).
  if [ "$REPO_BUILD" = 1 ]; then
    "$SCRIPT_DIR/finalize-strong-build.sh" "$BUILD_CWD" ".loop-result.json" "$RESULT_FILE" "$CLAIMED" \
      >>"$LOG_FILE" 2>&1 || echo "[$(date)] finalize-strong-build had an issue; see log." >>"$LOG_FILE"
  fi
else
  run_pi
fi

# Chat transcript: record the builder's reply — its structured result (or a crash note).
if [ -f "$RESULT_FILE" ]; then
  cat "$RESULT_FILE"
else
  printf '(no result file — builder crashed or was blocked mid-cycle; see cycle log)'
fi | "$SCRIPT_DIR/conv-log.sh" "builder" "loop" "result" - || true

# ── Slice 3: senior review gate (local cycles only) ───────────────────────────
# A weak local model's "done" is the loop's least trustworthy signal. Before
# complete-task.sh can merge the branch to main, a strong CLI reviews the branch diff; on
# VERDICT: BLOCK, review-gate.py rewrites .cycle-result.json to blocked so the SAME resume
# ladder handles it (no second ladder). Rescue builds are the strong model already — not
# gated. Fail-open: an unavailable reviewer or empty diff passes, never stalls the loop.
if [ "$CYCLE_MODE" = "local" ]; then
  python3 "$SCRIPT_DIR/review-gate.py" 2>&1 | tee -a "$LOG_FILE" || true
fi

# ── Deterministic completion ──────────────────────────────────────────────────
# The agent wrote loop/.cycle-result.json (done/blocked) and did NOT edit the task
# list structure itself. The shell does all markdown surgery + the merge to main, so
# the local model can never scramble its own state file. No result file = crashed
# mid-cycle → task stays in In progress and resumes next cycle.
python3 "$SCRIPT_DIR/complete-task.sh" "$CLAIMED" 2>&1 | tee -a "$LOG_FILE"

echo "[$(date)] loop cycle end ($CLAIMED) — log: $LOG_FILE" | tee -a "$LOG_FILE"
