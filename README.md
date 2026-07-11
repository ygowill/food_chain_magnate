# Food Chain Magnate - Fan-made Digital Edition (Toy Project)

[中文说明 / Chinese README](README.zh-CN.md)

This is a **toy project for trying “vibe coding”** and exploring Godot workflows.

It is **work in progress** and may contain **many bugs, broken rules, missing features, and rough UX**. Please do not treat it as a polished product.

Built with **Godot 4.5**, aiming to support local play and online multiplayer (Dedicated Server + WebSocket).

## Contents

- [Documentation](#documentation)
- [Development](#development)
- [Tests](#tests)
- [Run/Deploy Dedicated Server](#rundeploy-dedicated-server)
- [CI/CD (Automated Releases)](#cicd-automated-releases)
- [Acknowledgements](#acknowledgements)

## Documentation

- [Documentation hub and governance rules](docs/README.md)
- [Role-based document map](docs/DOC_MAP.md)
- [Current-system architecture](docs/architecture/README.md)
- [Testing guide](docs/testing.md)

## Development

- Godot: 4.5.x (editor/CLI)
- Read the [documentation hub](docs/README.md) before treating a design, plan, or progress snapshot as current-system truth.

## Tests

Run all headless tests (with timeout + log handling):

```bash
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120 --strict-exit
```

Run a single test scene:

```bash
tools/run_headless_test.sh res://ui/scenes/tests/replay_test.tscn ReplayTest 20
```

## Admin Portal (Users / Rooms / Matches)

The web portal now includes an admin page at `/admin` (after login).

- Backend admin APIs are under `/v1/admin/*`
- Admin access is controlled by `ADMIN_USER_IDS` (comma-separated user IDs)
- Example (local dev only): `ADMIN_USER_IDS=*`
- Supports bulk actions from admin tables (multi-select):
  - `POST /v1/admin/users/batch/status`
  - `POST /v1/admin/users/batch/delete`
  - `POST /v1/admin/rooms/batch/end`
  - `POST /v1/admin/rooms/batch/delete`
  - `POST /v1/admin/matches/batch/delete`

Set env when starting backend, for example:

```bash
export ADMIN_USER_IDS="your_user_id_1,your_user_id_2"
```

## Run/Deploy Dedicated Server

### Option A: Run locally (Godot CLI)

```bash
godot --headless --path . --scene res://server/dedicated_server.tscn -- --port=7000 --bind=*
```

Args:

- `--port`：监听端口（默认 `7000`）
- `--bind`：监听地址（默认 `*`，表示所有网卡）

### Option B: Docker (recommended for deployment)

This repo provides a one-click deploy script that **pulls the prebuilt images from GHCR** and runs/updates containers using **Docker Compose**:

```bash
./server/deploy.sh --port 7000
```

Start server + web client together:

```bash
./server/deploy.sh --port 7000 --enable-web --web-port 8080
```

If you already have an external reverse proxy such as Nginx Proxy Manager and do not want this repo to manage HTTPS, set the public origins explicitly before deploying. This avoids the backend defaulting room `ws_url` to `localhost`:

```bash
export FCM_WEB_ORIGIN="https://game.example.com"
export FCM_DEFAULT_WS_URL="wss://game.example.com/ws"
./server/deploy.sh --port 7000 --enable-web --web-port 8080
```

You can also pass the WebSocket address directly:

```bash
./server/deploy.sh \
  --port 7000 \
  --enable-web \
  --web-port 8080 \
  --default-ws-url "wss://game.example.com/ws" \
  --web-origin "https://game.example.com"
```

Use Docker Compose directly (optional):

```bash
FCM_TAG=v0.9.12 docker compose --profile web -f compose.yml up -d
```

Run deployment commands from a reviewed checkout pinned to the release tag or commit you intend to deploy. Do not pipe a script from a mutable branch such as `main` directly into a shell.

### HTTPS (required for Web client on the Internet)

Godot Web exports require a **secure context**. If you open the web client over plain HTTP on a public domain/IP, the browser will refuse to run it.

Recommended setup:

- Web client: `https://game.example.com/`
- WebSocket server (preferred): `wss://game.example.com/ws`
- WebSocket server (alternate): `wss://ws.game.example.com/`

This repo includes an HTTPS overlay using **Traefik + Let’s Encrypt** with **Cloudflare DNS-01**:

- ACME key type defaults to `EC256` (better Godot client compatibility).
- If you need RSA certificates, pass `--acme-key-type RSA2048` or `RSA4096`.

1) Create DNS records in Cloudflare:
   - `game.example.com` → A/AAAA to your server IP
   - `ws.game.example.com` → A/AAAA to your server IP

2) Create a Cloudflare API token:
   - Permissions: `Zone.DNS:Edit`
   - Scope: your zone

3) On the server, export env vars and deploy:

```bash
export ACME_EMAIL="you@example.com"
export CF_DNS_API_TOKEN="***"
./server/deploy.sh \
  --tag v0.9.12 --enable-web --https \
  --web-domain game.example.com \
  --ws-domain ws.game.example.com \
  --acme-key-type EC256
```

If you build images manually and prefer deploying with `docker compose` directly, you can use the root `.env.example` as a template:

```bash
cp .env.example .env
# Edit .env: at minimum set image tags, domains, origin, WS URL, secrets, DB password, ACME_EMAIL, CF_DNS_API_TOKEN
docker compose -f compose.yml -f compose.https.yml down
docker volume rm fcm_traefik_letsencrypt 2>/dev/null || true
docker compose -f compose.yml -f compose.https.yml up -d
```

Notes:
- `.env.example` lives at the repo root; copy it to `.env` and fill in real values.
- If you want to use local images, change `FCM_SERVER_IMAGE`, `FCM_WEB_IMAGE`, and `FCM_BACKEND_IMAGE` to your local tags.
- When switching from an old RSA certificate to `EC256`, removing `fcm_traefik_letsencrypt` forces Traefik to request a fresh certificate.


Optional: if your server pulls Docker Hub images slowly, you can use a mirror/prefix (GHCR images are unchanged):

```bash
./server/deploy.sh \
  --tag v0.9.12 --https \
  --docker-io-prefix m.daocloud.io/docker.io/
```

Optional: if your server downloads GitHub raw files slowly, you can use a GitHub raw accelerator/prefix (for compose files):

```bash
./server/deploy.sh \
  --tag v0.9.12 --github-raw-prefix https://ghfast.top/
```

Using a third-party mirror changes the software supply-chain trust boundary; avoid it for production unless that service and the downloaded files are independently verified.

4) Ensure your firewall/security group allows inbound:
   - TCP 80 and 443 (or your custom `--http-port` / `--https-port`)

After deployment, backend room API will default `ws_url` to:

- `wss://<web-domain>[:https-port]/ws` (preferred)
- Traefik also keeps the `wss://<ws-domain>[:https-port]/` route as an alternate entry.

If you can’t (or don’t want to) use ports 80/443, you can change them:

```bash
export ACME_EMAIL="you@example.com"
export CF_DNS_API_TOKEN="***"
./server/deploy.sh \
  --tag v0.9.12 --enable-web --https \
  --web-domain game.example.com \
  --ws-domain ws.game.example.com \
  --acme-key-type EC256 \
  --http-port 8080 \
  --https-port 8443
```

In the client, set server URL to (preferred):

```text
wss://game.example.com/ws
```

If you changed `--https-port` (not 443), include it:

```text
wss://game.example.com:8443/ws
```

Alternate URL (if you still want dedicated WS subdomain):

```text
wss://ws.game.example.com:8443
```

If you already created rooms before this change and they still store old URLs (for example `ws://localhost:7000`), migrate in-place:

```bash
tools/migration/update_rooms_ws_url.sh \
  --new-url "wss://game.example.com/ws" \
  --old-url "ws://localhost:7000"
```

If the repository is not checked out on the server, download a script pinned to a reviewed commit, inspect it, and only then run it. The example commit below corresponds to release `v0.9.12`; choose the commit and image tag you actually intend to deploy:

```bash
DEPLOY_COMMIT="3f8c9f735085181374b1425b123d50c36cff7971"
curl -fsSLo deploy.sh "https://raw.githubusercontent.com/ygowill/food_chain_magnate/${DEPLOY_COMMIT}/server/deploy.sh"
less deploy.sh
bash deploy.sh --tag v0.9.12 --port 7000
```

More options:

```bash
./server/deploy.sh --help
```

### Deployment safety

- Keep `.env`, database passwords, API tokens, and session secrets out of Git; provide them through a restricted deployment environment and rotate anything exposed.
- Use a least-privilege Cloudflare token limited to the required zone. Do not reuse personal or account-wide API keys.
- Prefer release tags or image digests over `latest`, and record the source commit, image version, and migration command for each deployment.
- Back up persistent data before upgrades or migrations. Confirm the target host and Compose project before `--down`, database cleanup, or any `docker volume rm` command.
- Treat the room URL migration as a production data change: take a backup, run it during an approved maintenance window, and verify affected rows.

### TLS Troubleshooting (`http_status: 0` / `cant_connect`)

If the client shows:

- `_http_status: 0`
- `_http_result_name: cant_connect`

that usually means TLS handshake failed before reaching backend APIs. Check in order:

1. Certificate chain is complete (`fullchain.pem` on Nginx, not just `cert.pem`).
2. Domain matches certificate SAN/CN, and server clock is correct.
3. For this repo's `deploy.sh --https`, prefer `--acme-key-type EC256`.
4. If old incompatible certs were already issued:
   - run `./server/deploy.sh --down`
   - run `docker volume rm fcm_traefik_letsencrypt` (clears cert cache only, keeps DB volume)
   - deploy HTTPS again to force ACME re-issuance.

## Web export (local)

Web export requires Godot export templates. This repo includes a helper script that uses a project-local HOME (`.tmp_home/`) to keep things reproducible:

```bash
tools/export_web.sh --out build/client/web/index.html
```

If templates are missing, you can install them via the Godot editor, or (optionally) let the script download official templates:

```bash
tools/export_web.sh --install-templates
```

For public deployment (`wss://`) suggestions:

- [Public multiplayer deployment guide](docs/refactors/multiplayer_public_deployment.md)

## CI/CD (Automated Releases)

This repo uses GitHub Actions:

- Pull requests run documentation-governance checks and strict headless `AllTests`; the test log is uploaded as commit-bound validation evidence.
- A pushed version tag (`v*`) starts the release pipeline only when the tagged commit is reachable from `main`.
- The release pipeline runs strict `AllTests` and uploads its logs/hashes, exports Windows and Web archives with checksums, builds and pushes the server/backend/web multi-platform images to GHCR, and creates the GitHub Release.

Release example:

```bash
git checkout main
git pull
git tag v0.9.13
git push origin v0.9.13
```

## Acknowledgements

- Many thanks to **Splotter Spellen** for publishing *Food Chain Magnate*. This project is a fan-made experiment.
- Thanks to [OnlineBoardGamers](https://www.onlineboardgamers.com/) — I’m grateful I discovered this game, and OnlineBoardGamers gave me a lot of inspiration for this development.
