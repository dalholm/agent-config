import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const MODEL_ROUTING_REGISTRY_URL = new URL(
  "../model-routing.json",
  import.meta.url,
);
export const MODEL_ROUTING_REASONING_EFFORTS = Object.freeze([
  "off",
  "minimal",
  "low",
  "medium",
  "high",
  "xhigh",
  "max",
]);

export class ModelRoutingError extends Error {
  constructor(message) {
    super(message);
    this.name = "ModelRoutingError";
  }
}

function fail(message) {
  throw new ModelRoutingError(message);
}

function record(value, path) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${path} must be an object`);
  }
  return value;
}

function string(value, path) {
  if (typeof value !== "string" || !value) fail(`${path} must be a string`);
  return value;
}

function optionalString(value, path) {
  if (value !== undefined) string(value, path);
}

function validateTarget(value, path) {
  const target = record(value, path);
  optionalString(target.provider, `${path}.provider`);
  optionalString(target.model, `${path}.model`);
  optionalString(target.profile, `${path}.profile`);
  optionalString(target.reasoning, `${path}.reasoning`);
  if (
    target.reasoning &&
    !MODEL_ROUTING_REASONING_EFFORTS.includes(target.reasoning)
  ) {
    fail(`${path} has unsupported reasoning effort "${target.reasoning}"`);
  }
  if (!target.model && !target.profile) {
    fail(`${path} must define model or profile`);
  }
}

export function validateModelRoutingRegistry(value) {
  const registry = record(value, "registry");
  if (registry.schemaVersion !== 1) fail("schemaVersion must be 1");

  const defaultRoute = record(registry.defaultRoute, "defaultRoute");
  const roles = record(registry.roles, "roles");
  const tiers = record(registry.tiers, "tiers");
  const presets = record(registry.presets, "presets");
  const harnesses = record(registry.harnesses, "harnesses");
  if (!Object.keys(roles).length) fail("roles must not be empty");
  if (!Object.keys(tiers).length) fail("tiers must not be empty");
  if (!Object.keys(harnesses).length) fail("harnesses must not be empty");

  for (const [role, config] of Object.entries(roles)) {
    string(
      record(config, `roles.${role}`).description,
      `roles.${role}.description`,
    );
  }
  for (const [tier, config] of Object.entries(tiers)) {
    const entry = record(config, `tiers.${tier}`);
    string(entry.description, `tiers.${tier}.description`);
    string(entry.reasoningIntent, `tiers.${tier}.reasoningIntent`);
  }

  const defaultRole = string(defaultRoute.role, "defaultRoute.role");
  const defaultTier = string(defaultRoute.tier, "defaultRoute.tier");
  if (!roles[defaultRole])
    fail(`defaultRoute.role references unknown role "${defaultRole}"`);
  if (!tiers[defaultTier])
    fail(`defaultRoute.tier references unknown tier "${defaultTier}"`);

  for (const [preset, config] of Object.entries(presets)) {
    const entry = record(config, `presets.${preset}`);
    const role = string(entry.role, `presets.${preset}.role`);
    const tier = string(entry.tier, `presets.${preset}.tier`);
    if (!roles[role])
      fail(`presets.${preset}.role references unknown role "${role}"`);
    if (!tiers[tier])
      fail(`presets.${preset}.tier references unknown tier "${tier}"`);
  }

  for (const [harness, config] of Object.entries(harnesses)) {
    const entry = record(config, `harnesses.${harness}`);
    const strategy = string(entry.strategy, `harnesses.${harness}.strategy`);
    if (!["explicit", "preset", "inherit"].includes(strategy)) {
      fail(`harnesses.${harness}.strategy is unknown`);
    }
    if (
      strategy === "inherit" &&
      (entry.tiers !== undefined ||
        entry.roleOverrides !== undefined ||
        entry.presetBindings !== undefined)
    ) {
      fail(
        `harnesses.${harness} strategy "inherit" must not define explicit bindings`,
      );
    }
    if (
      strategy === "preset" &&
      (entry.tiers !== undefined || entry.roleOverrides !== undefined)
    ) {
      fail(
        `harnesses.${harness} strategy "preset" must not define tier or role bindings`,
      );
    }
    const tierBindings =
      entry.tiers === undefined
        ? {}
        : record(entry.tiers, `harnesses.${harness}.tiers`);
    for (const [tier, target] of Object.entries(tierBindings)) {
      if (!tiers[tier])
        fail(`harnesses.${harness}.tiers references unknown tier "${tier}"`);
      validateTarget(target, `harnesses.${harness}.tiers.${tier}`);
    }
    const roleOverrides =
      entry.roleOverrides === undefined
        ? {}
        : record(entry.roleOverrides, `harnesses.${harness}.roleOverrides`);
    for (const [role, tierMap] of Object.entries(roleOverrides)) {
      if (!roles[role])
        fail(
          `harnesses.${harness}.roleOverrides references unknown role "${role}"`,
        );
      for (const [tier, target] of Object.entries(
        record(tierMap, `harnesses.${harness}.roleOverrides.${role}`),
      )) {
        if (!tiers[tier])
          fail(
            `harnesses.${harness}.roleOverrides.${role} references unknown tier "${tier}"`,
          );
        validateTarget(
          target,
          `harnesses.${harness}.roleOverrides.${role}.${tier}`,
        );
      }
    }
    const presetBindings =
      entry.presetBindings === undefined
        ? {}
        : record(entry.presetBindings, `harnesses.${harness}.presetBindings`);
    for (const [preset, target] of Object.entries(presetBindings)) {
      if (!presets[preset])
        fail(
          `harnesses.${harness}.presetBindings references unknown preset "${preset}"`,
        );
      validateTarget(target, `harnesses.${harness}.presetBindings.${preset}`);
    }
  }

  return registry;
}

export function loadModelRoutingRegistry(url = MODEL_ROUTING_REGISTRY_URL) {
  let parsed;
  try {
    parsed = JSON.parse(readFileSync(fileURLToPath(url), "utf8"));
  } catch (error) {
    fail(
      `cannot read registry: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
  return validateModelRoutingRegistry(parsed);
}

