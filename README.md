# agent-config

Mina globala instruktioner för AI-kodningsagenter. Styr **hur mycket** av
[Superpowers](https://github.com/obra/superpowers) som ska aktiveras per uppgift, så
att småfix går snabbt och billigt medan stora jobb får full disciplin.

## Idén

En **router** klassar uppgiftens komplexitet *innan* något körs och väljer spår
(T0 trivialt → T3 full Superpowers). En **kontrollant** eskalerar spåret om jobbet
visar sig växa. Ceremonin (brainstorm/spec/plan/subagenter) skalas; kvalitetsgrindarna
(framför allt TDD) behålls. Allt ligger **ovanpå** Superpowers och vinner via prioritet:
**mina instruktioner > Superpowers-skills > systemprompt.**

För **autonoma (T3) körningar** finns två roller som gör hands-off säkert:
**preference-oracle** svarar på återkommande lågrisk-frågor åt mig (utifrån
`preferences.md`) och eskalerar resten; **goal-watcher** vakar på att arbetet inte
driver från specen. Båda kör på stark modell; mekaniska implementer-subagenter kör
billigt. Se "Roller & modell-tiers" i `AGENTS.md`.

## En sanningskälla

`AGENTS.md` är hela innehållet. Alla harness pekas mot den:

| Harness | Global fil | Kopplas till |
|---------|-----------|--------------|
| Claude Code | `~/.claude/CLAUDE.md` | symlink → `AGENTS.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` | symlink → `AGENTS.md` |
| Codex | `~/.codex/AGENTS.md` | symlink → `AGENTS.md` |
| Pi | `~/.pi/agent/` | se `pi/` (instruktioner inline i `AGENTS.md` + hermes-memory) |

Eftersom en symlink behåller sitt eget filnamn får alla tre instruktionsfilerna exakt
samma innehåll. Du redigerar bara `AGENTS.md`. Pi-specifika tillägg (persistent minne)
lever i `pi/` — se `pi/README.md`.

## Installera

```sh
./install.sh --dry-run        # se vad som händer, ändrar inget
./install.sh                  # kör (befintliga filer säkerhetskopieras till .bak-<datum>)
./install.sh --no-bootstrap   # bara symlänkar/hook — installera inga externa verktyg
```

Scriptet symlinkar instruktionsfilerna, lägger Claude Code-skillen i
`~/.claude/skills/`, och fogar in hooken i `~/.claude/settings.json` (kräver `jq`,
annars skrivs manuell instruktion ut). Starta om agenten efteråt.

Det **bootstrappar** också verktygen configen förutsätter (om de saknas): installerar
Node/npm (via Homebrew), Pi (via `pi.dev/install.sh`) och pi-hermes-memory-extensionen.
Stäng av med `--no-bootstrap`.

**Superpowers** stödjer flera harness. Hur det installeras skiljer sig — scriptet kör
det som går att skripta och skriver ut resten:

| Harness | Hur | Skriptbart? |
|---------|-----|-------------|
| OpenCode | läggs i `plugin[]` i `opencode.jsonc` | ✅ scriptet mergar in det |
| Pi | `pi install git:github.com/obra/superpowers` | ✅ scriptet kör det (kräver Pi) |
| Claude Code | `/plugin`-slash i en session | ❌ scriptet skriver ut raderna |
| Codex CLI | `/plugins`-slash i en session | ❌ scriptet skriver ut steget |

```
# Claude (i en Claude Code-session):
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace
# Codex (i en Codex CLI-session):
/plugins   # sök "superpowers" -> Install
```

Pi har dessutom sitt *eget* skill-system (pi-hermes), skilt från Superpowers — se `pi/`.

### Auto-godkänn (agenterna agerar utan att fråga)

Scriptet sätter också "fråga aldrig"-läge i varje harness (mergas in i respektive
config — kan inte symlänkas eftersom filerna håller maskin-state som tema/auth):

| Harness | Fil | Nyckel |
|---------|-----|--------|
| Claude Code | `~/.claude/settings.json` | `permissions.defaultMode = "bypassPermissions"` |
| Codex | `~/.codex/config.toml` | `approval_policy = "never"` + `sandbox_mode = "danger-full-access"` |
| OpenCode | `~/.config/opencode/opencode.jsonc` | `permission.{edit,bash,webfetch} = "allow"` |
| Pi | `~/.pi/agent/settings.json` | `defaultProjectTrust = "always"` |

> ⚠️ Detta tar bort bekräftelse-grindarna helt — agenterna kör shell, redigerar filer
> och hämtar nät utan att fråga. Avsett för en betrodd, personlig maskin. Ångra genom
> att sätta tillbaka `default`/`ask`/`on-request` i respektive fil.

## Innehåll

- `AGENTS.md` — sanningskälla (router + kontrollant + autonomt läge + roller/modell-tiers).
- `CLAUDE.md`, `GEMINI.md` — tunna pekare (`@./AGENTS.md`) för manuell kopiering om du
  inte vill symlinka.
- `preferences.md` — mina stående preferenser; preference-oracle svarar utifrån denna. Fyll i den.
- `skills/complexity-router/SKILL.md` — router som riktig Claude Code-skill.
- `skills/goal-watcher/SKILL.md` — drift-väktare för autonoma körningar.
- `skills/preference-oracle/SKILL.md` — svarar på lågrisk-frågor åt mig, eskalerar resten.
- `hooks/router-reminder.sh` — UserPromptSubmit-hook, det deterministiska lagret som
  injicerar router-direktivet varje tur (bara Claude Code).
- `hooks/settings-snippet.json` — hook-config att klistra in manuellt vid behov.
- `install.sh` — symlinkar instruktionsfiler + alla skills, hooken, samt Pi-configen;
  bootstrappar Node/Pi/hermes-extensionen om de saknas och pekar ut Superpowers-installen.
- `pi/` — Pi-harness-tillägg. `hermes-memory-config.json` (symlänkas ut) + `memory/`
  (persistent minne, skills, sessionssök; `memoryDir` pekar hit). Se `pi/README.md`.

## Lager av styrka

1. **AGENTS.md** (portabelt) — funkar i alla harness, sanktionerad override via prioritet.
2. **complexity-router-skill** (Claude Code) — triggar automatiskt via sin description.
3. **hook** (Claude Code) — deterministiskt, beror inte på att modellen minns något.

För Codex/Gemini lever router-logiken inline i `AGENTS.md`. Skill och hook är
Claude-Code-specifika tillägg.

## Brasklapp

Det här är instruktionsföljande, inte en mekanisk spärr. På kapabla modeller håller
prioritetsregeln bra; svaga lokala modeller följer varken detta eller Superpowers
disciplin pålitligt. Hooken är det enda riktigt deterministiska lagret.
