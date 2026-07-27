#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_home="$(mktemp -d)"
trap 'rm -rf "$test_home"' EXIT

HOME="$test_home" "$repo/install.sh" --no-bootstrap >/dev/null

test -L "$test_home/.config/agent-config/model-routing.json"
test -L "$test_home/.local/bin/agent-model-route"
test -L "$test_home/.hermes/skills/complexity-router"
test -L "$test_home/.config/opencode/AGENTS.md"

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

HOME="$test_home" "$repo/uninstall.sh" --keep-permissions >/dev/null

test ! -e "$test_home/.config/agent-config/model-routing.json"
test ! -e "$test_home/.local/bin/agent-model-route"
test ! -e "$test_home/.hermes/skills/complexity-router"
test ! -e "$test_home/.config/opencode/AGENTS.md"
