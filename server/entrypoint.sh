#!/bin/sh
set -eu

PROJECT_PATH="/app"

PORT="${PORT:-7000}"
BIND="${BIND:-0.0.0.0}"

# Ensure `user://` is writable/deterministic and import the project once so
# `class_name` type hints work on first headless boot.
HOME_DIR="${PROJECT_PATH}/.tmp_home"
LOG_DIR="${PROJECT_PATH}/.godot"
CACHE_FILE="${LOG_DIR}/global_script_class_cache.cfg"
PREFLIGHT_LOG="${LOG_DIR}/_preflight.log"

mkdir -p "${HOME_DIR}" "${LOG_DIR}"

if [ ! -f "${CACHE_FILE}" ]; then
	: > "${PREFLIGHT_LOG}"
	HOME="${HOME_DIR}" godot --headless --import --quit \
		--path "${PROJECT_PATH}" --log-file "${PREFLIGHT_LOG}" >/dev/null 2>&1 || {
			echo "[entrypoint] preflight import failed; log tail:" >&2
			tail -n 200 "${PREFLIGHT_LOG}" 2>/dev/null || true
			exit 1
		}
fi

HOME="${HOME_DIR}" exec godot --headless \
	--path "${PROJECT_PATH}" \
	--scene res://server/dedicated_server.tscn -- \
	"--port=${PORT}" \
	"--bind=${BIND}" \
	"$@"
