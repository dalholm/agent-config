# pi/ — Pi-harness-tillägg

Allt som rör [Pi](https://pi.dev) lever här, versionerat i samma repo som resten av
min agent-config:

- `models.json` — lokala providers (LM Studio). Det här är vad som gör att Pi har
  modeller att välja på utan `/login`.
- `models-routing.json` — handsorterad `task-class → lokal builder-modell` för loopen.
  Läses av `loop/claim-task.sh` vid claim (taggen `class:` i Auto Tasks.md); `run-loop.sh`
  kör modellen som hamnar i `.claim-model`. Medvetet **inte** självmodifierande — redigera
  för hand. Saknad fil/okänd klass → säker default (qwen-35b).
- [`pi-hermes-memory`](https://pi.dev/packages/pi-hermes-memory) — persistent minne,
  sessionssök och secret-scanning (`hermes-memory-config.json` + `memory/`).
- `extensions/loop-guard-mine.ts` — lokal loop-vakt som installerats med
  `pi install ./pi/extensions/loop-guard-mine.ts` av `install.sh`.
- **Extensions** (installeras av `install.sh`, se `PI_PACKAGES` där). Valda för att
  aktivera AGENTS.md-filosofin utan att duplicera router/controller-flödet:
  - `pi-subagents` — task-delegering med model-tiers (AGENTS.md §5).
  - `pi-lens` — realtids-LSP/linter/formatter (TDD-grinden, §2).
  - `pi-simplify` — code review för klarhet/underhållbarhet (self-review-grinden).
  - `pi-lean-ctx` — token-effektiv bash/read/grep-routing; viktigast för lokal körning.
  - `pi-web-access` — web search + URL/PDF fetch (för `deep-research`).
  - `pi-mcp-adapter` — MCP-brygga.
  - `pi-goal` — goal-driven completion (stödjer `goal-watcher`, §4).
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
  och **renderas** från `pi/hermes-memory-config.json` av `install.sh`. Template-filen
  använder `__REPO__`, så `memoryDir` och `projectsMemoryDir` pekar på den checkout där
  du kör installern. Redigera template-filen i repot och kör `../install.sh` igen.
- **Datan** (MEMORY.md, USER.md, skills/, projects-memory/) styrs av `memoryDir` /
  `projectsMemoryDir` i configen, som pekar in i `pi/memory/`. Ingen per-fil-symlänk
  behövs för en katalog extensionen skriver till konstant.

## Vad som versioneras

| Fil | I git? | Varför |
|-----|--------|--------|
| `models.json` | ✅ | Lokala providers (LM Studio) — sanningskälla, symlänkas ut |
| `hermes-memory-config.json` | ✅ | Config — sanningskälla, som AGENTS.md |
| `extensions/loop-guard-mine.ts` | ✅ | Lokal Pi-extension för loop-detektion |
| `memory/USER.md` | ✅ | Min profil, stabil och kurerad |
| `memory/MEMORY.md` | ✅ | Agentens anteckningar (brusig historik — auto-skrivs var 10:e tur) |
| `memory/skills/**/SKILL.md` | ✅ | Procedurer agenten sparar |
| `memory/projects-memory/**` | ✅ | Projekt-scopat minne |
| `memory/sessions.db` (+ `-wal`/`-shm`) | ❌ gitignoreas | Binär, växande, rå konversationshistorik |

> OBS: två sorters skills möts i Pi. `memory/skills/` är **hermes-memory**s egna
> (procedurer agenten sparar, i `memoryDir`). Repots `../skills/` (complexity-router,
> ponytail, goal-watcher, preference-oracle) registreras dessutom i Pi via `"skills"[]` i
> `~/.pi/agent/settings.json` — samma katalog Claude använder, ingen kopia — så de
> triggar i Pi precis som i Claude Code. `complexity-router` är den som avgör om/hur
> mycket en uppgift går genom Superpowers.

## Installera

```sh
# 1. wira in config-symlänkar OCH installera alla Pi-extensions, idempotent
#    (hermes-memory + PI_PACKAGES-listan + lokal loop-guard-extension)
../install.sh

# 2. starta LM Studio + servern (port 1234), kör 'pi', välj modell med /model

# 3. (engång) indexera tidigare sessioner för sök
/memory-index-sessions
```

## Om du flyttar repot

`memoryDir`/`projectsMemoryDir` renderas från `__REPO__` när `../install.sh` körs.
Flyttar du repot, kör installern igen från den nya platsen.
