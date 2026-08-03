#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Given the canonical safety command
# When an interactive read decision is requested without an authorization grant
read_decision="$(
  node "$repo/scripts/agent-safety.mjs" decide \
    --operation read \
    --mode interactive \
    --authorized false \
    --format json
)"

# Then the operation is allowed by policy
node -e '
const decision = JSON.parse(process.argv[1]);
if (decision.operation !== "read") throw new Error("operation was not preserved");
if (decision.mode !== "interactive") throw new Error("mode was not preserved");
if (decision.decision !== "allow") throw new Error("read was not allowed");
if (decision.basis !== "policy") throw new Error("read did not cite policy authority");
' "$read_decision"

destructive_decision="$(
  node "$repo/scripts/agent-safety.mjs" decide \
    --operation destructive-local \
    --mode interactive \
    --authorized false \
    --format json
)"

node -e '
const decision = JSON.parse(process.argv[1]);
if (decision.decision !== "require-user") {
  throw new Error("destructive local work did not require the user");
}
if (decision.basis !== "policy") {
  throw new Error("the user gate did not cite policy authority");
}
' "$destructive_decision"

authorized_destructive_decision="$(
  node "$repo/scripts/agent-safety.mjs" decide \
    --operation destructive-local \
    --mode autonomous \
    --authorized true \
    --format json
)"

node -e '
const decision = JSON.parse(process.argv[1]);
if (decision.decision !== "allow") {
  throw new Error("an exact user grant did not satisfy the gate");
}
if (decision.basis !== "explicit-user-grant") {
  throw new Error("the grant was not exposed as the decision basis");
}
' "$authorized_destructive_decision"

catastrophic_decision="$(
  node "$repo/scripts/agent-safety.mjs" decide \
    --operation catastrophic \
    --mode autonomous \
    --authorized true \
    --format json
)"

node -e '
const decision = JSON.parse(process.argv[1]);
if (decision.decision !== "deny") {
  throw new Error("a user grant overrode a catastrophic denial");
}
if (decision.basis !== "policy") {
  throw new Error("the catastrophic denial did not cite policy authority");
}
' "$catastrophic_decision"

for expectation in \
  "read allow" \
  "local-write allow" \
  "destructive-local require-user" \
  "external-write require-user" \
  "sensitive require-user" \
  "catastrophic deny"; do
  read -r operation expected_decision <<<"$expectation"
  actual_decision="$(
    node "$repo/scripts/agent-safety.mjs" decide \
      --operation "$operation" \
      --mode autonomous \
      --authorized false \
      --format json
  )"
  node -e '
  const decision = JSON.parse(process.argv[1]);
  if (decision.decision !== process.argv[2]) {
    throw new Error(`${decision.operation} resolved to ${decision.decision}`);
  }
  ' "$actual_decision" "$expected_decision"
done

codex_profile="$(
  node "$repo/scripts/agent-safety.mjs" profile \
    --profile autonomous \
    --harness codex \
    --format json
)"

node -e '
const profile = JSON.parse(process.argv[1]);
if (profile.approvalPolicy !== "never") {
  throw new Error("the autonomous Codex profile could prompt a headless child");
}
if (profile.sandbox !== "workspace-write") {
  throw new Error("the autonomous Codex profile escaped the workspace sandbox");
}
if (profile.doctorScope !== "repository") {
  throw new Error("the workspace-sandboxed autonomous profile did not require repository checks");
}
if ("requiresDoctor" in profile) {
  throw new Error("the profile exposed the ambiguous requiresDoctor field");
}
' "$codex_profile"

assert_profile_field() {
  local profile_name="$1" harness="$2" field="$3" expected="$4"
  local resolved
  resolved="$(
    node "$repo/scripts/agent-safety.mjs" profile \
      --profile "$profile_name" \
      --harness "$harness" \
      --format json
  )"
  node -e '
  const profile = JSON.parse(process.argv[1]);
  const actual = String(profile[process.argv[2]]);
  if (actual !== process.argv[3]) {
    throw new Error(`${profile.profile}/${profile.harness} ${process.argv[2]} was ${actual}`);
  }
  ' "$resolved" "$field" "$expected"
}

assert_profile_field safe codex approvalPolicy on-request
assert_profile_field safe claude permissionMode default
assert_profile_field autonomous claude permissionMode dontAsk
assert_profile_field auto-approve codex sandbox danger-full-access
assert_profile_field auto-approve claude allowDangerouslySkipPermissions true
assert_profile_field safe opencode permission ask
assert_profile_field safe pi projectTrust ask
assert_profile_field auto-approve opencode permission allow
assert_profile_field auto-approve pi projectTrust always
