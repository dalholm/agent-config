---
name: web-research-fallback
description: Use when Codex cannot find a credible solution from local context, project files, built-in knowledge, or repeated attempts. Triggers include unresolved errors after local investigation, uncertain current APIs or product behavior, dependency/version questions, missing documentation, contradictory answers, or any point where continuing would mean guessing; search authoritative web sources before proceeding.
---

# Web Research Fallback

## Overview

Stop local guessing when the available context is not enough. Use current, authoritative external sources to close the knowledge gap, then return with cited findings and a concrete next step.

## Fallback Trigger

Invoke this skill when one or more of these are true:

- Local search found no relevant implementation, docs, tests, config, or history.
- An error remains unexplained after reading the nearby code and logs.
- A dependency, CLI, API, framework, model, law, standard, price, schedule, product behavior, or service status may have changed.
- Built-in memory is uncertain, contradictory, or older than the decision needs.
- The agent has tried two plausible fixes and still cannot explain the failure.
- The next action would depend on an undocumented assumption.

Do not use this skill as the first move for ordinary local code changes. Read the relevant project files first unless the user explicitly asks for current external information.

## Workflow

1. State the gap in one sentence: what is unknown, what was checked locally, and why guessing is unsafe.
2. Search the web for current information. If the user or higher-priority instructions forbid browsing, stop and report the blocker instead.
3. Prefer primary sources:
   - Official documentation, API references, release notes, status pages, standards, and vendor blogs.
   - Source repositories, issue trackers, changelogs, and maintainer comments.
   - Research papers, regulatory publications, or legal/medical/financial primary sources for high-stakes domains.
4. Use secondary sources only as leads. Cross-check them against primary sources or at least one independent source before relying on them.
5. Compare source dates and versions against the local environment. Current docs can still be wrong for an older pinned dependency.
6. Return to the task with:
   - The answer or narrowed hypothesis.
   - Source links and the relevant version/date context.
   - The next implementation or debugging step.

## Source Quality

Treat these as strong sources:

- Official docs for the exact product or library.
- Release notes or changelogs matching the installed version.
- Maintainer-authored issues, pull requests, commits, and discussions.
- Standards bodies and government or regulator publications.
- Vendor status pages for outages or incidents.

Treat these as weak unless confirmed:

- Blog posts, Stack Overflow answers, forum posts, generated answers, and tutorials.
- Docs for a different major version.
- Search snippets without opening the source.
- Old answers for fast-moving tools or hosted services.

## Reporting Format

Use this compact format when the research affects the answer or code change:

```text
Research gap: <what local context could not answer>
Sources: <source name + link + version/date relevance>
Finding: <what the sources establish>
Next step: <what to do now>
```

Keep the report short unless the user asked for a research write-up.

## Guardrails

- Do not browse to avoid reading local code or project documentation.
- Do not present uncited web claims as facts.
- Do not rely on a source that does not match the relevant version, platform, jurisdiction, or date.
- Do not continue applying fixes after this skill triggers until the research gap is addressed or explicitly reported as blocked.
