import { spawnSync } from "node:child_process";
import { constants } from "node:fs";
import { access, readFile, realpath } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

async function pathMatches(actual, expected) {
  try {
    return (await realpath(actual)) === (await realpath(expected));
  } catch {
    return false;
  }
}

async function settingsContainClaudeGuard(settingsPath, command) {
  try {
    const settings = JSON.parse(await readFile(settingsPath, "utf8"));
    const adapters = settings?.hooks?.PreToolUse;
    return (
      Array.isArray(adapters) &&
      adapters.some(
        (adapter) =>
          adapter?.matcher === "Bash" &&
          Array.isArray(adapter.hooks) &&
          adapter.hooks.some(
            (hook) => hook?.type === "command" && hook.command === command,
          ),
      )
    );
  } catch {
    return false;
  }
}

async function pathExists(path) {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function jsonMatches(path, predicate) {
  try {
    return predicate(JSON.parse(await readFile(path, "utf8")));
  } catch {
    return false;
  }
}

async function codexProfileMatches(path, profile) {
  try {
    const config = await readFile(path, "utf8");
    const values = new Map();
    let insideTable = false;
    for (const rawLine of config.split("\n")) {
      const line = rawLine.trim();
      if (!line || line.startsWith("#")) continue;
      if (line.startsWith("[")) {
        insideTable = true;
        continue;
      }
      if (insideTable) continue;
      const assignment = line.match(
        /^([A-Za-z0-9_-]+)\s*=\s*"([^"]*)"\s*(?:#.*)?$/,
      );
      if (!assignment) continue;
      const [, key, value] = assignment;
      if (values.has(key)) return false;
      values.set(key, value);
    }
    return (
      values.get("approval_policy") === profile.approvalPolicy &&
      values.get("sandbox_mode") === profile.sandbox
    );
  } catch {
    return false;
  }
}

export async function runDoctor(policy, profileName, preflight = false) {
  const profile = policy.profiles[profileName];
  if (!profile) return undefined;
  if (!["repository", "installed-profile"].includes(profile.doctorScope)) {
    return {
      profile: profileName,
      scope: profile.doctorScope,
      healthy: false,
      checks: [
        {
          name: "doctor-scope",
          status: "fail",
          detail: `unknown scope ${JSON.stringify(profile.doctorScope)}`,
        },
      ],
    };
  }

  const patternsPath = fileURLToPath(
    new URL(`../${policy.commandGuard.patternsFile}`, import.meta.url),
  );
  const guardPath = fileURLToPath(
    new URL("../hooks/deny-dangerous.sh", import.meta.url),
  );
  const policyPath = fileURLToPath(
    new URL("../safety-policy.json", import.meta.url),
  );
  const commandPath = fileURLToPath(
    new URL("./agent-safety.mjs", import.meta.url),
  );
  const home = process.env.HOME ?? homedir();
  const checks = [{ name: "doctor-scope", status: "pass" }];

  try {
    const patterns = (await readFile(patternsPath, "utf8"))
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith("#"));
    for (const pattern of patterns) new RegExp(pattern);
    checks.push({
      name: "catastrophic-patterns",
      status: patterns.length > 0 ? "pass" : "fail",
    });
  } catch (error) {
    checks.push({
      name: "catastrophic-patterns",
      status: "fail",
      detail: error instanceof Error ? error.message : String(error),
    });
  }

  try {
    await access(guardPath, constants.X_OK);
    checks.push({ name: "guard-executable", status: "pass" });
  } catch {
    checks.push({ name: "guard-executable", status: "fail" });
  }

  const probe = spawnSync(guardPath, {
    input: '{"tool_input":{"command":"rm -rf /"}}',
    encoding: "utf8",
  });
  checks.push({
    name: "guard-probe",
    status:
      probe.status === 2 && probe.stderr.includes("BLOCKED") ? "pass" : "fail",
  });

  if (profile.doctorScope === "installed-profile") {
    const installedPolicy = join(
      home,
      ".config/agent-config/safety-policy.json",
    );
    const installedCommand = join(home, ".local/bin/agent-safety");
    const claudeSettings = join(home, ".claude/settings.json");
    const openCodeSettings = join(home, ".config/opencode/opencode.jsonc");
    const openCodeConfigured = await pathExists(openCodeSettings);
    checks.push({
      name: "installed-policy",
      status: (await pathMatches(installedPolicy, policyPath))
        ? "pass"
        : "fail",
    });
    checks.push({
      name: "installed-command",
      status: (await pathMatches(installedCommand, commandPath))
        ? "pass"
        : "fail",
    });
    checks.push({
      name: "claude-guard-adapter",
      status: (await settingsContainClaudeGuard(claudeSettings, guardPath))
        ? "pass"
        : "fail",
    });
    if (openCodeConfigured) {
      checks.push({
        name: "opencode-config-readable",
        status: (await jsonMatches(openCodeSettings, () => true))
          ? "pass"
          : "fail",
      });
    }

    if (!preflight) {
      const claudeProfile = profile.harnesses.claude;
      const codexProfile = profile.harnesses.codex;
      const piProfile = profile.harnesses.pi;
      checks.push({
        name: "claude-permission-profile",
        status: (await jsonMatches(
          claudeSettings,
          (settings) =>
            settings?.permissions?.defaultMode === claudeProfile.permissionMode,
        ))
          ? "pass"
          : "fail",
      });
      checks.push({
        name: "codex-permission-profile",
        status: (await codexProfileMatches(
          join(home, ".codex/config.toml"),
          codexProfile,
        ))
          ? "pass"
          : "fail",
      });
      if (openCodeConfigured) {
        const openCodeProfile = profile.harnesses.opencode;
        checks.push({
          name: "opencode-permission-profile",
          status: (await jsonMatches(openCodeSettings, (settings) =>
            ["edit", "bash", "webfetch"].every(
              (operation) =>
                settings?.permission?.[operation] ===
                openCodeProfile.permission,
            ),
          ))
            ? "pass"
            : "fail",
        });
      }
      checks.push({
        name: "pi-permission-profile",
        status: (await jsonMatches(
          join(home, ".pi/agent/settings.json"),
          (settings) =>
            settings?.defaultProjectTrust === piProfile.projectTrust,
        ))
          ? "pass"
          : "fail",
      });
    }
  }

  return {
    profile: profileName,
    scope: profile.doctorScope,
    healthy: checks.every((check) => check.status === "pass"),
    checks,
  };
}
