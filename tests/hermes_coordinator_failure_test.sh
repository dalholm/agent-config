#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

assert_safety_installed() {
  local home="$1"

  jq -e --arg command "$repo/hooks/deny-dangerous.sh" '
    [.. | objects | .command? // empty] | index($command) != null
  ' "$home/.claude/settings.json" >/dev/null
  jq -e '.permissions.defaultMode == "default"' \
    "$home/.claude/settings.json" >/dev/null
  grep -Fq 'approval_policy = "on-request"' "$home/.codex/config.toml"
  grep -Fq 'sandbox_mode = "workspace-write"' "$home/.codex/config.toml"
  jq -e '.permission == {edit:"ask",bash:"ask",webfetch:"ask"}' \
    "$home/.config/opencode/opencode.jsonc" >/dev/null
  jq -e '.defaultProjectTrust == "ask"' \
    "$home/.pi/agent/settings.json" >/dev/null
}

run_install_expect_failure() {
  local home="$1"
  shift

  mkdir -p "$home/.config/opencode"
  printf '{}\n' > "$home/.config/opencode/opencode.jsonc"

  set +e
  HOME="$home" "$@" "$repo/install.sh" --no-bootstrap >/dev/null 2>&1
  local status=$?
  set -e

  [ "$status" -ne 0 ]
  assert_safety_installed "$home"
}

outside_home="$test_root/outside-home"
outside_target="$test_root/outside-target"
mkdir -p "$outside_home" "$outside_target"

run_install_expect_failure "$outside_home" env HERMES_HOME="$outside_target"
test ! -e "$outside_target/SOUL.md"

symlink_home="$test_root/symlink-home"
symlink_target="$test_root/symlink-target"
mkdir -p "$symlink_home/.hermes/profiles" "$symlink_target"
ln -s "$symlink_target" "$symlink_home/.hermes/profiles/cloud"
printf 'cloud\n' > "$symlink_home/.hermes/active_profile"
run_install_expect_failure "$symlink_home" env
test ! -e "$symlink_target/SOUL.md"

malformed_home="$test_root/malformed-home"
mkdir -p "$malformed_home/.hermes/profiles/cloud"
printf 'cloud\n' > "$malformed_home/.hermes/active_profile"
printf '%s\n' \
  'Original personality.' \
  '<!-- agent-config:hermes-orca-coordinator:start -->' \
  'Unclosed managed block.' \
  > "$malformed_home/.hermes/profiles/cloud/SOUL.md"
run_install_expect_failure "$malformed_home" env

node_home="$test_root/node-home"
fake_bin="$test_root/fake-bin"
real_node="$(command -v node)"
mkdir -p "$node_home" "$fake_bin"
apply_node_failure="$fake_bin/node"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "$1" == */resolve-hermes-home.mjs ]]; then exit 127; fi' \
  'exec "$REAL_NODE" "$@"' \
  > "$apply_node_failure"
chmod +x "$apply_node_failure"
run_install_expect_failure "$node_home" env REAL_NODE="$real_node" PATH="$fake_bin:$PATH"
