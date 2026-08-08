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

test("in-process workflows reject reviewer routes that cannot be independent", () => {
  assert.throws(
    () => bindWorkflowAgentRoute({ role: "reviewer", tier: "deep" }),
    /independent review.*subagent_spawn/i,
  );
  assert.throws(
    () => bindWorkflowAgentRoute({ role: "scout", tier: "fast" }),
    /local scout.*subagent_spawn/i,
  );
});

test("workflow routes preserve Pi inheritance by default", () => {
  assert.deepEqual(
    bindWorkflowAgentRoute({ role: "researcher", tier: "standard" }),
    {
      harness: "pi",
      role: "researcher",
      tier: "standard",
      strategy: "hybrid",
      providerFamily: "dynamic",
      modelSource: "inherit",
      reasoningSource: "inherit",
    },
  );
});

test("workflow model, provider, and effort overrides win", () => {
  assert.deepEqual(
    bindWorkflowAgentRoute({
      role: "coder",
      tier: "standard",
      provider: "fixture",
      model: "review-model",
      effort: "minimal",
    }),
    {
      harness: "pi",
      role: "coder",
      tier: "standard",
      strategy: "hybrid",
      providerFamily: "unknown",
      provider: "fixture",
      model: "review-model",
      reasoningEffort: "minimal",
      modelSource: "explicit",
      reasoningSource: "explicit",
    },
  );
});
