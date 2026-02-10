#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  server/deploy.sh [--port 7000] [--bind "*"] [--name fcm-server]
                   [--image <image:tag>] [--pull] [--no-build] [--foreground]

Default behavior:
  - Build local image from server/Dockerfile
  - Replace container (same name)
  - Run detached with --restart unless-stopped

Examples:
  # Build from current repo and run on 7000
  ./server/deploy.sh --port 7000

  # Bind to localhost only (for reverse proxy on same machine)
  ./server/deploy.sh --port 7000 --bind 127.0.0.1

  # Pull and run a prebuilt image
  ./server/deploy.sh --image ghcr.io/<owner>/<repo>/fcm-server:v0.1.2 --pull --no-build
EOF
}

PORT="7000"
BIND="*"
NAME="fcm-server"
IMAGE="fcm-server:local"
DO_PULL=0
DO_BUILD=1
DETACH=1

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
		--port)
			PORT="${2:-}"
			shift 2
			;;
		--bind)
			BIND="${2:-}"
			shift 2
			;;
		--name)
			NAME="${2:-}"
			shift 2
			;;
		--image)
			IMAGE="${2:-}"
			shift 2
			;;
		--pull)
			DO_PULL=1
			shift
			;;
		--no-build)
			DO_BUILD=0
			shift
			;;
		--foreground)
			DETACH=0
			shift
			;;
		*)
			echo "Unknown arg: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

if ! command -v docker >/dev/null 2>&1; then
	echo "ERROR: docker not found in PATH" >&2
	exit 1
fi

if ! docker info >/dev/null 2>&1; then
	echo "ERROR: docker daemon not available (is Docker running?)" >&2
	exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[deploy] repo_root=${repo_root}"
echo "[deploy] name=${NAME} image=${IMAGE} port=${PORT} bind=${BIND}"

if [[ "${DO_PULL}" -eq 1 ]]; then
	echo "[deploy] pulling image: ${IMAGE}"
	docker pull "${IMAGE}"
fi

if [[ "${DO_BUILD}" -eq 1 ]]; then
	echo "[deploy] building image: ${IMAGE}"
	docker build -t "${IMAGE}" -f "${repo_root}/server/Dockerfile" "${repo_root}"
fi

if docker ps -a --format '{{.Names}}' | grep -qx "${NAME}"; then
	echo "[deploy] stopping old container: ${NAME}"
	docker rm -f "${NAME}" >/dev/null
fi

run_args=(
	--name "${NAME}"
	-p "${PORT}:${PORT}"
	-e "PORT=${PORT}"
	-e "BIND=${BIND}"
	--restart unless-stopped
)

if [[ "${DETACH}" -eq 1 ]]; then
	run_args+=(-d)
fi

echo "[deploy] starting container..."
docker run "${run_args[@]}" "${IMAGE}"

echo "[deploy] done."
echo "[deploy] logs: docker logs -f ${NAME}"

