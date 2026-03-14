#!/bin/bash
# Synthetic tests for claude-code-hooks
# Runs in an isolated temp directory — no side effects on real system

set -e

PASSED=0
FAILED=0
TEST_DIR=$(mktemp -d)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
DIM='\033[0;90m'
NC='\033[0m'

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
    FAILED=$((FAILED + 1))
}

assert_file_exists() {
    [ -f "$1" ] && pass "$2" || fail "$2"
}

assert_file_not_exists() {
    [ ! -f "$1" ] && pass "$2" || fail "$2"
}

assert_exit_code() {
    local expected=$1 actual=$2 msg=$3
    [ "$actual" -eq "$expected" ] && pass "$msg" || fail "$msg (expected $expected, got $actual)"
}

# ============================================================
echo ""
echo "claude-code-hooks — test suite"
echo "=============================="

# ============================================================
echo ""
echo "1. claude-code-update"
echo "---------------------"

# Create mock environment
MOCK_HOME="$TEST_DIR/home"
MOCK_CACHE="$MOCK_HOME/.claude/plugins/cache"
MOCK_TIMESTAMP="$MOCK_CACHE/.claude-code-update-timestamp"
mkdir -p "$MOCK_CACHE"

# Create a wrapper that overrides HOME and mocks external commands
MOCK_BIN="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN"

# Mock claude: returns version 2.1.0
cat > "$MOCK_BIN/claude" << 'MOCK'
#!/bin/bash
echo "2.1.0 (Claude Code)"
MOCK
chmod +x "$MOCK_BIN/claude"

# Mock npm: "view" returns 2.2.0, "install" records the call
NPM_INSTALL_LOG="$TEST_DIR/npm-install.log"
cat > "$MOCK_BIN/npm" << MOCK
#!/bin/bash
if [ "\$1" = "view" ]; then
    echo "2.2.0"
elif [ "\$1" = "install" ]; then
    echo "\$@" > "$NPM_INSTALL_LOG"
fi
MOCK
chmod +x "$MOCK_BIN/npm"

# Test 1.1: First run — should check and update
HOME="$MOCK_HOME" PATH="$MOCK_BIN:$PATH" \
    bash "$SCRIPT_DIR/claude-code-update/auto-update.sh"
rc=$?
assert_exit_code 0 $rc "first run exits 0"
assert_file_exists "$MOCK_TIMESTAMP" "creates timestamp file"
assert_file_exists "$NPM_INSTALL_LOG" "triggers npm install (version mismatch 2.1.0 → 2.2.0)"

# Test 1.2: Second run within 24h — should skip
rm -f "$NPM_INSTALL_LOG"
HOME="$MOCK_HOME" PATH="$MOCK_BIN:$PATH" \
    bash "$SCRIPT_DIR/claude-code-update/auto-update.sh"
rc=$?
assert_exit_code 0 $rc "second run (within 24h) exits 0"
assert_file_not_exists "$NPM_INSTALL_LOG" "skips update within 24h window"

# Test 1.3: Expired timestamp — should check again
echo "1000000000" > "$MOCK_TIMESTAMP"  # year 2001
rm -f "$NPM_INSTALL_LOG"
HOME="$MOCK_HOME" PATH="$MOCK_BIN:$PATH" \
    bash "$SCRIPT_DIR/claude-code-update/auto-update.sh"
assert_file_exists "$NPM_INSTALL_LOG" "re-checks after expired timestamp"

# Test 1.4: Same version — should NOT install
echo "1000000000" > "$MOCK_TIMESTAMP"
rm -f "$NPM_INSTALL_LOG"
# Mock npm to return same version as claude
cat > "$MOCK_BIN/npm" << MOCK
#!/bin/bash
if [ "\$1" = "view" ]; then
    echo "2.1.0"
elif [ "\$1" = "install" ]; then
    echo "\$@" > "$NPM_INSTALL_LOG"
fi
MOCK
chmod +x "$MOCK_BIN/npm"
HOME="$MOCK_HOME" PATH="$MOCK_BIN:$PATH" \
    bash "$SCRIPT_DIR/claude-code-update/auto-update.sh"
assert_file_not_exists "$NPM_INSTALL_LOG" "skips install when versions match"

