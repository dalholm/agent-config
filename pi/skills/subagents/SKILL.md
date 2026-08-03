---
name: subagents
description: Delegate work to isolated Pi, Claude Code, or Codex subagents. Use when the user explicitly asks to use subagents.
---

# Subagents

Each subagent is headless, has its own context window, cannot see the parent conversation, cannot ask the user, and cannot spawn subagents or workflows. Give every child a self-contained prompt with paths, constraints, and the expected report.

## Pi Harness

**Harness:** `pi`
**Prompt nicknames:** “pi”, “pi agent”, “pi subagent”
**Best default:** Use when the user does not request another harness. Supply `role`
and `tier`; Pi inherits the parent model and thinking level unless the user explicitly
overrides `model` or `reasoning_effort`.

Do not use models from the Anthropic provider even if one appears in the model list.

Pi can use any model shown by `pi --list-models`. A concrete Pi model override must
use `provider/model-id`; a bare model id only works when unambiguous.

**Thinking budgets:** `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. These map directly to pi thinking levels.

## Claude Code Harness

**Harness:** `claude`
**Prompt nicknames:** “claude”, “Claude Code”, “claude agent”, “claude subagent”, "cc"
**Model routing:** Supply `role` and `tier`. The spawn seam resolves the canonical
Claude model alias and reasoning effort automatically.

**Thinking budgets:** `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. The extension maps these to Claude thinking-token budgets: 0, 1,024, 4,096, 10,000, 16,000, 32,000, and 63,999 tokens respectively.

Requires Claude Code to be installed and authenticated.

## Codex Harness

**Harness:** `codex`
**Prompt nicknames:** “codex”, “Codex CLI”, “codex agent”, “codex subagent”
**Model routing:** Supply `role` and `tier`. The spawn seam resolves the canonical
Codex model and reasoning effort automatically.

**Thinking budgets accepted by the extension:** `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. Codex maps these to the nearest effort supported by the selected model; `off`/`minimal` become `minimal`, while `max` becomes the highest extension-supported Codex effort.

Requires the Codex CLI to be installed and authenticated.

## Spawn and Manage

Choose the child's role and tier before spawning it. Call `subagent_spawn` with a
complete prompt, short `name`, chosen `harness`, `role`, `tier`, and optional
`working_dir`. Use `model` or `reasoning_effort` only for an explicit user override;
those values take precedence over the canonical binding. At most four subagents run
concurrently.

- `subagent_check({ id })`: peek without blocking.
- `subagent_list()`: list all runs.
- `subagent_wait({ ids })`: block only when results are required to proceed.
- `subagent_cancel({ ids })`: stop runs while preserving partial transcripts.
- `/subagents`: inspect or take over a run interactively.

Results return automatically. After spawning, continue useful parent work instead of immediately waiting.
