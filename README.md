# agent-config

Mina globala instruktioner och skills för AI-kodningsagenter. Styr hur mycket process
varje uppgift behöver, så att småfix går snabbt och billigt medan stora jobb får full
disciplin.

## Idén

En **router** klassar uppgiftens komplexitet *innan* något körs och väljer spår
(T0 trivialt → T3 fullt arbetsflöde). En **kontrollant** eskalerar spåret om jobbet
visar sig växa. Ceremonin (design/spec/plan/subagenter) skalas; kvalitetsgrindarna
(framför allt TDD) behålls. Repoets skills är en meny som routern väljer från, inte en
fast pipeline. Prioriteten är:
**uttrycklig användarinstruktion > AGENTS.md > relevanta skills > systemstandard.**

För **autonoma (T3) körningar** finns två roller som gör hands-off säkert:
**preference-oracle** svarar på återkommande lågrisk-frågor åt mig (utifrån
`preferences.md`) och eskalerar resten; **goal-watcher** vakar på att arbetet inte
driver från specen. Agenternas arbetsroll (`coder`, `researcher`, `designer` osv.) och
kapacitetsnivå (`fast`, `standard`, `deep`) routas separat till modeller för respektive
harness. Se "Provider-independent agent routing" i `AGENTS.md`.

## En sanningskälla

`AGENTS.md` är hela innehållet. Alla harness pekas mot den:

| Harness | Global fil | Kopplas till |
|---------|-----------|--------------|
| Claude Code | `~/.claude/CLAUDE.md` | symlink → `AGENTS.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` | symlink → `AGENTS.md` |
| Codex | `~/.codex/AGENTS.md` | symlink → `AGENTS.md` |
| OpenCode | `~/.config/opencode/AGENTS.md` | symlink → `AGENTS.md` |
| Pi | `~/.pi/agent/AGENTS.md` | symlink → `AGENTS.md` |

Eftersom en symlink behåller sitt eget filnamn får alla instruktionsfiler samma
innehåll. Du redigerar bara `AGENTS.md`. Pi-specifika extensions, skills, teman och
lokala modeller lever i `pi/` — se `pi/README.md`.

## Installera

```sh
./install.sh --dry-run        # se vad som händer, ändrar inget
./install.sh                  # kör (befintliga filer säkerhetskopieras till .bak-<datum>)
./install.sh --no-bootstrap   # bara symlänkar/hook — installera inga externa verktyg
./install.sh --safe-profile   # behåll prompts/sandboxing i stället för auto-godkänn
```

Scriptet symlinkar instruktionsfilerna, lägger skills i `~/.claude/skills/` och
`~/.codex/skills/`, fogar in hooken i `~/.claude/settings.json` (kräver `jq`,
annars skrivs manuell instruktion ut), och länkar den repoägda Pi-konfigurationen till
`~/.pi/agent/`. Det länkar också `model-routing.json` till
`~/.config/agent-config/` och installerar kommandot `agent-model-route` i
`~/.local/bin/`. Starta om agenten efteråt.

Det **bootstrappar** också verktygen configen förutsätter (om de saknas): installerar
Node/npm (via Homebrew), Pi (via `pi.dev/install.sh`) och Node-beroendena för våra
Pi-extensions. Stäng av med `--no-bootstrap`.

## Avinstallera

```sh
./uninstall.sh --dry-run              # se vad som skulle tas bort
./uninstall.sh                    # ta bort repo-kopplingar
./uninstall.sh --keep-permissions # lämna approval/sandbox-inställningar orörda
```

Avinstallern är konservativ: den tar bort symlänkar/config-rader som pekar på detta
repo och återställer permissiva agentinställningar till säkrare defaults. Den raderar
inte repot, Pi-autentisering, sessionshistorik, backupfiler eller externa verktyg som
Node/Pi.

Repoet innehåller fokuserade skills för bland annat TDD, implementation, diagnostik,
prototyper, grillning, domänmodellering, PRD:er, issues, review och QA. Installern
symlinkar samma skills till Claude Code och Codex; Pi registrerar samma katalog.

