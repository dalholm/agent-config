# Standing preferences (preference-oracle source of truth)

The `preference-oracle` answers recurring, low-stakes questions on my behalf using this
file. Keep it current — the oracle is only as good as what's written here. Anything not
covered here, or anything high-stakes, gets escalated to me (see the escalation rules at
the bottom). Write entries in any language; be specific.

## Tech defaults
<!-- Standing technical choices the oracle may apply without asking. Examples: -->
- Language / runtime: <!-- e.g. TypeScript, Node 20 -->
- Package manager: <!-- e.g. pnpm -->
- Test framework: <!-- e.g. vitest -->
- Lint/format: <!-- e.g. eslint + prettier, defaults -->
- Install scope when ambiguous: <!-- e.g. user-level (~/.config/...) not system -->

## Conventions
<!-- Code/style/structure preferences. Examples: -->
- File/dir naming: <!-- e.g. kebab-case files -->
- Commit style: <!-- e.g. conventional commits, imperative subject -->
- Comments: <!-- e.g. minimal, only for non-obvious why -->
- Error handling: <!-- e.g. fail fast, explicit errors over silent fallbacks -->

## Product / scope defaults
- YAGNI bias: build the minimum that meets the spec; don't add speculative features.
- When a small choice is reversible and low-cost: pick the simplest option, note it, move on.

## Decision authority — what the oracle MAY answer
- Mechanical/config questions with an obvious or stated-here answer.
- Naming, file placement, convention choices covered above.
- Low-stakes, easily reversible defaults.

## Escalate to me (never answer for me) — ALWAYS
- Anything irreversible or hard to undo (data deletion, schema/migration, releases, money).
- Public-facing or security/privacy-affecting decisions.
- Scope changes or new requirements not in the spec.
- Genuine ambiguity where two reasonable people would choose differently.
- Anything not covered by this file where guessing has real cost.

When escalating, batch questions where possible and state the oracle's best guess so I
can just confirm or correct.
