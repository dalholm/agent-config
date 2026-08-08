import assert from "node:assert/strict";
import test from "node:test";
import { toolPolicyForRole } from "./src/tool-policy.ts";

const available = [
  "read",
  "bash",
  "edit",
  "write",
  "rg",
  "fd",
  "subagent_spawn",
  "custom_mutation",
];

test("scouts receive only read and repository discovery tools", () => {
  assert.deepEqual(toolPolicyForRole("scout", available), {
    kind: "allowlist",
    toolNames: ["read", "rg", "fd"],
  });
});

test("non-scout roles preserve the child session tool policy", () => {
  assert.deepEqual(toolPolicyForRole("coder", available), { kind: "inherit" });
});

test("scouts fail closed when no approved tools are available", () => {
  assert.throws(
    () => toolPolicyForRole("scout", ["bash", "write"]),
    /scout.*read tool/i,
  );
});
