# User profile

Curated, stable facts about me (the user) that Pi should always know. Kept in git;
hermes-memory loads this into context. Edit by hand — this is not auto-generated noise.

## Specs & plans live in Obsidian

Written specs and plans go in my Obsidian vault, not scattered across repos. Canonical
folder:

**`/Users/dalholm/Documents/Obsidian/dalholm/Projekt/Specs/`**
(`~/Documents/Obsidian/dalholm/Projekt/Specs/`)

- When a task produces a spec or a written plan, **save it there** as a Markdown file —
  Obsidian-friendly (`# Title`, `[[wikilinks]]` to related notes).
- **Before** non-trivial work, check that folder for an existing spec on the topic and
  build on it instead of duplicating.
- The vault is the home of record; a repo-local copy is only a pointer back to it.

This mirrors AGENTS.md §8 (which covers Claude/Gemini/Codex); this file is how the same
rule reaches Pi.
§
User's previous session got stuck in a style-fix loop on the banking project - repeatedly fixing the same ESLint errors without building new features. Created project skill 'break-style-loop' to prevent this. Key lesson: fix ALL style errors in one batch, then immediately move to feature work. Never revisit style issues without explicit user request. <!-- created=2026-06-20, last=2026-06-20 -->
§
User speaks Swedish; expects Swedish UI language (SEK format). User is the bank manager perspective — not a customer-facing app. User wants specs/plans in Obsidian vault at ~/Documents/Obsidian/dalholm/Projekt/Specs/. User calls out when I'm stuck in loops — expect direct corrections. <!-- created=2026-06-20, last=2026-06-20 -->
§
User communicates in Swedish. Respond in Swedish by default. User is direct, calls out problems immediately, dislikes unnecessary rewrites when things already work. <!-- created=2026-06-20, last=2026-06-20 -->