# claude-usage-sh

A small bash script that displays your Claude Code usage (5-hour window and 7-day utilization) in i3bar via i3xrocks/i3blocks.

```
CC: 75% 5h (3h29m) | 40% 7d (4d2h)
```

## Dependencies

- `curl`
- `jq`
- Claude Code (for the OAuth credentials at `~/.claude/.credentials.json`)

## Setup

### i3xrocks (Regolith)

Copy or symlink the block config:

```sh
cp i3xrocks.conf ~/.config/regolith3/i3xrocks/conf.d/02_claude-usage
```

Then reload i3 (`Super+Shift+r`).

### i3blocks

Add to your i3blocks config:

```ini
[claude-usage]
command=/path/to/claude-usage.sh
interval=60
```

## Features

- Shows 5-hour and 7-day utilization percentages
- Shows time remaining until each window resets
- Click to open the [Claude usage page](https://claude.ai/settings/usage)
- Graceful error handling (shows `CC: no creds`, `CC: no token`, or `CC: err`)

## Configuration

Set `CLAUDE_CONFIG_DIR` to override the default credentials path (`~/.claude`).

## Credits

Inspired by [claude-usage-extension](https://github.com/Haletran/claude-usage-extension) for GNOME.
