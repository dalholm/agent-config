#!/usr/bin/env bash
# conv-log.sh — append ONE inter-agent message to logs/conversations.jsonl (JSON Lines).
#
# This is the loop's "chat transcript": every message that flows between the loop, the
# builder, the oracle, and the stronger-model CLI is recorded here, in order, so the
# dashboard can render it as a chat window.
#
# Usage:
#   conv-log.sh <from> <to> <kind> "<text>"
#   printf '%s' "$big" | conv-log.sh <from> <to> <kind> -    # text via stdin (large/unsafe text)
#
#   from/to : loop | builder | oracle | stronger-model | claude | codex
#   kind    : instruction | question | answer | result | note
#
# Never fails the caller: best-effort logging (callers should append `|| true`).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${CONV_LOG:-$SCRIPT_DIR/logs/conversations.jsonl}"

FROM="${1:-?}"; TO="${2:-?}"; KIND="${3:-msg}"; TEXT="${4:-}"
[ "$TEXT" = "-" ] && TEXT="$(cat)"

mkdir -p "$(dirname "$LOG")"
LOG="$LOG" FROM="$FROM" TO="$TO" KIND="$KIND" TEXT="$TEXT" python3 - <<'PY'
import os, json, datetime
rec = {
    "ts":   datetime.datetime.now().isoformat(timespec="seconds"),
    "from": os.environ.get("FROM", ""),
    "to":   os.environ.get("TO", ""),
    "kind": os.environ.get("KIND", ""),
    "text": os.environ.get("TEXT", ""),
}
with open(os.environ["LOG"], "a", encoding="utf-8") as f:
    f.write(json.dumps(rec, ensure_ascii=False) + "\n")
PY
