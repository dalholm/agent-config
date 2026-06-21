# Autonomous loop — cycle prompt

You are running one **cycle** of the autonomous task loop. This prompt is fed to you
on every wake (manual or scheduled). Your operating rules in `AGENTS.md` are in force —
this prompt does not override them; it tells you what one cycle is.

**Task list (home of record):**
`/Users/dalholm/Documents/Obsidian/dalholm/Projekt/Auto Tasks.md`

## Task types — the loop is general, not code-only

A task is whatever its `Done when` describes. Detect the type from the task and adapt:

- **Code in a repo** (task has a `repo:`). Work on the `Branch:`, implement, write/run
  the gate (tests, build, lint), commit. Read the project's own instructions first (see
  below) for conventions and any extra gates.
- **Research / ops / personal** (no `repo:`, or a `deliverable:` instead — e.g. "find X
  on the web", "draft a reply", "plan my day"). No branch, no commit, no tests. Produce
  the deliverable the task names (a note saved to a path, an answer written back into the
  task, a draft file) and let the oracle sign off against the `Done when`. Use the tools
  pi has: web access works out of the box; **mail / calendar / other apps only work if a
  connector is configured** — if the task needs one that isn't available, don't fake it:
  say so via the oracle and move the task to Blocked.

## Project instructions live with the project (not in this prompt)

When a task has a `repo:`, that project owns its rules. Before building:

- Read `<repo>/LOOP.md` if it exists — it holds the project's conventions, invariants,
  and extra sign-off gates. Follow it.
- If there's no `LOOP.md` but the task links a spec (e.g. FeatureSociety's
  `Agent-brief` / `Acceptanskriterier`), that spec **is** the project instruction —
  follow it, and optionally drop a short `LOOP.md` in the repo pointing at it.
- If a non-trivial coding project has neither, create a starter `<repo>/LOOP.md`
  recording the conventions you settle on (with the oracle), so the next cycle is
  consistent instead of re-deciding.

This keeps THIS prompt generic. Project-specific gates (e.g. FeatureSociety's determinism
+ money-conservation) come from the project's instructions, never hardcoded here.

## One cycle = at most one task

1. **Your task is already claimed for you.** Before you ran, the shell (`claim-task.sh`)
   moved exactly one task into `## In progress` and marked it `- [/]`. **That is your
   task — read it there.** Do NOT pick from `## Queue` yourself, do NOT claim a second
   task, do NOT touch `## Inbox`. If `## In progress` is empty, stop and report "nothing
   to do" (the shell found no runnable task).
2. **If this is a RESUME, diagnose before you touch anything.** A `resume-attempts:` line
   (or a `claimed:` line from a prior cycle) means the **last cycle did not finish** — treat
   it as a BLOCKED situation from the start, not "carry on cheerfully". A fresh pi process
   has no memory of why the previous one stalled, so blindly continuing just walks into the
   same wall and burns the next resume-attempt. Instead:
   - **Gather the state:** `git -C <repo> status` and `git -C <repo> diff` (what's on disk,
     uncommitted), the tail of the previous `loop/logs/cycle-*.log`, and the task notes.
   - **Get a diagnosis from the stronger model:** call
     `loop/ask-cli-helper.sh "<the task + that state + 'this resumed after a stall; what is
     the REAL blocker, and what is the single next concrete step — or is this a genuine
     dead-end to Block for the human?'>"` (via bash).
   - **Act on the verdict:** if it names a concrete next step, do exactly that and continue.
     If it says dead-end, write a `status:blocked` result file (step 8) with the diagnosis
     as the reason — don't keep grinding. Record the diagnosis in the task notes.
   If it is NOT a resume (no prior `claimed:`/`resume-attempts:`), skip this and go to step 3.
3. **Pre-flight (AGENTS.md §4 preconditions):**
   - Work on the task's `Branch:` — create it from a clean main if it doesn't exist.
     Never run autonomously on `main`.
   - If the task needs a spec it doesn't have and is more than trivial, move it to
     **Blocked / escalated**, reason "needs a spec", and stop.
4. **Kickoff — clear every question mark with the oracle FIRST.** Before writing any
   code, read the task's spec/requirements (its `Done when`, any linked spec) and list
   *all* open questions, ambiguities, and decisions. Resolve them in **one consultation
   round** by calling the oracle on its own LLM: run `loop/ask-oracle.sh "<your questions
   + the context it needs>"` (via bash). It answers as my stand-in (skeptical, YAGNI)
   on its own cloud model (Claude, falling back to Codex via `loop/ask-cli-helper.sh`),
   independent of your builder context. Record the resolutions in the task notes. You
   enter implementation only once there are **no open question marks left**. Do not
   discover-and-ask piecemeal mid-build; front-load it.
