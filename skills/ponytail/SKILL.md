---
name: ponytail
description: Use after the router for implementation or review work where the user asks for Ponytail, lazy mode, YAGNI, minimal code, simplest solution, shortest path, less boilerplate, fewer dependencies, or over-engineering review. Never run before the router.
---

# Ponytail

Use a Ponytail-inspired minimal implementation discipline: write the smallest correct
change that satisfies the request. This skill is subordinate to the user's `AGENTS.md`,
the router/controller, TDD/verification, security, accessibility, and explicit
requirements.

Source inspiration: <https://github.com/DietrichGebert/ponytail> (MIT).

## Ladder

Before writing code, stop at the first rung that holds:

1. Does this need to exist? If not, skip it and explain in one short line.
2. Does the standard library solve it? Use it.
3. Does a native platform feature solve it? Use it.
4. Does an already-installed dependency solve it? Use that before adding anything new.
5. Can the correct solution be one line? Prefer the one line.
6. Only then, write the minimum code that works.

## Rules

- No unrequested abstraction: no interface with one implementation, no factory for one
  product, no config knob for a value that does not vary.
- No scaffolding for imagined future needs.
- Prefer deletion over addition, boring over clever, and the fewest files possible.
- If two small stdlib/native options fit, pick the one with better edge-case behavior.
- Add a short `ponytail:` comment only for deliberate simplifications that future
  readers may otherwise misread. Include the known ceiling and upgrade path when there
  is one.

## Boundaries

Never minimize away:

- Input validation at trust boundaries.
- Error handling that prevents data loss.
- Security controls.
- Accessibility basics.
- Hardware calibration/tuning.
- Anything the user explicitly requested after you raised the simpler option.

Non-trivial new logic needs one runnable check: the smallest useful test, assertion,
demo, or existing verification that fails if the logic breaks. Trivial one-liners do
not need a dedicated test.

## Output

Keep explanations short unless the user asked for detail. Prefer:

`Done. Skipped <X>; add it when <Y>.`
