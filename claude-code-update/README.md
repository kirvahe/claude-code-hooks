# claude-code-update

Auto-updates Claude Code CLI once per day on session start.

## What it does

1. Checks if 24 hours have passed since the last check
2. Compares your installed version with the latest on npm
3. Updates if a new version is available

Runs asynchronously — does not block Claude Code startup.

## Manual install

```bash
cp auto-update.sh ~/.claude/scripts/auto-update-claude-code.sh
chmod +x ~/.claude/scripts/auto-update-claude-code.sh
```

Then add to `~/.claude/settings.json` under `hooks.SessionStart`:

```json
{
  "type": "command",
  "command": "~/.claude/scripts/auto-update-claude-code.sh",
  "async": true
}
```
