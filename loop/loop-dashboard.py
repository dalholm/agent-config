#!/usr/bin/env python3
"""loop-dashboard.py — a tiny local web view of the autonomous loop.

No dependencies (Python stdlib only). It reads the loop's own files — the lock, the
per-cycle logs, the cycle result, and the Auto Tasks list — and serves an auto-refreshing
page so you can see, at a glance:

  • is a cycle running right now, and which task it claimed
  • what it's doing this second (live tail of the active log)
  • the task board: Queue / In progress / Blocked / Done
  • recent cycles and how each ended

Run:    python3 loop-dashboard.py            # then open http://localhost:8787
Env:    AUTO_TASKS  overrides the task-list path · PORT overrides the port.
"""
import os, re, json, glob, html, signal, shutil, datetime, subprocess, http.server, socketserver

HERE = os.path.dirname(os.path.abspath(__file__))
LOGS = os.path.join(HERE, "logs")
LOCK = os.path.join(HERE, ".loop.lock", "pid")
LOCK_DIR = os.path.join(HERE, ".loop.lock")
RESULT = os.path.join(HERE, ".cycle-result.json")
CONV = os.path.join(LOGS, "conversations.jsonl")   # inter-agent chat transcript
RUNLOOP = os.path.join(HERE, "run-loop.sh")
WATCH = os.path.join(HERE, "watch-cycle.sh")

# launchd schedule controls
UID = os.getuid()
LABEL = "se.dalholm.autoloop"
PLIST_SRC = os.path.join(HERE, LABEL + ".plist")
PLIST_DST = os.path.expanduser("~/Library/LaunchAgents/%s.plist" % LABEL)
TASKS = os.environ.get(
    "AUTO_TASKS", "/Users/dalholm/Documents/Obsidian/dalholm/Projekt/Auto Tasks.md")
PORT = int(os.environ.get("PORT", "8787"))
REFRESH = 3  # seconds

SECTION = re.compile(r"^## (.+?)\s*$")
HEADER = re.compile(r"^- \[([ x/!])\] \*\*(T-\d+)\*\*\s*(.*)$")
STATUS_ICON = {" ": "•", "/": "▶", "x": "✓", "!": "⚠"}


def pid_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except Exception:
        return False


def read_lock():
    try:
        pid = open(LOCK).read().strip()
        return pid, pid_alive(pid)
    except Exception:
        return None, False


def newest_log():
    files = sorted(glob.glob(os.path.join(LOGS, "cycle-*.log")), key=os.path.getmtime)
    return files[-1] if files else None


def tail(path, n=45):
    try:
        with open(path, errors="replace") as f:
            return "".join(f.readlines()[-n:])
    except Exception:
        return ""


def parse_tasks():
    try:
        lines = open(TASKS, encoding="utf-8").read().split("\n")
    except Exception:
        return {}
    idxs = [(i, m.group(1)) for i, l in enumerate(lines) for m in [SECTION.match(l)] if m]
    out = {}
    for k, (i, name) in enumerate(idxs):
        end = idxs[k + 1][0] if k + 1 < len(idxs) else len(lines)
        items = []
        for l in lines[i + 1:end]:
            m = HEADER.match(l)
            if m:
                items.append((m.group(1), m.group(2), m.group(3)[:90]))
        out[name] = items
    return out


def recent_cycles(k=8):
    files = sorted(glob.glob(os.path.join(LOGS, "cycle-*.log")), key=os.path.getmtime,
                   reverse=True)[:k]
    rows = []
    for f in files:
        txt = open(f, errors="replace").read()
        claimed = (re.search(r"claimed task: (\S+)", txt) or [None, "—"])[1]
        ended = "loop cycle end" in txt
        # outcome heuristic from the agent report / shell lines
        if "completed " in txt and "armed next" in txt:
            outcome = "✓ completed"
        elif re.search(r"blocked|BLOCKED", txt):
            outcome = "⚠ blocked"
        elif "nothing to do" in txt:
            outcome = "· nothing to do"
        elif "no result file" in txt:
            outcome = "↻ no result (resumes)"
        elif not ended:
            outcome = "▶ running"
        else:
            outcome = "ended"
        ts = datetime.datetime.fromtimestamp(os.path.getmtime(f)).strftime("%H:%M:%S")
        rows.append((ts, os.path.basename(f), claimed, outcome, ended))
    return rows


