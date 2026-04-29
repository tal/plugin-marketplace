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

Available plugins: `tal`, `smart-notifications`, `plan-refiner`, `karabiner`, `sort`.

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
