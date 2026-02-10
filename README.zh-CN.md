# Food Chain Magnate（快餐连锁大亨）- 电子版（玩具项目）

[English README](README.md)

这是一个**用于尝试 “vibe coding” 的玩具项目**，主要用来探索 Godot 工作流与快速迭代方式。

项目仍在**开发中（WIP）**，可能存在**大量问题**：bug、规则实现不完整/不正确、功能缺失、体验粗糙等，请不要把它当作成熟产品。

引擎：**Godot 4.5**。目标包括本地对局与联机（Dedicated Server + WebSocket）。

## 测试

跑全部 headless 测试（带超时与日志处理）：

```bash
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

## Dedicated Server（运行/部署）

本机运行（Godot CLI）：

```bash
godot --headless --path . --scene res://server/dedicated_server.tscn -- --port=7000 --bind=*
```

Docker 一键部署脚本（从 GHCR 拉取镜像，并使用 Docker Compose 运行/更新容器）：

```bash
./server/deploy.sh --port 7000
```

同时启动 server + 网页版客户端：

```bash
./server/deploy.sh --port 7000 --enable-web --web-port 8080
```

也可以直接使用 Docker Compose（可选）：

```bash
FCM_TAG=v0.1.0 docker compose --profile web -f compose.yml up -d
```

一行命令部署（下载并直接执行部署脚本）：

```bash
curl -fsSL https://raw.githubusercontent.com/ygowill/food_chain_magnate/main/server/deploy.sh | bash -s -- --port 7000
```

一行命令部署（server + 网页版客户端）：

```bash
curl -fsSL https://raw.githubusercontent.com/ygowill/food_chain_magnate/main/server/deploy.sh | bash -s -- --port 7000 --enable-web --web-port 8080
```

如果你不希望 `curl | bash`，可以先下载脚本并检查后再执行：

```bash
curl -fsSL -o deploy.sh https://raw.githubusercontent.com/ygowill/food_chain_magnate/main/server/deploy.sh
bash deploy.sh --port 7000
```

更多参数：

```bash
./server/deploy.sh --help
```

## Web 导出（本地）

Web 导出需要安装 Godot Export Templates。本仓库提供了一个辅助脚本，会使用项目内的 HOME（`.tmp_home/`）以避免污染你的用户目录：

```bash
tools/export_web.sh --out build/client/web/index.html
```

如果缺少模板，可以在 Godot 编辑器中安装，或者（可选）让脚本自动下载官方模板：

```bash
tools/export_web.sh --install-templates
```

## 致谢

- 感谢出版商 **Splotter Spellen** 出版了《Food Chain Magnate》，让我遇到了这款游戏。本项目为粉丝向实验性质项目。
- 感谢 [OnlineBoardGamers](https://www.onlineboardgamers.com/)：我很感谢我遇到了这款游戏，以及 OnlineBoardGamers 给我的开发带来的灵感。
