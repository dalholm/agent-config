# pi/ — Pi-harness-tillägg

Allt som rör [Pi](https://pi.dev) lever här, versionerat i samma repo som resten av
min agent-config. Just nu: [`pi-hermes-memory`](https://pi.dev/packages/pi-hermes-memory)
— persistent minne, sessionssök och secret-scanning.

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
# 1. wira in config-symlänken (idempotent, säkerhetskopierar befintligt)
../install.sh

# 2. installera själva extensionen i Pi
pi install npm:pi-hermes-memory

# 3. (engång) indexera tidigare sessioner för sök
/memory-index-sessions
```

## Om du flyttar repot

`memoryDir`/`projectsMemoryDir` i configen är hårdkodade till
`~/develop/software/agent-config/pi/memory`. Flyttar du repot — ändra de två raderna.
