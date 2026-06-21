#!/usr/bin/env bash
# test-claim-task.sh — focused behaviour test for claim-task.sh's resume/rescue ladder.
#
# Runs claim-task.sh against synthetic Auto Tasks.md fixtures (AUTO_TASKS override) and
# asserts the last-ditch rescue rung: 2 local resumes, then one strong-CLI rescue attempt,
# then park in Blocked. Also checks the claim-mode sidecar each path writes.
#
# Run: ./loop/test-claim-task.sh   (exit 0 = all pass)

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "  ok: $1"; else
    echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails+1)); fi
}

# A skeleton task list with one task in In progress at a given resume-attempts value.
fixture_inprogress() { # fixture_inprogress <attempts>
  cat <<EOF
# Auto Tasks
## Queue
<!-- c -->
- [ ] **T-009** A queued fallback task \`prio:med\`
  - **Done when:** trivially done
  - **Branch:** auto/T-009-x
## In progress
<!-- c -->
- [/] **T-005** A stuck task \`prio:high\`
  - resume-attempts: $1
  - **Done when:** something
  - **Branch:** auto/T-005-x
## Blocked / escalated to me
<!-- c -->
## Done
EOF
}

# Hermetic routing fixture so model-routing assertions don't depend on the real config.
ROUTING="$TMP/routing.json"
cat > "$ROUTING" <<'EOF'
{ "default_class": "coding-general", "fallback_model": "lmstudio/FALLBACK",
  "classes": { "mechanical-small": "lmstudio/SMALL", "coding-general": "lmstudio/GENERAL" } }
EOF

run_claim() { # run_claim <fixturefile> ; echoes claimed id. mode/model land in $TMP after.
  rm -f "$TMP/mode" "$TMP/model"
  CLAIM_MODE_FILE="$TMP/mode" CLAIM_MODEL_FILE="$TMP/model" MODELS_ROUTING="$ROUTING" \
    AUTO_TASKS="$1" python3 "$DIR/claim-task.sh" 12345
}
read_mode() { cat "$TMP/mode" 2>/dev/null || echo MISSING; }
read_model() { cat "$TMP/model" 2>/dev/null || echo MISSING; }

echo "test: 2 prior resumes -> third attempt is a RESCUE (not parked)"
F="$TMP/a.md"; fixture_inprogress 2 > "$F"
ID="$(run_claim "$F")"; MODE="$(read_mode)"
check "claims the stuck task"        "T-005"  "$ID"
check "mode is rescue"               "rescue" "$MODE"
check "attempts bumped to 3"         "1"      "$(grep -c 'resume-attempts: 3' "$F")"
check "still in In progress (not parked)" "0" "$(awk '/## Blocked/{f=1} f&&/\*\*T-005\*\*/{c++} END{print c+0}' "$F")"

echo "test: 3 prior resumes -> rescue already spent -> PARK in Blocked"
F="$TMP/b.md"; fixture_inprogress 3 > "$F"
ID="$(run_claim "$F")"
check "falls through to queue task"  "T-009"  "$ID"
check "stuck task moved to Blocked"  "1"      "$(awk '/## Blocked/{f=1} f&&/\*\*T-005\*\*/{c++} END{print c+0}' "$F")"

echo "test: fresh queue claim -> mode local"
F="$TMP/c.md"; cat > "$F" <<'EOF'
# Auto Tasks
## Queue
<!-- c -->
- [ ] **T-009** A queued task `prio:med`
  - **Done when:** x
  - **Branch:** auto/T-009-x
## In progress
<!-- c -->
## Blocked / escalated to me
<!-- c -->
## Done
EOF
ID="$(run_claim "$F")"; MODE="$(read_mode)"
check "claims queued task"           "T-009"  "$ID"
check "mode is local"                "local"  "$MODE"

echo "test: a builder:strong task claims straight into rescue mode (attempt 1)"
F="$TMP/d.md"; cat > "$F" <<'EOF'
# Auto Tasks
## Queue
<!-- c -->
- [ ] **T-020** Heavy phase `prio:high` `builder:strong` `repo:/x`
  - **Done when:** x
  - **Branch:** auto/T-020-x
## In progress
<!-- c -->
## Blocked / escalated to me
<!-- c -->
## Done
EOF
ID="$(run_claim "$F")"; MODE="$(read_mode)"
check "claims the strong task"       "T-020"  "$ID"
check "mode is rescue from attempt 1" "rescue" "$MODE"

echo "test: model routing — default class -> coding-general model"
F="$TMP/m1.md"; cat > "$F" <<'EOF'
# Auto Tasks
## Queue
<!-- c -->
- [ ] **T-030** A normal task `prio:med`
  - **Done when:** x
  - **Branch:** auto/T-030-x
## In progress
<!-- c -->
## Blocked / escalated to me
<!-- c -->
## Done
EOF
run_claim "$F" >/dev/null; check "default class -> general model" "lmstudio/GENERAL" "$(read_model)"

echo "test: model routing — class:mechanical-small -> small model"
F="$TMP/m2.md"; cat > "$F" <<'EOF'
# Auto Tasks
## Queue
<!-- c -->
- [ ] **T-031** Tiny mechanical task `prio:med` `class:mechanical-small`
  - **Done when:** x
  - **Branch:** auto/T-031-x
## In progress
<!-- c -->
## Blocked / escalated to me
<!-- c -->
## Done
EOF
run_claim "$F" >/dev/null; check "mechanical-small -> small model" "lmstudio/SMALL" "$(read_model)"

echo "test: model routing — unknown class -> fallback model"
F="$TMP/m3.md"; cat > "$F" <<'EOF'
# Auto Tasks
## Queue
<!-- c -->
- [ ] **T-032** Odd task `prio:med` `class:nonsense-xyz`
  - **Done when:** x
  - **Branch:** auto/T-032-x
## In progress
<!-- c -->
## Blocked / escalated to me
<!-- c -->
## Done
EOF
run_claim "$F" >/dev/null; check "unknown class -> fallback model" "lmstudio/FALLBACK" "$(read_model)"

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILURES"; exit 1; fi
