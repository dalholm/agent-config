#!/usr/bin/env python3
"""claim-task.sh — deterministically claim ONE task before the LLM runs.

The local builder model is unreliable at bookkeeping, so the shell (not the model)
owns the claim. This script:

  1. If a task is already in `## In progress` (`- [/]`), prints its id and exits — that
     is a claimed/orphaned task to resume; we never claim a second one.
  2. Otherwise moves the top runnable `- [ ]` task from `## Queue` into `## In progress`,
     flips it to `- [/]`, stamps `claimed:`/`pid:`, prints its id.
  3. If there is nothing to claim, prints `NONE`.

"Top runnable" = highest prio (high > med > low), then document order — matching the
loop-prompt. This guarantees a task is never left re-pickable as `- [ ]` while it runs,
which is what caused the same task to restart every cycle.

Usage:  claim-task.sh <pid>          (pid stamped into the claim)
Env:    AUTO_TASKS  overrides the task-list path.
"""
import os, re, sys, datetime, json

TASKS = os.environ.get(
    "AUTO_TASKS",
    "/Users/dalholm/Documents/Obsidian/dalholm/Projekt/Auto Tasks.md",
)
PID = sys.argv[1] if len(sys.argv) > 1 else str(os.getpid())

# Sidecar telling run-loop.sh WHO should execute this cycle:
#   "local"  → the local builder model (pi) — the default.
#   "rescue" → the strong cloud CLI (Claude/Codex) with write access — the last-ditch
#              attempt, after the local model has burned its resumes but before we give up.
CLAIM_MODE_FILE = os.environ.get(
    "CLAIM_MODE_FILE",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), ".claim-mode"),
)
# Sidecar with the claimed task's repo path (from its `repo:` tag), so run-loop can run a
# strong-CLI build with cwd = the repo. codex's workspace-write sandbox only allows writes
# under cwd, so without this the build can read the vault but cannot write the repo.
CLAIM_REPO_FILE = os.environ.get(
    "CLAIM_REPO_FILE",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), ".claim-repo"),
)
# Sidecar with the local builder MODEL routed for this cycle, resolved from the task's
# `class:` tag against pi/models-routing.json. run-loop.sh reads it instead of hardcoding a
# model, so a small mechanical task can run on a faster small local model. Only consulted
# for local cycles (rescue cycles use the strong CLI, not this).
CLAIM_MODEL_FILE = os.environ.get(
    "CLAIM_MODEL_FILE",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), ".claim-model"),
)
MODELS_ROUTING = os.environ.get(
    "MODELS_ROUTING",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pi", "models-routing.json"),
)
# Safe default if routing is missing/unreadable — the proven general local builder.
DEFAULT_CLASS = "coding-general"
DEFAULT_MODEL = "lmstudio/qwen/qwen3.6-35b-a3b"
# Resume ladder: local attempts 1..(RESCUE_AT-1), one strong-CLI rescue at RESCUE_AT,
# then park in Blocked once even the rescue has failed (>= PARK_AT).
RESCUE_AT = 3
PARK_AT = 4


def write_mode(mode):
    with open(CLAIM_MODE_FILE, "w", encoding="utf-8") as f:
        f.write(mode)


def is_strong(header_line):
    """A `builder:strong` tag pins the task to the strong cloud CLI (codex/claude) from
    attempt 1 — for heavy/fuzzy phases the local builder keeps stalling on."""
    return "builder:strong" in header_line


def extract_repo(header_line):
    """Pull the repo path out of a `repo:/abs/path` tag (backtick-wrapped). Empty if none."""
    m = re.search(r"`?repo:([^`\s]+)`?", header_line)
    return m.group(1) if m else ""


def write_repo(path):
    with open(CLAIM_REPO_FILE, "w", encoding="utf-8") as f:
        f.write(path)


def extract_class(header_line):
    """Pull the task class out of a `class:<name>` tag; default when absent."""
    m = re.search(r"`?class:([a-z0-9-]+)`?", header_line)
    return m.group(1) if m else DEFAULT_CLASS


def resolve_model(task_class):
    """Map a task class to a local builder model via models-routing.json. Robust: any
    problem (missing file, bad JSON, unknown class) falls back to a safe default, so the
    loop never dies on routing."""
    try:
        with open(MODELS_ROUTING, "r", encoding="utf-8") as f:
            routing = json.load(f)
    except (OSError, ValueError):
        return DEFAULT_MODEL
    fallback = routing.get("fallback_model", DEFAULT_MODEL)
    return routing.get("classes", {}).get(task_class, fallback)


def write_model(header_line):
    with open(CLAIM_MODEL_FILE, "w", encoding="utf-8") as f:
        f.write(resolve_model(extract_class(header_line)))

HEADER = re.compile(r"^- \[([ x/!])\] \*\*(T-\d+)\*\*")
PRIO = re.compile(r"`prio:(high|med|low)`")
PRIO_RANK = {"high": 0, "med": 1, "low": 2}
SECTION = re.compile(r"^## (.+?)\s*$")


