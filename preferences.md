# Standing preferences (preference-oracle source of truth)

The `preference-oracle` answers recurring, low-stakes questions on my behalf using this
file. Keep it current — the oracle is only as good as what's written here. Anything not
covered here, or anything high-stakes, gets escalated to me (see the escalation rules at
the bottom). Write entries in any language; be specific.

## Tech defaults
<!-- Standing technical choices the oracle may apply without asking. -->
- Language / runtime: TypeScript by default. Node LTS.
- **No UI frameworks by default.** We favour maximum control: hand-rolled code over a
  framework's conventions. Do NOT reach for Vue/React/Next/Tailwind or any framework
  unless a project already uses one or I explicitly ask. Match what a project already
  has; never introduce a new framework on your own.
- **Styling = our own design-token system.** Style via our own tokens (CSS custom
  properties / a tokens layer we own), not a third-party styling framework. Plain CSS
  driven by tokens; explicit classes.
- Package manager: pnpm.
- Test framework: vitest.
- Lint/format: eslint + prettier, defaults.
- Install scope when ambiguous: user-level (`~/.config`, `~/.pi`, `~/.claude`), not
  system-wide.
- Locale: Swedish UI text, SEK currency formatting, for user-facing strings.

## Conventions
- File/dir naming: kebab-case files.
- Commit style: short, concise English commit messages. Always write them with me as
  the user/author, not as the agent.
- Code & docs language: English (identifiers, comments, READMEs) per AGENTS.md §6 —
  even when we converse in Swedish.
- Comments: minimal; only the non-obvious *why*.
- Error handling: fail fast, explicit errors over silent fallbacks.
- **Don't rewrite working code.** If it works, leave it. Fix all style/lint errors in
  one batch, then move to feature work; never revisit style without me asking. (This is
  a standing correction from past loops — treat re-litigating working code as drift.)
- **Refactor on reuse, not before.** Start inline and concrete (YAGNI). The moment a
  piece of code is genuinely needed a second time, extract it — component-based for UI,
  a shared module/service for backend. Don't pre-abstract for a reuse that hasn't
  appeared; don't leave a third copy un-extracted either. The trigger is *observed*
  reuse, not anticipated reuse.

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
