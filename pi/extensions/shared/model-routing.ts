import {
  MODEL_ROUTING_HARNESSES,
  MODEL_ROUTING_REASONING_EFFORTS,
  MODEL_ROUTING_ROLES,
  MODEL_ROUTING_TIERS,
  ModelRoutingError,
  modelRoutingRegistry,
  resolveModelRoute,
  type AgentRole,
  type AgentTier,
  type ModelRoutingHarness,
  type ModelRoutingReasoningEffort,
  type ModelRoutingStrategy,
} from "../../../scripts/model-routing.mjs";

export {
  MODEL_ROUTING_HARNESSES,
  MODEL_ROUTING_REASONING_EFFORTS,
  MODEL_ROUTING_ROLES,
  MODEL_ROUTING_TIERS,
  type AgentRole,
  type AgentTier,
  type ModelRoutingHarness,
  type ModelRoutingReasoningEffort,
  type ModelRoutingStrategy,
};

export const ROUTED_REASONING_EFFORTS = MODEL_ROUTING_REASONING_EFFORTS;
export type RoutedReasoningEffort = ModelRoutingReasoningEffort;

export interface BindModelRouteOptions {
  readonly harness: ModelRoutingHarness;
  readonly role: AgentRole;
  readonly tier: AgentTier;
  readonly provider?: string;
  readonly model?: string;
  readonly reasoningEffort?: RoutedReasoningEffort;
}

export interface BoundModelRoute {
  readonly harness: ModelRoutingHarness;
  readonly role: AgentRole;
  readonly tier: AgentTier;
  readonly strategy: ModelRoutingStrategy;
  readonly provider?: string;
  readonly model?: string;
  readonly reasoningEffort?: RoutedReasoningEffort;
  readonly modelSource: "explicit" | "registry" | "inherit";
  readonly reasoningSource: "explicit" | "registry" | "inherit";
}

function isReasoningEffort(value: string): value is RoutedReasoningEffort {
  return ROUTED_REASONING_EFFORTS.some((effort) => effort === value);
}

export function bindModelRoute(
  options: BindModelRouteOptions,
): BoundModelRoute {
  if (options.provider !== undefined && options.model === undefined) {
    throw new ModelRoutingError("provider override requires a model override");
  }

  const route = resolveModelRoute(modelRoutingRegistry, {
    harness: options.harness,
    role: options.role,
    tier: options.tier,
  });
  let registryReasoning: RoutedReasoningEffort | undefined;
  if (route.reasoning) {
    if (!isReasoningEffort(route.reasoning)) {
      throw new ModelRoutingError(
        `harness "${route.harness}" resolved unsupported reasoning effort "${route.reasoning}"`,
      );
    }
    registryReasoning = route.reasoning;
  }

  const modelSource =
    options.model !== undefined
      ? "explicit"
      : route.model
        ? "registry"
        : "inherit";
  const reasoningSource =
    options.reasoningEffort !== undefined
      ? "explicit"
      : registryReasoning
        ? "registry"
        : "inherit";
  const model = options.model ?? route.model;
  const provider =
    options.model !== undefined ? options.provider : route.provider;
  const reasoningEffort = options.reasoningEffort ?? registryReasoning;

  return {
    harness: route.harness,
    role: route.role,
    tier: route.tier,
    strategy: route.strategy,
    ...(provider === undefined ? {} : { provider }),
    ...(model === undefined ? {} : { model }),
    ...(reasoningEffort === undefined ? {} : { reasoningEffort }),
    modelSource,
    reasoningSource,
  };
}