def load():
    with open(TASKS, "r", encoding="utf-8") as f:
        return f.read().split("\n")


def sections(lines):
    """Return {name: (start_idx_of_header, end_idx_exclusive)} for each ## section."""
    idxs = [(i, m.group(1)) for i, l in enumerate(lines) for m in [SECTION.match(l)] if m]
    out = {}
    for k, (i, name) in enumerate(idxs):
        end = idxs[k + 1][0] if k + 1 < len(idxs) else len(lines)
        out[name] = (i, end)
    return out


def block_end(lines, start, limit):
    """A task block = header line + following indented lines, until a blank/non-indent."""
    j = start + 1
    while j < limit and (lines[j].startswith((" ", "\t"))):
        j += 1
    return j


def find_blocks(lines, lo, hi, status):
    blocks = []
    i = lo
    while i < hi:
        m = HEADER.match(lines[i])
        if m and m.group(1) == status:
            end = block_end(lines, i, hi)
            pm = PRIO.search(lines[i])
            prio = pm.group(1) if pm else "med"
            blocks.append({"id": m.group(2), "start": i, "end": end, "prio": prio})
            i = end
        else:
            i += 1
    return blocks


def main():
    lines = load()
    sec = sections(lines)
    if "Queue" not in sec or "In progress" not in sec:
        print("NONE")
        return

    # 1) Already-claimed / orphan task in In progress? Resume it, with a crash cap.
    ip_lo, ip_hi = sec["In progress"]
    inprog = find_blocks(lines, ip_lo, ip_hi, "/")
    if inprog:
        blk = inprog[0]
        s, e = blk["start"], blk["end"]
        # find/increment a deterministic resume counter inside the block
        ai, attempts = None, 0
        for k in range(s, e):
            mm = re.match(r"\s*- resume-attempts:\s*(\d+)", lines[k])
            if mm:
                ai, attempts = k, int(mm.group(1))
                break
        attempts += 1
        if attempts >= PARK_AT:
            # local resumes AND the strong-CLI rescue all failed → park for the human.
            block = lines[s:e]
            block[0] = block[0].replace("- [/]", "- [!]", 1)
            block.insert(1, "  - blocked: %dx failed (local resumes + strong-CLI rescue) — needs your eyes" % attempts)
            del lines[s:e]
            bsec = sections(lines)
            bname = next((n for n in bsec if n.startswith("Blocked")), None)
            if bname:
                blo, bhi = bsec[bname]
                at = blo + 1
                while at < bhi and (lines[at].strip().startswith("<!--") or lines[at].strip() == ""):
                    at += 1
                lines[at:at] = block + [""]
            with open(TASKS, "w", encoding="utf-8") as f:
                f.write("\n".join(lines))
            sys.stderr.write("resume cap hit for %s — moved to Blocked\n" % blk["id"])
            sec = sections(lines)  # fall through to claim a fresh task below
        else:
            counter = "  - resume-attempts: %d" % attempts
            if ai is not None:
                lines[ai] = counter
            else:
                lines.insert(s + 1, counter)
            with open(TASKS, "w", encoding="utf-8") as f:
                f.write("\n".join(lines))
            # Strong-CLI from attempt 1 if pinned; otherwise the last-ditch rescue rung
            # hands attempt RESCUE_AT to the strong cloud CLI.
            strong = is_strong(lines[s]) or attempts >= RESCUE_AT
            write_mode("rescue" if strong else "local")
            write_repo(extract_repo(lines[s]))
            write_model(lines[s])
            print(blk["id"])  # resume this one; don't claim another
            return

    # 2) Pick the top runnable task in Queue.
    q_lo, q_hi = sec["Queue"]
    runnable = find_blocks(lines, q_lo, q_hi, " ")
    if not runnable:
        print("NONE")
        return
    runnable.sort(key=lambda b: (PRIO_RANK.get(b["prio"], 1), b["start"]))
    pick = runnable[0]

    block = lines[pick["start"]:pick["end"]]
    # flip checkbox and stamp claim on the header's first sub-line
    block[0] = block[0].replace("- [ ]", "- [/]", 1)
    stamp = "  - claimed: %s  pid: %s" % (
        datetime.datetime.now().isoformat(timespec="seconds"), PID)
    block.insert(1, stamp)

    # remove from Queue
    del lines[pick["start"]:pick["end"]]

    # re-locate In progress header (indices shifted) and insert block after its comment
    sec = sections("\n".join(lines).split("\n"))
    ip_lo, ip_hi = sec["In progress"]
    insert_at = ip_lo + 1
    while insert_at < ip_hi and (lines[insert_at].strip().startswith("<!--")
                                 or lines[insert_at].strip() == ""):
        insert_at += 1
    lines[insert_at:insert_at] = block + [""]

    with open(TASKS, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    # builder:strong pins to the strong CLI from the first attempt; else the local builder.
    write_mode("rescue" if is_strong(block[0]) else "local")
    write_repo(extract_repo(block[0]))
    write_model(block[0])
    print(pick["id"])


if __name__ == "__main__":
    main()
