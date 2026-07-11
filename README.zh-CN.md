# Food Chain Magnate（快餐连锁大亨）- 电子版（玩具项目）

[English README](README.md)

这是一个**用于尝试 “vibe coding” 的玩具项目**，主要用来探索 Godot 工作流与快速迭代方式。

项目仍在**开发中（WIP）**，可能存在**大量问题**：bug、规则实现不完整/不正确、功能缺失、体验粗糙等，请不要把它当作成熟产品。

引擎：**Godot 4.5**。目标包括本地对局与联机（Dedicated Server + WebSocket）。

## 文档导航

- [文档总入口与治理规则](docs/README.md)
- [按角色划分的文档地图](docs/DOC_MAP.md)
- [当前系统架构](docs/architecture/README.md)
- [测试指南](docs/testing.md)

在把设计稿、计划或进度快照当作当前事实之前，请先从文档总入口确认它的职责与状态。

## 测试

跑全部 headless 测试（带超时与日志处理）：

```bash
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120 --strict-exit
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

如果你已经有外部反代（例如 Nginx Proxy Manager），并且不希望由本仓库管理 HTTPS，部署前应显式设置公网地址，避免 backend 默认把房间 `ws_url` 写成 `localhost`：

```bash
export FCM_WEB_ORIGIN="https://game.example.com"
export FCM_DEFAULT_WS_URL="wss://game.example.com/ws"
./server/deploy.sh --port 7000 --enable-web --web-port 8080
```

也可以直接通过参数传入 WebSocket 地址：

```bash
./server/deploy.sh \
  --port 7000 \
  --enable-web \
  --web-port 8080 \
  --default-ws-url "wss://game.example.com/ws" \
  --web-origin "https://game.example.com"
```

也可以直接使用 Docker Compose（可选）：

```bash
FCM_TAG=v0.9.12 docker compose --profile web -f compose.yml up -d
```

部署命令应从已经审查并固定到目标发布 tag 或 commit 的工作副本执行。不要把 `main` 等可变分支上的远程脚本直接通过管道交给 shell。

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
./server/deploy.sh \
  --tag v0.9.12 --enable-web --https \
  --web-domain game.example.com \
  --ws-domain ws.game.example.com \
  --acme-key-type EC256
```

如果你是手动 build 镜像并打算直接使用 `docker compose` 部署，可以：

```bash
cp .env.example .env
# 编辑 .env，至少设置镜像名、域名、Origin、WS 地址、密钥、数据库密码、ACME_EMAIL、CF_DNS_API_TOKEN
docker compose -f compose.yml -f compose.https.yml down
docker volume rm fcm_traefik_letsencrypt 2>/dev/null || true
docker compose -f compose.yml -f compose.https.yml up -d
```

说明：
- `.env.example` 在仓库根目录，复制为 `.env` 后再改。
- 若你要使用本地镜像，把 `.env` 里的 `FCM_SERVER_IMAGE`、`FCM_WEB_IMAGE`、`FCM_BACKEND_IMAGE` 改成你的 tag。
- 如果这是从旧的 RSA 证书切换到 `EC256`，删除 `fcm_traefik_letsencrypt` 是为了强制重新签发证书。


可选：如果服务器拉取 Docker Hub 镜像很慢，可以配置镜像站前缀（GHCR 镜像不受影响）：

```bash
./server/deploy.sh \
  --tag v0.9.12 --https \
  --docker-io-prefix m.daocloud.io/docker.io/
```

可选：如果服务器下载 GitHub raw 很慢，可以配置加速前缀（用于 compose 文件下载）：

```bash
./server/deploy.sh \
  --tag v0.9.12 --github-raw-prefix https://ghfast.top/
```

第三方镜像会改变软件供应链的信任边界；生产环境除非已审查该服务并独立校验下载文件，否则不要使用。

4) 确保防火墙/安全组放行：
   - TCP 80 和 443（或你自定义的 `--http-port` / `--https-port`）

部署完成后，后端房间接口会默认返回：

- `wss://<web-domain>[:https-port]/ws`（推荐）
- Traefik 同时保留 `wss://<ws-domain>[:https-port]/` 作为备用入口

如果你不能（或不想）使用 80/443 端口，可以改成其他端口：

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

如果服务器没有检出仓库，应下载固定到已审查 commit 的脚本，检查后再执行。下面的 commit 对应 `v0.9.12`；实际操作时应选择你确实要部署的源码 commit 与镜像 tag：

```bash
DEPLOY_COMMIT="3f8c9f735085181374b1425b123d50c36cff7971"
curl -fsSLo deploy.sh "https://raw.githubusercontent.com/ygowill/food_chain_magnate/${DEPLOY_COMMIT}/server/deploy.sh"
less deploy.sh
bash deploy.sh --tag v0.9.12 --port 7000
```

更多参数：

```bash
./server/deploy.sh --help
```

### 安全部署提示

- 不要把 `.env`、数据库密码、API Token 或 session secret 提交到 Git；通过受限的部署环境注入，并轮换任何已经泄露的凭据。
- Cloudflare Token 应使用最小权限并仅限目标 Zone；不要复用个人或账号级全局 API Key。
- 生产部署优先固定 release tag 或镜像 digest，不使用 `latest`；为每次部署记录源码 commit、镜像版本和迁移命令。
- 升级或迁移前备份持久化数据。执行 `--down`、数据库清理或任何 `docker volume rm` 前，确认目标主机和 Compose 项目。
- 房间 URL 迁移属于生产数据变更：应在获批维护窗口中备份、执行并核对受影响记录。

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

## CI/CD（自动检查与发布）

本仓库使用 GitHub Actions：

- Pull Request 会执行文档治理检查和严格模式的 headless `AllTests`，并上传与 commit 绑定的测试日志作为验证证据。
- 推送版本标签（`v*`）后，只有当标签指向的 commit 可从 `main` 到达时才会进入发布流水线。
- 发布流水线会执行严格 `AllTests` 并上传日志与 Hash 证物，导出带校验和的 Windows 与 Web 压缩包，构建并推送 server/backend/web 多架构 GHCR 镜像，并创建 GitHub Release。

发布示例：

```bash
git checkout main
git pull
git tag v0.9.13
git push origin v0.9.13
```

## 致谢

- 感谢出版商 **Splotter Spellen** 出版了《Food Chain Magnate》，让我遇到了这款游戏。本项目为粉丝向实验性质项目。
- 感谢 [OnlineBoardGamers](https://www.onlineboardgamers.com/)：我很感谢我遇到了这款游戏，以及 OnlineBoardGamers 给我的开发带来的灵感。
