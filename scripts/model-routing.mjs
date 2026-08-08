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
  if (registry.schemaVersion !== 2) fail("schemaVersion must be 2");

  const defaultRoute = record(registry.defaultRoute, "defaultRoute");
  const providers = record(registry.providers, "providers");
  const roles = record(registry.roles, "roles");
  const tiers = record(registry.tiers, "tiers");
  const presets = record(registry.presets, "presets");
  const harnesses = record(registry.harnesses, "harnesses");
  const dispatch = record(registry.dispatch, "dispatch");
  if (!Object.keys(roles).length) fail("roles must not be empty");
  if (!Object.keys(tiers).length) fail("tiers must not be empty");
  if (!Object.keys(harnesses).length) fail("harnesses must not be empty");
  if (!Object.keys(providers).length) fail("providers must not be empty");

  for (const [provider, config] of Object.entries(providers)) {
    const entry = record(config, `providers.${provider}`);
    string(entry.family, `providers.${provider}.family`);
    if (typeof entry.local !== "boolean") {
      fail(`providers.${provider}.local must be a boolean`);
    }
  }

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
    if (!["explicit", "preset", "inherit", "hybrid"].includes(strategy)) {
      fail(`harnesses.${harness}.strategy is unknown`);
    }
    string(entry.providerFamily, `harnesses.${harness}.providerFamily`);
    if (strategy === "hybrid" && entry.providerFamily !== "dynamic") {
      fail(
        `harnesses.${harness} strategy "hybrid" must use providerFamily "dynamic"`,
      );
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
      validateHarnessTarget(
        registry,
        harness,
        entry,
        target,
        `harnesses.${harness}.tiers.${tier}`,
      );
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
        validateHarnessTarget(
          registry,
          harness,
          entry,
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
      validateHarnessTarget(
        registry,
        harness,
        entry,
        target,
        `harnesses.${harness}.presetBindings.${preset}`,
      );
    }
  }

  if (!Array.isArray(dispatch.automaticRoutes)) {
    fail("dispatch.automaticRoutes must be an array");
  }
  const automaticKeys = new Set();
  for (const [index, config] of dispatch.automaticRoutes.entries()) {
    const entry = record(config, `dispatch.automaticRoutes.${index}`);
    const role = string(entry.role, `dispatch.automaticRoutes.${index}.role`);
    const tier = string(entry.tier, `dispatch.automaticRoutes.${index}.tier`);
    const harness = string(
      entry.harness,
      `dispatch.automaticRoutes.${index}.harness`,
    );
    if (!roles[role])
      fail(
        `dispatch.automaticRoutes.${index} references unknown role "${role}"`,
      );
    if (!tiers[tier])
      fail(
        `dispatch.automaticRoutes.${index} references unknown tier "${tier}"`,
      );
    if (!harnesses[harness])
      fail(
        `dispatch.automaticRoutes.${index} references unknown harness "${harness}"`,
      );
    const key = `${role}/${tier}`;
    if (automaticKeys.has(key)) fail(`duplicate automatic route "${key}"`);
    automaticKeys.add(key);
    const target =
      harnesses[harness].roleOverrides?.[role]?.[tier] ??
      harnesses[harness].tiers?.[tier];
    if (!target)
      fail(`automatic route "${key}" has no binding on harness "${harness}"`);
    const provider = target.provider;
    if (!provider || !providers[provider]?.local) {
      fail(`automatic route "${key}" must resolve to a local provider`);
    }
  }

  const independentReview = record(
    dispatch.independentReview,
    "dispatch.independentReview",
  );
  const reviewMap = record(
    independentReview.byAuthorProviderFamily,
    "dispatch.independentReview.byAuthorProviderFamily",
  );
  const knownFamilies = new Set(
    Object.values(providers).map((provider) => provider.family),
  );
  for (const [authorFamily, reviewerHarnessValue] of Object.entries(
    reviewMap,
  )) {
    const reviewerHarness = string(
      reviewerHarnessValue,
      `dispatch.independentReview.byAuthorProviderFamily.${authorFamily}`,
    );
    if (!knownFamilies.has(authorFamily))
      fail(
        `independent review references unknown provider family "${authorFamily}"`,
      );
    if (!harnesses[reviewerHarness])
      fail(
        `independent review references unknown reviewer harness "${reviewerHarness}"`,
      );
    if (harnesses[reviewerHarness].providerFamily === authorFamily) {
      fail(
        `independent review for provider family "${authorFamily}" must use a different provider family`,
      );
    }
    const reviewTarget =
      harnesses[reviewerHarness].roleOverrides?.reviewer?.deep ??
      harnesses[reviewerHarness].tiers?.deep;
    if (!reviewTarget)
      fail(
        `independent reviewer harness "${reviewerHarness}" has no deep binding`,
      );
    if (!reviewTarget.provider || providers[reviewTarget.provider]?.local) {
      fail(
        `independent reviewer harness "${reviewerHarness}" must use a frontier provider`,
      );
    }
  }

  return registry;
}

