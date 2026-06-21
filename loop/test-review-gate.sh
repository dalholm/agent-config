#!/usr/bin/env bash
# test-review-gate.sh — focused test for review-gate.py (Slice 3).
#
# Hermetic: injects the diff and the reviewer's text via REVIEW_*_OVERRIDE, so no git repo
# and no CLI are needed. Asserts that a BLOCK verdict demotes a `done` result to `blocked`
# (and drops the merge), a PASS leaves it alone, and the gate no-ops on empty diffs and on
# already-blocked results.
#
# Run: ./loop/test-review-gate.sh   (exit 0 = all pass)

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

fails=0
check() { if [ "$2" = "$3" ]; then echo "  ok: $1"; else
  echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails+1)); fi; }

R="$TMP/result.json"
done_result() { cat > "$R" <<'EOF'
{"status":"done","task_id":"T-050","repo":"/x","branch":"auto/T-050","merge_to_main":true}
EOF
}
status_of() { python3 -c "import json;print(json.load(open('$R'))['status'])"; }
has_merge() { python3 -c "import json;print('merge_to_main' in json.load(open('$R')))"; }

echo "test: BLOCK verdict demotes a done result to blocked"
done_result
CYCLE_RESULT="$R" REVIEW_DIFF_OVERRIDE="+ change" REVIEW_TEXT_OVERRIDE=$'Subtle bug.\nVERDICT: BLOCK' \
  python3 "$DIR/review-gate.py" >/dev/null
check "status -> blocked"        "blocked" "$(status_of)"
check "merge_to_main dropped"    "False"   "$(has_merge)"

echo "test: PASS verdict leaves a done result untouched"
done_result
CYCLE_RESULT="$R" REVIEW_DIFF_OVERRIDE="+ change" REVIEW_TEXT_OVERRIDE=$'Looks correct.\nVERDICT: PASS' \
  python3 "$DIR/review-gate.py" >/dev/null
check "status stays done"        "done"    "$(status_of)"

echo "test: empty diff passes without review"
done_result
CYCLE_RESULT="$R" REVIEW_DIFF_OVERRIDE="" REVIEW_TEXT_OVERRIDE="VERDICT: BLOCK" \
  python3 "$DIR/review-gate.py" >/dev/null
check "empty diff -> stays done" "done"    "$(status_of)"

echo "test: an already-blocked result is not re-reviewed"
cat > "$R" <<'EOF'
{"status":"blocked","task_id":"T-051","reason":"x"}
EOF
CYCLE_RESULT="$R" REVIEW_DIFF_OVERRIDE="+x" REVIEW_TEXT_OVERRIDE="VERDICT: BLOCK" \
  python3 "$DIR/review-gate.py" >/dev/null
check "blocked stays blocked"    "blocked" "$(status_of)"

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILURES"; exit 1; fi
