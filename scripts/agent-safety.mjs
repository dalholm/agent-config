#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { runDoctor } from "./safety-doctor.mjs";

const policyUrl = new URL("../safety-policy.json", import.meta.url);

function fail(message) {
  process.stderr.write(`agent-safety: ${message}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (!command) fail("a command is required");

  const options = {};
  for (let index = 0; index < rest.length; index += 1) {
    const argument = rest[index];
    if (!argument.startsWith("--")) {
      fail(`unexpected argument "${argument}"`);
    }

    const name = argument.slice(2);
    const value = rest[index + 1];
    if (!value || value.startsWith("--")) {
      fail(`missing value for --${name}`);
    }

    options[name] = value;
    index += 1;
  }

  return { command, options };
}

function parseAuthorized(value) {
  if (value === "true") return true;
  if (value === "false") return false;
  fail('--authorized must be "true" or "false"');
}

function resolveDecision(policy, options) {
  const operation = options.operation;
  const mode = options.mode;
  if (!operation) fail("--operation is required");
  if (!mode) fail("--mode is required");
  if (!policy.operations[operation]) fail(`unknown operation "${operation}"`);
  if (!policy.modes[mode]) fail(`unknown mode "${mode}"`);

  const authorized = parseAuthorized(options.authorized);
  const rule = policy.operations[operation];
  const grantSatisfied = authorized && rule.decision === "require-user";
  return {
    operation,
    mode,
    authorized,
    decision: grantSatisfied ? "allow" : rule.decision,
    basis: grantSatisfied ? "explicit-user-grant" : "policy",
    reason: rule.reason,
  };
}

function resolveProfile(policy, options) {
  const profileName = options.profile;
  const harness = options.harness;
  if (!profileName) fail("--profile is required");
  if (!harness) fail("--harness is required");

  const profile = policy.profiles[profileName];
  if (!profile) fail(`unknown profile "${profileName}"`);
  const target = profile.harnesses[harness];
  if (!target) {
    fail(`profile "${profileName}" has no adapter for harness "${harness}"`);
  }

  return {
    profile: profileName,
    harness,
    doctorScope: profile.doctorScope,
    ...target,
  };
}

async function checkCommand(policy, options) {
  const command = options.command;
  if (!command) fail("--command is required");

  const patternsUrl = new URL(
    `../${policy.commandGuard.patternsFile}`,
    import.meta.url,
  );
  const patterns = (await readFile(fileURLToPath(patternsUrl), "utf8"))
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"));
  const normalizedCommand = command.replace(/["']/g, "");
  const pattern = patterns.find((candidate) => {
    const expression = new RegExp(candidate);
    return expression.test(command) || expression.test(normalizedCommand);
  });
  if (!pattern) return;

  const rule = policy.operations[policy.commandGuard.operation];
  if (rule.decision !== "deny") {
    fail("the command guard operation is not denied by policy");
  }

  process.stderr.write(
    `BLOCKED: command matches catastrophic pattern ${JSON.stringify(pattern)}\n`,
  );
  process.exit(2);
}

function record(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value
    : undefined;
}

async function commandFromHookInput() {
  let input = "";
  for await (const chunk of process.stdin) input += chunk;

  let payload;
  try {
    payload = JSON.parse(input);
  } catch {
    fail("hook input is not valid JSON");
  }

  const root = record(payload);
  const toolInput = record(root?.tool_input) ?? record(root?.toolInput);
  const command = toolInput?.command ?? root?.command;
  if (typeof command !== "string" || !command.trim()) {
    fail("hook input has no shell command");
  }
  return command;
}

function formatDoctor(report, format) {
  if (format === "json") return `${JSON.stringify(report, null, 2)}\n`;
  if (format && format !== "text") fail(`unknown format "${format}"`);
  return (
    [
      `Safety doctor: ${report.healthy ? "healthy" : "unhealthy"}`,
      `Profile: ${report.profile}`,
      ...report.checks.map(
        (check) =>
          `${check.status === "pass" ? "PASS" : "FAIL"} ${check.name}${check.detail ? `: ${check.detail}` : ""}`,
      ),
    ].join("\n") + "\n"
  );
}

function formatDecision(decision, format) {
  if (format === "json") return `${JSON.stringify(decision, null, 2)}\n`;
  if (format && format !== "text") fail(`unknown format "${format}"`);
  return (
    [
      `Operation: ${decision.operation}`,
      `Mode: ${decision.mode}`,
      `Decision: ${decision.decision}`,
      `Basis: ${decision.basis}`,
      `Reason: ${decision.reason}`,
    ].join("\n") + "\n"
  );
}

const { command, options } = parseArgs(process.argv.slice(2));
const policy = JSON.parse(await readFile(fileURLToPath(policyUrl), "utf8"));
if (command === "decide") {
  const decision = resolveDecision(policy, options);
  process.stdout.write(formatDecision(decision, options.format));
} else if (command === "profile") {
  const profile = resolveProfile(policy, options);
  if (options.format && options.format !== "json") {
    fail('profile currently requires "--format json"');
  }
  process.stdout.write(`${JSON.stringify(profile, null, 2)}\n`);
} else if (command === "check-command") {
  await checkCommand(policy, options);
} else if (command === "hook") {
  await checkCommand(policy, { command: await commandFromHookInput() });
} else if (command === "doctor") {
  const profileName = options.profile ?? "safe";
  const preflight = options.preflight === "true";
  if (options.preflight && !["true", "false"].includes(options.preflight)) {
    fail('--preflight must be "true" or "false"');
  }
  const report = await runDoctor(policy, profileName, preflight);
  if (!report) fail(`unknown profile "${profileName}"`);
  process.stdout.write(formatDoctor(report, options.format));
  if (!report.healthy) process.exit(1);
} else {
  fail(`unknown command "${command}"`);
}
