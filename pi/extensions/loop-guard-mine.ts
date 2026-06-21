// loop-guard-mine.ts — vår egen loop-vakt för pi, i en enda fil vi kontrollerar.
//
// Bygger på idéerna i @isr4el-silv4/loop-guard (MIT) men är omskriven och
// konsoliderad så att vi äger och förstår varje rad. Kreditrad enligt MIT nedan.
//   Original: https://github.com/isr4el-silv4/loop-guard  © isr4el-silv4, MIT
//
// Vad den fångar:
//   • Tool-loopar    — samma verktyg + identiska argument (exact), liknande
//                      argument (fuzzy, Jaccard), eller cykler (read→edit→read→edit).
//   • Result-stagnation — samma verktyg returnerar samma resultat om och om igen.
//   • Thinking-loopar — repetitivt resonemang, både live under streaming
//                      (consecutive + density) och efter färdigt svar (n-gram).
//
// Hur den ingriper — progressiv eskalering istället för en hård knapp:
//   hint  → injicerar en knuff i system-prompten
//   block → blockerar tool-anropet med en stark korrigering
//   terminate → stoppar agenten helt tills du kör /loopguard reset
//
// Testa:   pi -e ./loop-guard-mine.ts
// Styr:    /loopguard reset   |   /loopguard config

import type {
  ExtensionAPI,
  ExtensionContext,
  ExtensionCommandContext,
} from "@earendil-works/pi-coding-agent";

// ─────────────────────────────────────────────────────────────────────────
// Inställningar — ändra fritt, eller justera live med /loopguard config
// ─────────────────────────────────────────────────────────────────────────
interface Config {
  // Tool-loopar
  toolCallWindow: number;
  exactRepeatThreshold: number;
  fuzzySimilarityThreshold: number;
  cycleLength: number;
  cycleRepetitions: number;
  cycleSimilarityThreshold: number;
  // Result-stagnation
  resultStagnationThreshold: number;
  // Thinking — streaming
  consecutiveThreshold: number;
  densityThreshold: number;
  densityWindow: number;
  lineSimilarityThreshold: number;
  maxBufferSize: number;
  escalationTurns: number;
  // Safety net: fångar block av rader som cyklar (A,B,C,A,B,C…) där varken
  // consecutive eller density slår till. Räknar hur ofta varje rad återkommer
  // i HELA meddelandet — flaggar om någon rad återkommer för många gånger.
  lineRepeatThreshold: number;
  lineRepeatMinLength: number;
  // Thinking — post-hoc
  thinkingWindow: number;
  thinkingSimilarityThreshold: number;
  thinkingMinLength: number;
  // Eskalering
  hintAfter: number;
  blockAfter: number;
  blockBeforeTerminate: number;
  // Övrigt
  ignoredTools: string[];
}

const CONFIG: Config = {
  toolCallWindow: 5,
  exactRepeatThreshold: 4,
  fuzzySimilarityThreshold: 0.85,
  cycleLength: 4,
  cycleRepetitions: 2,
  cycleSimilarityThreshold: 0.7,
  resultStagnationThreshold: 3,
  consecutiveThreshold: 4,
  densityThreshold: 0.75,
  densityWindow: 100,
  lineSimilarityThreshold: 0.85,
  maxBufferSize: 10240,
  escalationTurns: 2,
  lineRepeatThreshold: 4,
  lineRepeatMinLength: 40,
  thinkingWindow: 3,
  thinkingSimilarityThreshold: 0.8,
  thinkingMinLength: 100,
  hintAfter: 1,
  blockAfter: 2,
  blockBeforeTerminate: 3,
  ignoredTools: ["edit"],
};

// ─────────────────────────────────────────────────────────────────────────
// Likhetsmått (noll beroenden)
// ─────────────────────────────────────────────────────────────────────────

