#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_home="$(mktemp -d)"
trap 'rm -rf "$test_home"' EXIT

mkdir -p \
  "$test_home/.agents/skills/computer-use" \
  "$test_home/.agents/skills/external-only" \
  "$test_home/.config/opencode"
printf '%s\n' \
  '---' \
  'name: computer-use' \
  'description: Duplicate fixture.' \
  '---' > "$test_home/.agents/skills/computer-use/SKILL.md"
printf '%s\n' \
  '---' \
  'name: external-only' \
  'description: Non-repository fixture.' \
  '---' > "$test_home/.agents/skills/external-only/SKILL.md"
printf '{}\n' > "$test_home/.config/opencode/opencode.jsonc"

HOME="$test_home" "$repo/install.sh" --no-bootstrap >/dev/null

HOME="$test_home" node --input-type=module - "$repo" <<'JS'
import { DefaultPackageManager } from "./pi/node_modules/@earendil-works/pi-coding-agent/dist/core/package-manager.js";
import { SettingsManager } from "./pi/node_modules/@earendil-works/pi-coding-agent/dist/core/settings-manager.js";
import { loadSkills } from "./pi/node_modules/@earendil-works/pi-coding-agent/dist/core/skills.js";

const repo = process.argv[2];
const cwd = repo;
const agentDir = `${process.env.HOME}/.pi/agent`;
const settingsManager = SettingsManager.create(cwd, agentDir, {
  projectTrusted: true,
});
const packageManager = new DefaultPackageManager({
  cwd,
  agentDir,
  settingsManager,
});
const resolved = await packageManager.resolve(async () => "skip");
const skillPaths = resolved.skills
  .filter((resource) => resource.enabled)
  .map((resource) => resource.path);
const loaded = loadSkills({
  cwd,
  agentDir,
  skillPaths,
  includeDefaults: false,
});
const collisions = loaded.diagnostics.filter(
  (diagnostic) => diagnostic.type === "collision",
);

if (collisions.length !== 0) {
  throw new Error(`expected no skill collisions, got ${collisions.length}`);
}
if (!loaded.skills.some((skill) => skill.name === "external-only")) {
  throw new Error("non-repository ~/.agents skill was incorrectly disabled");
}
const computerUse = loaded.skills.find((skill) => skill.name === "computer-use");
if (!computerUse?.filePath.startsWith(`${repo}/skills/`)) {
  throw new Error("repo-owned computer-use skill did not win");
}
JS

HOME="$test_home" "$repo/uninstall.sh" --keep-permissions >/dev/null
if jq -e --arg prefix "!$test_home/.agents/skills/{" '
  any((.skills // [])[]; startswith($prefix))
' "$test_home/.pi/agent/settings.json" >/dev/null; then
  echo "uninstall.sh left managed ~/.agents skill exclusions behind" >&2
  exit 1
fi
