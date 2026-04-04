#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  bash tools/run_local_online_server.sh [--port 7000] [--bind 127.0.0.1]

Description:
  Starts the local Godot dedicated online server for manual browser testing.
  This is useful for validating reconnect / surrender / room cleanup flows
  without rebuilding and deploying the production server.

Environment:
  GODOT_BIN             Override Godot binary path (default: godot)
  PLATFORM_BACKEND_URL  Backend base URL used by the dedicated server
                        (default: http://127.0.0.1:8000)
  INTERNAL_API_SECRET   Internal backend secret
                        (default: dev-internal-secret-change-in-production)
  HMAC_SECRET           Connect-token signing secret
                        (default: local-dev-secret)
  GAME_SERVER_ID        Stable game server id for local testing
                        (default: local-manual)
  GAME_SERVER_WS_URL    Optional externally visible ws:// URL override

Examples:
  PATH="/Applications/Godot.app/Contents/MacOS:$PATH" bash tools/run_local_online_server.sh
  GODOT_BIN="/Applications/Godot.app/Contents/MacOS/godot" \
  PLATFORM_BACKEND_URL="https://your-backend.example.com" \
  GAME_SERVER_WS_URL="ws://127.0.0.1:7000" \
  bash tools/run_local_online_server.sh --port 7000
EOF
}

PORT=7000
BIND="127.0.0.1"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--port)
			PORT="${2:?missing value for --port}"
			shift 2
			;;
		--bind)
			BIND="${2:?missing value for --bind}"
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
GODOT_BIN="${GODOT_BIN:-godot}"
HOME_DIR="$PROJECT_PATH/.tmp_home_local_server"
LOG_DIR="$PROJECT_PATH/.godot"
LOG_FILE="$LOG_DIR/LocalOnlineServer.log"

PLATFORM_BACKEND_URL="${PLATFORM_BACKEND_URL:-http://127.0.0.1:8000}"
INTERNAL_API_SECRET="${INTERNAL_API_SECRET:-dev-internal-secret-change-in-production}"
HMAC_SECRET="${HMAC_SECRET:-local-dev-secret}"
GAME_SERVER_ID="${GAME_SERVER_ID:-local-manual}"
PUBLIC_HOST="$BIND"
if [[ -z "$PUBLIC_HOST" || "$PUBLIC_HOST" == "0.0.0.0" || "$PUBLIC_HOST" == "::" || "$PUBLIC_HOST" == "*" ]]; then
	PUBLIC_HOST="127.0.0.1"
fi
GAME_SERVER_WS_URL="${GAME_SERVER_WS_URL:-ws://$PUBLIC_HOST:$PORT}"

mkdir -p "$HOME_DIR" "$LOG_DIR"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
	echo "[LocalOnlineServer] FAIL Godot binary not found: $GODOT_BIN" >&2
	echo "Use GODOT_BIN=/absolute/path/to/godot or add Godot to PATH." >&2
	exit 127
fi

echo "[LocalOnlineServer] START port=$PORT bind=$BIND"
echo "[LocalOnlineServer] backend=$PLATFORM_BACKEND_URL"
echo "[LocalOnlineServer] public_ws=$GAME_SERVER_WS_URL"
echo "[LocalOnlineServer] log=$LOG_FILE"

HOME="$HOME_DIR" \
PLATFORM_BACKEND_URL="$PLATFORM_BACKEND_URL" \
INTERNAL_API_SECRET="$INTERNAL_API_SECRET" \
HMAC_SECRET="$HMAC_SECRET" \
GAME_SERVER_ID="$GAME_SERVER_ID" \
GAME_SERVER_WS_URL="$GAME_SERVER_WS_URL" \
"$GODOT_BIN" --headless \
	--log-file "$LOG_FILE" \
	--path "$PROJECT_PATH" \
	--scene res://server/dedicated_server.tscn -- \
	--port="$PORT" \
	--bind="$BIND"