// Jaccard på ordnivå — för att jämföra serialiserade tool-argument.
function jaccard(a: string, b: string): number {
  const A = new Set(a.toLowerCase().split(/\s+/).filter(Boolean));
  const B = new Set(b.toLowerCase().split(/\s+/).filter(Boolean));
  if (A.size === 0 && B.size === 0) return 1;
  if (A.size === 0 || B.size === 0) return 0;
  let inter = 0;
  for (const t of A) if (B.has(t)) inter++;
  return inter / new Set([...A, ...B]).size;
}

// N-gram på teckennivå — för att jämföra tankeblock/textrader.
function ngram(a: string, b: string, n = 2): number {
  const grams = (s: string) => {
    const t = s.toLowerCase().replace(/\s+/g, " ").trim();
    const g = new Set<string>();
    for (let i = 0; i + n <= t.length; i++) g.add(t.slice(i, i + n));
    return g;
  };
  const A = grams(a);
  const B = grams(b);
  if (A.size === 0 && B.size === 0) return 1;
  if (A.size === 0 || B.size === 0) return 0;
  let inter = 0;
  for (const x of A) if (B.has(x)) inter++;
  return inter / new Set([...A, ...B]).size;
}

// ─────────────────────────────────────────────────────────────────────────
// Detektionsresultat
// ─────────────────────────────────────────────────────────────────────────
interface Detection {
  kind: "exact" | "fuzzy" | "cycle" | "result_stagnation" | "thinking";
  details: string;
}

// ─────────────────────────────────────────────────────────────────────────
// Tool-tracker: exact / fuzzy / cycle
// ─────────────────────────────────────────────────────────────────────────
interface Sig {
  tool: string;
  hash: string;
  args: Record<string, unknown>;
}

class ToolTracker {
  private recent: Sig[] = [];
  private seq: Sig[] = [];
  constructor(private c: Config) {}

  reset() {
    this.recent = [];
    this.seq = [];
  }

  check(tool: string, args: Record<string, unknown>): Detection | null {
    const sig = this.makeSig(tool, args);
    return (
      this.exact(sig) ?? this.fuzzy(sig) ?? this.cycle(sig) ?? this.record(sig)
    );
  }

  private record(sig: Sig): null {
    this.recent.push(sig);
    if (this.recent.length > this.c.toolCallWindow)
      this.recent = this.recent.slice(-this.c.toolCallWindow);
    this.seq.push(sig);
    return null;
  }

  private makeSig(tool: string, args: Record<string, unknown>): Sig {
    return { tool, hash: JSON.stringify(sortKeys(args)), args };
  }

  private exact(sig: Sig): Detection | null {
    const w = this.recent.slice(-this.c.toolCallWindow);
    let count = 0;
    for (let i = w.length - 1; i >= 0; i--) {
      if (w[i].tool === sig.tool && w[i].hash === sig.hash) count++;
      else break;
    }
    if (count >= this.c.exactRepeatThreshold)
      return {
        kind: "exact",
        details: `"${sig.tool}" anropat ${count} ggr i rad med identiska argument.`,
      };
    return null;
  }

  private fuzzy(sig: Sig): Detection | null {
    const w = this.recent.slice(-this.c.toolCallWindow);
    for (let i = w.length - 1; i >= 0; i--) {
      const r = w[i];
      if (r.tool !== sig.tool || r.hash === sig.hash) continue;
      const sim = jaccard(argsToTokens(r.args), argsToTokens(sig.args));
      if (sim >= this.c.fuzzySimilarityThreshold)
        return {
          kind: "fuzzy",
          details: `"${sig.tool}" anropat med liknande argument (likhet ${sim.toFixed(2)}).`,
        };
    }
    return null;
  }

