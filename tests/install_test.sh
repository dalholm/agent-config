#!/usr/bin/env bash
set -euo pipefail

test_home="$(mktemp -d)"
trap 'rm -rf "$test_home"' EXIT
output="$(HOME="$test_home" ./install.sh --dry-run --no-bootstrap)"

grep -Fq "$test_home/.pi/agent/node_modules" <<<"$output" || {
  echo "install.sh does not link Pi extension dependencies into ~/.pi/agent" >&2
  exit 1
}

grep -Fq "$test_home/.hermes/skills/complexity-router" <<<"$output" || {
  echo "install.sh does not link shared skills into ~/.hermes/skills" >&2
  exit 1
}

grep -Fq "$test_home/.config/agent-config/model-routing.json" <<<"$output" || {
  echo "install.sh does not expose the shared model-routing registry" >&2
  exit 1
}

grep -Fq "$test_home/.local/bin/agent-model-route" <<<"$output" || {
  echo "install.sh does not expose the model-routing command" >&2
  exit 1
}

grep -Fq "$test_home/.config/opencode/AGENTS.md" <<<"$output" || {
  echo "install.sh does not expose shared instructions to OpenCode" >&2
  exit 1
}
