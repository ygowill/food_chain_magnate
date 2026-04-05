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
GODOT_BIN="${GODOT_BIN:-godot}"

HOME_DIR="$PROJECT_PATH/.tmp_home"
LOG_DIR="$PROJECT_PATH/.godot"
LOG_FILE="$LOG_DIR/${NAME}.log"

mkdir -p "$HOME_DIR" "$LOG_DIR"

# Godot 会缓存 `class_name` 全局类名到项目内的 `.godot/global_script_class_cache.cfg`。
# 当脚本被移动/删除（例如从 core 迁移到 modules）时，该缓存可能残留旧路径，导致：
# - "Class X hides a global script class"
# - 无法解析 type hints（例如 Result）
# 进而让 headless 测试全部失败。
#
# 这里做一次轻量自检：若缓存缺失或包含不存在的脚本路径，则用 headless editor 预热刷新缓存。
CACHE_FILE="$LOG_DIR/global_script_class_cache.cfg"
PREFLIGHT_LOG="$LOG_DIR/_preflight.log"
needs_cache_refresh=0
if [[ ! -f "$CACHE_FILE" ]]; then
	needs_cache_refresh=1
else
	# 检查缓存中引用的脚本路径是否都存在（只要发现 1 个不存在，就触发刷新）
	while IFS= read -r line; do
		path="${line#*\"path\": \"}"
		path="${path%\"*}"
		local_path="${path#res://}"
		if [[ -n "$local_path" && ! -f "$PROJECT_PATH/$local_path" ]]; then
			needs_cache_refresh=1
			break
		fi
	done < <(grep -E '\"path\": \"res://' "$CACHE_FILE" 2>/dev/null || true)
fi

if [[ "$GODOT_BIN" == */* ]]; then
	if [[ ! -x "$GODOT_BIN" ]]; then
		echo "[$NAME] FAIL Godot binary not executable: $GODOT_BIN"
		exit 127
	fi
elif ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "[$NAME] FAIL Godot binary not found: $GODOT_BIN"
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

if [[ $needs_cache_refresh -eq 1 ]]; then
	: > "$PREFLIGHT_LOG"
	echo "[$NAME] INFO refreshing Godot global script class cache"
	HOME="$HOME_DIR" "$GODOT_BIN" --headless --editor --quit \
		--path "$PROJECT_PATH" --log-file "$PREFLIGHT_LOG" >/dev/null 2>&1 || {
			if can_treat_nonzero_as_success "$PREFLIGHT_LOG"; then
				echo "[$NAME] WARN cache refresh exited nonzero with benign shutdown leak warnings; continuing"
			else
				echo "[$NAME] FAIL cache refresh failed"
				echo "[$NAME] LOG TAIL (last 120 lines)"
				tail -n 120 "$PREFLIGHT_LOG" 2>/dev/null || true
				exit 1
			fi
		}
fi

# Godot runtime loads imported resources from `.godot/imported/*.ctex`. When new `.import` metadata files
# are added to the repo (e.g. new product icons), the corresponding `.ctex` may be missing in fresh
# checkouts, causing `load("res://...png")` to fail in headless tests. Ensure imports are up to date.
IMPORT_LOG="$LOG_DIR/_import.log"
needs_import=0
missing_import_path=""
while IFS= read -r line; do
	# line format: <file>.import:path="res://.godot/imported/<hash>.ctex"
	import_path="${line#*path=\"}"
	import_path="${import_path%\"*}"
	local_path="${import_path#res://}"
	if [[ -n "$local_path" && ! -f "$PROJECT_PATH/$local_path" ]]; then
		needs_import=1
		missing_import_path="$import_path"
		break
	fi
done < <(grep -R --line-number '^path="res://.godot/imported/' "$PROJECT_PATH" \
	--include='*.import' --exclude-dir='.godot' --exclude-dir='.tmp_home' 2>/dev/null || true)

if [[ $needs_import -eq 1 ]]; then
	: > "$IMPORT_LOG"
	echo "[$NAME] INFO importing project assets (missing: ${missing_import_path:-unknown})"
	HOME="$HOME_DIR" "$GODOT_BIN" --headless --import --path "$PROJECT_PATH" --log-file "$IMPORT_LOG" >/dev/null 2>&1 || {
		if can_treat_nonzero_as_success "$IMPORT_LOG"; then
			echo "[$NAME] WARN import exited nonzero with benign shutdown leak warnings; continuing"
		else
			echo "[$NAME] FAIL import failed"
			echo "[$NAME] LOG TAIL (last 120 lines)"
			tail -n 120 "$IMPORT_LOG" 2>/dev/null || true
			exit 1
		fi
	}
fi

: > "$LOG_FILE"

echo "[$NAME] START scene=$SCENE timeout=${TIMEOUT_SECONDS}s log=$LOG_FILE"

nohup env HOME="$HOME_DIR" "$GODOT_BIN" --headless \
	--path "$PROJECT_PATH" \
	--scene "$SCENE" -- --autorun >"$LOG_FILE" 2>&1 </dev/null &

PID=$!

check_log_for_script_errors() {
	local log_file="$1"
	if [[ ! -f "$log_file" ]]; then
		return 0
	fi
	if has_script_errors "$log_file"; then
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
	if detect_log_outcome "$LOG_FILE"; then
		if ! check_log_for_script_errors "$LOG_FILE"; then
			kill "$PID" 2>/dev/null || true
			sleep 1
			kill -9 "$PID" 2>/dev/null || true
			wait "$PID" 2>/dev/null || true
			exit 1
		fi
		if kill -0 "$PID" 2>/dev/null; then
			kill "$PID" 2>/dev/null || true
			sleep 1
			kill -9 "$PID" 2>/dev/null || true
			wait "$PID" 2>/dev/null || true
			echo "[$NAME] WARN log indicates PASS before godot exited; terminating process"
		fi
		exit 0
	fi
	result=$?
	if [[ $result -eq 1 ]]; then
		kill "$PID" 2>/dev/null || true
		sleep 1
		kill -9 "$PID" 2>/dev/null || true
		wait "$PID" 2>/dev/null || true
		echo "[$NAME] FAIL detected in log"
		echo "[$NAME] LOG EXCERPT (first 40 FAIL lines)"
		grep -nE "^\\[$NAME\\] FAIL" "$LOG_FILE" | head -n 40 || true
		echo "[$NAME] LOG TAIL (last 120 lines)"
		tail -n 120 "$LOG_FILE" 2>/dev/null || true
		exit 1
	fi

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

		if [[ $code -ne 0 ]] && can_treat_nonzero_as_success "$LOG_FILE"; then
			echo "[$NAME] WARN godot_exit_code=$code with benign shutdown leak warnings; treating as success"
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
