import assert from "node:assert/strict";
import { test } from "node:test";
import {
  assertIndependentReviewRoute,
  bindModelRoute,
} from "./model-routing.ts";

test("Pi binds explicit local scout work to Qwen", () => {
  assert.deepEqual(
    bindModelRoute({ harness: "pi", role: "scout", tier: "fast" }),
    {
      harness: "pi",
      role: "scout",
      tier: "fast",
      strategy: "hybrid",
      providerFamily: "local",
      provider: "omlx",
      model: "qwen3.8-27b",
      modelSource: "registry",
      reasoningSource: "inherit",
    },
  );
});

test("independent review validation rejects the author harness", () => {
  assert.throws(
    () =>
      assertIndependentReviewRoute({
        harness: "codex",
        role: "reviewer",
        tier: "deep",
        reviewOfHarness: "codex",
      }),
    /independent review.*claude/i,
  );
  assert.doesNotThrow(() =>
    assertIndependentReviewRoute({
      harness: "claude",
      role: "reviewer",
      tier: "deep",
      reviewOfHarness: "codex",
    }),
  );
});

test("bindModelRoute applies registry defaults for explicit harness bindings", () => {
  assert.deepEqual(
    bindModelRoute({ harness: "codex", role: "coder", tier: "standard" }),
    {
      harness: "codex",
      role: "coder",
      tier: "standard",
      strategy: "explicit",
      providerFamily: "openai-codex",
      provider: "openai-codex",
      model: "gpt-5.6-sol",
      reasoningEffort: "high",
      modelSource: "registry",
      reasoningSource: "registry",
    },
  );
});

test("bindModelRoute gives explicit model and effort overrides precedence", () => {
  assert.deepEqual(
    bindModelRoute({
      harness: "codex",
      role: "reviewer",
      tier: "deep",
      model: "custom-codex",
      reasoningEffort: "low",
    }),
    {
      harness: "codex",
      role: "reviewer",
      tier: "deep",
      strategy: "explicit",
      providerFamily: "openai-codex",
      model: "custom-codex",
      reasoningEffort: "low",
      modelSource: "explicit",
      reasoningSource: "explicit",
    },
  );
});

test("bindModelRoute preserves Pi hybrid fallback without selecting a provider", () => {
  assert.deepEqual(
    bindModelRoute({ harness: "pi", role: "researcher", tier: "fast" }),
    {
      harness: "pi",
      role: "researcher",
      tier: "fast",
      strategy: "hybrid",
      providerFamily: "dynamic",
      modelSource: "inherit",
      reasoningSource: "inherit",
    },
  );
});

test("bindModelRoute records the actual provider family for Pi overrides", () => {
  const route = bindModelRoute({
    harness: "pi",
    role: "coder",
    tier: "standard",
    provider: "anthropic",
    model: "sonnet",
  });

  assert.equal(route.providerFamily, "anthropic");
});

test("bindModelRoute derives Pi provider provenance from model-only hints", () => {
  assert.equal(
    bindModelRoute({
      harness: "pi",
      role: "scout",
      tier: "fast",
      model: "anthropic/sonnet",
    }).providerFamily,
    "anthropic",
  );
  assert.equal(
    bindModelRoute({
      harness: "pi",
      role: "scout",
      tier: "fast",
      model: "unregistered/model",
    }).providerFamily,
    "unknown",
  );
});
