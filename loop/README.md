# loop/ — autonomous task loop

A plan-bounded loop: the agent wakes, reads a task list, runs **one** task hands-off,
updates the list, commits, and stops. It reuses the machinery already in this repo
(`AGENTS.md` §4, `complexity-router`, `preference-oracle`, `goal-watcher`, `loop-guard`)
rather than inventing a new one.

## Pieces

| File | Role |
|------|------|
| `loop-prompt.md` | The cycle instruction fed to pi on every wake. The brain of the loop. |
| `run-loop.sh` | Runs **one** cycle now. Manual trigger. Builder model routed per task class. Logs to `loop/logs/`. |
| `plan-prompt.md` | **Slice 2:** instruction the strong CLI uses to write a junior plan (+ tests) the local builder implements. Plans cache in `Projekt/Auto Plans/`. |
| `review-gate.py` | **Slice 3:** strong-CLI review of a local cycle's branch diff before merge; `VERDICT: BLOCK` demotes the result to blocked. Tested by `test-review-gate.sh`. |
| `ask-oracle.sh` | The `preference-oracle` — the builder calls it for decisions and phase sign-off. Now runs on a cloud CLI via `ask-cli-helper.sh`. |
| `ask-cli-helper.sh` | Headless "stronger model" helper: tries Claude CLI, falls back to Codex. Backs the oracle, the plan pre-step, the review gate, and the BLOCKED protocol's stronger-model rung. |
| `ensure-path.sh` | Sourced by the above to make `pi`/`node` (nvm) and `claude`/`codex` (`~/.local/bin`) resolvable under launchd's minimal PATH. |
| `models-routing.json` (in `pi/`) | Hand-ordered task-class → local builder model, read at claim time. |
| `se.dalholm.autoloop.plist` | Prepared (not loaded) launchd schedule for later. |
| `Auto Tasks.md` (in Obsidian) | The backlog. Home of record: `~/Documents/Obsidian/dalholm/Projekt/Auto Tasks.md`. |

## Models (verified against pi's CLI)

- **Builder:** a local LM Studio model, **routed per task class** by `pi/models-routing.json`
  at claim time (default `lmstudio/qwen/qwen3.6-35b-a3b`; `class:mechanical-small` → gemma-12b).
  `run-loop.sh` runs whatever lands in `.claim-model`, with the qwen pin as fallback.
- **Oracle / stronger model:** a cloud coding CLI — **Claude** (`claude -p`), falling back
  to **Codex** (`codex exec`) — invoked by `ask-cli-helper.sh`. The oracle is therefore a
  genuinely independent voice, separate from the local builder, with strong-tier judgment.
  No local fallback: if neither CLI answers, the task blocks and escalates to you (that is
  the human gate). Only the builder model needs LM Studio loaded; install + log in to the
  CLI(s). Verify the exact flags in `ask-cli-helper.sh` against your installed versions.

## How one cycle works

```
wake → claim top runnable Queue task (one!) → route builder model by class
     → [local] strong CLI writes a junior plan + tests (cached in Auto Plans/)
     → branch → mark in-progress
     → run under router (T3 autonomous: oracle + goal-watcher + TDD + loop-guard)
     → [local] strong-CLI review gate on the diff → BLOCK demotes to blocked
     → success: → Done + merge to main   |   dead-end/scope/BLOCK: → resume ladder
     → write report → STOP
```

One task per wake, on purpose. The cadence (you, or the schedule) decides the next cycle.

### Resume ladder — self-rescue before it ever escalates to you

A crashed/unfinished cycle leaves the task in `## In progress`; the next cycle resumes it
(`claim-task.sh` counts `resume-attempts:`). The escalation to you is the *last* rung, not
the first:

1. **Local resumes** (attempts 1–2): the local builder retries, diagnosing the real
   blocker with the stronger model first (loop-prompt step 2).
2. **Strong-CLI rescue** (attempt 3): instead of giving up, the shell flips the cycle to
   `rescue` mode (`.claim-mode`) and hands the **same** cycle to the strong cloud CLI in
   **write mode** (`ask-cli-helper.sh HELPER_MODE=build`) — Claude/Codex actually edits,
   tests, and commits, not just advises. It writes the same `.cycle-result.json`, so
   completion is identical.
3. **Park for you** (attempt 4): only once the local resumes *and* the strong-CLI rescue
   have all failed does the task move to `## Blocked / escalated to me`.

So a task that lands in Blocked has genuinely exhausted both the local builder and a
stronger cloud agent — it's a real dead-end, not a flaky stall. Tune the rungs via
`RESCUE_AT` / `PARK_AT` in `claim-task.sh`.

**Skip straight to the strong builder.** Tag a task `builder:strong` in its header and the
shell runs it via the strong CLI (codex, build mode) from attempt 1 — no wasted local
grinds. Use it for heavy/fuzzy phases the local model keeps stalling on (e.g. a multi-part
simulation phase). The strong CLI reads the spec vault and writes/tests/commits the repo
itself. Override the CLI with `RESCUE_CLI=claude` if needed.

## Run it (manual, the current mode)

```sh
chmod +x loop/run-loop.sh      # first time only
./loop/run-loop.sh
```

Before the first real run, open `run-loop.sh` and check the **PI_RUN** line against
`pi --help` — that's the only harness-specific bit (how pi takes a one-shot prompt).

## Turn on a schedule later

You picked manual-first. When you trust it, enable the launchd job — see the comments
at the top of `se.dalholm.autoloop.plist`. The example fires at 08/12/16/20 daily; edit
the times or swap to `StartInterval` for "every N seconds".

**PATH under launchd is handled.** `pi` lives in nvm (and needs `node`); `claude`/`codex`
are in `~/.local/bin` — none of which launchd's minimal environment loads. `run-loop.sh`
and `ask-cli-helper.sh` source `ensure-path.sh`, which resolves the nvm node bin *by where
`pi` is* (so a `nvm install` of a newer node needs no edits) plus `~/.local/bin`. Override
the nvm dir with `PI_BIN_DIR` if needed.

## Safety rails (already enforced)

- **Plan-bounded:** tasks must have a `Done when:` line. Open-ended work is refused.
- **Never on main:** every task runs on its own `auto/T-###` branch.
- **Human gate intact:** `preference-oracle` only answers low-stakes, written-down
  questions; everything irreversible/ambiguous escalates to you in the
  *Blocked / escalated* section with a best guess to confirm.
- **Anti-thrash:** `loop-guard` stops the agent if it starts repeating itself.

## Add work

Edit `Auto Tasks.md` in Obsidian. Put loop-ready items (with a `Done when`) in
**Queue**; dump half-formed ideas in **Inbox** (the loop ignores those until you
promote them).
