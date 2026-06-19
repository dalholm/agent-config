---
name: complexity-router
description: Use at the very start of ANY build, code, fix, feature, or change request — BEFORE using-superpowers, brainstorming, or any other skill, and before clarifying questions. Classifies task complexity and selects how much process to apply (T0 trivial → T3 full Superpowers), then escalates the track if the task grows mid-flight.
---

# Complexity Router

Decide *how much* process a task needs before applying any of it. This skill is a
**dispatcher** that sits in front of Superpowers: it picks a track, and only the parts
of the Superpowers workflow that the track calls for get used.

> Priority: the user's AGENTS.md / CLAUDE.md / GEMINI.md is the source of truth. This
> skill implements that file's router. If they ever differ, the file wins.

## Run order

1. Classify the task into a track (below).
2. Announce it in one line: `Router: T1 (small) — TDD only.`
3. Enter only the workflow parts that track requires.
4. Keep the **Controller** (escalation) active for the rest of the task.

## Tracks

| Track | Looks like | Run |
|-------|-----------|-----|
| **T0 Trivial** | typo, rename, copy change, one-line config, a direct question | Just do it. No ceremony. |
| **T1 Small** | one function, one file, clear, low ambiguity | TDD only. Skip brainstorm/spec/plan/subagents. |
| **T2 Medium** | a few files, some integration, moderate ambiguity | Light brainstorm (1–2 Qs) + TDD, manual execution. |
| **T3 Large** | new feature, multiple subsystems, unclear, or hands-off autonomous work wanted | Full Superpowers: brainstorming → writing-plans → subagent-driven-development → review. |

**Signals:** files touched, ambiguity, bugfix vs. feature, blast radius, reversibility,
desire for autonomous work.

**Bias rule:** in doubt between two tracks, choose the **heavier** one. Do not route a
task *down* because it "feels simple" — that instinct is why estimates are wrong.

## Controller — escalate if it grows

A ratchet that only goes up. Trip on **objective** signals:

- More files than the track assumed (e.g. > 2 on T1).
- A test is hard to write (= unclear design).
- A bug needs investigation, not a one-liner.
- A design decision appears that wasn't in the request.
- 3+ edits to the same area / repeated "fixes".

Check at seams: **before writing code, before the second file, when a test is hard to
write.** On a trip: **stop, tell the user, propose moving up a track.** Never silently
grind on. Never downgrade mid-task.

## Ceremony vs. quality gates

Scale the **ceremony** (brainstorm, spec, plan, subagents). Keep the **quality gates**:
**TDD** (failing test first) and a final self-review — even on T1. Only drop TDD if the
user explicitly says so for this task.

## Red flags (you are rationalizing — stop)

| Thought | Reality |
|---------|---------|
| "Too simple to classify" | Classifying takes one line. Do it. |
| "I'll just start, it's obviously small" | That's skipping the router. Classify first. |
| "It grew but I'm almost done" | Trip the controller. Tell the user. |
| "Skip the test, it's tiny" | TDD is a quality gate, not ceremony. Keep it. |
| "Heavier track is overkill" | Under-routing costs more. Bias heavy. |