Pi har dessutom sitt eget extension- och minnessystem — se `pi/`.

### Permissions-profiler

Default är **auto-approve**: agenterna agerar utan att fråga. För okända repos eller
lägen där du vill ha prompts/sandboxing, kör:

```sh
./install.sh --safe-profile
```

`--safe-profile` installerar samma instruktioner/skills men sätter permission-nycklarna
till prompt/sandbox-läge i stället för full bypass.

Defaultprofilen sätter "fråga aldrig"-läge i varje harness (mergas in i respektive
config — kan inte symlänkas eftersom filerna håller maskin-state som tema/auth):

| Harness | Fil | Nyckel |
|---------|-----|--------|
| Claude Code | `~/.claude/settings.json` | `permissions.defaultMode = "bypassPermissions"` |
| Codex | `~/.codex/config.toml` | `approval_policy = "never"` + `sandbox_mode = "danger-full-access"` |
| OpenCode | `~/.config/opencode/opencode.jsonc` | `permission.{edit,bash,webfetch} = "allow"` |
| Pi | `~/.pi/agent/settings.json` | `defaultProjectTrust = "always"` |

> ⚠️ Detta tar bort bekräftelse-grindarna helt — agenterna kör shell, redigerar filer
> och hämtar nät utan att fråga. Avsett för en betrodd, personlig maskin. Ångra genom
> att köra `./install.sh --safe-profile` eller sätta tillbaka
> `default`/`ask`/`on-request` i respektive fil.

## Innehåll

- `AGENTS.md` — sanningskälla (router + kontrollant + autonomt läge + agent-routing).
- `model-routing.json` — provider-oberoende roller, tiers, presets och
  harness-bindningar.
- `scripts/resolve-model-route.mjs` — validerar och löser en logisk route till aktivt
  harness.
- `CLAUDE.md`, `GEMINI.md` — tunna pekare (`@./AGENTS.md`) för manuell kopiering om du
  inte vill symlinka.
- `preferences.md` — mina stående preferenser; preference-oracle svarar utifrån denna. Fyll i den.
- `skills/complexity-router/SKILL.md` — router som riktig skill där harnesset stödjer det.
- `skills/goal-watcher/SKILL.md` — drift-väktare för autonoma körningar.
- `skills/preference-oracle/SKILL.md` — svarar på lågrisk-frågor åt mig, eskalerar resten.
- `skills/web-research-fallback/SKILL.md` — stoppar gissningar och söker auktoritativa källor när lokal kontext inte räcker.
- `hooks/router-reminder.sh` — UserPromptSubmit-hook, det deterministiska lagret som
  injicerar router-direktivet varje tur (bara Claude Code).
- `hooks/settings-snippet.json` — hook-config att klistra in manuellt vid behov.
- `install.sh` — symlinkar instruktionsfiler + alla skills, hooken, samt Pi-configen;
  bootstrappar Node/Pi och installerar beroenden för Pi-extensionerna.
- `uninstall.sh` — tar bort repo-kopplingar och kan återställa agenternas
  permission-profiler till säkrare defaults.
- `pi/` — repoägda Pi-extensions, Pi-skills, tema, lokala modeller och Node-beroenden.
  Se `pi/README.md`.

## Lager av styrka

1. **AGENTS.md** (portabelt) — funkar i alla harness, sanktionerad override via prioritet.
2. **complexity-router-skill** (Claude Code/Codex/Pi där registrerat) — triggar automatiskt via sin description.
3. **hook** (Claude Code) — deterministiskt, beror inte på att modellen minns något.

För Gemini lever router-logiken inline i `AGENTS.md`. Hooken är ett
Claude-Code-specifikt tillägg.

## Brasklapp

Det här är instruktionsföljande, inte en mekanisk spärr. På kapabla modeller håller
prioritetsregeln bra; svaga lokala modeller följer inte alltid processen pålitligt.
Hooken är det enda riktigt deterministiska lagret.
