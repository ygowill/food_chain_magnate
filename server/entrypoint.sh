#!/bin/sh
set -eu

PORT="${PORT:-7000}"
BIND="${BIND:-*}"

exec godot --headless \
	--path /app \
	--scene res://server/dedicated_server.tscn -- \
	"--port=${PORT}" \
	"--bind=${BIND}" \
	"$@"

