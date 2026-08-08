import type { AgentRole } from "../../shared/model-routing.ts";

const SCOUT_TOOL_NAMES = new Set(["read", "rg", "fd"]);

export type RoleToolPolicy =
  | { readonly kind: "inherit" }
  | { readonly kind: "allowlist"; readonly toolNames: readonly string[] };

export function toolPolicyForRole(
  role: AgentRole,
  availableToolNames: readonly string[],
): RoleToolPolicy {
  if (role !== "scout") return { kind: "inherit" };
  if (!availableToolNames.includes("read")) {
    throw new Error("scout requires the read tool");
  }
  return {
    kind: "allowlist",
    toolNames: availableToolNames.filter((name) => SCOUT_TOOL_NAMES.has(name)),
  };
}
