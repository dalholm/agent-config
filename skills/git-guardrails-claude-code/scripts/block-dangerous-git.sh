#!/usr/bin/env bash
set -euo pipefail

input="$(cat)"
classification="$(
  node -e '
  const payload = JSON.parse(process.argv[1]);
  const command = payload?.tool_input?.command;
  if (typeof command !== "string") process.exit(2);

  const tokens = [];
  let token = "";
  let quote = "";
  let escaped = false;
  const push = () => {
    if (token) tokens.push(token);
    token = "";
  };
  for (const character of command) {
    if (escaped) {
      token += character;
      escaped = false;
    } else if (character === "\\") {
      escaped = true;
    } else if (quote) {
      if (character === quote) quote = "";
      else token += character;
    } else if (character === "\"" || character === "\u0027") {
      quote = character;
    } else if (/\s/.test(character)) {
      push();
    } else if (/[;&|]/.test(character)) {
      push();
      tokens.push(character);
    } else {
      token += character;
    }
  }
  if (escaped || quote) process.exit(2);
  push();

  const operators = new Set([";", "&", "|"]);
  const optionsWithValues = new Set([
    "-C",
    "-c",
    "--git-dir",
    "--work-tree",
    "--namespace",
    "--super-prefix",
    "--config-env",
    "--exec-path",
  ]);
  let operation = "";
  for (let gitIndex = 0; gitIndex < tokens.length; gitIndex += 1) {
    if (tokens[gitIndex].split("/").at(-1) !== "git") continue;
    let index = gitIndex + 1;
    while (index < tokens.length && tokens[index].startsWith("-")) {
      const option = tokens[index];
      const optionName = option.split("=", 1)[0];
      index += optionsWithValues.has(optionName) && !option.includes("=") ? 2 : 1;
    }
    const subcommand = tokens[index];
    if (!subcommand || operators.has(subcommand)) continue;
    const args = [];
    for (index += 1; index < tokens.length && !operators.has(tokens[index]); index += 1) {
      args.push(tokens[index]);
    }
    const shortBranchFlags = args
      .filter((arg) => /^-[^-]/.test(arg))
      .join("");
    const forcedBranchDelete =
      args.includes("-D") ||
      ((args.includes("--delete") || shortBranchFlags.includes("d")) &&
        (args.includes("--force") || shortBranchFlags.includes("f")));

    if (subcommand === "push") {
      operation = "external-write";
    } else if (
      (subcommand === "reset" && args.includes("--hard")) ||
      (subcommand === "clean" &&
        args.some((arg) => arg === "--force" || /^-[^-]*f/.test(arg))) ||
      (subcommand === "branch" && forcedBranchDelete) ||
      (["checkout", "restore"].includes(subcommand) &&
        args.some((arg) => [".", "./", ":/"].includes(arg)))
    ) {
      operation = "destructive-local";
    }
    if (operation) break;
  }

  process.stdout.write(JSON.stringify({ command, operation }));
  ' "$input"
)" || {
  echo "BLOCKED: git guard received invalid hook input." >&2
  exit 2
}

command="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).command)' "$classification")"
operation="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).operation)' "$classification")"
[ -n "$operation" ] || exit 0

safety_command="${AGENT_SAFETY_COMMAND:-agent-safety}"
if ! command -v "$safety_command" >/dev/null 2>&1; then
  echo "BLOCKED: agent-safety is unavailable; the git guard fails closed." >&2
  exit 2
fi

set +e
decision_json="$(
  "$safety_command" decide \
    --operation "$operation" \
    --mode interactive \
    --authorized false \
    --format json
)"
decision_status=$?
set -e
if [ "$decision_status" -ne 0 ]; then
  echo "BLOCKED: agent-safety could not resolve the git operation." >&2
  exit 2
fi

decision="$(
  node -e '
  const result = JSON.parse(process.argv[1]);
  if (typeof result?.decision !== "string") process.exit(2);
  process.stdout.write(result.decision);
  ' "$decision_json"
)" || {
  echo "BLOCKED: agent-safety returned an invalid decision." >&2
  exit 2
}

if [ "$decision" != "allow" ]; then
  echo "BLOCKED: agent-safety requires explicit user authority for $operation: '$command'." >&2
  exit 2
fi