def read_conversations(n=16):
    """Last n messages from the inter-agent chat transcript (JSONL)."""
    try:
        lines = open(CONV, errors="replace").read().splitlines()
    except Exception:
        return []
    out = []
    for l in lines[-n:]:
        l = l.strip()
        if not l:
            continue
        try:
            out.append(json.loads(l))
        except Exception:
            pass
    return out


# who-said-it → CSS accent class for the chat bubble
CHAT_CLS = {"loop": "c-loop", "builder": "c-builder", "oracle": "c-oracle",
            "stronger-model": "c-strong", "claude": "c-cli", "codex": "c-cli"}


def render_chat():
    msgs = read_conversations()
    if not msgs:
        return ("<p class='sub'>(no agent messages yet — the loop's instructions, the "
                "builder&#8596;oracle questions, and the answers appear here once a cycle runs)</p>")
    out = []
    for m in msgs:
        frm = m.get("from", "?"); to = m.get("to", "?")
        kind = m.get("kind", ""); ts = m.get("ts", "")
        text = m.get("text", "") or ""
        cls = CHAT_CLS.get(frm, "c-other")
        head = "%s &rarr; %s &middot; %s" % (esc(frm), esc(to), esc(kind))
        # long instructions/questions collapse; short answers/results show inline
        if kind in ("instruction", "question") and len(text) > 400:
            body = ("<details><summary>%d chars &mdash; expand</summary>"
                    "<pre class='bub'>%s</pre></details>") % (len(text), esc(text))
        else:
            body = "<pre class='bub'>%s</pre>" % esc(text)
        out.append("<div class='msg %s'><div class='mhead'>%s "
                   "<span class='ts'>%s</span></div>%s</div>" % (cls, head, esc(ts), body))
    return "".join(out)


def esc(s):
    return html.escape(s or "")