# Test 1.5: npm not available — should exit gracefully
echo "1000000000" > "$MOCK_TIMESTAMP"
EMPTY_BIN="$TEST_DIR/empty-bin"
mkdir -p "$EMPTY_BIN"
cat > "$EMPTY_BIN/claude" << 'MOCK'
#!/bin/bash
echo "2.1.0 (Claude Code)"
MOCK
chmod +x "$EMPTY_BIN/claude"
HOME="$MOCK_HOME" PATH="$EMPTY_BIN:/usr/bin:/bin" \
    bash "$SCRIPT_DIR/claude-code-update/auto-update.sh"
rc=$?
assert_exit_code 0 $rc "exits gracefully when npm not found"

# ============================================================
echo ""
echo "2. sync-compound-engineering"
echo "----------------------------"

MOCK_HOME2="$TEST_DIR/home2"
MOCK_MARKETPLACE="$MOCK_HOME2/.claude/plugins/marketplaces/every-marketplace"
MOCK_CACHE2="$MOCK_HOME2/.claude/plugins/cache"
MOCK_TIMESTAMP2="$MOCK_CACHE2/.compound-sync-timestamp"

# Test 2.1: No marketplace dir — should exit silently
mkdir -p "$MOCK_CACHE2"
HOME="$MOCK_HOME2" bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
rc=$?
assert_exit_code 0 $rc "exits 0 when marketplace dir missing"
assert_file_not_exists "$MOCK_TIMESTAMP2" "no timestamp when marketplace dir missing"

# Test 2.2: With marketplace dir — simulated git repo
mkdir -p "$MOCK_MARKETPLACE"
cd "$MOCK_MARKETPLACE" && git init --quiet && git commit --allow-empty -m "init" --quiet
cd "$SCRIPT_DIR"

# Mock git fetch/merge to succeed (use real git, just add a remote)
cd "$MOCK_MARKETPLACE"
# Create a bare "upstream" repo to fetch from
UPSTREAM_BARE="$TEST_DIR/upstream-bare"
git clone --bare . "$UPSTREAM_BARE" 2>/dev/null
git remote add upstream "$UPSTREAM_BARE" 2>/dev/null || true
cd "$SCRIPT_DIR"

HOME="$MOCK_HOME2" bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
rc=$?
assert_exit_code 0 $rc "runs successfully with valid marketplace dir"
assert_file_exists "$MOCK_TIMESTAMP2" "creates timestamp after sync"

# Test 2.3: Second run within 24h — should skip
BEFORE_TS=$(cat "$MOCK_TIMESTAMP2")
sleep 1
HOME="$MOCK_HOME2" bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
AFTER_TS=$(cat "$MOCK_TIMESTAMP2")
[ "$BEFORE_TS" = "$AFTER_TS" ] && pass "skips sync within 24h (timestamp unchanged)" || fail "should not update timestamp within 24h"

# Test 2.4: Expired timestamp — should sync again
echo "1000000000" > "$MOCK_TIMESTAMP2"
HOME="$MOCK_HOME2" bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
AFTER_TS=$(cat "$MOCK_TIMESTAMP2")
[ "$AFTER_TS" != "1000000000" ] && pass "re-syncs after expired timestamp" || fail "should have updated timestamp"

# ============================================================
echo ""
echo "3. install.sh"
echo "-------------"

MOCK_HOME3="$TEST_DIR/home3"
mkdir -p "$MOCK_HOME3/.claude/scripts"

# Test 3.1: Install single hook
HOME="$MOCK_HOME3" bash "$SCRIPT_DIR/install.sh" claude-code-update 2>&1 | grep -q "Installed" && \
    pass "installs single hook by name" || fail "single hook install"
assert_file_exists "$MOCK_HOME3/.claude/scripts/auto-update-claude-code.sh" "script copied to ~/.claude/scripts/"

# Test 3.2: Installed script is executable
[ -x "$MOCK_HOME3/.claude/scripts/auto-update-claude-code.sh" ] && \
    pass "installed script is executable" || fail "script should be executable"

# Test 3.3: Unknown hook name
HOME="$MOCK_HOME3" bash "$SCRIPT_DIR/install.sh" nonexistent-hook 2>&1 | grep -q "Unknown" && \
    pass "rejects unknown hook name" || fail "should reject unknown hook"

# ============================================================
echo ""
echo "=============================="
TOTAL=$((PASSED + FAILED))
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, $TOTAL total"
echo ""

[ "$FAILED" -eq 0 ] && exit 0 || exit 1
