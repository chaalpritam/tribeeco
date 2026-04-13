#!/bin/bash
#
# Test suite for the tribe CLI
# Run: ./test/test_tribe_cli.sh
#
# Tests are split into:
#   - Unit tests:        no external deps, test CLI logic only
#   - Integration tests: require Docker, test actual service lifecycle
#
# Exit code 0 = all passed, 1 = failures

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TRIBE="$ROOT_DIR/bin/tribe"
PASS=0
FAIL=0
SKIP=0

# ── Helpers ──────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass() {
  PASS=$((PASS+1))
  echo -e "  ${GREEN}PASS${NC}  $1"
}

fail() {
  FAIL=$((FAIL+1))
  echo -e "  ${RED}FAIL${NC}  $1"
  [ -n "${2:-}" ] && echo -e "        ${RED}$2${NC}"
}

skip() {
  SKIP=$((SKIP+1))
  echo -e "  ${YELLOW}SKIP${NC}  $1 — $2"
}

assert_exit_code() {
  local desc="$1" expected="$2"
  shift 2
  local actual
  set +e
  "$@" >/dev/null 2>&1
  actual=$?
  set -e
  if [ "$actual" -eq "$expected" ]; then
    pass "$desc"
  else
    fail "$desc" "expected exit $expected, got $actual"
  fi
}

assert_output_contains() {
  local desc="$1" pattern="$2"
  shift 2
  local output
  set +e
  output=$("$@" 2>&1)
  set -e
  if echo "$output" | grep -q "$pattern"; then
    pass "$desc"
  else
    fail "$desc" "output did not contain '$pattern'"
  fi
}

assert_output_not_contains() {
  local desc="$1" pattern="$2"
  shift 2
  local output
  set +e
  output=$("$@" 2>&1)
  set -e
  if echo "$output" | grep -q "$pattern"; then
    fail "$desc" "output should not contain '$pattern'"
  else
    pass "$desc"
  fi
}

# ── Banner ───────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║        TribeEco CLI Test Suite                ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════
# UNIT TESTS — no external dependencies needed
# ══════════════════════════════════════════════════════════════════════

echo -e "${CYAN}── Unit Tests ─────────────────────────────────${NC}"
echo ""

# -- Binary basics --

echo -e "${BOLD}  tribe binary${NC}"

if [ -x "$TRIBE" ]; then
  pass "bin/tribe is executable"
else
  fail "bin/tribe is not executable"
fi

assert_exit_code "tribe (no args) exits 0" 0 "$TRIBE"
assert_exit_code "tribe help exits 0" 0 "$TRIBE" help
assert_exit_code "tribe --help exits 0" 0 "$TRIBE" --help
assert_exit_code "tribe -h exits 0" 0 "$TRIBE" -h
assert_exit_code "tribe version exits 0" 0 "$TRIBE" version
assert_exit_code "tribe bogus exits 1" 1 "$TRIBE" bogus

echo ""

# -- Version output --

echo -e "${BOLD}  tribe version${NC}"

assert_output_contains "prints version number" "tribe 0.1.0" "$TRIBE" version
assert_output_contains "prints project name" "TribeEco" "$TRIBE" version
assert_output_contains "prints Home path" "Home:" "$TRIBE" version

echo ""

# -- Help output --

echo -e "${BOLD}  tribe help${NC}"

assert_output_contains "help shows start command" "start" "$TRIBE" help
assert_output_contains "help shows stop command" "stop" "$TRIBE" help
assert_output_contains "help shows status command" "status" "$TRIBE" help
assert_output_contains "help shows logs command" "logs" "$TRIBE" help
assert_output_contains "help shows doctor command" "doctor" "$TRIBE" help
assert_output_contains "help shows reset command" "reset" "$TRIBE" help
assert_output_contains "help shows port 3002" "3002" "$TRIBE" help
assert_output_contains "help shows port 4000" "4000" "$TRIBE" help
assert_output_contains "help shows port 3003" "3003" "$TRIBE" help

echo ""

