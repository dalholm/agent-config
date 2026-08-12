# agent-config

Mina globala instruktioner och skills för AI-kodningsagenter. Styr hur mycket process
varje uppgift behöver, så att småfix går snabbt och billigt medan stora jobb får full
disciplin.

## Idén

Direkta frågor besvaras utan workflow-ceremoni. När arbete ska utföras laddas
**complexity-router**, som väljer spår (T0 trivialt → T3 fullt arbetsflöde) och vars
**kontrollant** eskalerar om jobbet växer. Ceremonin (design/spec/plan/subagenter)
skalas; kvalitetsgrindarna (framför allt TDD) behålls. Repoets skills är en meny, inte
en fast pipeline. Prioriteten är:
**uttrycklig användarinstruktion > AGENTS.md > relevanta skills > systemstandard.**

För **autonoma (T3) körningar** finns två roller som gör hands-off säkert:
**preference-oracle** svarar på återkommande lågrisk-frågor åt mig (utifrån
`preferences.md`) och eskalerar resten; **goal-watcher** vakar på att arbetet inte
driver från specen. Agenternas arbetsroll (`coder`, `researcher`, `designer` osv.) och
kapacitetsnivå (`fast`, `standard`, `deep`) väljs vid orkestreringsgränsen. Orca eller
en annan orchestrator äger uppdelning, worktrees och schemaläggning;
`model-routing.json` äger modelltabellen; harness-adaptern binder modellen vid spawn.
`safety-policy.json` är den enda maskinläsbara auktoriteten för vilka
operationer och exekveringsprofiler som är tillåtna; modellval och preferensbeslut kan
inte utöka mandatet. Se "Keep authority separate from capability" i `AGENTS.md`.

## En sanningskälla

