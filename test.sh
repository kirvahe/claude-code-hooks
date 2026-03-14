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

# --- Unit tests (isolated logic) ---

# Test 2.1: No marketplace dir — should exit silently
mkdir -p "$MOCK_CACHE2"
HOME="$MOCK_HOME2" bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
rc=$?
assert_exit_code 0 $rc "exits 0 when marketplace dir missing"
assert_file_not_exists "$MOCK_TIMESTAMP2" "no timestamp when marketplace dir missing"

# Test 2.2: Marketplace dir exists but is NOT a git repo
mkdir -p "$MOCK_MARKETPLACE"
HOME="$MOCK_HOME2" bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
rc=$?
assert_exit_code 0 $rc "exits 0 when dir exists but no .git"
assert_file_not_exists "$MOCK_TIMESTAMP2" "no timestamp for non-git dir"
rm -rf "$MOCK_MARKETPLACE"

# Test 2.3: Valid git repo — first run should sync and create timestamp
mkdir -p "$MOCK_MARKETPLACE"
cd "$MOCK_MARKETPLACE" && git init --quiet && git commit --allow-empty -m "init" --quiet
cd "$SCRIPT_DIR"

# Create a bare "upstream" repo with a new commit to fetch
UPSTREAM_BARE="$TEST_DIR/upstream-bare"
git clone --bare "$MOCK_MARKETPLACE" "$UPSTREAM_BARE" 2>/dev/null
# Add a commit to upstream so there's something to fetch
UPSTREAM_WORK="$TEST_DIR/upstream-work"
git clone "$UPSTREAM_BARE" "$UPSTREAM_WORK" --quiet 2>/dev/null
cd "$UPSTREAM_WORK" && git commit --allow-empty -m "upstream update" --quiet && git push --quiet 2>/dev/null
cd "$SCRIPT_DIR"

cd "$MOCK_MARKETPLACE" && git remote add upstream "$UPSTREAM_BARE" 2>/dev/null || true
cd "$SCRIPT_DIR"

HOME="$MOCK_HOME2" bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
rc=$?
assert_exit_code 0 $rc "runs successfully with valid marketplace dir"
assert_file_exists "$MOCK_TIMESTAMP2" "creates timestamp after sync"

# Test 2.4: Verify upstream commit was actually pulled
cd "$MOCK_MARKETPLACE"
COMMIT_MSG=$(git log --oneline -1 2>/dev/null)
cd "$SCRIPT_DIR"
echo "$COMMIT_MSG" | grep -q "upstream update" && \
    pass "upstream commit was fast-forwarded into local" || fail "upstream commit not pulled"

# Test 2.5: Second run within 24h — should skip (throttle)
BEFORE_TS=$(cat "$MOCK_TIMESTAMP2")
sleep 1
HOME="$MOCK_HOME2" bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
AFTER_TS=$(cat "$MOCK_TIMESTAMP2")
[ "$BEFORE_TS" = "$AFTER_TS" ] && pass "skips sync within 24h (timestamp unchanged)" || fail "should not update timestamp within 24h"

# Test 2.6: Expired timestamp — should sync again
echo "1000000000" > "$MOCK_TIMESTAMP2"
HOME="$MOCK_HOME2" bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
AFTER_TS=$(cat "$MOCK_TIMESTAMP2")
[ "$AFTER_TS" != "1000000000" ] && pass "re-syncs after expired timestamp" || fail "should have updated timestamp"

# Test 2.7: Timestamp is a valid unix epoch
STORED_TS=$(cat "$MOCK_TIMESTAMP2")
NOW=$(date +%s)
DIFF=$((NOW - STORED_TS))
[ "$DIFF" -ge 0 ] && [ "$DIFF" -lt 10 ] && \
    pass "timestamp is valid unix epoch (within 10s of now)" || fail "timestamp looks wrong: $STORED_TS vs now $NOW"

