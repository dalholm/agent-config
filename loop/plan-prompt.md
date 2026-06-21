# Junior plan request (senior decomposition)

A weaker LOCAL model is about to implement task **__TASK__** autonomously. Your job is to
write the plan it will follow — small, unambiguous, mechanical — and to author its
**acceptance tests yourself**. You are READ-ONLY: do not modify the repo or run builds.

Read first:

- The task **__TASK__** in
  `/Users/dalholm/Documents/Obsidian/dalholm/Projekt/Auto Tasks.md` — its `Done when`,
  `repo:`, `Branch:`, and any linked spec under `Projekt/Specs/`.
- The target repo's existing code and conventions (and `<repo>/LOOP.md` if present), so the
  plan fits what's there instead of reinventing it.

Then output to stdout, in Markdown, EXACTLY these sections:

## Context
2–4 lines: what already exists, what this task must add, and the single acceptance
criterion in your own words.

## Acceptance tests (authoritative — the junior must NOT change these)
The concrete tests or commands that prove `Done when`. Prefer real test code the junior
drops in as-is (give exact file paths and the full test body), or exact commands whose
output is checkable. The junior implements TO these tests — so they must be precise, and if
they pass the task must genuinely be done. You write them BECAUSE if the same weak model
wrote both the code and the tests, a green run would be meaningless.

## Steps
A numbered list of the smallest mechanical steps (create file X; add function Y with this
exact signature; wire Z into W). No open-ended "improve/refactor" steps. Each step must be
independently checkable.

## Watch out for
0–3 bullets: the specific traps a weak model would hit here — a wrong import, an off-by-one,
an existing helper it should reuse instead of reinventing, a file it must NOT touch.

Keep it tight. The junior is literal and not creative: it follows instructions exactly, so
remove every ambiguity. Do not implement anything yourself — plan and tests only.
