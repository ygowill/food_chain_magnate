#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  server/deploy.sh [--tag latest] [--port 7000] [--bind "*"]
                   [--name fcm-server] [--web-name fcm-web]
                   [--image <image:tag>] [--web-image <image:tag>]
                   [--pull] [--no-pull] [--foreground]
                   [--enable-web] [--web-port 8080]
                   [--compose-ref main]
                   [--https --web-domain <domain> --ws-domain <domain>]

Default behavior:
  - Uses Docker Compose to run/update containers
  - Pulls prebuilt images from GHCR
  - Starts `server` by default; `web` is optional via --enable-web

Examples:
  # Run server on 7000 (latest images)
  ./server/deploy.sh --tag latest --port 7000

  # Start server + web client together
  ./server/deploy.sh --tag latest --port 7000 --enable-web --web-port 8080

  # Deploy a release tag (recommended)
  ./server/deploy.sh --tag v0.1.0 --enable-web

  # HTTPS for Web client (Cloudflare DNS-01 + Let's Encrypt)
  # Requires env: ACME_EMAIL, CF_DNS_API_TOKEN
  ./server/deploy.sh --tag v0.1.0 --enable-web --https --web-domain game.example.com --ws-domain ws.game.example.com

Notes:
  - Requires Docker Compose v2 (`docker compose`).
  - If `compose.yml` exists next to the repo root, it will be used.
    Otherwise the script downloads it from GitHub.
EOF
}

TAG="latest"
PORT="7000"
BIND="*"
NAME="fcm-server"
WEB_PORT="8080"
WEB_NAME="fcm-web"
IMAGE=""
WEB_IMAGE=""
DO_PULL=1
DETACH=1
ENABLE_WEB=0
COMPOSE_REF="main"
ENABLE_HTTPS=0
WEB_DOMAIN=""
WS_DOMAIN=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
		--tag)
			TAG="${2:-}"
			shift 2
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
		--web-port)
			WEB_PORT="${2:-}"
			shift 2
			;;
		--web-name)
			WEB_NAME="${2:-}"
			shift 2
			;;
		--image)
			IMAGE="${2:-}"
			shift 2
			;;
		--web-image)
			WEB_IMAGE="${2:-}"
			shift 2
			;;
		--pull)
			DO_PULL=1
			shift
			;;
		--no-pull)
			DO_PULL=0
			shift
			;;
		--foreground)
			DETACH=0
			shift
			;;
		--enable-web)
			ENABLE_WEB=1
			shift
			;;
		--compose-ref)
			COMPOSE_REF="${2:-}"
			shift 2
			;;
		--https)
			ENABLE_HTTPS=1
			shift
			;;
		--web-domain)
			WEB_DOMAIN="${2:-}"
			shift 2
			;;
		--ws-domain)
			WS_DOMAIN="${2:-}"
			shift 2
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
if ! docker compose version >/dev/null 2>&1; then
	echo "ERROR: Docker Compose v2 not available (expected: docker compose ...)" >&2
	exit 1
fi

if [[ -z "${IMAGE}" ]]; then
	IMAGE="ghcr.io/ygowill/food_chain_magnate/fcm-server:${TAG}"
fi
if [[ -z "${WEB_IMAGE}" ]]; then
	WEB_IMAGE="ghcr.io/ygowill/food_chain_magnate/fcm-web:${TAG}"
fi

echo "[deploy] tag=${TAG}"
echo "[deploy] server: name=${NAME} image=${IMAGE} port=${PORT} bind=${BIND}"
if [[ "${ENABLE_WEB}" -eq 1 ]]; then
	echo "[deploy] web: name=${WEB_NAME} image=${WEB_IMAGE} port=${WEB_PORT}"
fi
if [[ "${ENABLE_HTTPS}" -eq 1 ]]; then
	if [[ -z "${WEB_DOMAIN}" || -z "${WS_DOMAIN}" ]]; then
		echo "ERROR: --https requires --web-domain and --ws-domain" >&2
		exit 2
	fi
	if [[ -z "${ACME_EMAIL:-}" || -z "${CF_DNS_API_TOKEN:-}" ]]; then
		echo "ERROR: --https requires env vars ACME_EMAIL and CF_DNS_API_TOKEN" >&2
		exit 2
	fi
	echo "[deploy] https enabled: web_domain=${WEB_DOMAIN} ws_domain=${WS_DOMAIN}"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." 2>/dev/null && pwd || true)"