  private cycle(sig: Sig): Detection | null {
    const needed = this.c.cycleLength * this.c.cycleRepetitions;
    const seq = [...this.seq, sig];
    if (seq.length < needed) return null;
    const tail = seq.slice(-needed);
    const names = tail.map((s) => s.tool);
    const pattern = names.slice(0, this.c.cycleLength);

    // Steg 1: matchar verktygsnamnen ett upprepat mönster?
    for (let rep = 1; rep < this.c.cycleRepetitions; rep++)
      for (let i = 0; i < this.c.cycleLength; i++)
        if (names[rep * this.c.cycleLength + i] !== pattern[i]) return null;

    // Steg 2: bekräfta med argumentlikhet (om aktiverat) — annars utforskar agenten.
    if (this.c.cycleSimilarityThreshold > 0)
      for (let pos = 0; pos < this.c.cycleLength; pos++)
        for (let rep = 1; rep < this.c.cycleRepetitions; rep++) {
          const sim = jaccard(
            argsToTokens(tail[pos].args),
            argsToTokens(tail[rep * this.c.cycleLength + pos].args),
          );
          if (sim < this.c.cycleSimilarityThreshold) return null;
        }

    return {
      kind: "cycle",
      details: `cykel [${pattern.join(" → ")}] upprepad ${this.c.cycleRepetitions} ggr.`,
    };
  }
}

function sortKeys(obj: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const k of Object.keys(obj).sort()) {
    const v = obj[k];
    out[k] =
      v && typeof v === "object" && !Array.isArray(v)
        ? sortKeys(v as Record<string, unknown>)
        : v;
  }
  return out;
}

function argsToTokens(args: Record<string, unknown>): string {
  const parts: string[] = [];
  for (const [k, v] of Object.entries(args).sort((a, b) => a[0].localeCompare(b[0])))
    parts.push(k, String(v));
  return parts.join(" ");
}

// ─────────────────────────────────────────────────────────────────────────
// Result-tracker: samma verktyg returnerar samma resultat om och om igen
// ─────────────────────────────────────────────────────────────────────────
class ResultTracker {
  private byTool = new Map<string, string[]>();
  constructor(private c: Config) {}

  reset() {
    this.byTool = new Map();
  }

