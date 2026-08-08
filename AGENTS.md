# Agent Operating Rules

These are the user's standing instructions. They are the highest-priority
user-owned instructions and operate within system, developer, and safety constraints.

## 1. Dispatch work; answer questions directly

- If the message only asks a question, answer it directly. Do not announce a track,
  role, tier, or workflow.
- Before any build, code change, fix, feature, review, or investigation, load and
  follow [skills/complexity-router/SKILL.md](skills/complexity-router/SKILL.md). It owns
  T0-T3 classification, workflow selection, and upward-only Controller escalation.
- Announce the selected track only when starting work or when the Controller escalates.
- Skills are a menu, not a default pipeline. Use only the skills whose triggers match
  the task; an explicit user invocation takes precedence.

## 2. Keep quality gates on

- Use TDD for behavior-bearing code changes: write one failing behavior test, make it
  pass, and continue in vertical slices.
- For documentation, prompt, wiring, or configuration changes without a meaningful
  behavior test, use the nearest useful verification such as a dry-run, parser check,
  grep assertion, or syntax validation.
- Perform a final self-review before declaring work complete. Do not skip verification
  unless the user explicitly asks for that in the current task.

## 3. Keep authority separate from capability

- `safety-policy.json` is the sole machine-readable authority for safety and autonomy.
  Harness permissions, hooks, launchers, workflows, and skills may enforce it but may
  not independently expand authority.
- Use `agent-safety decide` when an operation's authority is unclear. A model, role,
  tier, preference, execution mode, or child agent never grants additional authority.
- Headless autonomy requires an approved, finite plan, an isolated branch/worktree,
  recorded grants for gated operations, and a healthy policy-defined execution
  profile. Never run autonomously on the main branch.
- Autonomous work stops when the plan is complete, genuinely blocked, or requires a
  fundamental scope change. Detailed T3 behavior lives in `complexity-router` and its
  supporting skills.

## 4. Route at the orchestration boundary

- When selecting or spawning a child agent, workflow agent, or harness model, load and
  follow [skills/model-routing/SKILL.md](skills/model-routing/SKILL.md).
- Agents select a logical `role` and `tier`. `model-routing.json` is the canonical
  registry that maps that request to a harness-specific model or profile.
- The orchestrator owns execution concerns such as task splitting, dependencies,
  worktrees, retries, and parallelism. The harness adapter resolves and binds the model
  at the spawn boundary. Neither owns a duplicate model table.
- Orca owns automatic worker selection. It routes eligible `scout/fast` and
  `coder/fast` work to the registry's local worker unless capability, risk, or an
  explicit user choice requires a frontier harness.
- A reviewer must identify the author harness and, for hybrid or inherited authors,
  the resolved author provider family. Review always uses `deep`, rejects model or
  reasoning overrides, and resolves to a different provider family. A model or
  provider never performs the final review of its own work.

## 5. Write code and documentation in English

Write identifiers, comments, commit messages, READMEs, specs, and inline documentation
in English unless the existing project clearly establishes another language. The
conversation may use another language.

## 6. Keep durable knowledge in the right place

- Stable rules that affect nearly every turn belong here.
- Reusable procedures belong in skills.
- Volatile provider and model bindings belong in registries.
- Project decisions, specs, and plans belong in the Obsidian vault, not as duplicate
  master copies in repositories.

For project context or prior decisions, search the vault before guessing:

`/Users/dalholm/Library/Mobile Documents/iCloud~md~obsidian/Documents/dalholm/`

Store any written spec or plan under:

`/Users/dalholm/Library/Mobile Documents/iCloud~md~obsidian/Documents/dalholm/Projects/{project-slug}/specs/`

Use the lowercase repository or project directory name as `{project-slug}`. If no
project is clear, use `Projects/general/specs/`. Make notes Obsidian-friendly with a
clear title, an internal date stamp, and relevant `[[wikilinks]]`.

## 7. Resolve instruction conflicts consistently

Within system, developer, and safety constraints, user-controlled priority is:

1. Explicit request for the current task.
2. This file or a project-specific user instruction file.
3. Applicable skills.
4. Harness defaults.

If a skill conflicts with these standing or project instructions, follow the user
instruction. Before adding permanent text here, ask whether every agent needs it in
every context; otherwise put it in a skill, registry, or project note.
