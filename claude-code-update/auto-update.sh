#!/bin/bash
# Auto-update Claude Code (npm) once per day
# Runs as async SessionStart hook — doesn't block startup

TIMESTAMP_FILE="$HOME/.claude/plugins/cache/.claude-code-update-timestamp"
SYNC_INTERVAL=86400  # 24 hours in seconds

# Check if enough time has passed since last check
if [ -f "$TIMESTAMP_FILE" ]; then
    last_sync=$(cat "$TIMESTAMP_FILE")
    now=$(date +%s)
    elapsed=$((now - last_sync))
    [ "$elapsed" -lt "$SYNC_INTERVAL" ] && exit 0
fi

# Check if npm is available
command -v npm &>/dev/null || exit 0

# Check for update (compare installed vs latest)
current=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
latest=$(npm view @anthropic-ai/claude-code version 2>/dev/null)

# Record check timestamp regardless of update
mkdir -p "$(dirname "$TIMESTAMP_FILE")"
date +%s > "$TIMESTAMP_FILE"

# Update if versions differ
if [ -n "$current" ] && [ -n "$latest" ] && [ "$current" != "$latest" ]; then
    npm install -g @anthropic-ai/claude-code@latest --quiet 2>/dev/null
fi
