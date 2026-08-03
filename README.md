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
harness. `safety-policy.json` är den enda maskinläsbara auktoriteten för vilka
operationer och exekveringsprofiler som är tillåtna; modellval och preferensbeslut kan
inte utöka mandatet. Se "One authority for safety and autonomy" i `AGENTS.md`.

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
./install.sh                  # säker standardprofil; filer backas upp till .bak-<datum>
./install.sh --no-bootstrap   # bara symlänkar/hook — installera inga externa verktyg
./install.sh --auto-approve   # explicit opt-in; kräver grönt agent-safety doctor
```

Scriptet symlinkar instruktionsfilerna, lägger skills i `~/.claude/skills/` och
`~/.codex/skills/`, fogar in router- och katastrofhookarna i
`~/.claude/settings.json` (kräver `jq`, annars skrivs manuell instruktion ut), och
länkar den repoägda Pi-konfigurationen till `~/.pi/agent/`. Det länkar också
`model-routing.json` och `safety-policy.json` till `~/.config/agent-config/` samt
installerar `agent-model-route` och `agent-safety` i `~/.local/bin/`. Starta om
agenten efteråt.

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

Default är **safe**: agentmiljöerna behåller prompts och workspace-sandboxing. Det
gamla flaggnamnet fungerar fortfarande explicit:

```sh
./install.sh --safe-profile
```

För en betrodd personlig maskin kan unrestricted auto-approve väljas explicit:

```sh
./install.sh --auto-approve
```

Installern länkar först policyn och hooken och kräver sedan att
`agent-safety doctor --profile auto-approve` är grönt innan permissiva
permission-nycklar skrivs. Dry-run visar kontrollen utan att ändra något.

Profilerna löses ur `safety-policy.json` och mergas in i respektive config, eftersom
filerna även håller maskin-state som tema och auth:

| Harness | Safe default | Explicit auto-approve |
|---------|--------------|-----------------------|
| Claude Code | `default` | `bypassPermissions` |
| Codex | `on-request` + `workspace-write` | `never` + `danger-full-access` |
| OpenCode | `ask` | `allow` |
| Pi | project trust `ask` | project trust `always` |

`--auto-approve` tar fortfarande bort breda bekräftelsegrindar. Katastrofhooken är en
nödbroms mot vissa shellmisstag, inte en sandbox och inte skydd mot motsvarande handling
via Python, API:er, MCP-verktyg eller harnesses utan verifierat hookstöd. Återgå med
`./install.sh --safe-profile`.

### Safety authority

Policyn kan inspekteras utan att ändra något:

```sh
agent-safety decide --operation read --mode interactive --authorized false
agent-safety decide --operation external-write --mode autonomous --authorized false
agent-safety profile --profile autonomous --harness codex --format json
agent-safety doctor
```

`--authorized true` betyder att den anropande adaptern redan har fastställt ett exakt
användarmandat i uppdraget eller den godkända planen. Kommandot autentiserar inte
mandatet och agenten får aldrig sätta värdet utifrån en preferens, en oracle-bedömning
eller själva subagent-spawnen. `deny` kan aldrig övertrumfas.

Varje profil har ett explicit doctor-scope. `repository` provar de gemensamma
repo-kontrollerna för workspace-sandboxad autonomi; `installed-profile` verifierar
dessutom installerade hooks, länkar och harness-inställningar innan en förhöjd profil
får aktiveras.

## Innehåll

- `AGENTS.md` — sanningskälla (router + kontrollant + autonomt läge + agent-routing).
- `model-routing.json` — provider-oberoende roller, tiers, presets och
  harness-bindningar.
- `safety-policy.json` — kanoniska operationsbeslut och exekveringsprofiler.
- `scripts/resolve-model-route.mjs` — validerar och löser en logisk route till aktivt
  harness.
- `scripts/agent-safety.mjs` — `decide`, `profile`, `check-command`, hook-adapter och
  `doctor` genom samma publika interface.
- `CLAUDE.md`, `GEMINI.md` — tunna pekare (`@./AGENTS.md`) för manuell kopiering om du
  inte vill symlinka.
- `preferences.md` — mina stående preferenser; preference-oracle svarar utifrån denna. Fyll i den.
- `skills/complexity-router/SKILL.md` — router som riktig skill där harnesset stödjer det.
- `skills/goal-watcher/SKILL.md` — drift-väktare för autonoma körningar.
- `skills/preference-oracle/SKILL.md` — svarar på lågrisk-frågor åt mig, eskalerar resten.
- `skills/web-research-fallback/SKILL.md` — stoppar gissningar och söker auktoritativa källor när lokal kontext inte räcker.
- `hooks/router-reminder.sh` — UserPromptSubmit-hook, det deterministiska lagret som
  injicerar router-direktivet varje tur (bara Claude Code).
- `hooks/deny-dangerous.sh` och `hooks/dangerous-patterns.txt` — tunn PreToolUse-adapter
  och testad klassificering av katastrofala shellkommandon.
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
3. **safety authority** — deterministiska operationsbeslut och permissionsprofiler.
4. **hooks/adapters** — verkställer routerpåminnelse och katastrofdeny där harnesset
   exponerar ett verifierat hookläge.

För Gemini lever router-logiken inline i `AGENTS.md`. Hooken är ett
Claude-Code-specifikt tillägg.

## Brasklapp

Safety-policyn, sandboxen och hooken ger mekaniska lager, men de täcker inte alla
verktygsytor. Instruktioner behövs fortfarande för MCP/API/browser-operationer och andra
harnesses som saknar verifierad pre-execution-adapter. Kör `agent-safety doctor` för att
se exakt vad den installerade profilen kan bevisa.