def render():
    pid, alive = read_lock()
    running = pid and alive
    nl = newest_log()
    tasks = parse_tasks()
    result_exists = os.path.exists(RESULT)

    banner_color = "#1f6f43" if running else "#3a3f4b"
    banner_text = ("● RUNNING — cycle pid %s" % pid) if running else "○ idle (no cycle running)"

    # controls row: schedule toggle + stop
    scheduled = schedule_loaded()
    if scheduled:
        sched_btn = ("<form method='post' action='/schedule-off' class='ctl'>"
                     "<button class='sched on'>⏱ Schedule ON (every 5 min) — turn off</button></form>")
    else:
        sched_btn = ("<form method='post' action='/schedule-on' class='ctl'>"
                     "<button class='sched'>⏱ Schedule OFF — run every 5 min</button></form>")
    stop_btn = ("<form method='post' action='/stop' class='ctl'>"
                "<button class='stop' %s>■ Stop current cycle</button></form>" %
                ("" if running else "disabled"))
    controls = sched_btn + stop_btn

    # task board
    board = ""
    for sec in ["Queue", "In progress", "Blocked / escalated to me", "Done"]:
        items = tasks.get(sec, [])
        rows = "".join(
            "<li><span class='st st-%s'>%s</span> <b>%s</b> %s</li>" %
            (st.strip() or "q", STATUS_ICON.get(st, "•"), esc(tid), esc(rest))
            for (st, tid, rest) in items) or "<li class='empty'>—</li>"
        board += "<div class='col'><h3>%s <span class='cnt'>%d</span></h3><ul>%s</ul></div>" % (
            esc(sec), len(items), rows)

    # recent cycles
    crows = "".join(
        "<tr class='%s'><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" %
        ("run" if not ended else "", ts, esc(claimed), esc(outcome), esc(name))
        for (ts, name, claimed, outcome, ended) in recent_cycles())

    live = esc(tail(nl)) if nl else "(no cycle logs yet)"
    live_name = os.path.basename(nl) if nl else ""
    note = " · result file present (cycle finishing)" if result_exists else ""

    return """<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="refresh" content="{refresh}">
<title>Loop dashboard</title>
<style>
 body{{font:13px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;margin:0;background:#0f1115;color:#e7e9ea}}
 .wrap{{max-width:1100px;margin:0 auto;padding:16px}}
 .banner{{background:{bc};padding:12px 16px;border-radius:10px;font-weight:600;font-size:15px}}
 h2{{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:#8a92a0;margin:22px 0 8px}}
 .board{{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}}
 .col{{background:#171a21;border:1px solid #232732;border-radius:10px;padding:10px}}
 .col h3{{margin:0 0 6px;font-size:12px;color:#aab2c0}} .cnt{{color:#6b7280}}
 .col ul{{list-style:none;margin:0;padding:0}} .col li{{padding:3px 0;border-top:1px solid #20242e;font-size:12px}}
 .col li.empty{{color:#4b5563;border:0}}
 .st{{display:inline-block;width:14px}} .st-/{{color:#f0b73f}} .st-x{{color:#3fae6e}} .st-!{{color:#e0524b}}
 table{{width:100%;border-collapse:collapse;font-size:12px}}
 td{{padding:5px 8px;border-top:1px solid #20242e}} tr.run td{{background:#16241b}}
 pre{{background:#0a0c10;border:1px solid #232732;border-radius:10px;padding:12px;overflow:auto;
      max-height:340px;font:12px/1.45 SFMono-Regular,Menlo,monospace;color:#cdd3db;white-space:pre-wrap}}
 .sub{{color:#6b7280;font-size:11px;margin:4px 0 0}}
 .topbar{{display:flex;gap:10px;align-items:stretch}} .topbar .banner{{flex:1}}
 .trigger button{{height:100%;border:0;border-radius:10px;background:#2c5cff;color:#fff;
   font-weight:600;font-size:13px;padding:0 16px;cursor:pointer}}
 .trigger button:hover{{background:#1f4ae0}}
 .trigger button:disabled{{background:#2a2f3a;color:#6b7280;cursor:not-allowed}}
 .trigger button.alt{{background:#2d3340}} .trigger button.alt:hover{{background:#3a4150}}
 .controls{{display:flex;gap:10px;margin-top:10px;flex-wrap:wrap}}
 .controls button{{border:0;border-radius:10px;padding:9px 14px;font-weight:600;font-size:13px;cursor:pointer}}
 .controls .sched{{background:#2d3340;color:#e7e9ea}} .controls .sched.on{{background:#1f6f43;color:#fff}}
 .controls .stop{{background:#7a2620;color:#fff}} .controls .stop:hover{{background:#9a3027}}
 .controls .stop:disabled{{background:#2a2f3a;color:#6b7280;cursor:not-allowed}}
 .chat{{display:flex;flex-direction:column;gap:8px;max-height:440px;overflow:auto;
   background:#0a0c10;border:1px solid #232732;border-radius:10px;padding:12px}}
 .msg{{border-left:3px solid #3a3f4b;padding:1px 0 3px 10px}}
 .mhead{{font-size:11px;color:#aab2c0;font-weight:700;text-transform:uppercase;letter-spacing:.04em}}
 .mhead .ts{{color:#5b6472;font-weight:400;text-transform:none;margin-left:6px}}
 .bub{{margin:4px 0 0;background:#11141b;border:1px solid #20242e;border-radius:8px;
   padding:8px 10px;font:12px/1.45 SFMono-Regular,Menlo,monospace;color:#cdd3db;
   white-space:pre-wrap;max-height:240px;overflow:auto}}
 .msg details summary{{cursor:pointer;color:#8a92a0;font-size:12px;padding:4px 0}}
 .c-loop{{border-color:#2c5cff}} .c-builder{{border-color:#3fae6e}}
 .c-oracle{{border-color:#b06cff}} .c-strong{{border-color:#f0b73f}} .c-cli{{border-color:#33b5b5}}
 .c-other{{border-color:#3a3f4b}}
</style></head><body><div class="wrap">
 <div class="topbar">
   <div class="banner">{banner}{note}</div>
   <form method="post" action="/run" class="trigger"><button {disabled}>▶ Run (headless)</button></form>
   <form method="post" action="/watch" class="trigger"><button class="alt">🖥 Open live window</button></form>
 </div>
 <div class="controls">{controls}</div>
 <h2>Live activity {live_name}</h2>
 <p class="sub">pi -p doesn't stream — the full report appears when the cycle ends. A quiet
   tail with the lock held means it's working.</p>
 <pre>{live}</pre>
 <h2>Agent chat</h2>
 <p class="sub">Everything that flows between the loop, the builder, the oracle, and the
   stronger-model CLI — the kickoff instructions, the questions, and the answers. Newest at the bottom.</p>
 <div class="chat">{chat}</div>
 <h2>Task board</h2>
 <div class="board">{board}</div>
 <h2>Recent cycles</h2>
 <table>{crows}</table>
 <p class="sub">auto-refresh every {refresh}s · {now}</p>
</div></body></html>""".format(
        refresh=REFRESH, bc=banner_color, banner=esc(banner_text), note=note,
        disabled=("disabled" if running else ""), controls=controls,
        live_name=esc(live_name), live=live, chat=render_chat(), board=board, crows=crows,
        now=datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))


