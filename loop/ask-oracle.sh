#!/usr/bin/env bash
# ask-oracle.sh — the preference-oracle: the user's skeptical, YAGNI-biased stand-in.
#
# The oracle now runs on a cloud coding CLI (Claude, falling back to Codex) via
# ask-cli-helper.sh — NOT on local gemma. This keeps it a genuinely independent voice,
# separate from the builder model, while giving it strong-tier judgment. The entrypoint
# name and the output contract are unchanged, so every `loop/ask-oracle.sh "…"` call in
# loop-prompt.md keeps working as-is.
#
# Usage:
#   ./ask-oracle.sh "<question + the context the oracle needs to judge>"
# Prints the oracle's verdict (APPROVE/REJECT + basis) to stdout, in the skill's format.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../skills/preference-oracle/SKILL.md"
HELPER="$SCRIPT_DIR/ask-cli-helper.sh"

QUESTION="${1:-}"
if [ -z "$QUESTION" ]; then
  echo "usage: ask-oracle.sh \"<question + context>\"" >&2
  exit 2
fi

# Load the preference-oracle persona. The CLI doesn't load pi's `--skill`, so we inline
# the skill text as the system framing — a faithful port of the same rules.
PERSONA="$(cat "$SKILL_MD" 2>/dev/null || true)"

PROMPT="You are the preference-oracle — the user's autonomous, skeptical, YAGNI-biased
stand-in during a hands-off run. You are running on your OWN model, independent of and
separate from the builder. Be adversarial and conservative: steelman the objection first,
default to the smaller thing, defend the project's locked decisions, and never sign off a
phase without the gate actually green. Read preferences.md and the cited spec before
deciding; if a call isn't grounded in those, your default is no.

Answer ONLY in the skill's output format:
  Oracle: <APPROVE | REJECT>
  Question: <restated>
  Strongest objection: <the devil's-advocate case>
  Decision: <the call>
  Basis: <preferences.md section / spec ref / derived YAGNI default>
  Recorded: <yes — added to Auto Tasks notes>   # for high-stakes calls

=== preference-oracle skill (your operating rules) ===
${PERSONA}
=== end skill ===

=== the question + context to decide ===
${QUESTION}"

# Tag the channel so the chat transcript shows this as an ORACLE consultation
# (not a generic stronger-model call).
HELPER_CHANNEL=oracle exec "$HELPER" "$PROMPT"
