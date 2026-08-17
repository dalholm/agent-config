import assert from "node:assert/strict";
import test from "node:test";
import { bindSpawnTask } from "./src/spawn-route.ts";
import type { ParentContext, SpawnTask } from "./src/domain.ts";

const parent: ParentContext = {
  parentCwd: "/workspace",
  projectTrusted: true,
};

function task(overrides: Partial<SpawnTask> = {}): SpawnTask {
  return {
    prompt: "Inspect the project",
    title: "profile test",
    cwd: "/workspace",
    role: "coder",
    tier: "standard",
    parent,
    ...overrides,
  };
}

test("bindSpawnTask resolves the logical profile before backend launch", () => {
  const bound = bindSpawnTask("codex", task());

  assert.equal(bound.model, "gpt-5.6-sol");
  assert.equal(bound.reasoningEffort, "high");
  assert.deepEqual(bound.route, {
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
  });
});

test("bindSpawnTask preserves explicit model and effort overrides", () => {
  const bound = bindSpawnTask(
    "claude",
    task({ model: "custom-alias", reasoningEffort: "minimal" }),
  );

  assert.equal(bound.model, "custom-alias");
  assert.equal(bound.reasoningEffort, "minimal");
  assert.equal(bound.route.modelSource, "explicit");
  assert.equal(bound.route.reasoningSource, "explicit");
});

test("bindSpawnTask uses the explicit Pi harness for a local scout", () => {
  const bound = bindSpawnTask("pi", task({ role: "scout", tier: "fast" }));

  assert.equal(bound.route.harness, "pi");
  assert.equal(bound.model, "qwen3.8-27b");
});

test("bindSpawnTask records the inherited provider family for Pi work", () => {
  const bound = bindSpawnTask(
    "pi",
    task({
      parent: {
        ...parent,
        inheritedModel: { provider: "anthropic", id: "sonnet" },
      },
    }),
  );

  assert.equal(bound.route.providerFamily, "anthropic");
});

test("bindSpawnTask records a valid independent review author", () => {
  const bound = bindSpawnTask(
    "claude",
    task({
      role: "reviewer",
      tier: "deep",
      reviewOfHarness: "codex",
    }),
  );
  assert.equal(bound.route.reviewOfHarness, "codex");
  assert.equal(bound.route.provider, "anthropic");
});

test("bindSpawnTask requires author provider provenance for Pi reviews", () => {
  assert.throws(
    () =>
      bindSpawnTask(
        "claude",
        task({ role: "reviewer", tier: "deep", reviewOfHarness: "pi" }),
      ),
    /reviewOfProviderFamily.*required/i,
  );

  const bound = bindSpawnTask(
    "codex",
    task({
      role: "reviewer",
      tier: "deep",
      reviewOfHarness: "pi",
      reviewOfProviderFamily: "anthropic",
    }),
  );
  assert.equal(bound.route.reviewOfProviderFamily, "anthropic");
  assert.equal(bound.route.provider, "openai-codex");
});

test("bindSpawnTask rejects reviewer overrides and non-Pi scouts", () => {
  assert.throws(
    () =>
      bindSpawnTask(
        "claude",
        task({
          role: "reviewer",
          tier: "deep",
          reviewOfHarness: "codex",
          reasoningEffort: "low",
        }),
      ),
    /reviewer.*overrides/i,
  );
  assert.throws(
    () => bindSpawnTask("codex", task({ role: "scout", tier: "fast" })),
    /scout.*local Pi/i,
  );
});

test("bindSpawnTask rejects review by the author harness", () => {
  assert.throws(
    () =>
      bindSpawnTask(
        "codex",
        task({
          role: "reviewer",
          tier: "deep",
          reviewOfHarness: "codex",
        }),
      ),
    /independent review.*claude/i,
  );
});
