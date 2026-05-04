# smart-notifications

Desktop notifications for Claude Code events on macOS using `terminal-notifier`.

## Install

Claude Code (from inside the session):

```
/plugin install smart-notifications@tal-marketplace
```

Or from the shell with the `claude` CLI:

```
claude plugin install smart-notifications@tal-marketplace
```

Codex:

```
codex plugin install smart-notifications@tal-marketplace
```

## Features

### Smart Terminal/IDE Detection

The plugin automatically detects your terminal or IDE and activates it when you click on a notification. Supported applications include:

- **Terminals**: iTerm2, Warp, Apple Terminal, Alacritty, Kitty, Hyper
- **IDEs**: VSCode, Cursor, JetBrains IDEs (IntelliJ, etc.)
- **Multiplexers**: tmux (detects the terminal the active tmux client is attached to, and on click jumps back to the exact session/window/pane that produced the notification)

When a notification is clicked, your terminal/IDE window is automatically brought to the front.

Ghostty is intentionally skipped — it has its own built-in notification handling, so the plugin does not emit notifications when running under Ghostty.

### Context-Aware Notifications

Notifications include contextual information:

- **Project Name**: Displayed as a subtitle using either the `PROJECT_NAME` environment variable or the current working directory name
- **Notification Type**: Different types trigger distinct notification styles:
  - `permission_prompt`: Permission Required (Glass sound)
  - `idle_prompt`: Waiting for Input (Purr sound)
  - `auth_success`: Authentication (Hero sound)
  - `elicitation_dialog`: Input Needed (Pop sound)

### Repeat Detection

The plugin tracks notifications per project and adds a 🔁 emoji to the title when the same user message triggers multiple notifications. This helps you identify when Claude is repeatedly waiting on the same task.

### Unsupported Terminal Warning

If your terminal/IDE cannot be detected, you'll receive a one-time warning notification. The plugin will still show notifications, but they won't auto-activate your terminal when clicked.

## Notification Logging

You can enable detailed logging of all notifications to help debug issues or track Claude's activity.

### Enabling Logging

Add the `ENABLE_CLAUDE_NOTIFICATION_LOGGING` environment variable to your Claude Code settings.

Edit your Claude Code settings file (`~/.config/claude/settings.json`) and add to the `env` section:

```json
{
  "env": {
    "ENABLE_CLAUDE_NOTIFICATION_LOGGING": "1"
  }
}
```

Alternatively, you can set it in your shell configuration:

```bash
export ENABLE_CLAUDE_NOTIFICATION_LOGGING=1
```

### Log File Location

When enabled, notifications are logged to `claude-notifications.jsonl` in each project's working directory.

### Log Format

Each log entry is a JSON object containing:

```json
{
  "message": "Notification message text",
  "notification_type": "idle_prompt",
  "cwd": "/path/to/project",
  "transcript_file": "/path/to/transcript.jsonl",
  "timestamp": "2026-01-29T12:34:56Z",
  "timestamp_ny": "2026-01-29T07:34:56-0500",
  "is_repeat": "false",
  "last_transcript_line": {...}
}
```

The log file is automatically limited to the 500 most recent entries to prevent unbounded growth.

## Requirements

- macOS
- [terminal-notifier](https://github.com/julienXX/terminal-notifier) installed via Homebrew:
  ```bash
  brew install terminal-notifier
  ```

## Custom Project Names

By default, notifications show your project folder name as the subtitle. You can customize this by setting the `PROJECT_NAME` environment variable in your project settings:

**Local settings** (`.claude/settings.local.json` - not committed to git):
```json
{
  "env": {
    "PROJECT_NAME": "My Awesome Project"
  }
}
```

**Committed settings** (`.claude/settings.json` - shared with team):
```json
{
  "env": {
    "PROJECT_NAME": "My Awesome Project"
  }
}
```

## Troubleshooting

### Notifications Not Appearing

1. Check that `terminal-notifier` is installed: `which terminal-notifier`
2. Verify macOS notification permissions for terminal-notifier in System Settings > Notifications

### Terminal Not Activating on Click

If clicking notifications doesn't bring your terminal to the front:

1. Check for a configuration warning notification on first use
2. The plugin may not support your specific terminal yet - please open an issue with your `$TERM_PROGRAM` value

### Finding Your Terminal Information

Run these commands to help troubleshoot detection issues:

```bash
echo "TERM_PROGRAM: $TERM_PROGRAM"
echo "__CFBundleIdentifier: $__CFBundleIdentifier"
echo "TERMINAL_EMULATOR: $TERMINAL_EMULATOR"
```
