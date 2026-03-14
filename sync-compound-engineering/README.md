# sync-compound-engineering

Syncs the [compound-engineering plugin](https://github.com/EveryInc/compound-engineering-plugin) from upstream once per day on session start.

## Prerequisites

The plugin must be installed as a marketplace plugin with a git remote:

```
~/.claude/plugins/marketplaces/every-marketplace/
```

## What it does

1. Checks if 24 hours have passed since the last sync
2. Fetches from upstream (EveryInc/compound-engineering-plugin)
3. Fast-forward merges new changes

Runs asynchronously — does not block Claude Code startup.

## Manual install

```bash
cp sync.sh ~/.claude/scripts/sync-compound-engineering.sh
chmod +x ~/.claude/scripts/sync-compound-engineering.sh
```

Then add to `~/.claude/settings.json` under `hooks.SessionStart`:

```json
{
  "type": "command",
  "command": "~/.claude/scripts/sync-compound-engineering.sh",
  "async": true
}
```
