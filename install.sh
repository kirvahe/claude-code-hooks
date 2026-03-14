#!/bin/bash
# Install Claude Code session hooks
# Usage: ./install.sh [hook-name]
# Without arguments: interactive mode (install all or pick)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$HOME/.claude/scripts"
SETTINGS_FILE="$HOME/.claude/settings.json"

# Hook registry: folder -> script name
declare -A HOOKS
HOOKS=(
    ["claude-code-update"]="auto-update-claude-code.sh:auto-update.sh"
    ["sync-compound-engineering"]="sync-compound-engineering.sh:sync.sh"
)

mkdir -p "$DEST_DIR"

install_hook() {
    local folder="$1"
    local dest_name="${HOOKS[$folder]%%:*}"
    local src_name="${HOOKS[$folder]##*:}"
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
    for folder in "${!HOOKS[@]}"; do
        local dest_name="${HOOKS[$folder]%%:*}"
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
    if [ -z "${HOOKS[$1]}" ]; then
        echo "Unknown hook: $1"
        echo "Available: ${!HOOKS[*]}"
        exit 1
    fi
    echo "Installing $1..."
    install_hook "$1"
    show_settings_hint
    exit 0
fi

# Interactive mode
echo "Claude Code Hooks Installer"
echo "==========================="
echo ""
echo "Available hooks:"
i=1
for folder in $(echo "${!HOOKS[@]}" | tr ' ' '\n' | sort); do
    echo "  $i) $folder"
    ((i++))
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
        for folder in "${!HOOKS[@]}"; do
            install_hook "$folder"
        done
        show_settings_hint
        ;;
    q|Q)
        echo "Cancelled."
        exit 0
        ;;
    [0-9]*)
        folders=($(echo "${!HOOKS[@]}" | tr ' ' '\n' | sort))
        idx=$((choice - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#folders[@]}" ]; then
            folder="${folders[$idx]}"
            echo ""
            echo "Installing $folder..."
            install_hook "$folder"
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