local_compose="${repo_root}/compose.yml"

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "${tmp_dir}"; }
trap cleanup EXIT

compose_file="${tmp_dir}/compose.yml"
compose_https_file="${tmp_dir}/compose.https.yml"
env_file="${tmp_dir}/.env"

if [[ -f "${local_compose}" ]]; then
	compose_file="${local_compose}"
	echo "[deploy] using local compose.yml: ${compose_file}"
else
	if ! command -v curl >/dev/null 2>&1; then
		echo "ERROR: curl not found, and compose.yml not available locally" >&2
		exit 1
	fi
	echo "[deploy] downloading compose.yml (ref=${COMPOSE_REF})"
	curl -fsSL "https://raw.githubusercontent.com/ygowill/food_chain_magnate/${COMPOSE_REF}/compose.yml" -o "${compose_file}"
fi

if [[ "${ENABLE_HTTPS}" -eq 1 && "${compose_file}" == "${tmp_dir}/compose.yml" ]]; then
	echo "[deploy] downloading compose.https.yml (ref=${COMPOSE_REF})"
	curl -fsSL "https://raw.githubusercontent.com/ygowill/food_chain_magnate/${COMPOSE_REF}/compose.https.yml" -o "${compose_https_file}"
fi

cat > "${env_file}" <<EOF
FCM_TAG=${TAG}
FCM_SERVER_IMAGE=${IMAGE}
FCM_WEB_IMAGE=${WEB_IMAGE}
FCM_SERVER_NAME=${NAME}
FCM_WEB_NAME=${WEB_NAME}
FCM_SERVER_PORT=${PORT}
FCM_SERVER_BIND=${BIND}
FCM_WEB_PORT=${WEB_PORT}
FCM_WEB_DOMAIN=${WEB_DOMAIN}
FCM_WS_DOMAIN=${WS_DOMAIN}
ACME_EMAIL=${ACME_EMAIL:-}
CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN:-}
EOF

up_args=(--env-file "${env_file}" -f "${compose_file}" -p fcm)
if [[ "${ENABLE_HTTPS}" -eq 1 ]]; then
	if [[ "${compose_file}" == "${tmp_dir}/compose.yml" ]]; then
		up_args+=(-f "${compose_https_file}")
	else
		# Local compose mode: expect compose.https.yml next to compose.yml
		local_compose_https="${repo_root}/compose.https.yml"
		if [[ ! -f "${local_compose_https}" ]]; then
			echo "ERROR: missing ${local_compose_https} (required for --https)" >&2
			exit 2
		fi
		up_args+=(-f "${local_compose_https}")
	fi
fi
if [[ "${DETACH}" -eq 1 ]]; then
	up_args+=(up -d)
else
	up_args+=(up)
fi
if [[ "${DO_PULL}" -eq 1 ]]; then
	up_args+=(--pull always)
fi

if [[ "${ENABLE_WEB}" -eq 1 ]]; then
	echo "[deploy] docker compose up (server + web)"
	docker compose --profile web "${up_args[@]}"
else
	echo "[deploy] docker compose up (server only)"
	docker compose "${up_args[@]}" server
	docker compose --profile web --env-file "${env_file}" -f "${compose_file}" -p fcm rm -sf web >/dev/null 2>&1 || true
fi

echo "[deploy] done."
echo "[deploy] server logs: docker logs -f ${NAME}"
if [[ "${ENABLE_WEB}" -eq 1 ]]; then
	if [[ "${ENABLE_HTTPS}" -eq 1 ]]; then
		echo "[deploy] web: https://${WEB_DOMAIN}/"
		echo "[deploy] ws:  wss://${WS_DOMAIN}/"
	else
		echo "[deploy] web: http://localhost:${WEB_PORT} (or your server IP)"
	fi
	echo "[deploy] web logs: docker logs -f ${WEB_NAME}"
fi
