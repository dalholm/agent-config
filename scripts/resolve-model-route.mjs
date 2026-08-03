#!/usr/bin/env node

import {
  modelRoutingRegistry,
  resolveModelRoute,
  routingCatalog,
} from "./model-routing.mjs";

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
if (options.list) {
  const catalog = routingCatalog(modelRoutingRegistry);
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

try {
  const route = resolveModelRoute(modelRoutingRegistry, options);
  process.stdout.write(formatRoute(route, options.format));
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}
