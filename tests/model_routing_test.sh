#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

codex_route="$(
  node "$repo/scripts/resolve-model-route.mjs" \
    --harness codex \
    --role researcher \
    --tier standard \
    --format json
)"

node -e '
const route = JSON.parse(process.argv[1]);
if (route.role !== "researcher") throw new Error("role was not preserved");
if (route.tier !== "standard") throw new Error("tier was not preserved");
if (route.harness !== "codex") throw new Error("harness was not preserved");
if (route.provider !== "openai-codex") throw new Error("Codex provider was not resolved");
if (route.model !== "gpt-5.6-sol") throw new Error("Codex standard model was not resolved");
if (route.reasoning !== "high") throw new Error("Codex standard reasoning was not resolved");
' "$codex_route"

codex_designer_route="$(
  node "$repo/scripts/resolve-model-route.mjs" \
    --harness codex \
    --role designer \
    --tier standard \
    --format json
)"

node -e '
const route = JSON.parse(process.argv[1]);
if (route.model !== "gpt-5.6-terra") {
  throw new Error("Codex designer override was not resolved");
}
' "$codex_designer_route"

claude_route="$(
  node "$repo/scripts/resolve-model-route.mjs" \
    --harness claude \
    --role researcher \
    --tier standard \
    --format json
)"

node -e '
const route = JSON.parse(process.argv[1]);
if (route.harness !== "claude") throw new Error("Claude harness was not preserved");
if (route.provider !== "anthropic") throw new Error("Claude provider was not resolved");
if (route.model !== "sonnet") throw new Error("Claude standard alias was not resolved");
if (route.reasoning !== "high") throw new Error("Claude standard effort was not resolved");
' "$claude_route"

hermes_designer_route="$(
  node "$repo/scripts/resolve-model-route.mjs" \
    --harness hermes \
    --preset designer \
    --format json
)"

node -e '
const route = JSON.parse(process.argv[1]);
if (route.preset !== "designer") throw new Error("Hermes preset was not preserved");
if (route.role !== "designer") throw new Error("Hermes preset role was not expanded");
if (route.tier !== "standard") throw new Error("Hermes preset tier was not expanded");
if (route.strategy !== "preset") throw new Error("Hermes did not use preset routing");
if (route.profile !== "designer") throw new Error("Hermes profile was not resolved");
if (route.model !== "gpt-5.6-terra") throw new Error("Hermes profile model was not resolved");
' "$hermes_designer_route"

routing_catalog="$(
  node "$repo/scripts/resolve-model-route.mjs" \
    --list \
    --format json
)"

node -e '
const catalog = JSON.parse(process.argv[1]);
for (const role of ["generalist", "researcher", "coder", "designer", "reviewer", "orchestrator"]) {
  if (!catalog.roles.includes(role)) throw new Error(`missing role ${role}`);
}
for (const tier of ["fast", "standard", "deep"]) {
  if (!catalog.tiers.includes(tier)) throw new Error(`missing tier ${tier}`);
}
for (const preset of ["fast", "coder", "designer", "thinker"]) {
  if (!catalog.presets.includes(preset)) throw new Error(`missing preset ${preset}`);
}
for (const harness of ["claude", "codex", "gemini", "hermes", "opencode", "pi"]) {
  if (!catalog.harnesses.includes(harness)) throw new Error(`missing harness ${harness}`);
}
if (catalog.bindings.codex.tiers.standard.model !== "gpt-5.6-sol") {
  throw new Error("catalog does not expose Codex bindings");
}
if (catalog.bindings.pi.strategy !== "inherit") {
  throw new Error("catalog does not expose inherit strategies");
}
' "$routing_catalog"

pi_route="$(
  node "$repo/scripts/resolve-model-route.mjs" \
    --harness pi \
    --role coder \
    --tier standard \
    --format json
)"

node -e '
const route = JSON.parse(process.argv[1]);
if (route.strategy !== "inherit") throw new Error("Pi did not inherit safely");
if ("provider" in route || "model" in route) {
  throw new Error("Pi silently selected an explicit provider");
}
' "$pi_route"

assert_invalid_route() {
  local expected="$1" invalid_output invalid_status
  shift

  set +e
  invalid_output="$(node "$repo/scripts/resolve-model-route.mjs" "$@" 2>&1)"
  invalid_status=$?
  set -e

  if [ "$invalid_status" -eq 0 ]; then
    echo "model resolver accepted an invalid route: $*" >&2
    exit 1
  fi

  grep -Fq "$expected" <<<"$invalid_output" || {
    echo "model resolver did not explain the invalid route: $*" >&2
    exit 1
  }
}

assert_invalid_route 'unknown role "fortune_teller"' \
  --harness codex --role fortune_teller --tier standard
assert_invalid_route 'unknown tier "limitless"' \
  --harness codex --role researcher --tier limitless
assert_invalid_route 'unknown harness "telegraph"' \
  --harness telegraph --role researcher --tier standard
assert_invalid_route 'unknown preset "oracle"' \
  --harness hermes --preset oracle
assert_invalid_route 'harness "hermes" has no binding for tier "standard"' \
  --harness hermes --role researcher --tier standard
