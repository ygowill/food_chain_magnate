# Food Chain Magnate（快餐连锁大亨）- 电子版

基于 Godot 4.5 的桌游《Food Chain Magnate》电子版项目，支持本地对局与联机（Dedicated Server + WebSocket）。

## 目录

- [开发环境](#开发环境)
- [测试](#测试)
- [运行/部署 Dedicated Server](#运行部署-dedicated-server)
- [CI/CD（自动发版）](#cicd自动发版)

## 开发环境

- Godot：4.5.x（编辑器/CLI）
- 建议先阅读：`docs/testing.md`

## 测试

推荐用仓库脚本跑全部 headless 测试（带超时与日志处理）：

```bash
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

单个测试场景：

```bash
tools/run_headless_test.sh res://ui/scenes/tests/replay_test.tscn ReplayTest 20
```

## 运行/部署 Dedicated Server

### 方式 A：本机直接运行（Godot CLI）

```bash
godot --headless --path . --scene res://server/dedicated_server.tscn -- --port=7000 --bind=*
```

参数：

- `--port`：监听端口（默认 `7000`）
- `--bind`：监听地址（默认 `*`，表示所有网卡）

### 方式 B：Docker（推荐用于部署）

仓库已提供一键部署脚本（会构建镜像并以容器方式运行/更新）：

```bash
./server/deploy.sh --port 7000
```

更多参数：

```bash
./server/deploy.sh --help
```

公网部署（`wss://`）建议参考：

- `docs/refactors/multiplayer_public_deployment.md`

## CI/CD（自动发版）

本仓库使用 GitHub Actions：

- 仅当 `main` 分支上的版本号 tag（`v*`）被 push 时触发
- 自动执行：
  - headless 测试（`AllTests`）
  - 构建并打包 Windows 客户端（`.exe`），作为 GitHub Release Assets
  - 构建并推送 server Docker image（GHCR）
  - 创建 GitHub Release

发版示例：

```bash
git checkout main
git pull
git tag v0.1.2
git push origin v0.1.2
```

