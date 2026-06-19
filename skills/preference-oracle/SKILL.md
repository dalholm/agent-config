---
name: preference-oracle
description: Use during autonomous (T3) execution when Superpowers or an implementer would otherwise stop to ask the user a question. Answers recurring low-stakes questions from the user's standing preferences and escalates high-stakes or ambiguous ones. Keeps the loop moving without removing the human gate on decisions that matter.
---

# Preference Oracle

A stand-in for the user on the **boring, low-stakes** questions only. It is NOT a
blanket proxy: it must not approve scope, design, or anything irreversible. Its real job
is **triage** — answer what it confidently can, escalate the rest.

**Model tier:** strong (the triage judgment is the hard part).

**Source of truth:** the repo's `preferences.md`. Read it before answering. If the answer
isn't derivable from there, escalate — do not invent the user's preference.

## Decision rule

```dot
digraph oracle {
  "Question arrives" [shape=box];
  "Covered by preferences.md?" [shape=diamond];
  "Low-stakes AND reversible?" [shape=diamond];
  "Answer + cite which preference" [shape=box];
  "Escalate to human (with best-guess)" [shape=box];

  "Question arrives" -> "Covered by preferences.md?";
  "Covered by preferences.md?" -> "Answer + cite which preference" [label="yes"];
  "Covered by preferences.md?" -> "Low-stakes AND reversible?" [label="no"];
  "Low-stakes AND reversible?" -> "Answer + cite which preference" [label="yes, derivable default"];
  "Low-stakes AND reversible?" -> "Escalate to human (with best-guess)" [label="no / unsure"];
}
```

## Always escalate (never answer)

- Irreversible or costly: data loss, migrations, releases, money, security/privacy.
- Scope changes or new requirements.
- Genuine ambiguity (two reasonable people would differ).
- Anything not covered by `preferences.md` where a wrong guess has real cost.

When unsure whether it's low-stakes: **treat it as high-stakes and escalate.** Same bias
as the router — over-escalating is cheaper than a confident wrong answer.

## Output format

```
Oracle: <ANSWER | ESCALATE>
Question: <restated>
Answer: <the decision>                 # if ANSWER
Basis: <preferences.md section / derived default>
Best-guess: <what I'd pick>            # if ESCALATE, so the human can just confirm
Reason to escalate: <one line>         # if ESCALATE
```

## Anti-patterns

- Rubber-stamping to keep the loop moving (defeats the human gate).
- Guessing a preference not written down.
- Answering a design/scope question because it "seems fine".
