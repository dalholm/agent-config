# pi/ — Pi-harness-tillägg

Allt som rör [Pi](https://pi.dev) lever här, versionerat i samma repo som resten av
min agent-config:

- `models.json` — lokala providers (LM Studio). Det här är vad som gör att Pi har
  modeller att välja på utan `/login`.
- [`pi-hermes-memory`](https://pi.dev/packages/pi-hermes-memory) — persistent minne,
  sessionssök och secret-scanning (`hermes-memory-config.json` + `memory/`).
- **Extensions** (installeras av `install.sh`, se `PI_PACKAGES` där). Valda för att
  aktivera AGENTS.md-filosofin utan att duplicera router/controller-flödet:
  - `pi-subagents` — task-delegering med model-tiers (AGENTS.md §4).
  - `pi-lens` — realtids-LSP/linter/formatter (TDD-grinden, §2).
  - `pi-simplify` — code review för klarhet/underhållbarhet (self-review-grinden).
  - `pi-lean-ctx` — token-effektiv bash/read/grep-routing; viktigast för lokal körning.
  - `pi-web-access` — web search + URL/PDF fetch (för `deep-research`).
  - `pi-mcp-adapter` — MCP-brygga.
  - `pi-goal` — goal-driven completion (stödjer `goal-watcher`, §3).
  - `pi-ask-user` — strukturerade frågor (human-gate / `preference-oracle`).
  - `pi-retry` — retry-hantering; lokala LM Studio-servrar kan timeouta.
  - `pi-handoff-rebase` — context-komprimering vid handoff (snäv lokal context).

## Modeller (models.json)

Pi läser lokala/custom-providers från `~/.pi/agent/models.json` (separat från
subscriptions via `/login`). Min config speglar opencode-providern: LM Studio på
`http://127.0.0.1:1234/v1`, API-typ `openai-completions`, tre modeller.

- `apiKey` är "lmstudio" — LM Studio ignorerar värdet men fältet krävs.
- `compat.supportsDeveloperRole: false` + `supportsReasoningEffort: false` är säkra
  defaults för lokala OpenAI-kompatibla servrar.
- **Reasoning är av.** Vill du slå på thinking för Qwen/DeepSeek lokalt: sätt
  `"reasoning": true` på modellen och oftast `compat.thinkingFormat`
  (`"qwen-chat-template"` för lokala Qwen). Se
  [models.md](https://pi.dev/docs/latest/models).

Filen laddas om varje gång du öppnar `/model` — ingen omstart behövs. Starta LM Studio
och dess server (port 1234), kör `pi`, välj modell med `/model`.

> Bakgrundsjobben i hermes-memory (review/consolidation) är pekade mot
> `lmstudio/huihui-deepseek-v4-flash-abliterated-ds4` via `llmModelOverride`, så de
> kör på den snabba lokala modellen med thinking av.

## Hur det kopplas

Två mekanismer, en för varje sorts fil:

- **Config-filen** ligger på en fast sökväg (`~/.pi/agent/hermes-memory-config.json`)
  och **symlänkas** ut från `pi/hermes-memory-config.json` av `install.sh` — samma
  mönster som `AGENTS.md`. Redigera filen i repot = den är live.
- **Datan** (MEMORY.md, USER.md, skills/, projects-memory/) styrs av `memoryDir` /
  `projectsMemoryDir` i configen, som pekar in i `pi/memory/`. Ingen per-fil-symlänk
  behövs för en katalog extensionen skriver till konstant.

## Vad som versioneras

| Fil | I git? | Varför |
|-----|--------|--------|
| `models.json` | ✅ | Lokala providers (LM Studio) — sanningskälla, symlänkas ut |
| `hermes-memory-config.json` | ✅ | Config — sanningskälla, som AGENTS.md |
| `memory/USER.md` | ✅ | Min profil, stabil och kurerad |
| `memory/MEMORY.md` | ✅ | Agentens anteckningar (brusig historik — auto-skrivs var 10:e tur) |
| `memory/skills/**/SKILL.md` | ✅ | Procedurer agenten sparar |
| `memory/projects-memory/**` | ✅ | Projekt-scopat minne |
| `memory/sessions.db` (+ `-wal`/`-shm`) | ❌ gitignoreas | Binär, växande, rå konversationshistorik |

> OBS: Pi-hermes skills (`memory/skills/`) är ett **separat** skill-system från
> Claude Code-skills i `../skills/`. install.sh symlänkar `../skills/*` till
> `~/.claude/skills/`; Pi-skills hanteras av extensionen i `memoryDir`.

## Installera

```sh
# 1. wira in config-symlänkar OCH installera alla Pi-extensions, idempotent
#    (hermes-memory + PI_PACKAGES-listan: subagents, lens, lean-ctx, web-access,
#     goal, ask-user, simplify, mcp-adapter, retry, handoff-rebase)
../install.sh

# 2. starta LM Studio + servern (port 1234), kör 'pi', välj modell med /model

# 3. (engång) indexera tidigare sessioner för sök
/memory-index-sessions
```

## Om du flyttar repot

`memoryDir`/`projectsMemoryDir` i configen är hårdkodade till
`~/develop/software/agent-config/pi/memory`. Flyttar du repot — ändra de två raderna.
