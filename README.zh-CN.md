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

## 管理后台（用户 / 房间 / 对局）

网页登录后可访问 `/admin` 管理页。

- 后端管理接口位于 `/v1/admin/*`
- 管理员由 `ADMIN_USER_IDS` 控制（逗号分隔的 user_id）
- 本地调试可临时使用：`ADMIN_USER_IDS=*`
- 支持表格多选批量操作：
  - `POST /v1/admin/users/batch/status`
  - `POST /v1/admin/users/batch/delete`
  - `POST /v1/admin/rooms/batch/end`
  - `POST /v1/admin/rooms/batch/delete`
  - `POST /v1/admin/matches/batch/delete`

例如启动 backend 前设置：

```bash
export ADMIN_USER_IDS="your_user_id_1,your_user_id_2"
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
- WebSocket 服务（推荐）：`wss://game.example.com/ws`
- WebSocket 服务（备用）：`wss://ws.game.example.com/`

本仓库提供 **Traefik + Let’s Encrypt**（通过 **Cloudflare DNS-01**）的 HTTPS 叠加配置：

- ACME 证书密钥类型默认使用 `EC256`（对 Godot 客户端兼容性更好）。
- 如需改回 RSA，可在部署脚本里传 `--acme-key-type RSA2048` 或 `RSA4096`。

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
  --ws-domain ws.game.example.com \
  --acme-key-type EC256
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

部署完成后，后端房间接口会默认返回：

- `wss://<web-domain>[:https-port]/ws`（推荐）
- Traefik 同时保留 `wss://<ws-domain>[:https-port]/` 作为备用入口

如果你不能（或不想）使用 80/443 端口，可以改成其他端口：

```bash
export ACME_EMAIL="you@example.com"
export CF_DNS_API_TOKEN="***"
curl -fsSL https://raw.githubusercontent.com/ygowill/food_chain_magnate/main/server/deploy.sh | bash -s -- \
  --tag v0.4.2 --enable-web --https \
  --web-domain game.example.com \
  --ws-domain ws.game.example.com \
  --acme-key-type EC256 \
  --http-port 8080 \
  --https-port 8443
```

客户端里把服务器地址填成（推荐）：

```text
wss://game.example.com/ws
```

如果你改了 `--https-port`（不是 443），需要把端口也带上：

```text
wss://game.example.com:8443/ws
```

备用地址（如果你仍希望使用独立 WS 子域名）：

```text
wss://ws.game.example.com:8443
```

如果你在这次改动之前创建过房间，数据库里可能还存着旧地址（例如 `ws://localhost:7000`），可以执行一次迁移：

```bash
tools/migration/update_rooms_ws_url.sh \
  --new-url "wss://game.example.com/ws" \
  --old-url "ws://localhost:7000"
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

### TLS 排障（`http_status: 0` / `cant_connect`）

如果客户端联机入口提示：

- `_http_status: 0`
- `_http_result_name: cant_connect`

通常表示 HTTPS/TLS 握手阶段失败（还没到业务接口）。建议按顺序检查：

1. 服务端证书链是否完整（Nginx 必须用 `fullchain.pem`，不是 `cert.pem`）。
2. 域名与证书 SAN/CN 是否匹配，服务器系统时间是否准确。
3. 若你使用本仓库 `deploy.sh --https`，优先使用 `--acme-key-type EC256` 重新签发证书。
4. 若此前已经签过不兼容证书，建议：
   - 先执行 `./server/deploy.sh --down`
   - 再执行 `docker volume rm fcm_traefik_letsencrypt`（仅清理证书缓存，不删数据库卷）
   - 然后重新部署 HTTPS 以触发重签。

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
