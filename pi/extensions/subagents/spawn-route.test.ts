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
