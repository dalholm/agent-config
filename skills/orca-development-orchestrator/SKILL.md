---
name: orca-development-orchestrator
description: Coordinate repository development through Orca when Hermes receives an investigation, design, implementation, debugging, testing, review, or manual-QA request.
---

# Orca Development Orchestrator

Hermes is the development coordinator. Orca owns isolated worktrees, terminals,
supervised workers, execution surfaces, run state, and orchestration history. Workers
own source-level investigation, design, implementation, debugging, tests, review, and
manual QA. Do not replace a worker with Hermes source reading or editing.

## Coordinate a development request

1. Load `complexity-router` and classify the request. For pure knowledge questions,
   answer directly and stop. Completion means the selected track is recorded without
   copying its track or escalation rules here.
2. Assemble control-plane context: the repository path, applicable instruction files,
   approved vault spec or plan, requested outcome, relevant Orca state, and any grants
   already present in the request. Do not inspect repository source or tests to do a
   worker's development work. Completion means the contract can be dispatched without
   guessing requirements or authority.
3. Load `model-routing` and select a logical role and tier for each worker. Load the
   installed, version-matched `orca-cli` and `orchestration` guides before choosing
   concrete Orca commands. Completion means routing is resolved at the dispatch
   boundary rather than embedded in this skill.
4. Preflight the operation through `agent-safety`. For headless work, require the
   approved finite plan, recorded grants, an isolated non-main worktree, and the
   policy-required healthy doctor scope. A `deny` stops; `require-user` needs an exact
   user grant. Completion means safety authority and execution readiness are both
   explicit.
5. Dispatch a bounded worker contract containing role/tier, objective, repository and
   worktree basis, applicable instructions and skills, specification, in-scope and
   out-of-scope work, acceptance criteria, quality and safety gates, required evidence,
   and a stop condition. Completion means the worker can finish without inventing
   scope.
6. Monitor Orca state, heartbeats, questions, and completion messages. Answer only from
   approved context and documented preferences. Set a finite retry limit, and retry a
   failed dispatch only when the objective and authority are unchanged; otherwise
   escalate. Completion means every active task is finished, genuinely blocked, or
   returned for a scope decision.
7. Verify worker evidence against every acceptance criterion. Require behavior tests
   or the nearest observable configuration check, targeted and relevant full tests,
   and a clean self-review. Dispatch an independent `reviewer/deep` review from a
   different provider family when available, using `model-routing` for the binding.
   Completion means findings are fixed or explicitly reported.
8. Run real-surface QA through an Orca browser, desktop, or terminal worker when the
   change has a user-visible or installed surface. Completion means the observed
   result, commands, and limitations are recorded.
9. Report what changed, verification evidence, review and QA results, remaining risks,
   commit references, and any safe user-owned next step. Completion means the report
   distinguishes verified results from pending installation or deployment.

## Worker dispatch policy

Orca, not the generic worker adapter, owns automatic harness selection.

- Resolve `scout/fast` and `coder/fast` without a harness through
  `agent-model-route`. When the registry returns Pi with the local Qwen binding,
  dispatch that explicit harness/model route to the worker adapter.
- Give `scout/fast` read-only contracts for file discovery, code mapping, convention
  discovery, and test inventory. Its Pi adapter exposes only `read`, `rg`, and `fd`.
- Give `coder/fast` only small, explicit file and command scopes. Escalate to a
  frontier `coder/standard` worker when the task crosses its file boundary, needs a
  design decision, touches sensitive operations, or repeats a failure.
- An explicit user model choice, a capability requirement, or a risk escalation
  overrides the automatic local route. Record the reason with the dispatch.

For review, record the author harness and resolved provider family from the completed
worker route. Resolve `reviewer/deep` with `--review-of-harness <author-harness>` and,
for hybrid or inherited authors, `--review-of-provider-family <family>`. Dispatch the
returned frontier harness. The reviewer must differ from the author provider family;
a worker's own self-review or a local preliminary check never satisfies final review.