def _spawn(script):
    """Launch a loop script detached. Inherits this process's PATH (so pi/tmux are found,
    unlike under launchd). The run-loop lock keeps cycles single-flight."""
    try:
        subprocess.Popen(["bash", script], cwd=HERE,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        return True
    except Exception:
        return False


def trigger_cycle():
    return _spawn(RUNLOOP)        # headless: output → log


def trigger_watch():
    return _spawn(WATCH)         # tmux: live streaming window


def _sh(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=10)
    except Exception:
        return None


def schedule_loaded():
    r = _sh(["launchctl", "list"])
    return bool(r and r.returncode == 0 and LABEL in r.stdout)


def schedule_on():
    os.makedirs(os.path.dirname(PLIST_DST), exist_ok=True)
    if not os.path.exists(PLIST_DST) and os.path.exists(PLIST_SRC):
        try:
            shutil.copy(PLIST_SRC, PLIST_DST)
        except Exception:
            pass
    _sh(["launchctl", "bootout", "gui/%d/%s" % (UID, LABEL)])   # clear any stale, ignore err
    _sh(["launchctl", "bootstrap", "gui/%d" % UID, PLIST_DST])


def schedule_off():
    _sh(["launchctl", "bootout", "gui/%d/%s" % (UID, LABEL)])


def stop_cycle():
    """Kill the running cycle (run-loop.sh + its pi child) and clean up the lock + tmux."""
    pid, alive = read_lock()
    if pid and alive:
        try:
            os.killpg(os.getpgid(int(pid)), signal.SIGTERM)   # whole process group
        except Exception:
            try:
                os.kill(int(pid), signal.SIGTERM)
            except Exception:
                pass
    shutil.rmtree(LOCK_DIR, ignore_errors=True)
    _sh(["tmux", "kill-session", "-t", "loop"])


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = render().encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        p = self.path
        if p.startswith("/watch"):
            trigger_watch()
        elif p.startswith("/run"):
            trigger_cycle()
        elif p.startswith("/schedule-on"):
            schedule_on()
        elif p.startswith("/schedule-off"):
            schedule_off()
        elif p.startswith("/stop"):
            stop_cycle()
        # redirect back to the dashboard
        self.send_response(303)
        self.send_header("Location", "/")
        self.end_headers()

    def log_message(self, *a):
        pass  # quiet


if __name__ == "__main__":
    with socketserver.TCPServer(("127.0.0.1", PORT), Handler) as httpd:
        print("Loop dashboard → http://localhost:%d   (Ctrl+C to stop)" % PORT)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            pass
