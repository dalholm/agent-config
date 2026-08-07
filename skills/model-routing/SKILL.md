---
name: model-routing
description: Select and bind a logical agent role and capability tier when dispatching subagents, workflow agents, reviews, or harness-specific model runs. Use at the spawn or orchestration boundary, not for ordinary direct answers.
---

# Model Routing

Keep task semantics independent from providers. Select a logical role and tier first;
resolve the concrete model only at the harness launch boundary.

## Ownership boundaries

- The calling agent chooses the next concrete step's `role` and `tier`.
- An orchestrator such as Orca owns decomposition, dependencies, worktrees, retries,
  scheduling, and parallelism.
- `model-routing.json` owns role/tier-to-model and profile bindings.
- The harness adapter calls the resolver and applies the returned binding at spawn.
- Skills describe how work is performed. They do not own model bindings.

Do not copy provider or model tables into prompts, skills, Orca workflows, or harness
configuration. Pass logical routing metadata across those seams instead.

## Roles

Choose the role for the next concrete step, not the entire conversation.

| Role | Use for |
|------|---------|
| `generalist` | Direct questions and ordinary mixed work |
| `researcher` | Gathering, verifying, and synthesizing sources |
| `coder` | Implementation, debugging, refactoring, and tests |
| `designer` | Product, UX, interface, and system design |
| `reviewer` | Independent verification of completed work |
| `orchestrator` | Splitting and coordinating multi-step work |

Selection priority:

1. Explicit user selection.
2. Workflow or task capability requirement.
3. Project override.
4. Parent-agent assignment.
5. The role table above.
6. `generalist` when no specialist role fits.

## Tiers

| Tier | Use for |
|------|---------|
| `fast` | Low-risk routine work where latency matters |
| `standard` | Normal implementation, research, and coordination |
| `deep` | Difficult, high-risk, architectural, or final-review work |

Start with the cheapest tier that can safely complete the step. Escalate when sources
conflict, stakes are high, synthesis is difficult, the first result is insufficient,
or the task is architectural or security-sensitive. Routine research is not
automatically deep. Mechanical implementation from a clear specification is normally
fast; integration and debugging are normally standard.

## Resolve the harness binding

The installed registry lives at `~/.config/agent-config/model-routing.json`. Inspect
its supported roles, tiers, presets, and harnesses with:

```sh
agent-model-route --list
```

Resolve before supplying an explicit child model:

```sh
agent-model-route --harness codex --role coder --tier standard
agent-model-route --harness claude --role researcher --tier deep
agent-model-route --harness hermes --preset designer
```

If the installed command is unavailable, read the repository's `model-routing.json`.
Do not invent a binding.

The registry supports three strategies:

- `explicit`: bind the logical route to a concrete provider, model, and reasoning
  effort.
- `preset`: select only a real isolated harness profile. Hermes uses verified presets;
  do not manufacture unsupported role/tier combinations.
- `inherit`: retain the active harness model and reasoning. Never reinterpret inherit
  as permission to route through a paid provider.

Explicit user model or profile selection takes precedence, followed by capability and
independence constraints, project overrides, the canonical registry binding, and then
a permitted inherited fallback.

## Child and review rules

- A parent supplies an explicit role and tier whenever the child interface supports
  them. The child does not infer its assignment from a vague title.
- Record the requested role/tier, resolved target, and any fallback in run metadata or
  the result when the harness supports it.
- For an explicitly independent security or final review, prefer a different model
  family and provider from the author when one is available. Do not silently downgrade
  the requested review tier.
