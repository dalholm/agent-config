#!/usr/bin/env bash
# test-finalize-strong.sh — focused test for finalize-strong-build.sh.
#
# Builds a throwaway git repo, simulates a sandboxed strong build (uncommitted changes +
# an in-repo .loop-result.json), and asserts the bridge relays the result out and commits
# the work on the branch — plus the blocked, clean-tree, no-result, and on-main cases.
#
# Run: ./loop/test-finalize-strong.sh   (exit 0 = all pass)

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "  ok: $1"; else
  echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails+1)); fi; }

# Fresh repo on a task branch with one base commit on main.
new_repo() {
  local r="$1"; rm -rf "$r"; mkdir -p "$r"; git -C "$r" init -q -b main
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  echo base > "$r/base.txt"; git -C "$r" add -A; git -C "$r" commit -q -m base
  git -C "$r" checkout -q -b auto/T-099
}
dirty() { echo work > "$1/src.txt"; }                       # an untracked change to commit
result() { printf '{"status":"%s","task_id":"T-099"}' "$2" > "$1/.loop-result.json"; }
commits_on_branch() { git -C "$1" rev-list --count HEAD; }

echo "test: done result -> relays out, commits the work, removes sidecar"
R="$TMP/r1"; new_repo "$R"; dirty "$R"; result "$R" done
bash "$DIR/finalize-strong-build.sh" "$R" ".loop-result.json" "$TMP/out1.json" T-099 >/dev/null
check "result relayed out"        "yes" "$([ -f "$TMP/out1.json" ] && echo yes || echo no)"
check "sidecar gone from repo"    "yes" "$([ ! -f "$R/.loop-result.json" ] && echo yes || echo no)"
check "work committed (2 commits)" "2"  "$(commits_on_branch "$R")"
check "tree clean after commit"   "yes" "$([ -z "$(git -C "$R" status --porcelain)" ] && echo yes || echo no)"
check "sidecar NOT committed"      "no" "$(git -C "$R" ls-files | grep -q loop-result && echo yes || echo no)"

echo "test: blocked result -> relays out, does NOT commit"
R="$TMP/r2"; new_repo "$R"; dirty "$R"; result "$R" blocked
bash "$DIR/finalize-strong-build.sh" "$R" ".loop-result.json" "$TMP/out2.json" T-099 >/dev/null
check "blocked relayed out"       "yes" "$([ -f "$TMP/out2.json" ] && echo yes || echo no)"
check "no commit (still 1)"        "1"  "$(commits_on_branch "$R")"
check "tree still dirty"          "yes" "$([ -n "$(git -C "$R" status --porcelain)" ] && echo yes || echo no)"

echo "test: no in-repo result -> no-op, no relay"
R="$TMP/r3"; new_repo "$R"; dirty "$R"
bash "$DIR/finalize-strong-build.sh" "$R" ".loop-result.json" "$TMP/out3.json" T-099 >/dev/null
check "no relay file"             "yes" "$([ ! -f "$TMP/out3.json" ] && echo yes || echo no)"
check "no commit (still 1)"        "1"  "$(commits_on_branch "$R")"

echo "test: done but on main -> relays, refuses to auto-commit"
R="$TMP/r4"; new_repo "$R"; git -C "$R" checkout -q main; dirty "$R"; result "$R" done
bash "$DIR/finalize-strong-build.sh" "$R" ".loop-result.json" "$TMP/out4.json" T-099 >/dev/null 2>&1
check "relayed out"               "yes" "$([ -f "$TMP/out4.json" ] && echo yes || echo no)"
check "main not committed (1)"     "1"  "$(commits_on_branch "$R")"

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "$fails FAILURES"; exit 1; fi