`AGENTS.md` är den lilla, stabila defaultpolicyn. Procedurer och volatila bindningar
laddas vid behov från skills respektive register. Alla harness pekas mot samma policy:

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
./install.sh --no-bootstrap   # bara konfiguration — installera inga externa verktyg
./install.sh --auto-approve   # explicit opt-in; kräver grönt agent-safety doctor
```

Scriptet symlinkar instruktionsfilerna, lägger skills i `~/.claude/skills/`,
`~/.codex/skills/` och `~/.hermes/skills/`, tar bort den pensionerade router-hooken
från `~/.claude/settings.json` (med `jq`; annars skrivs en manuell instruktion ut),
installerar katastrofhooken och länkar den repoägda Pi-konfigurationen till
`~/.pi/agent/`. Det länkar också
`model-routing.json` och `safety-policy.json` till `~/.config/agent-config/` samt
installerar `agent-model-route` och `agent-safety` i `~/.local/bin/`. Starta om
agenten efteråt.

Det **bootstrappar** också verktygen configen förutsätter (om de saknas): installerar
Node/npm (via Homebrew), Pi (via `pi.dev/install.sh`) och Node-beroendena för våra
Pi-extensions. Stäng av med `--no-bootstrap`.

### Hermes som utvecklingskoordinator

Hermes äger koordineringen av utvecklingsuppdrag men inte källkodsarbetet. Den
repoägda skillen `orca-development-orchestrator` instruerar Hermes att samla
kontrollplanskontext, preflighta Orca och safety-policyn, skicka avgränsade
worker-kontrakt och verifiera test-, review- och QA-evidens. Pi, Codex eller Claude
utför undersökning, design, implementation, felsökning, test, review och manuell QA i
Orca-ägda worktrees. Rena kunskapsfrågor besvaras fortfarande direkt.

Installern behåller kompatibilitetslänkarna i `~/.hermes/skills/` och länkar dessutom
alla delade skills i den aktiva koordinatorprofilen. Målet väljs i denna ordning:

1. `HERMES_HOME`, om variabeln är satt till en katalog strikt under användarens
   hemkatalog (inte till `$HOME` självt). Relativa värden tolkas från `$HOME`;
   absoluta värden används direkt.
2. `~/.hermes/profiles/{active-profile}`, om `~/.hermes/active_profile` pekar ut en
   befintlig profilkatalog.
3. `~/.hermes` som fallback.

Målet kan vara nytt, men dess längsta befintliga sökväg kanoniseras innan något
skrivs. Symlänkar följs vid kontrollen och det slutliga målet måste vara `$HOME` eller
ligga under `$HOME`; ett explicit `HERMES_HOME` måste dessutom vara en strikt
underkatalog. Ett `HERMES_HOME` eller en befintlig profillsymlänk som leder utanför
hemkatalogen avvisas. Profilnamnet måste vara en enda komponent med bokstäver, siffror,
punkt, understreck eller bindestreck, men får inte vara `.` eller `..`. Ogiltiga namn
och saknade profilkataloger ger fallback till `~/.hermes`.

Endast den valda profilen får det marköravgränsade, repoägda koordinationsblocket i
`SOUL.md`. Befintlig personlighet behålls. En tidsstämplad `SOUL.md.bak-*` skapas bara
när en befintlig fil faktiskt behöver ändras; en identisk ominstallation skapar ingen
backup. Filens befintliga behörighetsläge behålls vid omskrivning. Safety-hook och vald
permission-profil installeras innan koordinatormålet hanteras, så ett avvisat mål eller
ett felaktigt `SOUL.md` lämnar säkerhetskopplingen på plats även när installern avslutas
med fel. Ett `SOUL.md` som är en symlänk avvisas också utan att länken eller dess mål
ändras. Om en befintlig personlighet saknar avslutande radbrytning lägger installationen
in en som avskiljare; den radbrytningen blir kvar efter avinstallation som en avsiktlig
round-trip-normalisering. `--dry-run` visar både profilmål, skill-länkar, backup och
SOUL-merge utan att ändra dem.

## Avinstallera

```sh
./uninstall.sh --dry-run              # se vad som skulle tas bort
./uninstall.sh                    # ta bort repo-kopplingar
./uninstall.sh --keep-permissions # lämna approval/sandbox-inställningar orörda
```

Avinstallern är konservativ: den tar bort symlänkar/config-rader som pekar på detta
repo, söker igenom `~/.hermes` och alla säkert resolverade kataloger under
`~/.hermes/profiles/`, och tar bara bort det marköravgränsade koordinatorblocket och
repoägda skill-länkar. Därmed städas även profiler som var aktiva vid en tidigare
installation. Ett explicit koordinatorhem utanför dessa standardplatser återupptäcks
bara om samma `HERMES_HOME` skickas till avinstallationen. All annan
Hermes-personlighet, främmande skill-länkar och alla backupfiler behålls. En felaktigt
markerad eller symlänkad `SOUL.md` lämnas orörd utan att stoppa konservativ städning i
övriga profiler. En tom `SOUL.md` och tomma `skills/`-kataloger kan därför bli kvar;
avinstallern tar konservativt bort repoägt innehåll men inte artefakter som den inte
säkert kan tillskriva repot. Den raderar inte repot, Pi-autentisering,
sessionshistorik eller externa verktyg som Node/Pi.

Repoet innehåller fokuserade skills för bland annat TDD, implementation, diagnostik,
prototyper, grillning, domänmodellering, PRD:er, issues, review och QA. Installern
symlinkar samma skills till Claude Code och Codex; Pi registrerar samma katalog.
Orca-relaterade discovery-skills som `orca-cli`, `orchestration`, emulatorstyrning,
Linear och computer-use är också repoägda och följer därför med till andra datorer.
De laddar sin fulla, versionsmatchade referens från den installerade `orca`-binären,
så Orca behöver fortfarande vara installerat separat på målmaskinen.

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

- `AGENTS.md` — liten sanningskälla för stabil defaultpolicy och pekare till on-demand-procedurer.
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
- `hermes/coordinator-soul.md` — det marköravgränsade aktiveringsblocket för den
  aktiva Hermes-koordinatorprofilen.
- `skills/orca-development-orchestrator/SKILL.md` — Hermes-specifik procedur för
  delegerad utveckling genom Orca.
- `skills/spec-with-orca/SKILL.md` — Hermes-ledd specifikationsintervju där
  kodbasundersökning och designsondering delegeras till Orca-workers.
- `skills/complexity-router/SKILL.md` — router som riktig skill där harnesset stödjer det.
- `skills/model-routing/SKILL.md` — roll/tier-policy och ansvarsfördelning vid dispatch/spawn.
- `skills/goal-watcher/SKILL.md` — drift-väktare för autonoma körningar.
- `skills/preference-oracle/SKILL.md` — svarar på lågrisk-frågor åt mig, eskalerar resten.
- `skills/web-research-fallback/SKILL.md` — stoppar gissningar och söker auktoritativa källor när lokal kontext inte räcker.
- `hooks/deny-dangerous.sh` och `hooks/dangerous-patterns.txt` — tunn PreToolUse-adapter
  och testad klassificering av katastrofala shellkommandon.
- `hooks/settings-snippet.json` — hook-config att klistra in manuellt vid behov.
- `install.sh` — symlinkar instruktionsfiler + alla skills, säkerhetshooken och Pi-configen;
  bootstrappar Node/Pi och installerar beroenden för Pi-extensionerna.
- `uninstall.sh` — tar bort repo-kopplingar och kan återställa agenternas
  permission-profiler till säkrare defaults.
- `pi/` — repoägda Pi-extensions, Pi-skills, tema, lokala modeller och Node-beroenden.
  Se `pi/README.md`.

## Lager av styrka

1. **AGENTS.md** (portabelt) — minimal, stabil policy i alla harness.
2. **skills** — `complexity-router`, `model-routing` och övriga procedurer laddas vid behov.
3. **register** — provider- och modellbindningar hålls utanför promptpolicyn.
4. **harness/Orca-adaptrar** — verkställer routing vid dispatch/spawn.
5. **safety authority + hooks** — deterministiska operationsbeslut och katastrofdeny
   där harnesset exponerar ett verifierat hookläge.

## Brasklapp

Safety-policyn, sandboxen och säkerhetshooken ger mekaniska lager, men de täcker inte alla
verktygsytor. Instruktioner behövs fortfarande för MCP/API/browser-operationer och andra
harnesses som saknar verifierad pre-execution-adapter. Kör `agent-safety doctor` för att
se exakt vad den installerade profilen kan bevisa.
