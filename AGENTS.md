# Agent Operating Rules

These are my (the user's) standing instructions. They are the **highest priority**
context: they override Superpowers skills and the default system prompt. If a skill
or the system prompt conflicts with this file, this file wins.

---

## 0. THE ROUTER — run this FIRST, before anything else

Before invoking `using-superpowers`, `brainstorming`, or **any** skill — and before
asking clarifying questions — first decide whether the user's message is asking for
work or only asking a question. If it is only a question, answer it directly as T0 and
do **not** enter a code/change workflow. If it asks for a build, code change, fix,
feature, implementation, review, investigation, or other work, classify the task's
complexity and pick a track.
The router is a **dispatcher**: it decides *how much* Superpowers to apply, from
"none" up to the full pipeline. Superpowers is a menu, not a default.

If you are running inside Superpowers, this means: do the complexity classification
first, then enter only the parts of the Superpowers workflow the chosen track calls
for.

### Tracks

| Track | Looks like | What to run |
|-------|-----------|-------------|
| **T0 — Trivial** | typo, rename, copy/text change, one-line config, a direct question | Just do it. No ceremony. |
| **T1 — Small** | one function, one file, clear requirements, low ambiguity | TDD only. Skip brainstorm, spec, plan, subagents. |
| **T2 — Medium** | a few files, some integration, moderate ambiguity | Light brainstorm (1–2 questions) + TDD. Manual execution. Skip the spec doc and subagent ceremony unless it helps. |
| **T3 — Large** | new feature, multiple subsystems, unclear requirements, or you want autonomous multi-step work | Full Superpowers: brainstorming → spec → writing-plans → subagent-driven-development → review. |

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

## 3. Minimal implementation discipline

After the router picks a track, keep a Ponytail-inspired minimality bias active for
implementation and review work: prefer the smallest correct change that satisfies the
request. This is a quality constraint, not a replacement for the router, TDD, security,
or explicit user requirements.

When a task uses Superpowers, Ponytail applies inside that workflow at the
implementation and review stages. Superpowers decides the process; Ponytail shapes the
diff.

Before writing code, stop at the first rung that holds:

1. Does this need to exist at all? If not, skip it and say why briefly.
2. Does the standard library already solve it? Use that.
3. Does the native platform already cover it? Use that.
4. Does an already-installed dependency solve it? Use it before adding another one.
5. Can the correct solution be one line? Prefer the one line.
6. Only then, write the minimum code that works.

Rules:

- Do not add abstractions, factories, interfaces, configuration, or scaffolding unless
  the request or existing codebase justifies them now.
- Prefer deletion over addition, boring over clever, and the fewest touched files that
  keep the change clear.
- If two small standard-library/native options fit, choose the one that handles edge
  cases correctly.
- Mark deliberate simplifications with a short `ponytail:` comment only when future
  readers might otherwise mistake the shortcut for ignorance. If the shortcut has a
  known ceiling, name the ceiling and the upgrade path.
- Never simplify away trust-boundary validation, data-loss prevention, security,
  accessibility, hardware calibration/tuning, or anything the user explicitly asked for.
- Non-trivial new logic still needs one runnable check: the smallest test, assertion,
  demo, or existing verification that would fail if the logic breaks.

---

## 4. Autonomous mode (T3 hands-off)

When the user asks for hands-off / autonomous work, T3 runs continuously. To stay safe:

- **Preconditions:** an approved plan exists, and work is on its own branch/worktree —
  never autonomous on main.
- **Controller changes behaviour:** do NOT stop-and-ask at every tripwire (that kills
  autonomy). Self-resolve via the Superpowers BLOCKED protocol (more context → stronger
  model → break the task down). Escalate to the human ONLY for a genuine dead-end or a
  **fundamental scope change**.
- **Quality gates stay on:** TDD + review between tasks, always.
- **Stop conditions:** all plan tasks done, an unresolvable BLOCKED, or a scope change.
- **Report back:** what was built, what was skipped, what needs your eyes.
- Keep the loop **plan-bounded** (a finite task list). No open-ended "keep improving"
  loops.

Two roles make autonomy safe — see their skills for detail:
`preference-oracle` answers recurring low-stakes questions on the user's behalf and
escalates the rest; `goal-watcher` guards against drift from the spec.

## 5. Roles & model tiers

Use the cheapest model that can do each role (Superpowers' own guidance).

| Role | Model tier | Why |
|------|-----------|-----|
| **goal-watcher**, **preference-oracle** | strong (e.g. Claude Sonnet/Opus) | Judgment & alignment calls |
| Architecture, design, final review | strong | Broad reasoning |
| Integration / multi-file / debugging | standard | Coordination |
| Mechanical implementer (1–2 files, clear spec) | cheap/fast (Haiku or local) | Most impl is mechanical |

Model routing is harness-dependent: Claude Code can set a model per subagent; Codex /
OpenCode set it in their own config. Treat this table as intent.

## 6. Language: write code and docs in English

**Always write all code and documentation in English** — identifiers, comments,
commit messages, code comments, READMEs, specs, and inline docs — unless an existing
file or project already establishes another language, in which case match it. This
applies regardless of the language we converse in: I may write to you in Swedish, but
the artifacts you produce stay in English by default.

---

## 7. Interaction with Superpowers

Superpowers stays installed and unchanged. This file sits on top and decides how much
of it activates per task. Priority order: **this file > Superpowers skills > system
prompt.** If the user's CLAUDE.md / AGENTS.md / GEMINI.md says one thing and a skill
says another, follow the user.

## 8. Specs & plans live in Obsidian

Use my Obsidian vault as the persistent project memory. When I ask about projects,
plans, decisions, prior work, or context that may already exist, search the whole
vault before guessing:

**`~/Documents/Obsidian/dalholm/`**
(absolute: `/Users/dalholm/Documents/Obsidian/dalholm/`)

Written specs and plans are stored in that vault — not scattered across repos. The
canonical folder for specs and plans is:

**`~/Documents/Obsidian/dalholm/Projekt/Specs/`**
(absolute: `/Users/dalholm/Documents/Obsidian/dalholm/Projekt/Specs/`)

- When a task produces a spec or a written plan — T2's light spec, or T3's
  brainstorming → spec → writing-plan — **save it there as a Markdown file**. Make it
  Obsidian-friendly: a clear `# Title` and `[[wikilinks]]` to related notes where useful.
- **Before** starting non-trivial work, check that folder for an existing spec on the
  same topic and build on it instead of duplicating.
- Name files descriptively (`<projekt>-<feature>.md`) and date-stamp inside the doc.
- The vault is the home of record. A repo-local copy is fine only as a pointer back to
  the vault note, never the master.
