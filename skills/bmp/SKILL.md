---
name: bmp
description: "Better My Prompt: improve rough prompts by asking focused follow-up questions until no meaningful questions remain, then rewrite the prompt with clear structure, XML delimiters for examples/preferences/context, variables, constraints, and output format. Use when the user invokes $bmp, says \"Better my prompt\", asks to improve/refine/structure a prompt, or provides a draft prompt that needs clarification before use."
---

# Better My Prompt

## Overview

Turn an unclear or underspecified prompt into a stronger prompt through questioning first, then rewriting. Optimize for a prompt another AI can execute directly.

## Workflow

1. Read the user's draft prompt and identify missing information that would materially change the final prompt.
2. Check the current project context when the prompt may depend on it: repository files, docs, package metadata, tests, existing conventions, and any user-provided project notes.
3. Ask concise follow-up questions one at a time. Wait for the user's answer before asking the next question.
4. Continue asking until there are no meaningful open questions. Do not rewrite the final prompt early unless the user explicitly asks for a draft.
5. When enough information is available, produce the improved prompt only, unless the user asked for commentary.

## Questioning Rules

- Ask about audience, goal, inputs, constraints, examples, preferences, exclusions, output format, tone, depth, and success criteria when they matter.
- Ask only one question per message when follow-up information is needed.
- Skip questions whose answers are obvious from the draft, discoverable from project context, or unlikely to change the prompt.
- If the draft is already clear, ask at most one confirmation question before rewriting.
- If the user says to proceed, make reasonable assumptions and include them in the prompt as explicit defaults.
- Preserve the user's intent. Improve structure, specificity, and executability without adding unrelated scope.

## Project Awareness

- Treat the current working directory as the default project unless the user names another project.
- Prefer local context over generic assumptions. Use existing project terminology, frameworks, commands, file paths, constraints, and style conventions when they are relevant.
- If project context is missing or ambiguous, ask one targeted question rather than guessing.
- Do not invent project facts. If the final prompt relies on inferred context, state that context explicitly in the prompt.

## Prompt Structure

Use XML delimiters when they make inputs easier to separate or reuse. Good candidates include:

- `<role>`
- `<task>`
- `<context>`
- `<project_context>`
- `<inputs>`
- `<example>`
- `<user_preference>`
- `<constraints>`
- `<output_format>`
- `<success_criteria>`

Use placeholders for user-supplied values:

```text
{{LOCATION}}
{{NUM_DAYS}}
{{USER_PREFERENCES}}
```

Prefer valid, consistent tag names: `<num_days>` rather than `<num days>`, and matching open/close tags.

## Final Output

When ready, return a polished prompt with this shape:

```text
You are [role].

<task>
[Clear task]
</task>

<context>
[Relevant background]
</context>

<inputs>
...
</inputs>

<user_preference>
...
</user_preference>

<constraints>
...
</constraints>

<output_format>
...
</output_format>
```

Only include sections that help the prompt. Do not force every tag into every prompt.

## Example Direction

For a travel-itinerary prompt, ask for location, trip length, budget, traveler profile, pace, interests, dietary needs, accommodation style, transport constraints, and output format. Then structure the final prompt with tags such as `<location>`, `<num_days>`, `<user_preferences>`, `<example>`, and `<itinerary_output_format>`.