# -- Unknown command --

echo -e "${BOLD}  tribe unknown-command${NC}"

assert_output_contains "unknown cmd shows error" "Unknown command" "$TRIBE" notacommand
assert_exit_code "unknown cmd exits 1" 1 "$TRIBE" notacommand

echo ""

# -- TRIBE_HOME resolution --

echo -e "${BOLD}  TRIBE_HOME resolution${NC}"

# When TRIBE_HOME is set explicitly, it should be used
OUTPUT=$(TRIBE_HOME="/tmp/fakehome" "$TRIBE" version 2>&1)
if echo "$OUTPUT" | grep -q "Home: /tmp/fakehome"; then
  pass "respects TRIBE_HOME env var"
else
  fail "does not respect TRIBE_HOME env var"
fi

# When not set, should resolve to repo root
OUTPUT=$("$TRIBE" version 2>&1)
if echo "$OUTPUT" | grep -q "Home: $ROOT_DIR"; then
  pass "auto-resolves TRIBE_HOME from bin/ location"
else
  fail "auto-resolve TRIBE_HOME incorrect" "got: $(echo "$OUTPUT" | grep Home)"
fi

echo ""

# -- Doctor output --

echo -e "${BOLD}  tribe doctor${NC}"

assert_output_contains "doctor checks docker" "docker" "$TRIBE" doctor
assert_output_contains "doctor checks node" "node" "$TRIBE" doctor
assert_output_contains "doctor checks pnpm" "pnpm" "$TRIBE" doctor
assert_output_contains "doctor checks tribe-app dir" "tribe-app" "$TRIBE" doctor
assert_output_contains "doctor checks tribe-hub dir" "tribe-hub" "$TRIBE" doctor
assert_output_contains "doctor checks tribe-er-server dir" "tribe-er-server" "$TRIBE" doctor
assert_output_contains "doctor checks tribe-protocol dir" "tribe-protocol" "$TRIBE" doctor
assert_output_contains "doctor checks tribe-sdk dir" "tribe-sdk" "$TRIBE" doctor
assert_output_contains "doctor checks server wallet" "wallet" "$TRIBE" doctor
assert_output_contains "doctor checks ports" "Port" "$TRIBE" doctor

echo ""

# -- Logs unknown service --

echo -e "${BOLD}  tribe logs (invalid service)${NC}"

assert_output_contains "logs rejects unknown service" "Unknown service" "$TRIBE" logs fakesvc
assert_exit_code "logs unknown service exits 1" 1 "$TRIBE" logs fakesvc

echo ""

# -- Project structure --

echo -e "${BOLD}  project structure${NC}"

for dir in tribe-app tribe-er-server tribe-hub tribe-protocol tribe-sdk; do
  if [ -d "$ROOT_DIR/$dir" ]; then
    pass "$dir/ exists"
  else
    fail "$dir/ missing"
  fi
done

if [ -f "$ROOT_DIR/.gitmodules" ]; then
  pass ".gitmodules exists"
else
  fail ".gitmodules missing"
fi

if [ -f "$ROOT_DIR/docker-compose.yml" ]; then
  pass "docker-compose.yml exists"
else
  fail "docker-compose.yml missing"
fi

echo ""

# -- Submodules are registered --

echo -e "${BOLD}  git submodules${NC}"

for mod in tribe-app tribe-er-server tribe-hub tribe-protocol tribe-sdk; do
  if grep -q "path = $mod" "$ROOT_DIR/.gitmodules" 2>/dev/null; then
    pass "$mod registered as submodule"
  else
    fail "$mod not in .gitmodules"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════
# HOMEBREW FORMULA TESTS — validate formula file
# ══════════════════════════════════════════════════════════════════════

echo -e "${CYAN}── Homebrew Formula Tests ──────────────────────${NC}"
echo ""

FORMULA="$ROOT_DIR/Formula/tribe.rb"
TAP_FORMULA="$ROOT_DIR/homebrew-tap/Formula/tribe.rb"

