#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

node --input-type=module -e '
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const repo = process.argv[1];
const routing = await import(pathToFileURL(`${repo}/scripts/model-routing.mjs`));
const route = routing.resolveModelRoute(routing.modelRoutingRegistry, {
  harness: "codex",
  role: "coder",
  tier: "standard",
});
assert.equal(route.model, "gpt-5.6-sol");
const localScout = routing.resolveDispatchRoute(routing.modelRoutingRegistry, {
  role: "scout",
  tier: "fast",
});
assert.equal(localScout.harness, "pi");
assert.equal(localScout.provider, "omlx");
assert.equal(localScout.model, "qwen3.8-27b");
assert.equal(localScout.selection, "automatic");
assert.throws(
  () => routing.resolveDispatchRoute(routing.modelRoutingRegistry, {
    harness: "codex",
    role: "scout",
    tier: "fast",
  }),
  /scout.*local Pi/i,
);
const codexReview = routing.resolveDispatchRoute(routing.modelRoutingRegistry, {
  role: "reviewer",
  tier: "deep",
  reviewOfHarness: "codex",
});
assert.equal(codexReview.harness, "claude");
assert.equal(codexReview.provider, "anthropic");
assert.equal(codexReview.selection, "independent-review");
assert.equal(codexReview.providerFamily, "anthropic");
assert.throws(
  () => routing.resolveDispatchRoute(routing.modelRoutingRegistry, {
    role: "reviewer",
    tier: "fast",
    reviewOfHarness: "codex",
  }),
  /reviewer.*deep/i,
);
assert.throws(
  () => routing.resolveDispatchRoute(routing.modelRoutingRegistry, {
    harness: "codex",
    role: "reviewer",
    tier: "deep",
    reviewOfHarness: "codex",
  }),
  /independent review.*claude/i,
);
assert.throws(
  () => routing.resolveDispatchRoute(routing.modelRoutingRegistry, {
    role: "reviewer",
    tier: "deep",
  }),
  /reviewOfHarness.*required/,
);
assert.throws(
  () => routing.validateModelRoutingRegistry({ schemaVersion: 2 }),
  /defaultRoute/,
);
const malformed = structuredClone(routing.modelRoutingRegistry);
malformed.harnesses.codex.tiers.fast.reasoning = "limitless";
assert.throws(
  () => routing.validateModelRoutingRegistry(malformed),
  /unsupported reasoning effort "limitless"/,
);
const unsafeInherit = structuredClone(routing.modelRoutingRegistry);
unsafeInherit.harnesses.pi.strategy = "inherit";
unsafeInherit.harnesses.pi.tiers = {
  standard: {
    provider: "paid-provider",
    model: "paid-model",
    reasoning: "high",
  },
};
assert.throws(
  () => routing.validateModelRoutingRegistry(unsafeInherit),
  /inherit.*must not define explicit bindings/,
);
const unsafeHybrid = structuredClone(routing.modelRoutingRegistry);
unsafeHybrid.harnesses.pi.roleOverrides.scout.fast = {
  provider: "anthropic",
  model: "haiku",
};
assert.throws(
  () => routing.validateModelRoutingRegistry(unsafeHybrid),
  /hybrid.*local provider/i,
);
const unsafeAutomatic = structuredClone(routing.modelRoutingRegistry);
unsafeAutomatic.dispatch.automaticRoutes[0].harness = "codex";
assert.throws(
  () => routing.validateModelRoutingRegistry(unsafeAutomatic),
  /automatic route.*local provider/i,
);
assert.throws(
  () => routing.resolveDispatchRoute(routing.modelRoutingRegistry, {
    role: "reviewer",
    tier: "deep",
    reviewOfHarness: "pi",
  }),
  /reviewOfProviderFamily.*required/i,
);
const localPiReview = routing.resolveDispatchRoute(routing.modelRoutingRegistry, {
  role: "reviewer",
  tier: "deep",
  reviewOfHarness: "pi",
  reviewOfProviderFamily: "local",
});
assert.equal(localPiReview.harness, "claude");
assert.equal(localPiReview.providerFamily, "anthropic");
const inheritedClaudePiReview = routing.resolveDispatchRoute(routing.modelRoutingRegistry, {
  role: "reviewer",
  tier: "deep",
  reviewOfHarness: "pi",
  reviewOfProviderFamily: "anthropic",
});
assert.equal(inheritedClaudePiReview.harness, "codex");
assert.equal(inheritedClaudePiReview.providerFamily, "openai-codex");
assert.throws(
  () => routing.resolveModelRoute(unsafeInherit, {
    harness: "pi",
    role: "coder",
    tier: "standard",
  }),
  /inherit.*must not define explicit bindings/,
);
const unsafePreset = structuredClone(routing.modelRoutingRegistry);
unsafePreset.harnesses.hermes.tiers = {
  standard: {
    provider: "paid-provider",
    model: "paid-model",
    reasoning: "high",
  },
};
assert.throws(
  () => routing.resolveModelRoute(unsafePreset, {
    harness: "hermes",
    role: "researcher",
    tier: "standard",
  }),
  /preset.*must not define tier or role bindings/,
);
' "$repo"

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
if (!catalog.roles.includes("scout")) throw new Error("missing role scout");
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
if (catalog.bindings.pi.strategy !== "hybrid") {
  throw new Error("catalog does not expose hybrid local-worker strategy");
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
if (route.strategy !== "hybrid") throw new Error("Pi did not preserve hybrid fallback");
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
assert_invalid_route 'review provenance is only valid for reviewer routes' \
  --harness hermes --preset designer --review-of-harness codex
assert_invalid_route 'reviewer routes must use tier deep' \
  --role reviewer --tier fast --review-of-harness codex