  check(tool: string, text: string): Detection | null {
    const norm = text.trim().replace(/\s+/g, " ").slice(0, 500);
    const results = this.byTool.get(tool) ?? [];
    let count = 0;
    for (let i = results.length - 1; i >= 0; i--) {
      if (results[i] === norm) count++;
      else break;
    }
    results.push(norm);
    if (results.length > this.c.resultStagnationThreshold)
      results.splice(0, results.length - this.c.resultStagnationThreshold);
    this.byTool.set(tool, results);

    if (count >= this.c.resultStagnationThreshold - 1)
      return {
        kind: "result_stagnation",
        details: `"${tool}" gav samma resultat ${count + 1} ggr i rad.`,
      };
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Thinking-tracker: live streaming-detektion + post-hoc kontroll
// ─────────────────────────────────────────────────────────────────────────
class ThinkingTracker {
  // per meddelande
  private buf = "";
  private lines: string[] = [];
  private consec = 0;
  private last = "";
  private firedThisMsg = false;
  private freq = new Map<number, number>();
  private nextGroup = 0;
  private groups: number[] = [];
  private lineCounts = new Map<string, number>(); // hela meddelandet, för blockcykler
  // per prompt
  private promptLoops = 0;
  private aborted = false;
  // post-hoc
  private recentThoughts: string[] = [];

  constructor(private c: Config) {}

  reset() {
    this.resetMessage();
    this.promptLoops = 0;
    this.aborted = false;
    this.recentThoughts = [];
  }

  resetMessage() {
    this.buf = "";
    this.lines = [];
    this.consec = 0;
    this.last = "";
    this.firedThisMsg = false;
    this.freq = new Map();
    this.nextGroup = 0;
    this.groups = [];
    this.lineCounts = new Map();
  }

  onChunk(delta: string, ctx: ExtensionContext) {
    if (this.aborted) return;
    this.buf += delta;
    if (this.buf.length > this.c.maxBufferSize) {
      if (this.buf.trim()) this.processLine(this.buf.trim(), ctx);
      this.buf = "";
      this.freq = new Map();
      this.nextGroup = 0;
      this.groups = [];
      return;
    }
    while (this.buf.includes("\n")) {
      const i = this.buf.indexOf("\n");
      const line = this.buf.slice(0, i).trim();
      this.buf = this.buf.slice(i + 1);
      if (line) this.processLine(line, ctx);
      if (this.aborted) break;
    }
  }

  onThinkingEnd(ctx: ExtensionContext) {
    if (this.aborted) return;
    if (this.buf.trim()) this.processLine(this.buf.trim(), ctx);
    this.buf = "";
  }

  private similar(a: string, b: string): boolean {
    return a === b || ngram(a, b) >= this.c.lineSimilarityThreshold;
  }

  private processLine(line: string, ctx: ExtensionContext) {
    // consecutive
    this.consec = this.similar(line, this.last) ? this.consec + 1 : 1;
    this.last = line;
    // sliding window
    this.lines.push(line);
    if (this.lines.length > this.c.densityWindow) this.lines.shift();
    this.assignGroup(line);
    // safety net: räkna återkommande rader över hela meddelandet (blockcykler)
    let blockHit = false;
    if (line.length >= this.c.lineRepeatMinLength) {
      const n = (this.lineCounts.get(line) ?? 0) + 1;
      this.lineCounts.set(line, n);
      blockHit = n >= this.c.lineRepeatThreshold;
    }
    // triggers
    const consecHit = this.consec >= this.c.consecutiveThreshold;
    const densHit =
      this.lines.length >= 5 && this.density() >= this.c.densityThreshold;
    if (consecHit || densHit || blockHit) this.onLoop(ctx);
  }

  private assignGroup(line: string) {
    let found: number | null = null;
    for (const [gid] of this.freq) {
      const idx = this.groups.indexOf(gid);
      if (idx !== -1 && this.similar(line, this.lines[idx])) {
        found = gid;
        break;
      }
    }
    if (found !== null) {
      this.freq.set(found, (this.freq.get(found) ?? 0) + 1);
      this.groups.push(found);
    } else {
      const id = this.nextGroup++;
      this.freq.set(id, 1);
      this.groups.push(id);
    }
    while (this.groups.length > this.c.densityWindow) {
      const removed = this.groups.shift()!;
      const n = this.freq.get(removed) ?? 1;
      if (n <= 1) this.freq.delete(removed);
      else this.freq.set(removed, n - 1);
    }
  }

  private density(): number {
    if (this.lines.length === 0) return 0;
    let max = 0;
    for (const n of this.freq.values()) if (n > max) max = n;
    return max / this.lines.length;
  }

  // Streaming-loop hanteras direkt här (varna en gång, abort andra gången).
  private onLoop(ctx: ExtensionContext) {
    if (this.firedThisMsg) return;
    this.firedThisMsg = true;
    this.promptLoops++;
    if (this.promptLoops >= this.c.escalationTurns) {
      this.aborted = true;
      ctx.ui.notify(
        `loop-guard: ihållande tanke-loop (${this.promptLoops}/${this.c.escalationTurns}), avbryter`,
        "error",
      );
      ctx.abort();
    } else {
      ctx.ui.notify(
        `loop-guard: repetitivt resonemang (${this.promptLoops}/${this.c.escalationTurns})`,
        "warning",
      );
    }
  }

  // Post-hoc: jämför hela tankeblock mot de senaste.
  checkPostHoc(thought: string): Detection | null {
    const norm = thought.trim().replace(/\s+/g, " ").slice(0, 2000);
    if (norm.length < this.c.thinkingMinLength) return null;
    const win = this.recentThoughts.slice(-this.c.thinkingWindow);
    let count = 0;
    let lastSim = 0;
    for (let i = win.length - 1; i >= 0; i--) {
      const sim = ngram(win[i], norm, 2);
      if (sim >= this.c.thinkingSimilarityThreshold) {
        count++;
        lastSim = sim;
      } else break;
    }
    this.recentThoughts.push(norm);
    if (this.recentThoughts.length > this.c.thinkingWindow)
      this.recentThoughts = this.recentThoughts.slice(-this.c.thinkingWindow);
    if (count >= 1)
      return {
        kind: "thinking",
        details: `${count} liknande tankeblock i följd (likhet ${lastSim.toFixed(2)}).`,
      };
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Eskalering: hint → block → terminate
// ─────────────────────────────────────────────────────────────────────────
type Action =
  | { level: "none" }
  | { level: "hint"; message: string }
  | { level: "block"; reason: string }
  | { level: "terminate"; reason: string };

const HINT_1 =
  "⚠ Loop upptäckt: du verkar upprepa samma handling eller resonemang. " +
  "Prova ett annat angreppssätt — vad saknar du för information, eller vilket annat verktyg skulle hjälpa?";
const HINT_2 =
  "⚠ Loop upptäckt igen: du upprepar samma mönster. Stoppa nuvarande väg, " +
  "sammanfatta vad som redan gjorts och välj ett tydligt annorlunda nästa steg. Har du nog för att svara — gör det nu.";
const BLOCK_MSG =
  "🚫 Blockerad: upprepad loop utan framsteg. Du måste prova ett fundamentalt annat angreppssätt eller avsluta med det du har.";

class Escalation {
  private count = 0;
  constructor(private c: Config) {}
  reset() {
    this.count = 0;
  }
  record(): Action {
    this.count++;
    if (this.shouldTerminate())
      return {
        level: "terminate",
        reason: `🛑 Agenten stoppad: ihållande loopande efter ${this.count} försök. Kör /loopguard reset för att fortsätta.`,
      };
    if (this.count >= this.c.blockAfter) return { level: "block", reason: BLOCK_MSG };
    if (this.count >= this.c.hintAfter)
      return {
        level: "hint",
        message: this.count >= this.c.hintAfter + 1 ? HINT_2 : HINT_1,
      };
    return { level: "none" };
  }
  hint(): string | null {
    if (this.count < this.c.hintAfter) return null;
    if (this.count >= this.c.blockAfter) return BLOCK_MSG;
    return this.count >= this.c.hintAfter + 1 ? HINT_2 : HINT_1;
  }
  shouldTerminate(): boolean {
    return this.count > this.c.blockAfter + this.c.blockBeforeTerminate - 1;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Extension-ingång: koppla pi:s events till våra trackers
// ─────────────────────────────────────────────────────────────────────────
export default function (pi: ExtensionAPI) {
  // Autonomy escape hatch: the headless loop sets LOOP_GUARD_OFF=1 so legitimate large
  // builds (which compile/test many times) aren't mistaken for a loop and hard-terminated
  // with no interactive session to run `/loopguard reset`. The loop has its own guards
  // instead (oracle gate + run-loop.sh wall-clock timeout + 3-strike resume cap). This
  // only disables loop-guard for those runs; interactive pi keeps it fully active.
  if (process.env.LOOP_GUARD_OFF === "1") {
    return;
  }

  const tool = new ToolTracker(CONFIG);
  const result = new ResultTracker(CONFIG);
  const thinking = new ThinkingTracker(CONFIG);
  const esc = new Escalation(CONFIG);

  const resetAll = () => {
    tool.reset();
    result.reset();
    thinking.reset();
    esc.reset();
  };

  const handle = (d: Detection, ctx: ExtensionContext) => {
    const a = esc.record();
    if (a.level === "hint") ctx.ui.notify(`loop-guard: ${a.message}`, "warning");
    else if (a.level !== "none") ctx.ui.notify(`loop-guard: ${a.reason}`, "error");
  };

  pi.on("session_start", async (_e: unknown, ctx: ExtensionContext) => {
    resetAll();
    ctx.ui.notify("loop-guard (egen): aktiv", "info");
  });

  pi.on("agent_start", async () => thinking.reset());

  pi.on("message_start", async (e: { message: any }) => {
    if (e.message?.role === "assistant") thinking.resetMessage();
  });

  // Live streaming-detektion av tankar.
  pi.on("message_update", async (e: any, ctx: ExtensionContext) => {
    const ev = e?.assistantMessageEvent;
    if (!ev) return;
    if (ev.type === "thinking_delta") thinking.onChunk(ev.delta ?? "", ctx);
    if (ev.type === "thinking_end") thinking.onThinkingEnd(ctx);
  });

  // Injicera knuff i system-prompten när eskaleringen säger det.
  pi.on("before_agent_start", async (e: { systemPrompt: string }) => {
    const hint = esc.hint();
    if (hint) return { systemPrompt: e.systemPrompt + "\n\n" + hint };
  });

  // Tool-loopar + terminering.
  pi.on(
    "tool_call",
    async (e: { toolName: string; input: Record<string, unknown> }, ctx: ExtensionContext) => {
      if (CONFIG.ignoredTools.includes(e.toolName)) return;
      if (esc.shouldTerminate())
        return {
          block: true,
          reason: "loop-guard: agenten stoppad pga ihållande loopande. Kör /loopguard reset.",
        };
      const d = tool.check(e.toolName, e.input);
      if (d) {
        handle(d, ctx);
        if (esc.shouldTerminate())
          return { block: true, reason: "loop-guard: terminerad." };
        const hint = esc.hint();
        if (hint && esc.record().level === "block")
          return { block: true, reason: hint };
      }
    },
  );

  // Result-stagnation.
  pi.on(
    "tool_result",
    async (e: { toolName: string; content: unknown }, ctx: ExtensionContext) => {
      if (CONFIG.ignoredTools.includes(e.toolName)) return;
      const d = result.check(e.toolName, extractResultText(e.content));
      if (d) handle(d, ctx);
    },
  );

  // Post-hoc tankeanalys på färdigt svar.
  pi.on("message_end", async (e: { message: any }, ctx: ExtensionContext) => {
    if (e.message?.role !== "assistant") return;
    const t = extractThinking(e.message);
    if (t) {
      const d = thinking.checkPostHoc(t);
      if (d) handle(d, ctx);
    }
  });

  // Kommandon: /loopguard reset | config
  pi.registerCommand("loopguard", {
    description: "Styr loop-guard: reset eller config",
    handler: async (args: string, ctx: ExtensionCommandContext) => {
      const a = args.trim().toLowerCase();
      if (a === "reset") {
        resetAll();
        ctx.ui.notify("loop-guard: nollställd — agenten kan fortsätta.", "info");
        return;
      }
      // Enkel config-meny: välj fält, skriv nytt värde.
      const keys = Object.keys(CONFIG) as (keyof Config)[];
      const choices = keys.map((k) => `${k} (${String(CONFIG[k])})`);
      const picked = await ctx.ui.select("loop-guard: välj inställning", choices);
      if (picked == null) return;
      const key = keys[choices.indexOf(picked)];
      const val = await ctx.ui.input(`Nytt värde för ${key}`, String(CONFIG[key]));
      if (val == null) return;
      if (key === "ignoredTools") {
        (CONFIG as any)[key] = val.trim() === "" ? [] : val.split(",").map((s) => s.trim());
      } else {
        const n = Number(val);
        if (!Number.isFinite(n)) {
          ctx.ui.notify(`Ogiltigt värde för ${key}`, "error");
          return;
        }
        (CONFIG as any)[key] = n;
      }
      ctx.ui.notify(`loop-guard: ${key} = ${String(CONFIG[key])}`, "info");
    },
  });
}

// ── Hjälpare för att plocka ut text ur pi:s meddelandeformat ──
function extractResultText(content: unknown): string {
  if (Array.isArray(content))
    return content
      .filter((c: any) => c && typeof c === "object" && c.type === "text")
      .map((c: any) => c.text ?? "")
      .join("\n");
  return typeof content === "string" ? content : String(content);
}

function extractThinking(message: any): string | null {
  const content = message?.content;
  if (!Array.isArray(content)) return null;
  const block = content.find((c: any) => c && typeof c === "object" && c.type === "thinking");
  if (block) {
    const t = block.text ?? block.thinking;
    return typeof t === "string" ? t : null;
  }
  for (const b of content)
    if (b && typeof b === "object" && b.type === "text" && typeof b.text === "string") {
      const m = b.text.match(/```thinking\s*([\s\S]*?)```/);
      if (m) return m[1].trim();
    }
  return null;
}
