#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  bash tools/run_online_local_portal.sh [--host 127.0.0.1] [--port 5173]

Description:
  Starts the local Vite portal used for browser-based online manual testing.

Environment:
  NPM_BIN  Override npm binary (default: npm)

Examples:
  bash tools/run_online_local_portal.sh
  NPM_BIN="$HOME/.nvm/versions/node/current/bin/npm" bash tools/run_online_local_portal.sh --port 4173
EOF
}

HOST="127.0.0.1"
PORT="5173"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--host)
			HOST="${2:?missing value for --host}"
			shift 2
			;;
		--port)
			PORT="${2:?missing value for --port}"
			shift 2
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
PORTAL_PATH="$PROJECT_PATH/web/portal"
NPM_BIN="${NPM_BIN:-npm}"
NPM_DIR=""
if [[ "$NPM_BIN" == */* ]]; then
	NPM_DIR="$(cd "$(dirname "$NPM_BIN")" && pwd)"
fi

if ! command -v "$NPM_BIN" >/dev/null 2>&1; then
	echo "[OnlineLocalPortal] FAIL npm not found: $NPM_BIN" >&2
	echo "Install Node.js or pass NPM_BIN=/absolute/path/to/npm." >&2
	exit 127
fi
if [[ -n "$NPM_DIR" ]]; then
	export PATH="$NPM_DIR:$PATH"
fi
if ! command -v node >/dev/null 2>&1; then
	echo "[OnlineLocalPortal] FAIL node not found on PATH" >&2
	echo "Install Node.js or pass NPM_BIN from a directory that also contains node." >&2
	exit 127
fi

echo "[OnlineLocalPortal] START host=$HOST port=$PORT"

cd "$PORTAL_PATH"
exec "$NPM_BIN" run dev -- --host "$HOST" --port "$PORT"
