# Pi configuration

This directory is the version-controlled source of truth for the Pi coding agent.
`../install.sh` links the configuration into `~/.pi/agent` while leaving private
runtime state such as authentication and session history in place.

## Included features

- `extensions/ask-user` — structured multiple-choice questions.
- `extensions/background-terminals` — managed background commands and terminal UI.
- `extensions/copy-all` — copy the current conversation.
- `extensions/file-search` — first-class `fd` and `rg` tools.
- `extensions/git-info` and `extensions/model-info` — useful status information.
- `extensions/subagents` — Pi, Claude, and Codex subagent backends.
- `extensions/summaries` — run summaries.
- `extensions/ui-customization` — customized status bar.
- `extensions/workflows` — reusable multi-step workflows.
- `themes/github-dark-default.json` — the default Pi theme.
- `skills/` — instructions for the background-terminal and subagent tools.
- `models.json` — local LM Studio providers and models.

Firecrawl is deliberately not included. Web search can be added later when there is a
real need and an API key has been configured.

## Shared instructions and skills

Pi reads the same `AGENTS.md` as the other coding agents. The installer also registers
the repository's top-level `skills/` directory in Pi settings, so the complexity
router and the focused engineering skills remain shared across harnesses.

Pi-specific extensions and skills stay in this directory. General agent instructions
stay at the repository root.

## Install

From the repository root:

```sh
./install.sh
```

The installer:

1. links `AGENTS.md`, `models.json`, `extensions/`, `themes/`, and Pi-specific
   `skills/` into `~/.pi/agent`;
2. installs the Node dependencies in this directory;
3. selects the `github-dark-default` theme;
4. registers the shared top-level skills;
5. removes package references from the retired Pi setup without touching unrelated
   packages, authentication, sessions, or project data.

Use `./install.sh --dry-run` to inspect the changes first.

## Development

```sh
cd pi
npm install
npm test
npm run check
npm run format:check
```

The Pi extension source is maintained as part of this repository. Changes should be
tested here before the root installer is run.
