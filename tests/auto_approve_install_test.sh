#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_home="$(mktemp -d)"
invalid_home="$(mktemp -d)"
trap 'rm -rf "$test_home" "$invalid_home"' EXIT

mkdir -p "$invalid_home/.config/opencode"
printf '%s\n' '{ // JSONC comments require a non-jq adapter' '}' \
  > "$invalid_home/.config/opencode/opencode.jsonc"

set +e
HOME="$invalid_home" "$repo/install.sh" \
  --no-bootstrap \
  --auto-approve >/dev/null 2>&1
invalid_status=$?
set -e

if [ "$invalid_status" -eq 0 ]; then
  echo "auto-approve accepted an unverifiable OpenCode configuration" >&2
  exit 1
fi

if grep -Fq 'sandbox_mode = "danger-full-access"' \
    "$invalid_home/.codex/config.toml" 2>/dev/null; then
  echo "auto-approve changed permissions before preflight completed" >&2
  exit 1
fi

if jq -e '.permissions.defaultMode == "bypassPermissions"' \
    "$invalid_home/.claude/settings.json" >/dev/null 2>&1; then
  echo "auto-approve changed Claude permissions before preflight completed" >&2
  exit 1
fi

mkdir -p "$test_home/.config/opencode"
printf '{}\n' > "$test_home/.config/opencode/opencode.jsonc"

set +e
dry_run_output="$(
  HOME="$test_home" "$repo/install.sh" \
    --dry-run \
    --no-bootstrap \
    --auto-approve 2>&1
)"
dry_run_status=$?
set -e

if [ "$dry_run_status" -ne 0 ]; then
  echo "auto-approve dry-run should report failed prerequisites without failing" >&2
  exit 1
fi

grep -Fq "Safety doctor: unhealthy" <<<"$dry_run_output" || {
  echo "auto-approve dry-run did not explain its missing safety prerequisites" >&2
  exit 1
}

grep -Fq "FAIL installed-policy" <<<"$dry_run_output" || {
  echo "auto-approve dry-run did not identify the missing installed policy" >&2
  exit 1
}

output="$(
  HOME="$test_home" "$repo/install.sh" \
    --no-bootstrap \
    --auto-approve
)"

grep -Fq "Safety doctor: healthy" <<<"$output" || {
  echo "auto-approve was activated without a healthy safety doctor gate" >&2
  exit 1
}

grep -Fq 'approval_policy = "never"' "$test_home/.codex/config.toml"
grep -Fq 'sandbox_mode = "danger-full-access"' "$test_home/.codex/config.toml"

jq -e --arg command "$repo/hooks/deny-dangerous.sh" '
  [.. | objects | .command? // empty] | index($command) != null
' "$test_home/.claude/settings.json" >/dev/null

installed_report="$(
  HOME="$test_home" "$test_home/.local/bin/agent-safety" doctor \
    --profile auto-approve \
    --format json
)"

node -e '
const report = JSON.parse(process.argv[1]);
for (const name of [
  "claude-permission-profile",
  "codex-permission-profile",
  "opencode-permission-profile",
  "pi-permission-profile",
]) {
  const check = report.checks.find((candidate) => candidate.name === name);
  if (check?.status !== "pass") throw new Error(`${name} was not verified`);
}
' "$installed_report"

printf '%s\n' \
  '# approval_policy = "never"' \
  '# sandbox_mode = "danger-full-access"' \
  '[profile.misleading]' \
  'approval_policy = "never"' \
  'sandbox_mode = "danger-full-access"' \
  > "$test_home/.codex/config.toml"

set +e
misleading_report="$(
  HOME="$test_home" "$test_home/.local/bin/agent-safety" doctor \
    --profile auto-approve \
    --format json
)"
misleading_status=$?
set -e

if [ "$misleading_status" -ne 1 ]; then
  echo "doctor accepted Codex profile values from comments or a table" >&2
  exit 1
fi

node -e '
const report = JSON.parse(process.argv[1]);
const codex = report.checks.find((check) => check.name === "codex-permission-profile");
if (codex?.status !== "fail") {
  throw new Error("misleading Codex TOML was not identified");
}
' "$misleading_report"
