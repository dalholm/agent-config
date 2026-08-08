export type AgentRole =
  | "generalist"
  | "scout"
  | "researcher"
  | "coder"
  | "designer"
  | "reviewer"
  | "orchestrator";
export type AgentTier = "fast" | "standard" | "deep";
export type ModelRoutingHarness =
  "claude" | "codex" | "gemini" | "hermes" | "opencode" | "pi";
export type ModelRoutingStrategy = "explicit" | "preset" | "inherit" | "hybrid";
export type ModelRoutingReasoningEffort =
  "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";

export interface ModelRouteTarget {
  readonly provider?: string;
  readonly model?: string;
  readonly profile?: string;
  readonly reasoning?: ModelRoutingReasoningEffort;
}

export interface ModelRoutingRegistry {
  readonly schemaVersion: 2;
  readonly providers: Readonly<
    Record<string, { readonly family: string; readonly local: boolean }>
  >;
  readonly defaultRoute: { readonly role: AgentRole; readonly tier: AgentTier };
  readonly roles: Readonly<Record<AgentRole, { readonly description: string }>>;
  readonly tiers: Readonly<
    Record<
      AgentTier,
      { readonly description: string; readonly reasoningIntent: string }
    >
  >;
  readonly presets: Readonly<
    Record<string, { readonly role: AgentRole; readonly tier: AgentTier }>
  >;
  readonly harnesses: Readonly<
    Record<
      ModelRoutingHarness,
      {
        readonly strategy: ModelRoutingStrategy;
        readonly providerFamily: string;
        readonly tiers?: Readonly<Partial<Record<AgentTier, ModelRouteTarget>>>;
        readonly roleOverrides?: Readonly<
          Partial<
            Record<
              AgentRole,
              Readonly<Partial<Record<AgentTier, ModelRouteTarget>>>
            >
          >
        >;
        readonly presetBindings?: Readonly<Record<string, ModelRouteTarget>>;
      }
    >
  >;
  readonly dispatch: {
    readonly automaticRoutes: ReadonlyArray<{
      readonly role: AgentRole;
      readonly tier: AgentTier;
      readonly harness: ModelRoutingHarness;
    }>;
    readonly independentReview: {
      readonly byAuthorProviderFamily: Readonly<
        Record<string, ModelRoutingHarness>
      >;
    };
  };
}

export interface ResolveModelRouteOptions {
  readonly harness?: string;
  readonly role?: string;
  readonly tier?: string;
  readonly preset?: string;
}

export interface ResolveDispatchRouteOptions extends ResolveModelRouteOptions {
  readonly reviewOfHarness?: string;
  readonly reviewOfProviderFamily?: string;
}

export interface ResolvedModelRoute extends ModelRouteTarget {
  readonly preset?: string;
  readonly role: AgentRole;
  readonly tier: AgentTier;
  readonly harness: ModelRoutingHarness;
  readonly strategy: ModelRoutingStrategy;
  readonly providerFamily: string;
}

export class ModelRoutingError extends Error {}
export const MODEL_ROUTING_REGISTRY_URL: URL;
export const MODEL_ROUTING_REASONING_EFFORTS: readonly ModelRoutingReasoningEffort[];
export const modelRoutingRegistry: ModelRoutingRegistry;
export const MODEL_ROUTING_ROLES: readonly AgentRole[];
export const MODEL_ROUTING_TIERS: readonly AgentTier[];
export const MODEL_ROUTING_HARNESSES: readonly ModelRoutingHarness[];

export function validateModelRoutingRegistry(
  value: unknown,
): ModelRoutingRegistry;
export function loadModelRoutingRegistry(url?: URL): ModelRoutingRegistry;
export function routingCatalog(registry?: ModelRoutingRegistry): {
  readonly roles: string[];
  readonly tiers: string[];
  readonly presets: string[];
  readonly harnesses: string[];
  readonly bindings: ModelRoutingRegistry["harnesses"];
};
export function resolveModelRoute(
  registry: ModelRoutingRegistry,
  options: ResolveModelRouteOptions,
): ResolvedModelRoute;
export function resolveDispatchRoute(
  registry: ModelRoutingRegistry,
  options: ResolveDispatchRouteOptions,
): ResolvedModelRoute & {
  readonly selection: "automatic" | "explicit" | "independent-review";
  readonly reviewOfHarness?: string;
  readonly reviewOfProviderFamily?: string;
};
