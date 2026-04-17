# tal-marketplace

Personal Claude Code plugin marketplace.

## Setup

Add this marketplace to your `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "tal-marketplace": {
      "source": {
        "source": "github",
        "repo": "tal/claude-marketplace"
      }
    }
  }
}
```

Then enable plugins from the marketplace:

```json
{
  "enabledPlugins": {
    "plugin-name@tal-marketplace": true
  }
}
```

## Adding a Plugin

1. Create a directory under `plugins/`:

```
plugins/my-plugin/
  .claude-plugin/
    plugin.json
  commands/
  skills/
  agents/
  hooks/
```

2. Add a `plugin.json` manifest:

```json
{
  "name": "my-plugin",
  "version": "0.1.0",
  "description": "What the plugin does"
}
```

3. Register it in `.claude-plugin/marketplace.json`:

```json
{
  "name": "my-plugin",
  "source": "my-plugin",
  "description": "What the plugin does",
  "version": "0.1.0"
}
```
