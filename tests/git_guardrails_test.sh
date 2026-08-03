#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$repo/skills/git-guardrails-claude-code/scripts/block-dangerous-git.sh"
safety="$repo/scripts/agent-safety.mjs"

run_hook() {
  local command="$1"
  printf '{"tool_input":{"command":%s}}' \
    "$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$command")" \
    | AGENT_SAFETY_COMMAND="$safety" "$hook" 2>&1
}

for command in \
  "git push origin main" \
  "git -C /tmp push origin main" \
  "git --git-dir=.git push origin main" \
  "/usr/bin/git push origin main" \
  "git reset --hard HEAD~1" \
  "git clean -fd" \
  "git clean -d -f" \
  "git branch -D old-branch" \
  "git branch -d -f old-branch" \
  "git branch -f -d old-branch" \
  "git branch -df old-branch" \
  "git branch --delete --force old-branch" \
  "git checkout -- ." \
  "git checkout -- :/" \
  "git restore --source HEAD ." \
  "git restore :/"; do
  set +e
  output="$(run_hook "$command")"
  hook_status=$?
  set -e
  if [ "$hook_status" -ne 2 ]; then
    echo "git guard did not block a user-gated operation: $command" >&2
    exit 1
  fi
  grep -Fq "agent-safety" <<<"$output" || {
    echo "git guard did not identify the canonical authority" >&2
    exit 1
  }
done

run_hook "git status --short" >/dev/null

set +e
missing_output="$(
  printf '%s' '{"tool_input":{"command":"git push origin main"}}' \
    | AGENT_SAFETY_COMMAND="$repo/missing-agent-safety" "$hook" 2>&1
)"
missing_status=$?
set -e

if [ "$missing_status" -ne 2 ]; then
  echo "git guard did not fail closed when the safety authority was unavailable" >&2
  exit 1
fi

grep -Fq "unavailable" <<<"$missing_output" || {
  echo "git guard did not explain the missing safety authority" >&2
  exit 1
}
