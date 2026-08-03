import {
  bindModelRoute,
  MODEL_ROUTING_ROLES,
  MODEL_ROUTING_TIERS,
  ROUTED_REASONING_EFFORTS,
  type AgentRole,
  type AgentTier,
  type BoundModelRoute,
  type RoutedReasoningEffort,
} from "../shared/model-routing.ts";

export interface WorkflowAgentRouteInput {
  readonly role?: unknown;
  readonly tier?: unknown;
  readonly provider?: unknown;
  readonly model?: unknown;
  readonly effort?: unknown;
}

function member<T extends string>(
  values: readonly T[],
  value: unknown,
): value is T {
  return typeof value === "string" && values.some((entry) => entry === value);
}

function role(value: unknown): AgentRole {
  if (value === undefined) throw new Error("role is required");
  if (!member(MODEL_ROUTING_ROLES, value)) {
    throw new Error(`invalid role "${String(value)}"`);
  }
  return value;
}

function tier(value: unknown): AgentTier {
  if (value === undefined) throw new Error("tier is required");
  if (!member(MODEL_ROUTING_TIERS, value)) {
    throw new Error(`invalid tier "${String(value)}"`);
  }
  return value;
}

function optionalString(value: unknown, name: string): string | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "string") throw new Error(`${name} must be a string`);
  return value;
}

function effort(value: unknown): RoutedReasoningEffort | undefined {
  if (value === undefined) return undefined;
  if (!member(ROUTED_REASONING_EFFORTS, value)) {
    throw new Error(
      `invalid effort "${String(value)}" (use ${ROUTED_REASONING_EFFORTS.join("|")})`,
    );
  }
  return value;
}

export function bindWorkflowAgentRoute(
  input: WorkflowAgentRouteInput,
): BoundModelRoute {
  const provider = optionalString(input.provider, "provider");
  const model = optionalString(input.model, "model");
  const reasoningEffort = effort(input.effort);
  return bindModelRoute({
    harness: "pi",
    role: role(input.role),
    tier: tier(input.tier),
    ...(provider === undefined ? {} : { provider }),
    ...(model === undefined ? {} : { model }),
    ...(reasoningEffort === undefined ? {} : { reasoningEffort }),
  });
}
