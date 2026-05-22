# tal-marketplace

Personal plugin marketplace for both Claude Code and Codex.

## Claude Code Setup

Add the marketplace from inside Claude Code:

```
/plugin marketplace add tal/plugin-marketplace
```

Then install a plugin:

```
/plugin install <plugin-name>@tal-marketplace
```

For example:

```
/plugin install sort@tal-marketplace
/plugin install plan-refiner@tal-marketplace
/plugin install smart-notifications@tal-marketplace
```

Or from the shell with the `claude` CLI:

```
claude plugin marketplace add tal/plugin-marketplace
claude plugin install <plugin-name>@tal-marketplace
```

## Plugins

Each plugin has its own README with the full feature/command/skill inventory — follow the links for details.

- **[tal](./plugins/tal/README.md)** — common plugin with git workflows, PR feedback fetching, and CI troubleshooting helpers.
- **[smart-notifications](./plugins/smart-notifications/README.md)** — macOS desktop notifications for agent events (Stop, SubagentStop, Notification) with terminal activation support.
- **[plan-refiner](./plugins/plan-refiner/README.md)** — refine plans and specs through in-depth interviews driven by strategic questioning.
- **[karabiner](./plugins/karabiner/README.md)** — skills for configuring and writing Karabiner-Elements rules on macOS.
- **[sort](./plugins/sort/README.md)** — sort and process files in any folder; dispatchers for videos (transcription/OCR), images, documents, archives, and installers.
- **[iconifier](./plugins/iconifier/README.md)** — generate and apply custom macOS folder icons for a directory's subfolders, matching the existing house style of icons on peers and parent. macOS only.
- **[og-simplify](./plugins/og-simplify/README.md)** — the resurrected /simplify: a three-agent (reuse/quality/efficiency) review-and-fix pass over your changed code.

### Manual configuration

Alternatively, register the marketplace in `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "tal-marketplace": {
      "source": {
        "source": "github",
        "repo": "tal/plugin-marketplace"
      }
    }
  },
  "enabledPlugins": {
    "plugin-name@tal-marketplace": true
  }
}
```

## Codex Setup

Add the marketplace:

```
codex plugin marketplace add tal/plugin-marketplace
```

Then install a plugin:

```
codex plugin install <plugin-name>@tal-marketplace
```

## Repository Layout

Each plugin lives under `plugins/<plugin-name>/` and can expose metadata for both clients side by side:

```text
plugins/my-plugin/
  .claude-plugin/
    plugin.json
  .codex-plugin/
    plugin.json
  commands/
  skills/
  agents/
  hooks/
```

Marketplace catalogs live at:

- Claude Code: `.claude-plugin/marketplace.json`
- Codex: `.agents/plugins/marketplace.json`

## Adding a Plugin

1. Create a directory under `plugins/`.
2. Add a Claude manifest at `plugins/my-plugin/.claude-plugin/plugin.json` if the plugin should be installable from Claude Code.
3. Add a Codex manifest at `plugins/my-plugin/.codex-plugin/plugin.json` if the plugin should be installable from Codex.
4. Register the plugin in the relevant marketplace files:

Claude entry:

```json
{
  "name": "my-plugin",
  "source": "./plugins/my-plugin",
  "description": "What the plugin does",
  "version": "0.1.0"
}
```

Codex entry:

```json
{
  "name": "my-plugin",
  "source": {
    "source": "local",
    "path": "./plugins/my-plugin"
  },
  "policy": {
    "installation": "AVAILABLE",
    "authentication": "ON_INSTALL"
  },
  "category": "Productivity"
}
```
