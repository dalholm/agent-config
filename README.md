# agent-setup

Mina globala instruktioner för AI-kodningsagenter. Styr **hur mycket** av
[Superpowers](https://github.com/obra/superpowers) som ska aktiveras per uppgift, så
att småfix går snabbt och billigt medan stora jobb får full disciplin.

## Idén

En **router** klassar uppgiftens komplexitet *innan* något körs och väljer spår
(T0 trivialt → T3 full Superpowers). En **kontrollant** eskalerar spåret om jobbet
visar sig växa. Ceremonin (brainstorm/spec/plan/subagenter) skalas; kvalitetsgrindarna
(framför allt TDD) behålls. Allt ligger **ovanpå** Superpowers och vinner via prioritet:
**mina instruktioner > Superpowers-skills > systemprompt.**

## En sanningskälla

`AGENTS.md` är hela innehållet. Alla harness pekas mot den:

| Harness | Global fil | Kopplas till |
|---------|-----------|--------------|
| Claude Code | `~/.claude/CLAUDE.md` | symlink → `AGENTS.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` | symlink → `AGENTS.md` |
| Codex | `~/.codex/AGENTS.md` | symlink → `AGENTS.md` |

Eftersom en symlink behåller sitt eget filnamn får alla tre exakt samma innehåll. Du
redigerar bara `AGENTS.md`.

## Installera

```sh
./install.sh --dry-run   # se vad som händer, ändrar inget
./install.sh             # kör (befintliga filer säkerhetskopieras till .bak-<datum>)
```

Scriptet symlinkar instruktionsfilerna, lägger Claude Code-skillen i
`~/.claude/skills/`, och fogar in hooken i `~/.claude/settings.json` (kräver `jq`,
annars skrivs manuell instruktion ut). Starta om agenten efteråt.

## Innehåll

- `AGENTS.md` — sanningskälla (router + kontrollant + spår).
- `CLAUDE.md`, `GEMINI.md` — tunna pekare (`@./AGENTS.md`) för manuell kopiering om du
  inte vill symlinka.
- `skills/complexity-router/SKILL.md` — router som riktig Claude Code-skill.
- `hooks/router-reminder.sh` — UserPromptSubmit-hook, det deterministiska lagret som
  injicerar router-direktivet varje tur (bara Claude Code).
- `hooks/settings-snippet.json` — hook-config att klistra in manuellt vid behov.
- `install.sh` — symlink- och hook-installation.

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
