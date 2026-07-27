# Agent Operating Rules

These are my (the user's) standing instructions. They are the **highest priority**
context: they override skills and the default system prompt. If a skill or the system
prompt conflicts with this file, this file wins.

---

## 0. THE ROUTER — run this FIRST, before anything else

Before invoking **any** skill — and before asking clarifying questions — first decide
whether the user's message is asking for work or only asking a question. If it is only
a question, answer it directly as T0 and do **not** enter a code/change workflow. If it
asks for a build, code change, fix, feature, implementation, review, investigation, or
other work, classify the task's complexity and pick a track.
The router is a **dispatcher**: it decides how much process the task needs and which
of the available skills, if any, apply. Skills are a menu, not a default pipeline.

### Tracks

| Track | Looks like | What to run |
|-------|-----------|-------------|
| **T0 — Trivial** | typo, rename, copy/text change, one-line config, a direct question | Just do it. No ceremony. |
| **T1 — Small** | one function, one file, clear requirements, low ambiguity | TDD only. Skip brainstorm, spec, plan, subagents. |
| **T2 — Medium** | a few files, some integration, moderate ambiguity | Light brainstorm (1–2 questions) + TDD. Manual execution. Skip the spec doc and subagent ceremony unless it helps. |
| **T3 — Large** | new feature, multiple subsystems, unclear requirements, or you want autonomous multi-step work | Full workflow: grilling/design → spec and plan → implementation → review and QA. Use subagents when they materially help. |

### How to classify (signals)

Weigh: number of files touched, ambiguity of requirements, bugfix vs. new feature,
blast radius (how much breaks if wrong), reversibility, and whether the user wants
hands-off autonomous work.

### Bias rule

**When in doubt between two tracks, pick the heavier one.** Under-routing a task that
turns out to be big is far more expensive than a little extra ceremony. Do not
rationalize a task *down* a track because it "feels simple" — that exact instinct is
why estimates are wrong.

### Announce the track

State it in one short line before you start, e.g. `Router: T1 (small) — TDD only.`
The user can override the track at any time by saying so.

---

## 1. THE CONTROLLER — escalate if the task grows

A ratchet that only goes **up**: switch to a heavier track mid-task when the work
turns out bigger than the router assumed. Never downgrade mid-task (sunk-cost trap).

Trip on these **objective** signals (not vibes):

- Touching more files than the track assumed (e.g. > 2 files on T1).
- A test is hard to write → the design is unclear. Escalate.
- A bug appears that needs investigation rather than a one-line fix.
- A design decision is required that wasn't in the original request.
- You've edited the same area 3+ times or "fixed" the same thing repeatedly.

Check at natural seams, not constantly: **before writing code, before touching a
second file, and when a test is hard to write.**

When a tripwire fires: **stop, tell the user, propose moving up a track.** Do not
silently keep grinding on the light track. Example:
`Controller: this grew (now touching 4 files) — propose moving to T2 with a short design pass. OK?`

---

## 2. Ceremony vs. quality gates

Separate the two. The router/controller scale the **ceremony**. They do **not** turn
off the **quality gates**.

- **Ceremony (scalable):** brainstorming dialogue, written spec docs, formal plans,
  subagent dispatch + two-stage review.
- **Quality gates (keep on almost always):** **TDD** for behavior-bearing code changes
  (write the failing test first), and a final self-review before declaring done. Keep
  TDD even on T1 when code behavior changes — a test is cheap insurance. For pure
  documentation, prompt, copy, wiring, or config changes where no meaningful failing
  behavior test exists, use the nearest useful verification instead (for example a
  dry-run, parser check, grep assertion, or syntax validation). Only skip verification
  entirely if the user explicitly says so for this task.

---

## 3. Autonomous mode (T3 hands-off)

When the user asks for hands-off / autonomous work, T3 runs continuously. To stay safe:

- **Preconditions:** an approved plan exists, and work is on its own branch/worktree —
  never autonomous on main.
- **Controller changes behaviour:** do NOT stop-and-ask at every tripwire (that kills
  autonomy). Self-resolve via the BLOCKED ladder (more context → stronger model → break
  the task down). Escalate to the human ONLY for a genuine dead-end or a
  **fundamental scope change**.
- **Quality gates stay on:** TDD + review between tasks, always.
- **Stop conditions:** all plan tasks done, an unresolvable BLOCKED, or a scope change.
- **Report back:** what was built, what was skipped, what needs your eyes.
- Keep the work **plan-bounded** (a finite task list). No open-ended "keep improving"
  loops.

Two roles make autonomy safe — see their skills for detail:
`preference-oracle` answers recurring low-stakes questions on the user's behalf and
escalates the rest; `goal-watcher` guards against drift from the spec.

## 4. Provider-independent agent routing

Route each concrete work step on two independent axes:

- **Role** answers: what kind of work is this step doing?
- **Tier** answers: how difficult, risky, or expensive is this step?

Do not use a model family or provider as a role. Agent identity and memory are also
separate from routing: changing role or tier does not imply a new persona or memory
store.

### Choose the role

| Role | Use for |
|------|---------|
| `generalist` | Direct questions and ordinary mixed work |
| `researcher` | Gathering, verifying, and synthesizing sources |
| `coder` | Implementation, debugging, refactoring, and tests |
| `designer` | Product, UX, interface, and system design |
| `reviewer` | Independent verification of completed work |
| `orchestrator` | Splitting and coordinating multi-step work |

Choose the role for the **next concrete work step**, not the whole conversation. A
multi-phase request may move from `researcher` to `designer`, then `coder`, then
`reviewer`. State the transition when the role changes.

Role selection priority:

1. Explicit user selection.
2. Workflow or task requirement.
3. Project override.
4. Parent-agent assignment.
5. The role table above.
6. `generalist` if no specialist role fits.

If neither axis is selected explicitly, use `generalist/standard`.

A parent agent must assign `role` and `tier` explicitly when starting a child. The
child must not guess its assignment from a vague title.

### Choose the tier

| Tier | Use for |
|------|---------|
| `fast` | Low-risk routine work where latency matters |
| `standard` | Normal implementation, research, and coordination |
| `deep` | Difficult, high-risk, architectural, or final-review work |

Research is not automatically `deep`: a routine lookup is `researcher/fast`, normal
source comparison is `researcher/standard`, and difficult or high-stakes synthesis is
`researcher/deep`.

Start with the cheapest tier that can safely complete the step. Escalate when sources
conflict, stakes are high, synthesis is difficult, the first result is insufficient,
or the user explicitly asks for deeper reasoning. `goal-watcher`,
`preference-oracle`, architecture decisions, security review, and final review
normally use `deep`. Mechanical implementation with a clear specification normally
uses `fast`; integration, multi-file work, and debugging normally use `standard`.

### Resolve the harness-specific model

Agents request a logical `role` and `tier`; they do not hardcode a provider model
unless the user explicitly overrides routing. The canonical registry is installed at
`~/.config/agent-config/model-routing.json`.

Inspect available roles, tiers, presets, and harnesses:

```sh
agent-model-route --list
```

Resolve a route before choosing an explicit child model:

```sh
agent-model-route --harness codex --role coder --tier standard
agent-model-route --harness claude --role researcher --tier deep
agent-model-route --harness hermes --preset designer
```

The resolver maps the same logical request to the current model and reasoning setting
for Claude and Codex. Hermes uses `strategy: preset`: its `fast`, `coder`, `designer`,
and `thinker` names select the corresponding verified Hermes profile while also
expanding to role and tier. They are compatibility presets, not the underlying domain
model. Do not invent arbitrary Hermes role/tier mappings: no isolated profile exists
for combinations such as `researcher/standard`. Harnesses without a safe explicit
binding use `strategy: inherit`; do not silently route them through a paid provider.

Routing precedence is:

1. Explicit user model or profile selection.
2. Task capability or independence constraint.
3. Project override.
4. Canonical role/tier binding.
5. Permitted fallback or inherited harness model.

For independent review, prefer a different model family from the author and a
different provider when one is available. Do not silently downgrade a security or
final review. Report the requested role/tier, resolved target, and any fallback in the
result or run metadata.

## 5. Language: write code and docs in English

**Always write all code and documentation in English** — identifiers, comments,
commit messages, code comments, READMEs, specs, and inline docs — unless an existing
file or project already establishes another language, in which case match it. This
applies regardless of the language we converse in: I may write to you in Swedish, but
the artifacts you produce stay in English by default.

---

## 6. Instruction priority and skills

This file defines the shared operating rules. Available skills provide focused
workflows for particular tasks, but they do not replace the router or activate as one
fixed pipeline. Priority order: **explicit user request > this file > applicable
skills > system defaults.** If the user's CLAUDE.md / AGENTS.md / GEMINI.md says one
thing and a skill says another, follow the user.

## 7. Specs & plans live in Obsidian

Use my Obsidian vault as the persistent project memory. When I ask about projects,
plans, decisions, prior work, or context that may already exist, search the whole
vault before guessing:

**`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/dalholm/`**
(absolute: `/Users/dalholm/Library/Mobile Documents/iCloud~md~obsidian/Documents/dalholm/`)

Written specs and plans are stored in that vault — not scattered across repos. The
canonical folder for specs and plans is project-specific:

**`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/dalholm/Projects/{project-slug}/specs/`**
(absolute: `/Users/dalholm/Library/Mobile Documents/iCloud~md~obsidian/Documents/dalholm/Projects/{project-slug}/specs/`)

Use the current repository or project directory name as `{project-slug}`. Slug it with
lowercase letters, numbers, and hyphens. If there is no clear project name, use:

**`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/dalholm/Projects/general/specs/`**

- When a task produces a spec or a written plan — T2's light spec, or T3's
  brainstorming → spec → writing-plan — **save it there as a Markdown file**. Make it
  Obsidian-friendly: a clear `# Title` and `[[wikilinks]]` to related notes where useful.
- **Before** starting non-trivial work, check that folder for an existing spec on the
  same topic and build on it instead of duplicating.
- Name files descriptively (`<projekt>-<feature>.md`) and date-stamp inside the doc.
- The vault is the home of record. A repo-local copy is fine only as a pointer back to
  the vault note, never the master.
