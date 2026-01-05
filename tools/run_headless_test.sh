#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  tools/run_headless_test.sh <scene> [name] [timeout_seconds]

Examples:
  tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 30
  tools/run_headless_test.sh res://ui/scenes/tests/replay_test.tscn ReplayTest 20

Notes:
  - macOS default bash has no `timeout`; this script enforces a hard timeout.
  - Writes logs to .godot/<name>.log and sets HOME to .tmp_home to avoid user:// issues.
EOF
}

SCENE="${1:-}"
NAME="${2:-}"
TIMEOUT_SECONDS="${3:-${TIMEOUT_SECONDS:-30}}"

if [[ -z "$SCENE" ]]; then
	usage
	exit 2
fi

if [[ -z "$NAME" ]]; then
	NAME="$(basename "$SCENE")"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"

HOME_DIR="$PROJECT_PATH/.tmp_home"
LOG_DIR="$PROJECT_PATH/.godot"
LOG_FILE="$LOG_DIR/${NAME}.log"

mkdir -p "$HOME_DIR" "$LOG_DIR"
: > "$LOG_FILE"

echo "[$NAME] START scene=$SCENE timeout=${TIMEOUT_SECONDS}s log=$LOG_FILE"

HOME="$HOME_DIR" godot --headless \
	--path "$PROJECT_PATH" \
	--scene "$SCENE" -- --autorun >"$LOG_FILE" 2>&1 &

PID=$!

check_log_for_script_errors() {
	local log_file="$1"
	if [[ ! -f "$log_file" ]]; then
		return 0
	fi
	if grep -qE '^SCRIPT ERROR:' "$log_file"; then
		local count
		count="$(grep -cE '^SCRIPT ERROR:' "$log_file" || true)"
		echo "[$NAME] FAIL detected ${count:-1} script error(s) in log"
		echo "[$NAME] LOG EXCERPT (first 40 SCRIPT ERROR lines)"
		grep -nE '^SCRIPT ERROR:' "$log_file" | head -n 40 || true
		echo "[$NAME] LOG TAIL (last 120 lines)"
		tail -n 120 "$log_file" 2>/dev/null || true
		return 1
	fi
	return 0
}

detect_log_outcome() {
	local log_file="$1"
	if [[ ! -f "$log_file" ]]; then
		return 2
	fi

	if grep -qE "^\\[$NAME\\] FAIL" "$log_file"; then
		return 1
	fi

	if grep -qE "^\\[$NAME\\] SUMMARY" "$log_file"; then
		local line
		line="$(grep -E "^\\[$NAME\\] SUMMARY" "$log_file" | tail -n 1 || true)"
		if [[ "$line" == *"failed=[]"* ]]; then
			return 0
		fi
		return 1
	fi

	if grep -qE "^\\[$NAME\\] PASS" "$log_file"; then
		return 0
	fi

	return 2
}

for ((elapsed=0; elapsed<TIMEOUT_SECONDS; elapsed++)); do
	if ! kill -0 "$PID" 2>/dev/null; then
		if wait "$PID"; then
			code=0
		else
			code=$?
		fi
		if ! check_log_for_script_errors "$LOG_FILE"; then
			exit 1
		fi

		outcome=2
		# 等待日志刷盘：部分平台在进程退出后，log-file 的最后几行可能延迟写入。
		for ((i=0; i<50; i++)); do
			if detect_log_outcome "$LOG_FILE"; then
				outcome=0
				break
			fi
			result=$?
			if [[ $result -eq 1 ]]; then
				outcome=1
				break
			fi
			sleep 0.2
		done

		if [[ $outcome -eq 0 ]]; then
			if [[ $code -ne 0 ]]; then
				echo "[$NAME] WARN godot_exit_code=$code but log indicates PASS; treating as success"
			fi
			exit 0
		fi
		if [[ $outcome -eq 1 ]]; then
			echo "[$NAME] FAIL detected in log"
			echo "[$NAME] LOG EXCERPT (first 40 FAIL lines)"
			grep -nE "^\\[$NAME\\] FAIL" "$LOG_FILE" | head -n 40 || true
			echo "[$NAME] LOG TAIL (last 120 lines)"
			tail -n 120 "$LOG_FILE" 2>/dev/null || true
			exit 1
		fi

		# 兜底：如果日志最终已经写出 SUMMARY 且 failed=[]，则强制视为成功。
		# （macOS 上偶现进程退出后 log-file 尾部延迟写入，导致短轮询未命中）
		if detect_log_outcome "$LOG_FILE"; then
			if [[ $code -ne 0 ]]; then
				echo "[$NAME] WARN godot_exit_code=$code but log indicates PASS; treating as success"
			fi
			exit 0
		fi

		exit "$code"
	fi
	sleep 1
done

echo "[$NAME] TIMEOUT after ${TIMEOUT_SECONDS}s"
kill "$PID" 2>/dev/null || true
sleep 1
kill -9 "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

echo "[$NAME] LOG TAIL (last 120 lines)"
tail -n 120 "$LOG_FILE" 2>/dev/null || true

exit 124
