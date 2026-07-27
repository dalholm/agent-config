#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const registryUrl = new URL("../model-routing.json", import.meta.url);

function fail(message) {
  process.stderr.write(`agent-model-route: ${message}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const options = {};

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith("--")) {
      fail(`unexpected argument "${argument}"`);
    }

    const name = argument.slice(2);
    if (name === "list") {
      options.list = true;
      continue;
    }

    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      fail(`missing value for --${name}`);
    }

    options[name] = value;
    index += 1;
  }

  return options;
}

function routingCatalog(registry) {
  const keys = (value) => Object.keys(value).sort();
  return {
    roles: keys(registry.roles),
    tiers: keys(registry.tiers),
    presets: keys(registry.presets),
    harnesses: keys(registry.harnesses),
    bindings: registry.harnesses,
  };
}

function resolveRoute(registry, options) {
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

function formatRoute(route, format) {
  if (format === "json") {
    return `${JSON.stringify(route, null, 2)}\n`;
  }
  if (format && format !== "text") {
    fail(`unknown format "${format}"`);
  }

  const target =
    [route.provider, route.model].filter(Boolean).join("/") ||
    route.profile ||
    "inherit";
  return (
    [
      `Role: ${route.role}`,
      `Tier: ${route.tier}`,
      `Harness: ${route.harness}`,
      `Target: ${target}`,
      `Reasoning: ${route.reasoning ?? "inherit"}`,
    ].join("\n") + "\n"
  );
}

const options = parseArgs(process.argv.slice(2));
const registry = JSON.parse(await readFile(fileURLToPath(registryUrl), "utf8"));
if (options.list) {
  const catalog = routingCatalog(registry);
  if (options.format === "json") {
    process.stdout.write(`${JSON.stringify(catalog, null, 2)}\n`);
  } else if (!options.format || options.format === "text") {
    for (const [name, values] of Object.entries(catalog)) {
      if (Array.isArray(values)) {
        process.stdout.write(`${name}: ${values.join(", ")}\n`);
        continue;
      }

      const strategies = Object.entries(values)
        .map(([harness, binding]) => `${harness}=${binding.strategy}`)
        .join(", ");
      process.stdout.write(`${name}: ${strategies}\n`);
    }
  } else {
    fail(`unknown format "${options.format}"`);
  }
  process.exit(0);
}

const route = resolveRoute(registry, options);
process.stdout.write(formatRoute(route, options.format));