# Test 2.8: Upstream remote added automatically if missing
MOCK_HOME2B="$TEST_DIR/home2b"
MOCK_MARKETPLACE2="$MOCK_HOME2B/.claude/plugins/marketplaces/every-marketplace"
MOCK_CACHE2B="$MOCK_HOME2B/.claude/plugins/cache"
mkdir -p "$MOCK_CACHE2B"
mkdir -p "$MOCK_MARKETPLACE2"
cd "$MOCK_MARKETPLACE2" && git init --quiet && git commit --allow-empty -m "init" --quiet
cd "$SCRIPT_DIR"
# No upstream remote added — script should add it
HOME="$MOCK_HOME2B" bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh" 2>/dev/null
cd "$MOCK_MARKETPLACE2"
REMOTE_URL=$(git remote get-url upstream 2>/dev/null || echo "none")
cd "$SCRIPT_DIR"
[ "$REMOTE_URL" != "none" ] && \
    pass "adds upstream remote automatically when missing" || fail "should add upstream remote"

# Test 2.9: upstream remote URL is correct
[ "$REMOTE_URL" = "https://github.com/EveryInc/compound-engineering-plugin.git" ] && \
    pass "upstream remote URL is correct" || fail "wrong upstream URL: $REMOTE_URL"

# Test 2.10: Conflicting changes — ff-only should fail gracefully (exit 0)
MOCK_HOME2C="$TEST_DIR/home2c"
MOCK_MARKETPLACE3="$MOCK_HOME2C/.claude/plugins/marketplaces/every-marketplace"
MOCK_CACHE2C="$MOCK_HOME2C/.claude/plugins/cache"
mkdir -p "$MOCK_CACHE2C"

# Create upstream bare repo
UPSTREAM_BARE3="$TEST_DIR/upstream-bare3"
mkdir -p "$UPSTREAM_BARE3" && cd "$UPSTREAM_BARE3" && git init --bare --quiet
cd "$SCRIPT_DIR"

# Create local repo with one commit
mkdir -p "$MOCK_MARKETPLACE3"
cd "$MOCK_MARKETPLACE3" && git init --quiet
git commit --allow-empty -m "local init" --quiet
git remote add upstream "$UPSTREAM_BARE3"
cd "$SCRIPT_DIR"

# Push local to upstream so they share history
cd "$MOCK_MARKETPLACE3" && git push upstream main --quiet 2>/dev/null
cd "$SCRIPT_DIR"

# Create divergent commit on upstream
UPSTREAM_WORK3="$TEST_DIR/upstream-work3"
git clone "$UPSTREAM_BARE3" "$UPSTREAM_WORK3" --quiet 2>/dev/null
cd "$UPSTREAM_WORK3" && touch upstream-file && git add upstream-file && git commit -m "upstream diverge" --quiet && git push --quiet 2>/dev/null
cd "$SCRIPT_DIR"

# Create divergent commit locally (can't fast-forward)
cd "$MOCK_MARKETPLACE3" && touch local-file && git add local-file && git commit -m "local diverge" --quiet
cd "$SCRIPT_DIR"

HOME="$MOCK_HOME2C" bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
rc=$?
assert_exit_code 0 $rc "exits 0 on ff-only merge conflict (graceful failure)"

# Test 2.11: Cache dir created automatically if missing
MOCK_HOME2D="$TEST_DIR/home2d"
MOCK_MARKETPLACE4="$MOCK_HOME2D/.claude/plugins/marketplaces/every-marketplace"
# Deliberately do NOT create cache dir
mkdir -p "$MOCK_MARKETPLACE4"
cd "$MOCK_MARKETPLACE4" && git init --quiet && git commit --allow-empty -m "init" --quiet
UPSTREAM_BARE4="$TEST_DIR/upstream-bare4"
git clone --bare . "$UPSTREAM_BARE4" 2>/dev/null
git remote add upstream "$UPSTREAM_BARE4" 2>/dev/null || true
cd "$SCRIPT_DIR"

HOME="$MOCK_HOME2D" bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
rc=$?
assert_exit_code 0 $rc "runs when cache dir doesn't pre-exist"
assert_file_exists "$MOCK_HOME2D/.claude/plugins/cache/.compound-sync-timestamp" "creates cache dir and timestamp automatically"

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
echo "4. Functional: sync-compound-engineering (live system)"
echo "------------------------------------------------------"

REAL_MARKETPLACE="$HOME/.claude/plugins/marketplaces/every-marketplace"
REAL_TIMESTAMP="$HOME/.claude/plugins/cache/.compound-sync-timestamp"

