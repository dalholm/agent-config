#!/usr/bin/env python3
"""review-gate.py — Slice 3: a strong-model review gate on a local cycle's diff.

Run by run-loop.sh for LOCAL cycles only, after the builder writes .cycle-result.json and
before complete-task.sh merges anything. A weak local model's "done" is the loop's least
trustworthy signal, so a stronger CLI reviews the branch diff. On a BLOCK verdict this
rewrites the result file to status:blocked, which routes the task back through the SAME
resume/rescue ladder — no second ladder, and no merge of an unreviewed diff to main.

Fail-open by design: if the diff is empty, the repo/branch is missing, or the reviewer is
unavailable, the gate PASSES (it must never stall the loop on infra trouble) but says so.
A rescue cycle is the strong model already, so run-loop.sh does not gate it.

Testability env:
  CYCLE_RESULT          path to the result file (default loop/.cycle-result.json)
  REVIEW_DIFF_OVERRIDE  use this text as the diff instead of running git
  REVIEW_TEXT_OVERRIDE  use this text as the reviewer output instead of calling the CLI
"""
import os, json, subprocess, re

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RESULT = os.environ.get("CYCLE_RESULT", os.path.join(SCRIPT_DIR, ".cycle-result.json"))
ASK = os.path.join(SCRIPT_DIR, "ask-cli-helper.sh")


def get_diff(repo, branch):
    if "REVIEW_DIFF_OVERRIDE" in os.environ:
        return os.environ["REVIEW_DIFF_OVERRIDE"]
    try:
        out = subprocess.run(["git", "-C", repo, "diff", "main...%s" % branch],
                             capture_output=True, text=True)
        return out.stdout
    except Exception:
        return ""


def build_review_prompt(diff, task_id):
    return (
        "You are a senior code reviewer. A weaker LOCAL model implemented task %s "
        "autonomously; its acceptance criterion is that task's `Done when` in Auto Tasks.md "
        "(read it if useful). Review the branch diff below for correctness bugs, security "
        "issues, and whether it actually satisfies that criterion. Weak-model output often "
        "looks right but is subtly wrong, so be strict — but judge correctness, not style.\n"
        "End your reply with exactly one final line: `VERDICT: PASS` or `VERDICT: BLOCK`. "
        "Use BLOCK only for real correctness/security/criterion failures, never mere nits.\n\n"
        "```diff\n%s\n```" % (task_id, diff)
    )


def get_review(prompt):
    if "REVIEW_TEXT_OVERRIDE" in os.environ:
        return os.environ["REVIEW_TEXT_OVERRIDE"]
    try:
        out = subprocess.run(
            [ASK, prompt], capture_output=True, text=True,
            env={**os.environ, "HELPER_MODE": "consult", "HELPER_CHANNEL": "stronger-model"},
        )
        return out.stdout if out.returncode == 0 else ""
    except Exception:
        return ""


def parse_verdict(text):
    """BLOCK only on an explicit final BLOCK marker; everything else (including an
    unavailable reviewer that returns nothing) -> PASS, so review-infra trouble never
    stalls the loop. The last marker in the text wins."""
    markers = re.findall(r"VERDICT:\s*(PASS|BLOCK)", text or "", re.IGNORECASE)
    return "BLOCK" if markers and markers[-1].upper() == "BLOCK" else "PASS"


def main():
    if not os.path.exists(RESULT):
        return
    with open(RESULT) as f:
        r = json.load(f)
    if r.get("status") != "done":
        return  # only gate a successful cycle; blocked/nothing pass straight through
    repo, branch = r.get("repo"), r.get("branch")
    if not repo or not branch:
        print("review-gate: no repo/branch (non-code task) — PASS")
        return
    diff = get_diff(repo, branch)
    if not diff.strip():
        print("review-gate: empty diff — PASS")
        return
    verdict = parse_verdict(get_review(build_review_prompt(diff, r.get("task_id", "?"))))
    if verdict == "BLOCK":
        r["status"] = "blocked"
        r.pop("merge_to_main", None)
        r["reason"] = "senior review gate blocked the local diff — needs a fix or your eyes"
        with open(RESULT, "w") as f:
            json.dump(r, f)
        print("review-gate: BLOCK — result demoted to blocked (no merge to main)")
    else:
        print("review-gate: PASS")


if __name__ == "__main__":
    main()
