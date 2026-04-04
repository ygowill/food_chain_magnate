#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  bash tools/run_online_regression_suite.sh

Description:
  Runs a fast local regression suite for online resume / reconnect / quit flows.
  It first runs GameSmokeTest, then runs the focused online regression suite.

Environment:
  GODOT_BIN   Override Godot binary path (default: godot)

Examples:
  GODOT_BIN="/Applications/Godot.app/Contents/MacOS/godot" bash tools/run_online_regression_suite.sh
  PATH="/Applications/Godot.app/Contents/MacOS:$PATH" bash tools/run_online_regression_suite.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
HOME_DIR="$PROJECT_PATH/.tmp_home"
LOG_DIR="$PROJECT_PATH/.godot"
SUITE_LOG="$LOG_DIR/OnlineRegressionSuite.log"
STDOUT_LOG="$LOG_DIR/OnlineRegressionSuite.stdout.log"

mkdir -p "$HOME_DIR" "$LOG_DIR"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "[OnlineRegressionSuite] FAIL Godot binary not found: $GODOT_BIN" >&2
	echo "Use GODOT_BIN=/absolute/path/to/godot or add Godot to PATH." >&2
	exit 127
fi

echo "[OnlineRegressionSuite] STEP GameSmokeTest"
"$PROJECT_PATH/tools/run_headless_test.sh" res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 120

echo "[OnlineRegressionSuite] STEP FocusedOnlineSuite"
: > "$SUITE_LOG"
: > "$STDOUT_LOG"
set +e
HOME="$HOME_DIR" "$GODOT_BIN" --headless \
	--log-file "$SUITE_LOG" \
	--path "$PROJECT_PATH" \
	--script res://tools/run_online_regression_suite.gd 2>&1 | tee "$STDOUT_LOG"
godot_status=${PIPESTATUS[0]}
set -e

if grep -qE '^SCRIPT ERROR:' "$STDOUT_LOG" || grep -qE '^SCRIPT ERROR:' "$SUITE_LOG"; then
	echo "[OnlineRegressionSuite] FAIL script error detected" >&2
	exit 1
fi

summary_line="$(grep -E '^\[OnlineRegressionSuite\] SUMMARY' "$STDOUT_LOG" | tail -n 1 || true)"
if [[ -z "$summary_line" ]]; then
	echo "[OnlineRegressionSuite] FAIL missing summary output" >&2
	exit 1
fi
if [[ "$summary_line" != *"failed=[]"* ]]; then
	echo "[OnlineRegressionSuite] FAIL suite reported failures" >&2
	exit 1
fi
if [[ $godot_status -ne 0 ]]; then
	echo "[OnlineRegressionSuite] FAIL godot_exit_code=$godot_status" >&2
	exit "$godot_status"
fi

echo "[OnlineRegressionSuite] DONE log=$SUITE_LOG stdout=$STDOUT_LOG"
