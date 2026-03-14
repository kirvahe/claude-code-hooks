#!/bin/bash
# Install Claude Code session hooks
# Usage: ./install.sh [hook-name]
# Without arguments: interactive mode (install all or pick)
# Compatible with bash 3+ (macOS default)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$HOME/.claude/scripts"
SETTINGS_FILE="$HOME/.claude/settings.json"

# Hook registry: "folder:dest_script:src_script"
HOOK_LIST=(
    "claude-code-update:auto-update-claude-code.sh:auto-update.sh"
    "sync-compound-engineering:sync-compound-engineering.sh:sync.sh"
)

mkdir -p "$DEST_DIR"

get_field() {
    local entry="$1" field="$2"
    echo "$entry" | cut -d: -f"$field"
}

find_hook() {
    local name="$1"
    for entry in "${HOOK_LIST[@]}"; do
        if [ "$(get_field "$entry" 1)" = "$name" ]; then
            echo "$entry"
            return 0
        fi
    done
    return 1
}

install_hook() {
    local entry="$1"
    local folder=$(get_field "$entry" 1)
    local dest_name=$(get_field "$entry" 2)
    local src_name=$(get_field "$entry" 3)
    local src="$SCRIPT_DIR/$folder/$src_name"
    local dest="$DEST_DIR/$dest_name"

    if [ ! -f "$src" ]; then
        echo "  ✗ Source not found: $src"
        return 1
    fi

    cp "$src" "$dest"
    chmod +x "$dest"
    echo "  ✓ Installed: $dest"
}

show_settings_hint() {
    echo ""
    echo "Add to ~/.claude/settings.json under hooks.SessionStart:"
    echo ""
    for entry in "${HOOK_LIST[@]}"; do
        local dest_name=$(get_field "$entry" 2)
        echo "  {"
        echo "    \"type\": \"command\","
        echo "    \"command\": \"$DEST_DIR/$dest_name\","
        echo "    \"async\": true"
        echo "  }"
    done
    echo ""
    echo "See each hook's README for the exact JSON snippet."
}

# Single hook install
if [ -n "$1" ]; then
    entry=$(find_hook "$1" || true)
    if [ -z "$entry" ]; then
        echo "Unknown hook: $1"
        echo -n "Available:"
        for e in "${HOOK_LIST[@]}"; do
            echo -n " $(get_field "$e" 1)"
        done
        echo ""
        exit 1
    fi
    echo "Installing $1..."
    install_hook "$entry"
    show_settings_hint
    exit 0
fi

# Interactive mode
echo "Claude Code Hooks Installer"
echo "==========================="
echo ""
echo "Available hooks:"
i=1
for entry in "${HOOK_LIST[@]}"; do
    echo "  $i) $(get_field "$entry" 1)"
    i=$((i + 1))
done
echo ""
echo "  a) Install all"
echo "  q) Quit"
echo ""
read -rp "Choice: " choice

case "$choice" in
    a|A)
        echo ""
        echo "Installing all hooks..."
        for entry in "${HOOK_LIST[@]}"; do
            install_hook "$entry"
        done
        show_settings_hint
        ;;
    q|Q)
        echo "Cancelled."
        exit 0
        ;;
    [0-9]*)
        idx=$((choice - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#HOOK_LIST[@]}" ]; then
            entry="${HOOK_LIST[$idx]}"
            folder=$(get_field "$entry" 1)
            echo ""
            echo "Installing $folder..."
            install_hook "$entry"
            show_settings_hint
        else
            echo "Invalid choice."
            exit 1
        fi
        ;;
    *)
        echo "Invalid choice."
        exit 1
        ;;
esac
