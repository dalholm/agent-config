import assert from "node:assert/strict";
import { test } from "node:test";
import { bindModelRoute } from "./model-routing.ts";

test("bindModelRoute applies registry defaults for explicit harness bindings", () => {
  assert.deepEqual(
    bindModelRoute({ harness: "codex", role: "coder", tier: "standard" }),
    {
      harness: "codex",
      role: "coder",
      tier: "standard",
      strategy: "explicit",
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
      model: "custom-codex",
      reasoningEffort: "low",
      modelSource: "explicit",
      reasoningSource: "explicit",
    },
  );
});

test("bindModelRoute preserves Pi inheritance without selecting a provider", () => {
  assert.deepEqual(
    bindModelRoute({ harness: "pi", role: "researcher", tier: "fast" }),
    {
      harness: "pi",
      role: "researcher",
      tier: "fast",
      strategy: "inherit",
      modelSource: "inherit",
      reasoningSource: "inherit",
    },
  );
});
