#!/usr/bin/env bash
# watch-cycle.sh — run one loop cycle in a tmux session and open a live terminal window.
#
# Why tmux: pi streams token-by-token only when stdout is a real TTY. A tmux pane is a
# TTY, so running the cycle there (with STREAM=1) gives true live streaming — unlike the
# headless `>> log` path which buffers. The full transcript is still captured to a log
# via `tmux pipe-pane`. The dashboard's "Open live window" button calls this.
#
# macOS: opens Terminal.app attached to the session. Elsewhere: prints the attach command.

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION="loop"
LOGDIR="$DIR/logs"
mkdir -p "$LOGDIR"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux not found — install it: brew install tmux" >&2
  exit 1
fi

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "tmux session '$SESSION' already running — opening it."
else
  # STREAM=1 → pi streams to the pane. Keep the pane open after the cycle so you can read
  # the result before it closes.
  tmux new-session -d -s "$SESSION" -x 220 -y 50 -c "$DIR" \
    "STREAM=1 bash '$DIR/run-loop.sh'; printf '\n[cycle ended — press Enter to close]'; read -r _"
  # Capture the live pane transcript to a log.
  tmux pipe-pane -t "$SESSION" -o "cat >> '$LOGDIR/tmux-stream.log'"
  echo "started cycle in tmux session '$SESSION'."
fi

# Pop a real Terminal window attached to the session (macOS).
if command -v osascript >/dev/null 2>&1; then
  osascript >/dev/null 2>&1 <<OSA || echo "Attach manually: tmux attach -t $SESSION"
tell application "Terminal"
  activate
  do script "tmux attach -t ${SESSION}"
end tell
OSA
else
  echo "Attach with: tmux attach -t $SESSION"
fi
