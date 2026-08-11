#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_home="$(mktemp -d)"
trap 'rm -rf "$test_home"' EXIT

mkdir -p "$test_home/.config/opencode"
printf '{}\n' > "$test_home/.config/opencode/opencode.jsonc"
mkdir -p "$test_home/.claude"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"%s/hooks/router-reminder.sh"}]}]}}\n' \
  "$repo" > "$test_home/.claude/settings.json"

grep -Fq 'scripts/agent-safety.mjs" profile' "$repo/uninstall.sh" || {
  echo "uninstall.sh does not resolve safe defaults through the safety authority" >&2
  exit 1
}

if grep -Fq 'sandbox_mode = "workspace-write"' "$repo/uninstall.sh"; then
  echo "uninstall.sh still contains an independent Codex safety policy" >&2
  exit 1
fi

HOME="$test_home" "$repo/install.sh" --no-bootstrap --auto-approve >/dev/null

test -L "$test_home/.config/agent-config/model-routing.json"
test -L "$test_home/.local/bin/agent-model-route"
test -L "$test_home/.config/agent-config/safety-policy.json"
test -L "$test_home/.local/bin/agent-safety"
test -L "$test_home/.hermes/skills/complexity-router"
test -L "$test_home/.hermes/skills/model-routing"
test -L "$test_home/.config/opencode/AGENTS.md"
test -L "$test_home/.pi/agent/node_modules"

jq -e --arg skills "$repo/skills" '(.skills.paths // []) | index($skills) != null' \
  "$test_home/.config/opencode/opencode.jsonc" >/dev/null || {
  echo "install.sh does not register the shared skills dir with OpenCode" >&2
  exit 1
}

if jq -e --arg command "$repo/hooks/router-reminder.sh" '
    [.. | objects | .command? // empty] | index($command) != null
  ' "$test_home/.claude/settings.json" >/dev/null; then
  echo "install.sh left the retired per-prompt router hook installed" >&2
  exit 1
fi

jq -e --arg command "$repo/hooks/deny-dangerous.sh" '
  [.. | objects | .command? // empty] | index($command) != null
' "$test_home/.claude/settings.json" >/dev/null

installed_route="$(
  HOME="$test_home" "$test_home/.local/bin/agent-model-route" \
    --harness codex \
    --role coder \
    --tier standard \
    --format json
)"
node -e '
const route = JSON.parse(process.argv[1]);
if (route.model !== "gpt-5.6-sol") {
  throw new Error("installed resolver did not load the canonical registry");
}
' "$installed_route"

installed_decision="$(
  HOME="$test_home" "$test_home/.local/bin/agent-safety" decide \
    --operation read \
    --mode interactive \
    --authorized false \
    --format json
)"
node -e '
const decision = JSON.parse(process.argv[1]);
if (decision.decision !== "allow") {
  throw new Error("installed safety authority did not load the canonical policy");
}
' "$installed_decision"

opencode_before="$(<"$test_home/.config/opencode/opencode.jsonc")"
printf '%s\n' \
  '{' \
  '  // Valid JSONC that jq cannot safely rewrite' \
  '  "permission": {"edit":"allow","bash":"allow","webfetch":"allow"}' \
  '}' > "$test_home/.config/opencode/opencode.jsonc"

set +e
HOME="$test_home" "$repo/uninstall.sh" >/dev/null 2>&1
jsonc_status=$?
set -e

if [ "$jsonc_status" -eq 0 ]; then
  echo "uninstall removed enforcement without being able to reset JSONC permissions" >&2
  exit 1
fi

test -L "$test_home/.config/agent-config/safety-policy.json"
test -L "$test_home/.local/bin/agent-safety"
printf '%s\n' "$opencode_before" \
  > "$test_home/.config/opencode/opencode.jsonc"

no_jq_bin="$test_home/no-jq-bin"
mkdir -p "$no_jq_bin"
ln -s /bin/bash "$no_jq_bin/bash"
ln -s "$(command -v node)" "$no_jq_bin/node"
ln -s /usr/bin/dirname "$no_jq_bin/dirname"

set +e
PATH="$no_jq_bin" HOME="$test_home" \
  "$repo/uninstall.sh" >/dev/null 2>&1
no_jq_status=$?
set -e

if [ "$no_jq_status" -eq 0 ]; then
  echo "uninstall succeeded without the tool needed to reset permissive JSON settings" >&2
  exit 1
fi

test -L "$test_home/.config/agent-config/safety-policy.json"
test -L "$test_home/.local/bin/agent-safety"
jq -e --arg command "$repo/hooks/deny-dangerous.sh" '
  [.. | objects | .command? // empty] | index($command) != null
' "$test_home/.claude/settings.json" >/dev/null

fake_bin="$test_home/fake-bin"
mkdir -p "$fake_bin"
ln -s /bin/bash "$fake_bin/bash"
printf '%s\n' '#!/usr/bin/env bash' 'exit 9' > "$fake_bin/node"
chmod +x "$fake_bin/node"

set +e
PATH="$fake_bin:/usr/bin:/bin" HOME="$test_home" \
  "$repo/uninstall.sh" >/dev/null 2>&1
failed_uninstall_status=$?
set -e

if [ "$failed_uninstall_status" -eq 0 ]; then
  echo "uninstall succeeded even though safe profile resolution failed" >&2
  exit 1
fi

test -L "$test_home/.config/agent-config/safety-policy.json"
test -L "$test_home/.local/bin/agent-safety"
jq -e --arg command "$repo/hooks/deny-dangerous.sh" '
  [.. | objects | .command? // empty] | index($command) != null
' "$test_home/.claude/settings.json" >/dev/null

HOME="$test_home" "$repo/uninstall.sh" >/dev/null

test ! -e "$test_home/.config/agent-config/model-routing.json"
test ! -e "$test_home/.local/bin/agent-model-route"
test ! -e "$test_home/.config/agent-config/safety-policy.json"
test ! -e "$test_home/.local/bin/agent-safety"
test ! -e "$test_home/.hermes/skills/complexity-router"
test ! -e "$test_home/.hermes/skills/model-routing"
test ! -e "$test_home/.config/opencode/AGENTS.md"
test ! -e "$test_home/.pi/agent/node_modules"

if jq -e --arg command "$repo/hooks/deny-dangerous.sh" '
    [.. | objects | .command? // empty] | index($command) != null
  ' "$test_home/.claude/settings.json" >/dev/null; then
  echo "uninstall.sh left the catastrophic command guard installed" >&2
  exit 1
fi

jq -e '.permissions.defaultMode == "default"' \
  "$test_home/.claude/settings.json" >/dev/null
grep -Fq 'approval_policy = "on-request"' "$test_home/.codex/config.toml"
grep -Fq 'sandbox_mode = "workspace-write"' "$test_home/.codex/config.toml"
jq -e '.permission == {edit:"ask",bash:"ask",webfetch:"ask"}' \
  "$test_home/.config/opencode/opencode.jsonc" >/dev/null
if jq -e --arg skills "$repo/skills" '(.skills.paths // []) | index($skills) != null' \
  "$test_home/.config/opencode/opencode.jsonc" >/dev/null; then
  echo "uninstall.sh left the repo skills dir registered with OpenCode" >&2
  exit 1
fi
jq -e '.defaultProjectTrust == "ask"' \
  "$test_home/.pi/agent/settings.json" >/dev/null
