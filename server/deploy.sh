#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  server/deploy.sh [--tag latest] [--port 7000] [--bind "0.0.0.0"]
                   [--name fcm-server] [--web-name fcm-web]
                   [--image <image:tag>] [--web-image <image:tag>]
                   [--docker-io-prefix <prefix>]
                   [--docker-api-version <version>]
                   [--pull] [--no-pull] [--foreground]
                   [--enable-web] [--web-port 8080]
                   [--compose-ref main]
                   [--github-raw-prefix <prefix>]
                   [--https --web-domain <domain> --ws-domain <domain>]
                   [--http-port 80] [--https-port 443]
                   [--down] [--purge]

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

  # Use a Docker Hub mirror/prefix for faster pulls (only affects docker.io images like Traefik)
  ./server/deploy.sh --tag v0.1.0 --https --docker-io-prefix m.daocloud.io/docker.io/

  # Use a GitHub raw accelerator for faster downloads (compose files)
  ./server/deploy.sh --tag v0.1.0 --github-raw-prefix https://ghfast.top/

  # Stop & remove containers + network (keeps volumes by default)
  ./server/deploy.sh --down

  # Stop & remove containers + network + volumes (including Let's Encrypt cache)
  ./server/deploy.sh --down --purge

Notes:
  - Requires Docker Compose v2 (`docker compose`).
  - If `compose.yml` exists next to the repo root, it will be used.
    Otherwise the script downloads it from GitHub.
EOF
}

TAG="latest"
PORT="7000"
BIND="0.0.0.0"
NAME="fcm-server"
WEB_PORT="8080"
WEB_NAME="fcm-web"
IMAGE=""
WEB_IMAGE=""
DOCKER_IO_PREFIX=""
DOCKER_API_VERSION=""
DO_PULL=1
DETACH=1
ENABLE_WEB=0
COMPOSE_REF="main"
GITHUB_RAW_PREFIX=""
ENABLE_HTTPS=0
WEB_DOMAIN=""
WS_DOMAIN=""
HTTP_PORT="80"
HTTPS_PORT="443"
ACTION="up"
PURGE=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
		--down)
			ACTION="down"
			shift
			;;
		--purge)
			PURGE=1
			shift
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
		--docker-io-prefix)
			DOCKER_IO_PREFIX="${2:-}"
			shift 2
			;;
		--docker-api-version)
			DOCKER_API_VERSION="${2:-}"
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
		--github-raw-prefix)
			GITHUB_RAW_PREFIX="${2:-}"
			shift 2
			;;
		--https)
			ENABLE_HTTPS=1
			shift
			;;
		--http-port)
			HTTP_PORT="${2:-}"
			shift 2
			;;
		--https-port)
			HTTPS_PORT="${2:-}"
			shift 2
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

if [[ -n "${DOCKER_IO_PREFIX}" && "${DOCKER_IO_PREFIX}" != */ ]]; then
	DOCKER_IO_PREFIX="${DOCKER_IO_PREFIX}/"
fi
if [[ -n "${GITHUB_RAW_PREFIX}" && "${GITHUB_RAW_PREFIX}" != */ ]]; then
	GITHUB_RAW_PREFIX="${GITHUB_RAW_PREFIX}/"
fi
if [[ "${BIND}" == "*" ]]; then
	echo "[deploy] WARN --bind=\"*\" is not supported by Godot WebSocket server; using 0.0.0.0 instead."
	BIND="0.0.0.0"
fi

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

if [[ "${ACTION}" == "up" ]]; then
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
		echo "[deploy] https enabled: web_domain=${WEB_DOMAIN} ws_domain=${WS_DOMAIN} http_port=${HTTP_PORT} https_port=${HTTPS_PORT}"
	fi
else
	echo "[deploy] stopping (docker compose down)..."
fi

script_src="${BASH_SOURCE[0]}"
if [[ -n "${script_src}" && -f "${script_src}" ]]; then
	script_dir="$(cd "$(dirname "${script_src}")" && pwd)"
	repo_root="$(cd "${script_dir}/.." 2>/dev/null && pwd || true)"
else
	# `curl ... | bash` mode: treat current working directory as the "repo root".
	script_dir="$(pwd)"
	repo_root="${script_dir}"
fi
local_compose="${repo_root}/compose.yml"
local_compose_https="${repo_root}/compose.https.yml"

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "${tmp_dir}"; }
trap cleanup EXIT

compose_file="${tmp_dir}/compose.yml"
compose_https_file="${tmp_dir}/compose.https.yml"
env_file="${tmp_dir}/.env"
state_dir="${repo_root}/.fcm_deploy"
mkdir -p "${state_dir}"
traefik_dynamic_file="${state_dir}/traefik_dynamic.yml"

if [[ -f "${local_compose}" ]]; then
	compose_file="${local_compose}"
	echo "[deploy] using local compose.yml: ${compose_file}"
else
	if ! command -v curl >/dev/null 2>&1; then
		echo "ERROR: curl not found, and compose.yml not available locally" >&2
		exit 1
	fi
	if [[ -n "${GITHUB_RAW_PREFIX}" ]]; then
		echo "[deploy] github raw prefix: ${GITHUB_RAW_PREFIX}"
	fi
	echo "[deploy] downloading compose.yml (ref=${COMPOSE_REF})"
	raw_compose_url="https://raw.githubusercontent.com/ygowill/food_chain_magnate/${COMPOSE_REF}/compose.yml"
	curl -fsSL "${GITHUB_RAW_PREFIX}${raw_compose_url}" -o "${compose_file}"
fi

