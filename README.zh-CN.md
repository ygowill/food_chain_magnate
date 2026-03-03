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
FCM_TAG=v0.4.2 docker compose --profile web -f compose.yml up -d
```

### HTTPS（公网访问网页版必需）

Godot 的 Web 导出需要**安全上下文（Secure Context）**。如果你用公网域名/IP 通过 `http://` 访问网页客户端，浏览器会拒绝运行（你看到的就是这个提示）。

推荐部署方式：

- 网页客户端：`https://game.example.com/`
- WebSocket 服务：`wss://ws.game.example.com/`（用独立子域名最稳）

本仓库提供 **Traefik + Let’s Encrypt**（通过 **Cloudflare DNS-01**）的 HTTPS 叠加配置：

1) 在 Cloudflare 添加 DNS 记录：
   - `game.example.com` → A/AAAA 指向你的服务器 IP
   - `ws.game.example.com` → A/AAAA 指向你的服务器 IP

2) 创建 Cloudflare API Token：
   - 权限：`Zone.DNS:Edit`
   - 范围：你的 Zone

3) 在服务器上设置环境变量并部署：

```bash
export ACME_EMAIL="you@example.com"
export CF_DNS_API_TOKEN="***"
curl -fsSL https://raw.githubusercontent.com/ygowill/food_chain_magnate/main/server/deploy.sh | bash -s -- \
  --tag v0.4.2 --enable-web --https \
  --web-domain game.example.com \
  --ws-domain ws.game.example.com
```

可选：如果服务器拉取 Docker Hub 镜像很慢，可以配置镜像站前缀（GHCR 镜像不受影响）：

```bash
curl -fsSL https://raw.githubusercontent.com/ygowill/food_chain_magnate/main/server/deploy.sh | bash -s -- \
  --tag v0.4.2 --https \
  --docker-io-prefix m.daocloud.io/docker.io/
```

可选：如果服务器下载 GitHub raw 很慢，可以配置加速前缀（用于 compose 文件下载）：

```bash
curl -fsSL https://raw.githubusercontent.com/ygowill/food_chain_magnate/main/server/deploy.sh | bash -s -- \
  --tag v0.4.2 --github-raw-prefix https://ghfast.top/
```

4) 确保防火墙/安全组放行：
   - TCP 80 和 443（或你自定义的 `--http-port` / `--https-port`）

如果你不能（或不想）使用 80/443 端口，可以改成其他端口：

```bash
export ACME_EMAIL="you@example.com"
export CF_DNS_API_TOKEN="***"
curl -fsSL https://raw.githubusercontent.com/ygowill/food_chain_magnate/main/server/deploy.sh | bash -s -- \
  --tag v0.4.2 --enable-web --https \
  --web-domain game.example.com \
  --ws-domain ws.game.example.com \
  --http-port 8080 \
  --https-port 8443
```

客户端里把服务器地址填成：

```text
wss://ws.game.example.com
```

如果你改了 `--https-port`（不是 443），需要把端口也带上：

```text
wss://ws.game.example.com:8443
```

一行命令部署（下载并直接执行部署脚本）：

```bash
curl -fsSL https://raw.githubusercontent.com/ygowill/food_chain_magnate/main/server/deploy.sh | bash -s -- --port 7000
```

一行命令部署（server + 网页版客户端）：

```bash
curl -fsSL https://raw.githubusercontent.com/ygowill/food_chain_magnate/main/server/deploy.sh | bash -s -- --port 7000 --enable-web --web-port 8080
```

一行命令停止（删除容器 + network）：

```bash
curl -fsSL https://raw.githubusercontent.com/ygowill/food_chain_magnate/main/server/deploy.sh | bash -s -- --down
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
