#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook.
# Injects the complexity-router directive into context on every turn, so the router
# fires reliably even if the model would otherwise skip it. This is the deterministic
# layer — it does not depend on the model "remembering" CLAUDE.md.
#
# For UserPromptSubmit hooks, anything printed to stdout is added to the model's
# context for that turn. Keep it short to conserve tokens.

cat <<'EOF'
[router] First decide whether this is only a question. If yes, answer directly as T0
and do not enter a code/change workflow. For build/code/fix/change work, classify task
complexity and pick a track (T0 trivial → T3 full Superpowers) per AGENTS.md. Announce
it in one line. Bias heavier when unsure. Keep TDD for behavior changes; use dry-run or
syntax/grep verification for pure docs/config/prompt changes. Escalate mid-task if the
work grows (more files than assumed, hard-to-write test, unplanned design decision).
EOF

exit 0
