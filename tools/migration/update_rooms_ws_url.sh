#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  tools/migration/update_rooms_ws_url.sh \
    --new-url <ws://...|wss://...> \
    [--old-url <url>]... \
    [--db-container fcm-db] \
    [--db-user fcm] \
    [--db-name fcm]

Examples:
  # Default migration target (old localhost URLs -> new public wss URL)
  tools/migration/update_rooms_ws_url.sh \
    --new-url "wss://game.example.com/ws"

  # Migrate multiple old URLs in one run
  tools/migration/update_rooms_ws_url.sh \
    --new-url "wss://game.example.com/ws" \
    --old-url "ws://localhost:7000" \
    --old-url "wss://ws.game.example.com"
EOF
}

db_container="${DB_CONTAINER:-fcm-db}"
db_user="${FCM_DB_USER:-fcm}"
db_name="${FCM_DB_NAME:-fcm}"
new_url=""
old_urls=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
		--new-url)
			new_url="${2:-}"
			shift 2
			;;
		--old-url)
			old_urls+=("${2:-}")
			shift 2
			;;
		--db-container)
			db_container="${2:-}"
			shift 2
			;;
		--db-user)
			db_user="${2:-}"
			shift 2
			;;
		--db-name)
			db_name="${2:-}"
			shift 2
			;;
		*)
			echo "Unknown arg: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

if [[ -z "${new_url}" ]]; then
	echo "ERROR: --new-url is required" >&2
	exit 2
fi

if [[ "${#old_urls[@]}" -eq 0 ]]; then
	old_urls=("ws://localhost:7000")
fi

if ! command -v docker >/dev/null 2>&1; then
	echo "ERROR: docker not found in PATH" >&2
	exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -Fxq "${db_container}"; then
	echo "ERROR: db container not running: ${db_container}" >&2
	exit 1
fi

sql_escape() {
	printf "%s" "$1" | sed "s/'/''/g"
}

build_sql_in_list() {
	local out=""
	local first=1
	local item
	for item in "$@"; do
		local escaped
		escaped="$(sql_escape "${item}")"
		if [[ ${first} -eq 1 ]]; then
			out="'${escaped}'"
			first=0
		else
			out="${out}, '${escaped}'"
		fi
	done
	printf "%s" "${out}"
}

new_url_sql="$(sql_escape "${new_url}")"
old_in_list="$(build_sql_in_list "${old_urls[@]}")"

sql="UPDATE rooms SET ws_url='${new_url_sql}' WHERE ws_url IN (${old_in_list});"

echo "[migration] db_container=${db_container} db=${db_name} user=${db_user}"
echo "[migration] new_url=${new_url}"
echo "[migration] old_urls=${old_urls[*]}"
echo "[migration] executing update..."

docker exec "${db_container}" psql -U "${db_user}" -d "${db_name}" -v ON_ERROR_STOP=1 -c "${sql}"
docker exec "${db_container}" psql -U "${db_user}" -d "${db_name}" -c "SELECT room_code, ws_url, status, created_at FROM rooms ORDER BY created_at DESC LIMIT 20;"

echo "[migration] done."
