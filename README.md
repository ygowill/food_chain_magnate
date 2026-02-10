# Food Chain Magnate - Fan-made Digital Edition (Toy Project)

[中文说明 / Chinese README](README.zh-CN.md)

This is a **toy project for trying “vibe coding”** and exploring Godot workflows.

It is **work in progress** and may contain **many bugs, broken rules, missing features, and rough UX**. Please do not treat it as a polished product.

Built with **Godot 4.5**, aiming to support local play and online multiplayer (Dedicated Server + WebSocket).

## Contents

- [Development](#development)
- [Tests](#tests)
- [Run/Deploy Dedicated Server](#rundeploy-dedicated-server)
- [CI/CD (Automated Releases)](#cicd-automated-releases)
- [Acknowledgements](#acknowledgements)

## Development

- Godot: 4.5.x (editor/CLI)
- Read first: `docs/testing.md`

## Tests

Run all headless tests (with timeout + log handling):

```bash
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

Run a single test scene:

```bash
tools/run_headless_test.sh res://ui/scenes/tests/replay_test.tscn ReplayTest 20
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

This repo provides a one-click deploy script (builds an image and runs/updates the container):

```bash
./server/deploy.sh --port 7000
```

More options:

```bash
./server/deploy.sh --help
```

For public deployment (`wss://`) suggestions:

- `docs/refactors/multiplayer_public_deployment.md`

## CI/CD (Automated Releases)

This repo uses GitHub Actions:

- Triggers **only** when a version tag (`v*`) on `main` is pushed.
- Automatically runs:
  - headless tests (`AllTests`)
  - exports and zips Windows client (`.exe`) as GitHub Release assets
  - builds and pushes the server Docker image (GHCR)
  - creates a GitHub Release

Release example:

```bash
git checkout main
git pull
git tag v0.1.2
git push origin v0.1.2
```

## Acknowledgements

- Many thanks to **Splotter Spellen** for publishing *Food Chain Magnate*. This project is a fan-made experiment.
- Thanks to [OnlineBoardGamers](https://www.onlineboardgamers.com/) — I’m grateful I discovered this game, and OnlineBoardGamers gave me a lot of inspiration for this development.