export const modelRoutingRegistry = loadModelRoutingRegistry();
export const MODEL_ROUTING_ROLES = Object.freeze(
  Object.keys(modelRoutingRegistry.roles).sort(),
);
export const MODEL_ROUTING_TIERS = Object.freeze(
  Object.keys(modelRoutingRegistry.tiers).sort(),
);
export const MODEL_ROUTING_HARNESSES = Object.freeze(
  Object.keys(modelRoutingRegistry.harnesses).sort(),
);

export function routingCatalog(registry = modelRoutingRegistry) {
  const keys = (entry) => Object.keys(entry).sort();
  return {
    roles: keys(registry.roles),
    tiers: keys(registry.tiers),
    presets: keys(registry.presets),
    harnesses: keys(registry.harnesses),
    bindings: registry.harnesses,
  };
}

export function resolveModelRoute(registry, options) {
  registry = validateModelRoutingRegistry(registry);
  if (options.preset && (options.role || options.tier)) {
    fail("--preset cannot be combined with --role or --tier");
  }
  const preset = options.preset ? registry.presets[options.preset] : undefined;
  if (options.preset && !preset) fail(`unknown preset "${options.preset}"`);

  const role = preset?.role ?? options.role ?? registry.defaultRoute.role;
  const tier = preset?.tier ?? options.tier ?? registry.defaultRoute.tier;
  const harness = options.harness;
  if (!harness) fail("--harness is required");
  if (!registry.roles[role]) fail(`unknown role "${role}"`);
  if (!registry.tiers[tier]) fail(`unknown tier "${tier}"`);

  const harnessConfig = registry.harnesses[harness];
  if (!harnessConfig) fail(`unknown harness "${harness}"`);
  const target =
    (options.preset
      ? harnessConfig.presetBindings?.[options.preset]
      : undefined) ??
    harnessConfig.roleOverrides?.[role]?.[tier] ??
    harnessConfig.tiers?.[tier];
  if (!target && harnessConfig.strategy !== "inherit") {
    fail(`harness "${harness}" has no binding for tier "${tier}"`);
  }

  return {
    ...(options.preset ? { preset: options.preset } : {}),
    role,
    tier,
    harness,
    strategy: harnessConfig.strategy,
    ...(target ?? {}),
  };
}