function validateHarnessTarget(registry, harness, harnessConfig, target, path) {
  const provider = target.provider;
  if (!provider || !registry.providers[provider]) {
    fail(`${path}.provider must reference a known provider`);
  }
  const providerConfig = registry.providers[provider];
  if (harnessConfig.strategy === "hybrid" && !providerConfig.local) {
    fail(`harnesses.${harness} strategy "hybrid" must use a local provider`);
  }
  if (
    ["explicit", "preset"].includes(harnessConfig.strategy) &&
    providerConfig.family !== harnessConfig.providerFamily
  ) {
    fail(`${path} must use provider family "${harnessConfig.providerFamily}"`);
  }
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
  if (!target && !["inherit", "hybrid"].includes(harnessConfig.strategy)) {
    fail(`harness "${harness}" has no binding for tier "${tier}"`);
  }

  return {
    ...(options.preset ? { preset: options.preset } : {}),
    role,
    tier,
    harness,
    strategy: harnessConfig.strategy,
    providerFamily: target?.provider
      ? registry.providers[target.provider].family
      : harnessConfig.providerFamily,
    ...(target ?? {}),
  };
}

export function resolveDispatchRoute(registry, options) {
  registry = validateModelRoutingRegistry(registry);
  if (options.preset && (options.role || options.tier)) {
    fail("--preset cannot be combined with --role or --tier");
  }
  const preset = options.preset ? registry.presets[options.preset] : undefined;
  if (options.preset && !preset) fail(`unknown preset "${options.preset}"`);
  const role = preset?.role ?? options.role ?? registry.defaultRoute.role;
  const tier = preset?.tier ?? options.tier ?? registry.defaultRoute.tier;
  if (!registry.roles[role]) fail(`unknown role "${role}"`);
  if (!registry.tiers[tier]) fail(`unknown tier "${tier}"`);

  if (role === "reviewer") {
    if (tier !== "deep") fail("reviewer routes must use tier deep");
    if (options.preset) fail("reviewer routes must not use presets");
    if (!options.reviewOfHarness)
      fail("reviewOfHarness is required for reviewer routes");
    const authorConfig = registry.harnesses[options.reviewOfHarness];
    if (!authorConfig) fail(`unknown harness "${options.reviewOfHarness}"`);
    let authorProviderFamily = options.reviewOfProviderFamily;
    if (["inherit", "hybrid"].includes(authorConfig.strategy)) {
      if (!authorProviderFamily) {
        fail(
          `reviewOfProviderFamily is required when reviewing ${authorConfig.strategy} harness "${options.reviewOfHarness}"`,
        );
      }
    } else if (
      authorProviderFamily &&
      authorProviderFamily !== authorConfig.providerFamily
    ) {
      fail(
        `reviewOfProviderFamily "${authorProviderFamily}" does not match harness "${options.reviewOfHarness}"`,
      );
    } else {
      authorProviderFamily = authorConfig.providerFamily;
    }
    const knownFamilies = new Set(
      Object.values(registry.providers).map((provider) => provider.family),
    );
    if (!knownFamilies.has(authorProviderFamily)) {
      fail(`unknown reviewOfProviderFamily "${authorProviderFamily}"`);
    }
    const reviewerHarness =
      registry.dispatch.independentReview.byAuthorProviderFamily[
        authorProviderFamily
      ];
    if (!reviewerHarness) {
      fail(
        `no independent review route for provider family "${authorProviderFamily}"`,
      );
    }
    if (options.harness && options.harness !== reviewerHarness) {
      fail(
        `independent review of "${options.reviewOfHarness}" must use "${reviewerHarness}", not "${options.harness}"`,
      );
    }
    const reviewRoute = resolveModelRoute(registry, {
      harness: reviewerHarness,
      role,
      tier,
    });
    if (reviewRoute.providerFamily === authorProviderFamily) {
      fail("independent review must use a different provider family");
    }
    return {
      ...reviewRoute,
      selection: "independent-review",
      reviewOfHarness: options.reviewOfHarness,
      reviewOfProviderFamily: authorProviderFamily,
    };
  }
  if (options.reviewOfHarness || options.reviewOfProviderFamily) {
    fail("review provenance is only valid for reviewer routes");
  }

  if (role === "scout" && options.harness && options.harness !== "pi") {
    fail("scout routes must use the local Pi worker");
  }

  if (options.harness) {
    return {
      ...resolveModelRoute(
        registry,
        options.preset
          ? { harness: options.harness, preset: options.preset }
          : { harness: options.harness, role, tier },
      ),
      selection: "explicit",
    };
  }

  const automatic = registry.dispatch.automaticRoutes.find(
    (entry) => entry.role === role && entry.tier === tier,
  );
  if (!automatic) {
    fail(
      `--harness is required for ${role}/${tier}; no automatic route exists`,
    );
  }
  return {
    ...resolveModelRoute(registry, {
      harness: automatic.harness,
      role,
      tier,
      ...(options.preset ? { preset: options.preset } : {}),
    }),
    selection: "automatic",
  };
}
