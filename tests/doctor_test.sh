#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

safe_report="$(
  node "$repo/scripts/agent-safety.mjs" doctor \
    --profile safe \
    --format json
)"

node -e '
const report = JSON.parse(process.argv[1]);
if (report.healthy !== true) throw new Error("the repository safety controls are unhealthy");
if (!report.checks.every((check) => check.status === "pass")) {
  throw new Error("a repository safety check did not pass");
}
' "$safe_report"

test_home="$(mktemp -d)"
trap 'rm -rf "$test_home"' EXIT

set +e
uninstalled_report="$(
  HOME="$test_home" node "$repo/scripts/agent-safety.mjs" doctor \
    --profile auto-approve \
    --format json
)"
uninstalled_status=$?
set -e

if [ "$uninstalled_status" -ne 1 ]; then
  echo "auto-approve doctor did not reject missing installed enforcement" >&2
  exit 1
fi

node -e '
const report = JSON.parse(process.argv[1]);
if (report.healthy !== false) throw new Error("missing enforcement was reported healthy");
if (!report.checks.some((check) => check.status === "fail")) {
  throw new Error("the unhealthy report did not expose a failed check");
}
' "$uninstalled_report"

mkdir -p \
  "$test_home/.config/agent-config" \
  "$test_home/.local/bin" \
  "$test_home/.claude"
ln -s "$repo/safety-policy.json" \
  "$test_home/.config/agent-config/safety-policy.json"
ln -s "$repo/scripts/agent-safety.mjs" \
  "$test_home/.local/bin/agent-safety"
printf '%s\n' \
  '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"PLACEHOLDER"}]}]}}' \
  | sed "s|PLACEHOLDER|$repo/hooks/deny-dangerous.sh|" \
  > "$test_home/.claude/settings.json"

set +e
misplaced_report="$(
  HOME="$test_home" node "$repo/scripts/agent-safety.mjs" doctor \
    --profile auto-approve \
    --preflight true \
    --format json
)"
misplaced_status=$?
set -e

if [ "$misplaced_status" -ne 1 ]; then
  echo "doctor accepted a guard outside PreToolUse/Bash" >&2
  exit 1
fi

node -e '
const report = JSON.parse(process.argv[1]);
const adapter = report.checks.find((check) => check.name === "claude-guard-adapter");
if (adapter?.status !== "fail") {
  throw new Error("misplaced Claude guard was not identified");
}
' "$misplaced_report"

node --input-type module -e '
import { readFile } from "node:fs/promises";
import { runDoctor } from "./scripts/safety-doctor.mjs";
const policy = JSON.parse(await readFile("./safety-policy.json", "utf8"));
policy.profiles["auto-approve"].doctorScope = "installed-proflie";
const report = await runDoctor(policy, "auto-approve");
if (report.healthy !== false) {
  throw new Error("an unknown doctor scope degraded to repository-only checks");
}
const scope = report.checks.find((check) => check.name === "doctor-scope");
if (scope?.status !== "fail") {
  throw new Error("the unknown doctor scope was not identified");
}
'
