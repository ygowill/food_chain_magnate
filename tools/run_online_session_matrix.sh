#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  bash tools/run_online_session_matrix.sh
  bash tools/run_online_session_matrix.sh --group resync
  bash tools/run_online_session_matrix.sh --group lobby,ingame
  bash tools/run_online_session_matrix.sh --list

Description:
  Runs a scenario-oriented local validation matrix for online session flows.
  Use this before a full build/deploy to quickly verify reconnect, leave,
  surrender, room cleanup, delta/snapshot restore, and persistence scenarios.

Environment:
  GODOT_BIN   Override Godot binary path (default: godot)

Examples:
  GODOT_BIN="/Applications/Godot.app/Contents/MacOS/godot" bash tools/run_online_session_matrix.sh
  GODOT_BIN="/Applications/Godot.app/Contents/MacOS/godot" bash tools/run_online_session_matrix.sh --group resync
EOF
}

SELECTED_GROUPS=""
LIST_ONLY=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		--group)
			SELECTED_GROUPS="${2:?missing value for --group}"
			shift 2
			;;
		--group=*)
			SELECTED_GROUPS="${1#*=}"
			shift
			;;
		--list)
			LIST_ONLY=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
HOME_DIR="$PROJECT_PATH/.tmp_home"
LOG_DIR="$PROJECT_PATH/.godot"
MATRIX_LOG="$LOG_DIR/OnlineSessionMatrix.log"
STDOUT_LOG="$LOG_DIR/OnlineSessionMatrix.stdout.log"

mkdir -p "$HOME_DIR" "$LOG_DIR"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "[OnlineSessionMatrix] FAIL Godot binary not found: $GODOT_BIN" >&2
	echo "Use GODOT_BIN=/absolute/path/to/godot or add Godot to PATH." >&2
	exit 127
fi

cmd=(
	"$GODOT_BIN" --headless
	--log-file "$MATRIX_LOG"
	--path "$PROJECT_PATH"
	--script res://tools/run_online_session_matrix.gd
)

if [[ $LIST_ONLY -eq 1 || -n "$SELECTED_GROUPS" ]]; then
	cmd+=( -- )
	if [[ $LIST_ONLY -eq 1 ]]; then
		cmd+=( --list )
	fi
	if [[ -n "$SELECTED_GROUPS" ]]; then
		cmd+=( "--group=$SELECTED_GROUPS" )
	fi
fi

: > "$MATRIX_LOG"
: > "$STDOUT_LOG"
set +e
HOME="$HOME_DIR" "${cmd[@]}" 2>&1 | tee "$STDOUT_LOG"
godot_status=${PIPESTATUS[0]}
set -e

if grep -qE '^SCRIPT ERROR:' "$STDOUT_LOG" || grep -qE '^SCRIPT ERROR:' "$MATRIX_LOG"; then
	echo "[OnlineSessionMatrix] FAIL script error detected" >&2
	exit 1
fi

if [[ $LIST_ONLY -eq 1 ]]; then
	exit "$godot_status"
fi

summary_line="$(grep -E '^\[OnlineSessionMatrix\] SUMMARY' "$STDOUT_LOG" | tail -n 1 || true)"
if [[ -z "$summary_line" ]]; then
	echo "[OnlineSessionMatrix] FAIL missing summary output" >&2
	exit 1
fi
if [[ "$summary_line" != *"failed=[]"* ]]; then
	echo "[OnlineSessionMatrix] FAIL matrix reported failures" >&2
	exit 1
fi
if [[ $godot_status -ne 0 ]]; then
	echo "[OnlineSessionMatrix] FAIL godot_exit_code=$godot_status" >&2
	exit "$godot_status"
fi

echo "[OnlineSessionMatrix] DONE log=$MATRIX_LOG stdout=$STDOUT_LOG"
