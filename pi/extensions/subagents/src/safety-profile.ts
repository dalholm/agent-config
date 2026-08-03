import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { Type } from "typebox";
import { Value } from "typebox/value";

const SafetyPolicySchema = Type.Object({
  profiles: Type.Object({
    autonomous: Type.Object({
      harnesses: Type.Object({
        claude: Type.Object({
          permissionMode: Type.Union([
            Type.Literal("default"),
            Type.Literal("acceptEdits"),
            Type.Literal("bypassPermissions"),
            Type.Literal("plan"),
            Type.Literal("dontAsk"),
            Type.Literal("auto"),
          ]),
          allowDangerouslySkipPermissions: Type.Boolean(),
        }),
        codex: Type.Object({
          approvalPolicy: Type.Union([
            Type.Literal("untrusted"),
            Type.Literal("on-failure"),
            Type.Literal("on-request"),
            Type.Literal("never"),
          ]),
          sandbox: Type.Union([
            Type.Literal("read-only"),
            Type.Literal("workspace-write"),
            Type.Literal("danger-full-access"),
          ]),
        }),
      }),
    }),
  }),
});

const policyPath = fileURLToPath(
  new URL("../../../../safety-policy.json", import.meta.url),
);
const policy = Value.Parse(
  SafetyPolicySchema,
  JSON.parse(readFileSync(policyPath, "utf8")),
);

type ClaudeSubagentProfile =
  (typeof policy.profiles.autonomous.harnesses)["claude"];
type CodexSubagentProfile =
  (typeof policy.profiles.autonomous.harnesses)["codex"];
type SubagentHarness = "claude" | "codex";

function assertNever(value: never): never {
  throw new Error(`Unsupported subagent safety adapter: ${String(value)}`);
}

export function resolveSubagentProfile(
  harness: "claude",
): ClaudeSubagentProfile;
export function resolveSubagentProfile(harness: "codex"): CodexSubagentProfile;
export function resolveSubagentProfile(
  harness: SubagentHarness,
): ClaudeSubagentProfile | CodexSubagentProfile {
  switch (harness) {
    case "claude":
      return policy.profiles.autonomous.harnesses.claude;
    case "codex":
      return policy.profiles.autonomous.harnesses.codex;
    default:
      return assertNever(harness);
  }
}
