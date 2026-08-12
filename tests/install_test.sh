#!/usr/bin/env bash
set -euo pipefail

test_home="$(mktemp -d)"
trap 'rm -rf "$test_home"' EXIT
mkdir -p "$test_home/.config/opencode"
printf '{}\n' > "$test_home/.config/opencode/opencode.jsonc"
output="$(HOME="$test_home" ./install.sh --dry-run --no-bootstrap)"

grep -Fq "(permission profile: safe)" <<<"$output" || {
  echo "install.sh does not default to the safe permission profile" >&2
  exit 1
}

grep -Fq "approval_policy=on-request, sandbox_mode=workspace-write" <<<"$output" || {
  echo "the default Codex profile is not sandboxed and user-gated" >&2
  exit 1
}

grep -Fq "$test_home/.pi/agent/node_modules" <<<"$output" || {
  echo "install.sh does not link Pi extension dependencies into ~/.pi/agent" >&2
  exit 1
}

grep -Fq "$test_home/.hermes/skills/complexity-router" <<<"$output" || {
  echo "install.sh does not link shared skills into ~/.hermes/skills" >&2
  exit 1
}

grep -Fq "$test_home/.hermes/skills/model-routing" <<<"$output" || {
  echo "install.sh does not expose model-routing policy as an on-demand skill" >&2
  exit 1
}

portable_orca_skills=(
  computer-use
  linear-tickets
  orca-cli
  orca-emulator
  orca-emulator-android
  orca-linear
  orca-per-workspace-env
  orchestration
)
for skill in "${portable_orca_skills[@]}"; do
  test -f "$PWD/skills/$skill/SKILL.md" || {
    echo "repository does not own the portable $skill skill" >&2
    exit 1
  }
  grep -Fq "$test_home/.claude/skills/$skill" <<<"$output" || {
    echo "install.sh does not link $skill into Claude skills" >&2
    exit 1
  }
  grep -Fq "$test_home/.hermes/skills/$skill" <<<"$output" || {
    echo "install.sh does not link $skill into Hermes skills" >&2
    exit 1
  }
done

if grep -Fq "merge UserPromptSubmit hook" <<<"$output"; then
  echo "install.sh still injects the workflow router into every prompt" >&2
  exit 1
fi

grep -Fq "$test_home/.config/agent-config/model-routing.json" <<<"$output" || {
  echo "install.sh does not expose the shared model-routing registry" >&2
  exit 1
}

grep -Fq "$test_home/.local/bin/agent-model-route" <<<"$output" || {
  echo "install.sh does not expose the model-routing command" >&2
  exit 1
}

grep -Fq "$test_home/.config/agent-config/safety-policy.json" <<<"$output" || {
  echo "install.sh does not expose the canonical safety policy" >&2
  exit 1
}

grep -Fq "$test_home/.local/bin/agent-safety" <<<"$output" || {
  echo "install.sh does not expose the safety authority command" >&2
  exit 1
}

grep -Fq "$test_home/.config/opencode/AGENTS.md" <<<"$output" || {
  echo "install.sh does not expose shared instructions to OpenCode" >&2
  exit 1
}

# OpenCode auto-scans ~/.claude/skills, so the router only resolves there as long as
# Claude Code happens to be installed. The shared instructions apply to OpenCode too,
# so the skills they reference must be registered on OpenCode's own terms.
grep -Fq "$PWD/skills in skills.paths" <<<"$output" || {
  echo "install.sh does not register shared skills with OpenCode" >&2
  exit 1
}

grep -Fq "$PWD/hooks/deny-dangerous.sh" <<<"$output" || {
  echo "install.sh does not install the catastrophic command guard" >&2
  exit 1
}

grep -Fq 'scripts/agent-safety.mjs" profile' ./install.sh || {
  echo "install.sh does not resolve permissions through the safety authority" >&2
  exit 1
}

if grep -Eq 'CODEX_(APPROVAL|SANDBOX)="(never|on-request|workspace-write|danger-full-access)"' ./install.sh; then
  echo "install.sh still contains an independent Codex permission policy" >&2
  exit 1
fi

grep -Fq 'skills/complexity-router/SKILL.md' ./AGENTS.md || {
  echo "AGENTS.md does not delegate workflow details to complexity-router" >&2
  exit 1
}

grep -Fq 'skills/model-routing/SKILL.md' ./AGENTS.md || {
  echo "AGENTS.md does not delegate model-selection details to model-routing" >&2
  exit 1
}

if grep -Fq '## 4. Provider-independent agent routing' ./AGENTS.md; then
  echo "AGENTS.md still embeds the detailed routing procedure in default context" >&2
  exit 1
fi