5. **Then implement autonomously with Superpowers.** Run `complexity-router` first as
   always (it may rate a task T1/T2 — apply the matching ceremony; most queued tasks are
   T3). For T3, apply the full autonomous Superpowers pipeline (brainstorming already
   done in step 4 → spec → writing-plan → subagent-driven implementation → review):
   - Use the **BLOCKED protocol** to self-resolve (more context → **stronger model** →
     break it down). The *stronger model* rung is a cloud CLI: call
     `loop/ask-cli-helper.sh "<the problem + the context it needs>"` (via bash) to get a
     stronger agent's help BEFORE you ever escalate to me. Do **not** stop-and-ask at
     every tripwire.
   - **The oracle is the human stand-in — it does not escalate to me, it decides.**
     Whenever you would otherwise put a question to the user — a low-stakes default, a
     scope judgement, *or the phase sign-off itself* — call `loop/ask-oracle.sh` (via
     bash). That runs `preference-oracle` on its own cloud model via
     `loop/ask-cli-helper.sh` (Claude, falling back to Codex — separate from your builder
     model). It is a
     skeptical devil's advocate with a YAGNI bias: it may APPROVE or REJECT. If it
     REJECTs, treat that as a BLOCKED and fix the thing it objected to.
   - Run `goal-watcher` at plan checkpoints and before anything irreversible. A
     **SCOPE-CHANGE** is not an escalation to me — it goes to the oracle, whose YAGNI
     default is to reject scope the spec doesn't require.
   - **Quality gates stay on:** TDD for behaviour changes, self-review before "done".
   - `loop-guard` is active in pi; if it terminates the turn, treat that as a BLOCKED and
     follow the protocol — do not fight it.
6. **Sign-off (every task):** when the work meets its `Done when`, do NOT stop for me.
   Call `loop/ask-oracle.sh` with the task's `Done when` and your test/validation
   results, and ask it to sign off. It approves only with the gate actually green (tests
   pass / the checkable condition is true) and a passed devil's-advocate review. Write
   its verdict into the task notes (`Oracle-decision: …`) so I can audit.
   - *FeatureSociety phases only:* also enforce the cross-cutting gates from the spec —
     determinism (same seed → identical) and money-conservation each tick — on top of the
     phase's `Acceptanskriterier`. These are project invariants; they do NOT apply to
     unrelated tasks (a Tetris build has no money invariant — its `Done when` is the gate).
7. **On oracle APPROVE / success — commit, then HAND OFF bookkeeping to the shell.**
    You do NOT edit `Auto Tasks.md` structure yourself (the local model keeps scrambling
    it). Only after the oracle APPROVED (green gate + devil's-advocate pass):
    - **Commit** the work on the task branch, me as author (concise English, per
      preferences.md). Do the work on the branch only — never build on main.
    - **Write the result file** `/Users/dalholm/agent-config/loop/.cycle-result.json`
      and stop. The shell (`complete-task.sh`) then merges the branch into main, moves the
      task to `## Done`, and arms the next task — deterministically. JSON schema:
      ```json
      {
        "status": "done",
        "task_id": "T-002",
        "summary": "one line: result + commit ref + oracle verdict",
        "repo": "/Users/dalholm/develop/simulations/feature-society",
        "branch": "auto/T-002-fas1",
        "merge_to_main": true,
        "next_task": "- [ ] **T-003** Build FeatureSociety **Fas 2** ... (full task block, or null)"
      }
      ```
      For a FeatureSociety phase, `next_task` is the next phase from the Inbox roadmap as
      a full task block (Done-when = that phase's `Acceptanskriterier`, branch
      `auto/T-###-fasN`). Roadmap exhausted, or a standalone non-phase task → `next_task: null`.
8. **On a genuine dead-end (not an oracle REJECT — those you fix and retry):** write the
    same result file with `"status":"blocked"` and a `"reason"` (one line + best guess),
    then stop. The shell moves the task to `## Blocked / escalated to me`. Reserve this
    for true dead-ends the oracle can't resolve.
9. **Stop.** One task per cycle. You wrote the result file; the shell does the rest. Print
    a short report (task, outcome, commit, oracle decisions). **Do not edit the Queue / In
    progress / Done / Blocked sections yourself** — that is the shell's job now. End the run.

## Hard rules

- **Plan-bounded only.** Every task you run must have a checkable `Done when`. Refuse
  open-ended work.
- **One task per wake.** The schedule (or me) decides when the next cycle runs.
- **Build on branches, never directly on main.** One branch per task. An *approved*
  branch (oracle APPROVE + green gate) is merged into main in step 7 — that's the only
  time main is touched, and only after sign-off.
- **Ask the oracle, don't guess and don't ping me.** On anything irreversible,
  scope-affecting, or genuinely ambiguous, the `preference-oracle` (own LLM) decides as
  my stand-in — skeptical, YAGNI-biased, and it records the call for me to audit. Only a
  true dead-end the oracle also can't resolve goes to `## Blocked / escalated to me`.
- **The oracle defends `Låsta beslut`.** Neither you nor the oracle may redesign the
  spec; scope the spec doesn't require is rejected by default.