have_https_compose=0
if [[ "${compose_file}" == "${tmp_dir}/compose.yml" ]]; then
	if [[ "${ENABLE_HTTPS}" -eq 1 || "${ACTION}" == "down" ]]; then
		echo "[deploy] downloading compose.https.yml (ref=${COMPOSE_REF})"
		raw_compose_https_url="https://raw.githubusercontent.com/ygowill/food_chain_magnate/${COMPOSE_REF}/compose.https.yml"
		if curl -fsSL "${GITHUB_RAW_PREFIX}${raw_compose_https_url}" -o "${compose_https_file}"; then
			have_https_compose=1
		else
			echo "[deploy] compose.https.yml not found for ref=${COMPOSE_REF}; continuing without it."
		fi
	fi
else
	if [[ -f "${local_compose_https}" ]]; then
		have_https_compose=1
	fi
fi

cat > "${env_file}" <<EOF
FCM_TAG=${TAG}
FCM_SERVER_IMAGE=${IMAGE}
FCM_WEB_IMAGE=${WEB_IMAGE}
FCM_DOCKER_IO_PREFIX=${DOCKER_IO_PREFIX}
FCM_DOCKER_API_VERSION=${DOCKER_API_VERSION}
FCM_TRAEFIK_DYNAMIC_FILE=${traefik_dynamic_file}
FCM_SERVER_NAME=${NAME}
FCM_WEB_NAME=${WEB_NAME}
FCM_SERVER_PORT=${PORT}
FCM_SERVER_BIND=${BIND}
FCM_WEB_PORT=${WEB_PORT}
FCM_WEB_DOMAIN=${WEB_DOMAIN}
FCM_WS_DOMAIN=${WS_DOMAIN}
FCM_HTTP_PORT=${HTTP_PORT}
FCM_HTTPS_PORT=${HTTPS_PORT}
ACME_EMAIL=${ACME_EMAIL:-}
CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN:-}
EOF

if [[ "${ENABLE_HTTPS}" -eq 1 || ( "${ACTION}" == "down" && "${have_https_compose}" -eq 1 ) ]]; then
	# Ensure the mounted dynamic config file exists and is stable across restarts.
	cat > "${traefik_dynamic_file}" <<EOF
http:
  routers:
    fcm-ws:
      rule: Host(\`${WS_DOMAIN}\`)
      entryPoints:
        - websecure
      tls:
        certResolver: le
      service: fcm-ws
EOF
	if [[ "${ENABLE_WEB}" -eq 1 ]]; then
		cat >> "${traefik_dynamic_file}" <<EOF
    fcm-web:
      rule: Host(\`${WEB_DOMAIN}\`)
      entryPoints:
        - websecure
      tls:
        certResolver: le
      service: fcm-web
EOF
	fi
	cat >> "${traefik_dynamic_file}" <<EOF
  services:
    fcm-ws:
      loadBalancer:
        servers:
          - url: http://server:${PORT}
EOF
	if [[ "${ENABLE_WEB}" -eq 1 ]]; then
		cat >> "${traefik_dynamic_file}" <<EOF
    fcm-web:
      loadBalancer:
        servers:
          - url: http://web:80
EOF
	fi
fi

compose_args=(--env-file "${env_file}" -f "${compose_file}" -p fcm)
if [[ "${ENABLE_HTTPS}" -eq 1 ]]; then
	if [[ "${compose_file}" == "${tmp_dir}/compose.yml" ]]; then
		if [[ "${have_https_compose}" -ne 1 ]]; then
			echo "ERROR: missing compose.https.yml for ref=${COMPOSE_REF} (required for --https)" >&2
			exit 2
		fi
		compose_args+=(-f "${compose_https_file}")
	else
		# Local compose mode: expect compose.https.yml next to compose.yml
		if [[ ! -f "${local_compose_https}" ]]; then
			echo "ERROR: missing ${local_compose_https} (required for --https)" >&2
			exit 2
		fi
		compose_args+=(-f "${local_compose_https}")
	fi
else
	# For --down, try to include compose.https.yml if present to ensure Traefik is removed too.
	if [[ "${ACTION}" == "down" && "${have_https_compose}" -eq 1 ]]; then
		if [[ "${compose_file}" == "${tmp_dir}/compose.yml" ]]; then
			compose_args+=(-f "${compose_https_file}")
		else
			compose_args+=(-f "${local_compose_https}")
		fi
	fi
fi

if [[ "${ACTION}" == "down" ]]; then
	down_args=(down --remove-orphans)
	if [[ "${PURGE}" -eq 1 ]]; then
		down_args+=(--volumes)
	fi
	docker compose --profile web "${compose_args[@]}" "${down_args[@]}"
	echo "[deploy] stopped."
	exit 0
fi

up_args=("${compose_args[@]}")
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
	if [[ "${ENABLE_HTTPS}" -eq 1 ]]; then
		docker compose "${up_args[@]}" traefik server
	else
		docker compose "${up_args[@]}" server
	fi
	docker compose --profile web --env-file "${env_file}" -f "${compose_file}" -p fcm rm -sf web >/dev/null 2>&1 || true
fi

echo "[deploy] done."
echo "[deploy] server logs: docker logs -f ${NAME}"
if [[ "${ENABLE_WEB}" -eq 1 ]]; then
	if [[ "${ENABLE_HTTPS}" -eq 1 ]]; then
		web_port_suffix=""
		if [[ "${HTTPS_PORT}" != "443" ]]; then
			web_port_suffix=":${HTTPS_PORT}"
		fi
		echo "[deploy] web: https://${WEB_DOMAIN}${web_port_suffix}/"
		echo "[deploy] ws:  wss://${WS_DOMAIN}${web_port_suffix}/"
	else
		echo "[deploy] web: http://localhost:${WEB_PORT} (or your server IP)"
	fi
	echo "[deploy] web logs: docker logs -f ${WEB_NAME}"
fi
