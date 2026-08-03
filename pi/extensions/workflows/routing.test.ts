import assert from "node:assert/strict";
import test from "node:test";
import { bindWorkflowAgentRoute } from "./routing.ts";

test("workflow routes require an explicit logical role and tier", () => {
  assert.throws(
    () => bindWorkflowAgentRoute({ role: undefined, tier: "standard" }),
    /role.*required/,
  );
  assert.throws(
    () => bindWorkflowAgentRoute({ role: "coder", tier: undefined }),
    /tier.*required/,
  );
  assert.throws(
    () => bindWorkflowAgentRoute({ role: "wizard", tier: "deep" }),
    /invalid role "wizard"/,
  );
});

test("workflow routes preserve Pi inheritance by default", () => {
  assert.deepEqual(
    bindWorkflowAgentRoute({ role: "researcher", tier: "standard" }),
    {
      harness: "pi",
      role: "researcher",
      tier: "standard",
      strategy: "inherit",
      modelSource: "inherit",
      reasoningSource: "inherit",
    },
  );
});

test("workflow model, provider, and effort overrides win", () => {
  assert.deepEqual(
    bindWorkflowAgentRoute({
      role: "reviewer",
      tier: "deep",
      provider: "fixture",
      model: "review-model",
      effort: "minimal",
    }),
    {
      harness: "pi",
      role: "reviewer",
      tier: "deep",
      strategy: "inherit",
      provider: "fixture",
      model: "review-model",
      reasoningEffort: "minimal",
      modelSource: "explicit",
      reasoningSource: "explicit",
    },
  );
});
