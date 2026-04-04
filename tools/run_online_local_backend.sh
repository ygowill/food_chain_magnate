#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  bash tools/run_online_local_backend.sh [--host 127.0.0.1] [--port 8000]

Description:
  Starts the local FastAPI platform backend with defaults aligned to the
  local dedicated server and portal helper scripts.

Environment:
  PYTHON_BIN           Override Python binary (default: backend/.venv/bin/python)
  DATABASE_URL         SQLAlchemy database URL
                       (default: sqlite+aiosqlite:///./fcm_local_dev.db)
  HMAC_SECRET          Connect-token signing secret (default: local-dev-secret)
  INTERNAL_API_SECRET  Internal backend secret
                       (default: dev-internal-secret-change-in-production)
  DEFAULT_WS_URL       Public game server ws:// URL (default: ws://127.0.0.1:7000)
  WEB_ORIGIN           Allowed portal origin (default: http://127.0.0.1:5173)

Examples:
  bash tools/run_online_local_backend.sh
  PYTHON_BIN="backend/.venv/bin/python" bash tools/run_online_local_backend.sh --port 8010
EOF
}

HOST="127.0.0.1"
PORT="8000"

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
BACKEND_PATH="$PROJECT_PATH/backend"
PYTHON_BIN="${PYTHON_BIN:-$BACKEND_PATH/.venv/bin/python}"
DATABASE_URL="${DATABASE_URL:-sqlite+aiosqlite:///./fcm_local_dev.db}"
HMAC_SECRET="${HMAC_SECRET:-local-dev-secret}"
INTERNAL_API_SECRET="${INTERNAL_API_SECRET:-dev-internal-secret-change-in-production}"
DEFAULT_WS_URL="${DEFAULT_WS_URL:-ws://127.0.0.1:7000}"
WEB_ORIGIN="${WEB_ORIGIN:-http://127.0.0.1:5173}"

if [[ ! -x "$PYTHON_BIN" ]]; then
	echo "[OnlineLocalBackend] FAIL Python binary not found: $PYTHON_BIN" >&2
	echo "Create backend/.venv first or pass PYTHON_BIN=/absolute/path/to/python." >&2
	exit 127
fi

echo "[OnlineLocalBackend] START host=$HOST port=$PORT"
echo "[OnlineLocalBackend] ws_url=$DEFAULT_WS_URL web_origin=$WEB_ORIGIN"
echo "[OnlineLocalBackend] database=$DATABASE_URL"

cd "$BACKEND_PATH"
DATABASE_URL="$DATABASE_URL" \
HMAC_SECRET="$HMAC_SECRET" \
INTERNAL_API_SECRET="$INTERNAL_API_SECRET" \
DEFAULT_WS_URL="$DEFAULT_WS_URL" \
WEB_ORIGIN="$WEB_ORIGIN" \
exec "$PYTHON_BIN" -m uvicorn app.main:app --host "$HOST" --port "$PORT"
