---
name: spec-with-orca
description: Develop an approved repository specification through a Hermes-led interview while delegating codebase investigation, design probes, and throwaway prototypes to supervised Orca workers. Use when the user wants to create, sharpen, or finalize a repository-grounded spec or PRD before implementation.
---

# Spec With Orca

Keep the user-facing interview and durable specification in Hermes. Use Orca for every
source-level investigation, design probe, or prototype. Finish with an approved vault
artifact and stop before implementation.

## Establish the boundary

1. Load and follow `complexity-router`, `orca-development-orchestrator`,
   `model-routing`, `grilling`, and `domain-modeling`. Treat specification as the
   bounded objective; do not continue into implementation, production changes, issue
   creation, or deployment.
2. Identify the repository, requested outcome, known constraints, and the lowercase
   project slug. Search the Obsidian project folder for an existing specification or
   related decisions before creating another master document.
3. Confirm only genuinely missing scope that would materially change the interview.
   Use `grilling`'s design tree and ask the currently unblocked frontier as one numbered
   round, with a recommended answer for each question. Preserve approved decisions
   unless new evidence exposes a contradiction.

If Orca is unavailable, continue decisions that depend only on the user, but do not
silently replace worker investigation with Hermes source reading. Mark repository
grounding as pending and report the blocked evidence explicitly.

## Drive the interview with evidence

Maintain a compact working set of:

- approved decisions;
- unresolved user choices;
- repository facts that need evidence;
- risks, assumptions, and out-of-scope items.

For each repository question, dispatch a bounded Orca worker contract through the
coordinator workflow:

- use `researcher` to establish current behavior, constraints, and prior art;
- use `designer` to compare interfaces, flows, or architectural options;
- use `coder` only for an explicitly throwaway prototype needed to answer a design
  question; never merge or treat prototype code as implementation;
- select the cheapest safe tier and resolve the concrete harness at spawn;
- use another provider family for an independent check when a consequential decision
  depends on one worker's judgment.

Require file paths, commands, observations, and uncertainty in worker reports. Bring
the evidence back into the Hermes interview in plain language. Separate verified
repository behavior from proposals and ask the user only for decisions that evidence
cannot settle.

## Draft and approve the specification

When the important decisions are closed, present a concise decision summary, remaining
open questions, and proposed scope. Do not finalize the document until the user approves
that basis.

Write the master specification to:

```text
/Users/dalholm/Library/Mobile Documents/iCloud~md~obsidian/Documents/dalholm/Projects/{project-slug}/specs/{descriptive-slug}.md
```

Use `Projects/general/specs/` only when no repository or project is identifiable. Make
the note Obsidian-friendly with a clear title, an internal `Date: YYYY-MM-DD` stamp,
and relevant `[[wikilinks]]`. Do not create a duplicate master copy in the repository.

Include the applicable parts of this structure:

1. Problem and desired outcome
2. Scope and non-goals
3. Current verified behavior
4. Users, flows, and requirements
5. Domain language and decisions
6. Interfaces, data, and failure behavior
7. Security, safety, and operational constraints
8. Acceptance criteria
9. Testing and real-surface QA expectations
10. Implementation constraints and migration concerns
11. Resolved alternatives and remaining open questions
12. Evidence and related notes

Write requirements and acceptance criteria as observable outcomes. Keep provider and
model names out of the specification unless they are product requirements; volatile
worker bindings remain in `model-routing.json`.

## Hand off without implementing

Report the specification path, the approved decisions, evidence limitations, and any
open questions. Then stop. Do not invoke implementation automatically.

When the user later requests implementation, give the coordinator the approved spec
path as the source of truth. Let the normal Hermes-Orca development flow plan bounded
workers, implement with the required quality gates, run an independent review through
a different provider family when available, and perform real-surface QA.
