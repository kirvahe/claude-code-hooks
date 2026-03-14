#!/bin/bash
# Sync compound-engineering plugin from upstream (EveryInc) once per day
# Runs as async SessionStart hook — doesn't block Claude Code startup

MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/every-marketplace"
TIMESTAMP_FILE="$HOME/.claude/plugins/cache/.compound-sync-timestamp"
UPSTREAM_URL="https://github.com/EveryInc/compound-engineering-plugin.git"
SYNC_INTERVAL=86400  # 24 hours in seconds

# Exit if marketplace dir doesn't exist
[ -d "$MARKETPLACE_DIR/.git" ] || exit 0

# Check if enough time has passed since last sync
if [ -f "$TIMESTAMP_FILE" ]; then
    last_sync=$(cat "$TIMESTAMP_FILE")
    now=$(date +%s)
    elapsed=$((now - last_sync))
    [ "$elapsed" -lt "$SYNC_INTERVAL" ] && exit 0
fi

cd "$MARKETPLACE_DIR" || exit 1

# Add upstream remote if missing
if ! git remote get-url upstream &>/dev/null; then
    git remote add upstream "$UPSTREAM_URL"
fi

# Fetch and fast-forward merge
git fetch upstream main --quiet 2>/dev/null || exit 0
git merge upstream/main --ff-only --quiet 2>/dev/null || exit 0

# Record sync timestamp
mkdir -p "$(dirname "$TIMESTAMP_FILE")"
date +%s > "$TIMESTAMP_FILE"
