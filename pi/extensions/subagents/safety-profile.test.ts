import assert from "node:assert/strict";
import test from "node:test";
import {
  buildClaudeQueryOptions,
  buildCodexThreadStartParams,
} from "./src/backend-launch-options.ts";
import type { ParentContext, SpawnTask } from "./src/domain.ts";
import { bindSpawnTask } from "./src/spawn-route.ts";

const parent: ParentContext = {
  parentCwd: "/workspace",
  projectTrusted: false,
};

const task: SpawnTask = {
  prompt: "Inspect the project",
  title: "safety profile test",
  cwd: "/workspace",
  role: "coder",
  tier: "standard",
  model: "test-model",
  reasoningEffort: "low",
  parent,
};

test("backend launch payloads stay non-interactive without escaping the workspace sandbox", () => {
  const claude = buildClaudeQueryOptions(
    bindSpawnTask("claude", task),
    new AbortController(),
    "/usr/bin/claude",
  );
  const codex = buildCodexThreadStartParams(bindSpawnTask("codex", task));

  assert.equal(claude.permissionMode, "dontAsk");
  assert.equal(claude.allowDangerouslySkipPermissions, false);
  assert.deepEqual(claude.disallowedTools, ["Agent", "Task"]);
  assert.deepEqual(claude.settingSources, ["user"]);
  assert.equal(codex.approvalPolicy, "never");
  assert.equal(codex.sandbox, "workspace-write");
  assert.equal(codex.cwd, "/workspace");
  assert.equal(codex.ephemeral, false);
});