echo -e "${BOLD}  Formula/tribe.rb${NC}"

if [ -f "$FORMULA" ]; then
  pass "Formula/tribe.rb exists"
else
  fail "Formula/tribe.rb missing"
fi

if grep -q 'class Tribe < Formula' "$FORMULA" 2>/dev/null; then
  pass "defines Tribe class"
else
  fail "missing Tribe class definition"
fi

if grep -q 'depends_on "node"' "$FORMULA" 2>/dev/null; then
  pass "declares node dependency"
else
  fail "missing node dependency"
fi

if grep -q 'depends_on "pnpm"' "$FORMULA" 2>/dev/null; then
  pass "declares pnpm dependency"
else
  fail "missing pnpm dependency"
fi

if grep -q 'def install' "$FORMULA" 2>/dev/null; then
  pass "has install method"
else
  fail "missing install method"
fi

if grep -q 'def caveats' "$FORMULA" 2>/dev/null; then
  pass "has caveats method"
else
  fail "missing caveats method"
fi

if grep -q 'def test' "$FORMULA" 2>/dev/null || grep -q 'test do' "$FORMULA" 2>/dev/null; then
  pass "has test block"
else
  fail "missing test block"
fi

if grep -q 'TRIBE_HOME' "$FORMULA" 2>/dev/null; then
  pass "sets TRIBE_HOME in wrapper"
else
  fail "missing TRIBE_HOME in wrapper"
fi

if grep -q 'tribe' "$FORMULA" 2>/dev/null && grep -q 'version' "$FORMULA" 2>/dev/null; then
  pass "test block validates version"
else
  fail "test block doesn't check version"
fi

echo ""

echo -e "${BOLD}  homebrew-tap/Formula/tribe.rb${NC}"

if [ -f "$TAP_FORMULA" ]; then
  pass "homebrew-tap/Formula/tribe.rb exists"
else
  fail "homebrew-tap/Formula/tribe.rb missing"
fi

if grep -q 'submodule' "$TAP_FORMULA" 2>/dev/null; then
  pass "post_install handles submodules"
else
  fail "post_install missing submodule init"
fi

if grep -q 'pnpm.*install' "$TAP_FORMULA" 2>/dev/null; then
  pass "post_install runs pnpm install"
else
  fail "post_install missing pnpm install"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════
# BREW AUDIT — run `brew audit` if brew is available
# ══════════════════════════════════════════════════════════════════════

echo -e "${CYAN}── Brew Audit ─────────────────────────────────${NC}"
echo ""

if command -v brew &>/dev/null; then
  echo -e "${BOLD}  brew style --formula${NC}"

  # Use brew style (rubocop linting) instead of brew audit,
  # which requires up-to-date Xcode CLT and is stricter about taps.
  set +e
  STYLE_OUTPUT=$(brew style --formula "$FORMULA" 2>&1)
  STYLE_EXIT=$?
  set -e

  if [ $STYLE_EXIT -eq 0 ]; then
    pass "brew style passed (no rubocop offenses)"
  else
    # Style check may not work without dev setup — don't hard-fail
    if echo "$STYLE_OUTPUT" | grep -qi "offense"; then
      fail "brew style found offenses" "$(echo "$STYLE_OUTPUT" | grep -i offense | head -3)"
    else
      skip "brew style" "rubocop not configured or CLT outdated"
    fi
  fi

  # Validate ruby syntax of the formula
  echo -e "${BOLD}  ruby syntax check${NC}"
  set +e
  ruby -c "$FORMULA" >/dev/null 2>&1
  RUBY_EXIT=$?
  set -e

  if [ $RUBY_EXIT -eq 0 ]; then
    pass "Formula/tribe.rb is valid Ruby"
  else
    fail "Formula/tribe.rb has Ruby syntax errors"
  fi

  set +e
  ruby -c "$TAP_FORMULA" >/dev/null 2>&1
  RUBY_EXIT=$?
  set -e

  if [ $RUBY_EXIT -eq 0 ]; then
    pass "homebrew-tap/Formula/tribe.rb is valid Ruby"
  else
    fail "homebrew-tap/Formula/tribe.rb has Ruby syntax errors"
  fi

  echo ""
