# loop/ — autonomous task loop

A plan-bounded loop: the agent wakes, reads a task list, runs **one** task hands-off,
updates the list, commits, and stops. It reuses the machinery already in this repo
(`AGENTS.md` §4, `complexity-router`, `preference-oracle`, `goal-watcher`, `loop-guard`)
rather than inventing a new one.

## Pieces

| File | Role |
|------|------|
| `loop-prompt.md` | The cycle instruction fed to pi on every wake. The brain of the loop. |
| `run-loop.sh` | Runs **one** cycle now. Manual trigger. Builder model = qwen3.6. Logs to `loop/logs/`. |
| `ask-oracle.sh` | The `preference-oracle` — the builder calls it for decisions and phase sign-off. Now runs on a cloud CLI via `ask-cli-helper.sh`. |
| `ask-cli-helper.sh` | Headless "stronger model" helper: tries Claude CLI, falls back to Codex. Backs the oracle and the BLOCKED protocol's stronger-model rung. |
| `se.dalholm.autoloop.plist` | Prepared (not loaded) launchd schedule for later. |
| `Auto Tasks.md` (in Obsidian) | The backlog. Home of record: `~/Documents/Obsidian/dalholm/Projekt/Auto Tasks.md`. |

## Models (verified against pi's CLI)

- **Builder:** `lmstudio/qwen/qwen3.6-35b-a3b`, pinned in `run-loop.sh` via `pi -p --model …`.
- **Oracle / stronger model:** a cloud coding CLI — **Claude** (`claude -p`), falling back
  to **Codex** (`codex exec`) — invoked by `ask-cli-helper.sh`. The oracle is therefore a
  genuinely independent voice, separate from the local builder, with strong-tier judgment.
  No local fallback: if neither CLI answers, the task blocks and escalates to you (that is
  the human gate). Only the builder model needs LM Studio loaded; install + log in to the
  CLI(s). Verify the exact flags in `ask-cli-helper.sh` against your installed versions.

## How one cycle works

```
wake → read Auto Tasks.md → pick top runnable Queue task (one!)
     → branch → mark in-progress
     → run under router (T3 autonomous: oracle + goal-watcher + TDD + loop-guard)
     → success: → Done + commit   |   dead-end/scope: → Escalated + best guess
     → write report → STOP
```

One task per wake, on purpose. The cadence (you, or the schedule) decides the next cycle.

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
