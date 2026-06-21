#!/usr/bin/env python3
"""complete-task.sh — deterministic completion bookkeeping, run by the shell after pi.

The agent does the work, gets oracle sign-off, commits on the branch, then writes a
small result file (loop/.cycle-result.json) and stops. It does NOT edit the task-list
structure. This script reads that result and performs ALL markdown surgery + the
optional merge to main, so the flaky local model can never scramble its own state file.

Result file schema (the agent writes this):
{
  "status": "done" | "blocked" | "nothing",
  "task_id": "T-002",
  "summary": "one line for the Done entry (result, commit, oracle verdict)",
  "repo": "/abs/path/to/repo",        # for merge; optional
  "branch": "auto/T-002-fas1",        # for merge; optional
  "merge_to_main": true,              # merge the branch into main on done
  "reason": "why blocked",            # for status=blocked
  "next_task": "- [ ] **T-003** ...\n  - **Done when:** ..."  # markdown to arm; or null
}

No result file = the agent crashed mid-cycle → leave the task in In progress so the next
cycle resumes it (with the 3-strike cap in the loop-prompt).

Usage:  complete-task.sh [claimed_task_id]
Env:    AUTO_TASKS overrides the task-list path.
"""
import os, sys, json, re, subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TASKS = os.environ.get(
    "AUTO_TASKS", "/Users/dalholm/Documents/Obsidian/dalholm/Projekt/Auto Tasks.md")
RESULT = os.environ.get("CYCLE_RESULT", os.path.join(SCRIPT_DIR, ".cycle-result.json"))

SECTION = re.compile(r"^## (.+?)\s*$")
HEADER = re.compile(r"^- \[([ x/!])\] \*\*(T-\d+)\*\*")


def load():
    with open(TASKS, encoding="utf-8") as f:
        return f.read().split("\n")


def sections(lines):
    idxs = [(i, m.group(1)) for i, l in enumerate(lines) for m in [SECTION.match(l)] if m]
    out = {}
    for k, (i, name) in enumerate(idxs):
        end = idxs[k + 1][0] if k + 1 < len(idxs) else len(lines)
        out[name] = (i, end)
    return out


def block_end(lines, start, limit):
    j = start + 1
    while j < limit and lines[j].startswith((" ", "\t")):
        j += 1
    return j


def find_inprogress(lines, task_id):
    sec = sections(lines)
    if "In progress" not in sec:
        return None, None
    lo, hi = sec["In progress"]
    i = lo
    while i < hi:
        m = HEADER.match(lines[i])
        if m and m.group(1) == "/" and (not task_id or m.group(2) == task_id):
            return i, block_end(lines, i, hi)
        i += 1
    return None, None


def insert_after_header(lines, name, new_lines):
    sec = sections(lines)
    lo, hi = sec[name]
    at = lo + 1
    while at < hi and (lines[at].strip().startswith("<!--") or lines[at].strip() == ""):
        at += 1
    lines[at:at] = new_lines


def do_merge(repo, branch):
    try:
        subprocess.run(["git", "-C", repo, "checkout", "main"],
                       check=True, capture_output=True)
        subprocess.run(["git", "-C", repo, "merge", "--no-ff", "-m",
                        "Merge %s (loop)" % branch, branch],
                       check=True, capture_output=True)
        return True
    except Exception:
        return False


def main():
    claimed = sys.argv[1] if len(sys.argv) > 1 else None
    if not os.path.exists(RESULT):
        print("no result file — leaving task in progress to resume next cycle")
        return

    with open(RESULT) as f:
        r = json.load(f)
    status = r.get("status", "nothing")

    lines = load()
    bstart, bend = find_inprogress(lines, r.get("task_id") or claimed)
    if bstart is None:
        print("no matching in-progress task; nothing to complete")
        os.remove(RESULT)
        return
    tid = HEADER.match(lines[bstart]).group(2)

    # done: optionally merge first; a failed merge demotes to blocked
    merged = ""
    if status == "done" and r.get("merge_to_main") and r.get("repo") and r.get("branch"):
        if do_merge(r["repo"], r["branch"]):
            merged = "  Merged to main."
        else:
            status = "blocked"
            r["reason"] = "merge of %s into main failed (conflict?) — needs your eyes" % r["branch"]

    del lines[bstart:bend]  # remove from In progress

    if status == "done":
        summary = r.get("summary", "(no summary)").strip()
        insert_after_header(lines, "Done", ["- [x] **%s** %s%s" % (tid, summary, merged), ""])
        nxt = r.get("next_task")
        if nxt:
            insert_after_header(lines, "Queue", nxt.rstrip("\n").split("\n") + [""])
        print("completed %s; armed next: %s" % (tid, "yes" if r.get("next_task") else "no"))
    else:  # blocked
        reason = r.get("reason", "dead-end").strip()
        insert_after_header(lines, "Blocked / escalated to me",
                            ["- [!] **%s** %s" % (tid, reason), ""])
        print("blocked %s: %s" % (tid, reason))

    with open(TASKS, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    os.remove(RESULT)


if __name__ == "__main__":
    main()