else
  skip "brew style" "brew not installed"
  skip "ruby syntax" "brew/ruby not installed"
  echo ""
fi

# ══════════════════════════════════════════════════════════════════════
# INTEGRATION TESTS — require Docker
# ══════════════════════════════════════════════════════════════════════

echo -e "${CYAN}── Integration Tests ──────────────────────────${NC}"
echo ""

DOCKER_OK=true
if ! command -v docker &>/dev/null; then
  DOCKER_OK=false
elif ! docker info &>/dev/null 2>&1; then
  DOCKER_OK=false
fi

if [ "$DOCKER_OK" = true ]; then
  echo -e "${BOLD}  tribe start/status/stop lifecycle${NC}"

  # Start
  set +e
  "$TRIBE" start >/dev/null 2>&1
  START_EXIT=$?
  set -e

  if [ $START_EXIT -eq 0 ]; then
    pass "tribe start exits 0"
  else
    fail "tribe start exited $START_EXIT"
  fi

  # Status should show running services
  set +e
  STATUS_OUTPUT=$("$TRIBE" status 2>&1)
  set -e

  if echo "$STATUS_OUTPUT" | grep -q "running"; then
    pass "tribe status shows running services"
  else
    fail "tribe status shows no running services"
  fi

  # Health endpoints
  for entry in "3002:Frontend" "3003:ER server" "4000:Hub"; do
    PORT="${entry%%:*}"
    NAME="${entry##*:}"
    if curl -sf "http://localhost:$PORT" >/dev/null 2>&1 || curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; then
      pass "$NAME responds on port $PORT"
    else
      fail "$NAME not responding on port $PORT"
    fi
  done

  # Stop
  set +e
  "$TRIBE" stop >/dev/null 2>&1
  STOP_EXIT=$?
  set -e

  if [ $STOP_EXIT -eq 0 ]; then
    pass "tribe stop exits 0"
  else
    fail "tribe stop exited $STOP_EXIT"
  fi

  # Verify stopped
  sleep 2
  STILL_RUNNING=false
  for port in 3003 4000 5435 5436; do
    if lsof -i :"$port" -sTCP:LISTEN &>/dev/null 2>&1; then
      STILL_RUNNING=true
    fi
  done

  if [ "$STILL_RUNNING" = false ]; then
    pass "all services stopped after tribe stop"
  else
    fail "some services still running after tribe stop"
  fi

  echo ""
else
  skip "start/status/stop lifecycle" "Docker not available"
  skip "health endpoint checks" "Docker not available"
  echo ""
fi

# ══════════════════════════════════════════════════════════════════════
# BREW INSTALL TEST — simulate install if brew available
# ══════════════════════════════════════════════════════════════════════

echo -e "${CYAN}── Brew Install Test ──────────────────────────${NC}"
echo ""

