#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  tools/run_headless_script.sh <script> [script_args...]

Examples:
  tools/run_headless_script.sh res://tools/check_compile.gd
  tools/run_headless_script.sh res://tools/check_compile.gd res://server res://core/tests
EOF
}

SCRIPT_PATH="${1:-}"
if [[ -z "$SCRIPT_PATH" ]]; then
	usage
	exit 2
fi
shift || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"

HOME_DIR="$PROJECT_PATH/.tmp_home"
LOG_DIR="$PROJECT_PATH/.godot"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_NAME="${SCRIPT_NAME%.gd}"
PREFLIGHT_LOG="$LOG_DIR/${SCRIPT_NAME}_preflight.log"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME}.log"

mkdir -p "$HOME_DIR" "$LOG_DIR"

if [[ "$GODOT_BIN" == */* ]]; then
	if [[ ! -x "$GODOT_BIN" ]]; then
		echo "[$SCRIPT_NAME] FAIL Godot binary not executable: $GODOT_BIN"
		exit 127
	fi
elif ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "[$SCRIPT_NAME] FAIL Godot binary not found: $GODOT_BIN"
	exit 127
fi

has_script_errors() {
	local log_file="$1"
	[[ -f "$log_file" ]] || return 1
	grep -qE '^SCRIPT ERROR:' "$log_file"
}

has_known_benign_shutdown_errors() {
	local log_file="$1"
	[[ -f "$log_file" ]] || return 1
	grep -qE '^WARNING: ObjectDB instances leaked at exit|^WARNING: [0-9]+ RIDs? of type .* were leaked\.|^ERROR: [0-9]+ resources still in use at exit\.|^ERROR: [0-9]+ RID allocations? of type .* were leaked at exit\.|^ERROR: Condition "ret != noErr" is true\. Returning: ""' "$log_file"
}

has_unexpected_error_lines() {
	local log_file="$1"
	[[ -f "$log_file" ]] || return 1
	grep -E '^ERROR:' "$log_file" | grep -vqE '^ERROR: ([0-9]+ resources still in use at exit\.|[0-9]+ RID allocations? of type .* were leaked at exit\.|Condition "ret != noErr" is true\. Returning: "")$'
}

can_treat_nonzero_as_success() {
	local log_file="$1"
	[[ -f "$log_file" ]] || return 1
	if has_script_errors "$log_file"; then
		return 1
	fi
	if has_unexpected_error_lines "$log_file"; then
		return 1
	fi
	has_known_benign_shutdown_errors "$log_file"
}

: > "$PREFLIGHT_LOG"
echo "[$SCRIPT_NAME] INFO importing project and refreshing Godot caches"
HOME="$HOME_DIR" "$GODOT_BIN" --headless --import --quit \
	--path "$PROJECT_PATH" --log-file "$PREFLIGHT_LOG" >/dev/null 2>&1 || {
		if can_treat_nonzero_as_success "$PREFLIGHT_LOG"; then
			echo "[$SCRIPT_NAME] WARN preflight exited nonzero with benign shutdown leak warnings; continuing"
		else
			echo "[$SCRIPT_NAME] FAIL preflight import failed"
			echo "[$SCRIPT_NAME] LOG TAIL (last 120 lines)"
			tail -n 120 "$PREFLIGHT_LOG" 2>/dev/null || true
			exit 1
		fi
	}

: > "$LOG_FILE"
HOME="$HOME_DIR" "$GODOT_BIN" --headless \
	--log-file "$LOG_FILE" \
	--path "$PROJECT_PATH" \
	--script "$SCRIPT_PATH" -- "$@"