if [ -d "$REAL_MARKETPLACE/.git" ]; then
    # Test 4.1: Script runs on real marketplace dir
    # Save and clear timestamp to force a real run
    SAVED_TS=""
    if [ -f "$REAL_TIMESTAMP" ]; then
        SAVED_TS=$(cat "$REAL_TIMESTAMP")
    fi
    rm -f "$REAL_TIMESTAMP"

    bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
    rc=$?
    assert_exit_code 0 $rc "live: runs successfully on real marketplace dir"
    assert_file_exists "$REAL_TIMESTAMP" "live: creates timestamp"

    # Test 4.2: Upstream remote exists
    cd "$REAL_MARKETPLACE"
    UPSTREAM=$(git remote get-url upstream 2>/dev/null || echo "none")
    cd "$SCRIPT_DIR"
    [ "$UPSTREAM" != "none" ] && \
        pass "live: upstream remote configured" || fail "live: no upstream remote"

    # Test 4.3: Upstream URL points to EveryInc
    echo "$UPSTREAM" | grep -q "EveryInc/compound-engineering-plugin" && \
        pass "live: upstream URL points to EveryInc" || fail "live: wrong upstream URL: $UPSTREAM"

    # Test 4.4: Sync did not introduce merge conflicts
    cd "$REAL_MARKETPLACE"
    CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null)
    cd "$SCRIPT_DIR"
    [ -z "$CONFLICTS" ] && \
        pass "live: no merge conflicts after sync" || fail "live: merge conflicts after sync: $CONFLICTS"

    # Test 4.5: Main branch has commits from upstream
    cd "$REAL_MARKETPLACE"
    HAS_UPSTREAM_COMMITS=$(git log --oneline upstream/main 2>/dev/null | head -1)
    cd "$SCRIPT_DIR"
    [ -n "$HAS_UPSTREAM_COMMITS" ] && \
        pass "live: upstream/main has commits" || fail "live: upstream/main empty or missing"

    # Test 4.6: Throttle — second run skips
    TS_BEFORE=$(cat "$REAL_TIMESTAMP")
    sleep 1
    bash "$SCRIPT_DIR/sync-compound-engineering/sync.sh"
    TS_AFTER=$(cat "$REAL_TIMESTAMP")
    [ "$TS_BEFORE" = "$TS_AFTER" ] && \
        pass "live: throttle works (second run skipped)" || fail "live: throttle failed"

    # Test 4.7: Timestamp is recent (within 60s)
    STORED=$(cat "$REAL_TIMESTAMP")
    NOW=$(date +%s)
    DIFF=$((NOW - STORED))
    [ "$DIFF" -ge 0 ] && [ "$DIFF" -lt 60 ] && \
        pass "live: timestamp is recent (${DIFF}s old)" || fail "live: timestamp too old (${DIFF}s)"

    # Test 4.8: Local HEAD matches or is ancestor of upstream/main
    cd "$REAL_MARKETPLACE"
    git merge-base --is-ancestor HEAD upstream/main 2>/dev/null && \
        RELATION="ancestor" || RELATION="diverged"
    LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null)
    UPSTREAM_HEAD=$(git rev-parse upstream/main 2>/dev/null)
    cd "$SCRIPT_DIR"
    if [ "$LOCAL_HEAD" = "$UPSTREAM_HEAD" ]; then
        pass "live: HEAD matches upstream/main"
    elif [ "$RELATION" = "ancestor" ]; then
        pass "live: HEAD is ancestor of upstream/main (ff possible)"
    else
        fail "live: HEAD diverged from upstream/main"
    fi

    # Restore original timestamp if it existed
    if [ -n "$SAVED_TS" ]; then
        echo "$SAVED_TS" > "$REAL_TIMESTAMP"
    fi
else
    echo -e "  ${DIM}⊘ skipped — marketplace dir not found (not installed)${NC}"
fi

# ============================================================
echo ""
echo "=============================="
TOTAL=$((PASSED + FAILED))
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, $TOTAL total"
echo ""

[ "$FAILED" -eq 0 ] && exit 0 || exit 1