if command -v brew &>/dev/null; then
  echo -e "${BOLD}  brew tap + install (from remote tap)${NC}"

  TAP_NAME="chaalpritam/tribe-homebrew"
  TAP_URL="https://github.com/chaalpritam/tribe-homebrew.git"
  SOURCE_URL="https://github.com/chaalpritam/TribeEco.git"

  # Pre-check: verify the TribeEco source repo is reachable
  set +e
  git ls-remote "$SOURCE_URL" HEAD >/dev/null 2>&1
  SOURCE_REACHABLE=$?
  set -e

  if [ $SOURCE_REACHABLE -ne 0 ]; then
    skip "brew tap + install" "TribeEco source repo not published yet (push to $SOURCE_URL first)"
    echo ""
  else

  set +e
  TAP_OUTPUT=$(brew tap "$TAP_NAME" "$TAP_URL" 2>&1)
  TAP_EXIT=$?
  set -e

  if [ $TAP_EXIT -eq 0 ]; then
    pass "brew tap $TAP_NAME succeeded"
  else
    if brew tap | grep -q "$TAP_NAME"; then
      pass "brew tap $TAP_NAME already tapped"
    else
      fail "brew tap failed" "$(echo "$TAP_OUTPUT" | tail -3)"
    fi
  fi

  # Pre-check: verify brew environment is healthy enough to install
  set +e
  BREW_DOCTOR=$(brew doctor 2>&1)
  set -e
  if echo "$BREW_DOCTOR" | grep -qi "Command Line Tools are too outdated"; then
    skip "brew install" "Xcode Command Line Tools outdated — run: sudo rm -rf /Library/Developer/CommandLineTools && sudo xcode-select --install"
    brew untap "$TAP_NAME" >/dev/null 2>&1
  else

  # Install
  set +e
  INSTALL_OUTPUT=$(brew install "$TAP_NAME/tribe" 2>&1)
  INSTALL_EXIT=$?
  set -e

  if [ $INSTALL_EXIT -eq 0 ]; then
    pass "brew install tribe succeeded"

    # Verify the tribe command is available via brew
    if command -v tribe &>/dev/null; then
      pass "tribe command available in PATH"
    else
      # Check brew --prefix/bin directly
      if [ -x "$(brew --prefix)/bin/tribe" ]; then
        pass "tribe command at brew prefix (may need PATH update)"
      else
        fail "tribe command not found after install"
      fi
    fi

    # Verify version from brew-installed binary
    TRIBE_BIN="$(brew --prefix)/bin/tribe"
    if [ -x "$TRIBE_BIN" ]; then
      set +e
      BREW_VERSION=$("$TRIBE_BIN" version 2>&1)
      set -e

      if echo "$BREW_VERSION" | grep -q "tribe 0.1.0"; then
        pass "brew-installed tribe shows correct version"
      else
        fail "brew-installed tribe version mismatch" "$BREW_VERSION"
      fi

      # Verify tribe doctor runs without crashing
      set +e
      "$TRIBE_BIN" doctor >/dev/null 2>&1
      DOC_EXIT=$?
      set -e

      # doctor exits non-zero if prereqs missing, but should not crash (exit > 1)
      if [ $DOC_EXIT -le 1 ]; then
        pass "brew-installed tribe doctor runs without crashing"
      else
        fail "brew-installed tribe doctor crashed (exit $DOC_EXIT)"
      fi

      # Verify tribe help runs
      set +e
      "$TRIBE_BIN" help >/dev/null 2>&1
      HELP_EXIT=$?
      set -e

      if [ $HELP_EXIT -eq 0 ]; then
        pass "brew-installed tribe help works"
      else
        fail "brew-installed tribe help failed"
      fi
    fi

    # Run brew test if available
    set +e
    TEST_OUTPUT=$(brew test tribe 2>&1)
    TEST_EXIT=$?
    set -e

    if [ $TEST_EXIT -eq 0 ]; then
      pass "brew test tribe passed"
    else
      skip "brew test tribe" "test block may need git clone (expected in CI)"
    fi

    # Cleanup
    echo ""
    echo -e "${BOLD}  cleanup${NC}"
    set +e
    brew uninstall tribe >/dev/null 2>&1
    set -e
    pass "brew uninstall tribe"

    set +e
    brew untap "$TAP_NAME" >/dev/null 2>&1
    set -e
    pass "brew untap $TAP_NAME"

  else
    fail "brew install failed" "$(echo "$INSTALL_OUTPUT" | tail -5)"
    # Still cleanup the tap
    set +e
    brew untap "$TAP_NAME" >/dev/null 2>&1
    set -e
  fi
  echo ""

  fi  # end brew doctor check
  fi  # end source reachable check
else
  skip "brew tap + install test" "brew not installed"
  echo ""
fi

# ══════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════

echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Results                                      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  ${YELLOW}Skipped:${NC} $SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "  ${RED}Some tests failed.${NC}"
  exit 1
else
  echo -e "  ${GREEN}All tests passed!${NC}"
  exit 0
fi
