#!/usr/bin/env bash
# finalize-strong-build.sh — bridge a sandboxed strong build's output back to the loop.
#
# A strong (codex) build runs with cwd=<repo> under a workspace-write sandbox, so it
# CANNOT write the loop's result file (it lives outside the repo) or touch .git (commit
# blocked). Instead it writes its result to <repo>/<in_name> and leaves its changes
# uncommitted. This script — run by run-loop.sh in the normal, UNSANDBOXED parent shell —
# relays that result out to the loop's result path and commits the working tree on the
# build branch, so the rest of the loop (complete-task.sh: merge + bookkeeping) proceeds
# identically to a local cycle.
#
# Usage: finalize-strong-build.sh <repo> <in_name> <out_result> <task_id>
# No-op (exit 0) when the in-repo result file is absent (codex crashed → cycle resumes).

set -euo pipefail
REPO="${1:?repo}"; IN_NAME="${2:?in_name}"; OUT="${3:?out_result}"; TASK="${4:-?}"
IN="$REPO/$IN_NAME"

[ -f "$IN" ] || { echo "finalize-strong: no $IN_NAME in repo — nothing to relay"; exit 0; }

# Relay the result OUT first, so the commit below can never include the sidecar file.
mv "$IN" "$OUT"
echo "finalize-strong: relayed result -> $OUT"

STATUS="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('status','nothing'))" "$OUT" 2>/dev/null || echo nothing)"

if [ "$STATUS" != "done" ]; then
  echo "finalize-strong: status=$STATUS — leaving tree as-is (complete-task will handle it)"
  exit 0
fi

# Commit the work codex produced but could not commit (sandbox blocked .git). Guard against
# committing onto main, and skip if the tree is already clean (codex committed on some setups).
BR="$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
if [ "$BR" = "main" ] || [ "$BR" = "master" ]; then
  echo "finalize-strong: refusing to auto-commit on $BR — leaving tree for review" >&2
elif [ -n "$(git -C "$REPO" status --porcelain)" ]; then
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "loop strong-build: $TASK"
  echo "finalize-strong: committed work tree on $BR"
else
  echo "finalize-strong: tree already clean — codex committed itself"
fi
