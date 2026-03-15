# 联机公网部署（wss://）建议（Dedicated Server + WebSocket）

本文补充 `docs/refactors/multiplayer_websocket_plan.md` 中的公网部署细节，目标是让联机服务能在公网安全可用（TLS + 最小鉴权）。

---

## 1. 推荐拓扑

### A. 反向代理终止 TLS（推荐）

```
Client (wss://domain/...)  <—TLS—>  Reverse Proxy  <—ws://—>  Godot Dedicated Server (headless)
```

要点：

- Godot server 只监听内网/本机（例如 `127.0.0.1:8080`），不直接暴露到公网。
- 反向代理负责：
  - TLS 证书与续期（推荐 Let’s Encrypt）
  - WebSocket Upgrade 转发
  - 限流/黑白名单/基础防护
  - 访问日志（注意脱敏）

### B. Godot 直启 TLS（可选）

```
Client (wss://domain/...)  <—TLS—>  Godot Dedicated Server (headless)
```

要点：

- 需要在 Godot 侧配置 `TLSOptions.server(key, certificate)`。
- 证书链、续期、热更新复杂度更高；建议仅在不方便部署反向代理时采用。

---

## 2. WebSocket 反向代理示例

### 2.1 Nginx（示例）

> 说明：`/ws` 路径仅用于区分路由；`WebSocketMultiplayerPeer` 一般不会关心路径内容，但客户端连接 URL 需与代理一致。
>
> 本项目当前选型：**Nginx 终止 TLS**。

```nginx
server {
	listen 443 ssl;
	server_name example.com;

	ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
	ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

	# 可选：限制请求体大小（本项目消息应很小）
	client_max_body_size 1m;

	location /ws {
		proxy_pass http://127.0.0.1:8080;
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection "upgrade";
		proxy_set_header Host $host;
		proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_read_timeout 60s;
		proxy_send_timeout 60s;
	}
}
```

客户端连接形如：`wss://example.com/ws`。

### 2.2 Caddy（示例）

```caddyfile
example.com {
	reverse_proxy /ws* 127.0.0.1:8080
}
```

客户端连接形如：`wss://example.com/ws`。

---

## 3. 证书与 TLS 要点

- 推荐：使用 Let’s Encrypt 自动签发与续期（Caddy 默认支持；Nginx 可配合 certbot）。
- 若 Godot 直启 TLS：
  - `TLSOptions.server(key, certificate)` 的 `certificate` 应包含完整证书链（可拼接中间证书到同一 crt）。
  - 客户端建议使用系统信任链；如使用自签证书，需显式提供受信 CA 链给 `TLSOptions.client(trusted_chain, ...)`。

---

## 4. 房间鉴权（password / join_token）

公网环境建议至少启用一种鉴权，避免房间被随机加入：

- `room_password`（默认）：房主自定义口令；加入者必须提供。
- `join_token`（可选）：服务器生成高熵随机串，只给房主；加入者必须提供。

安全要点：

- **必须在 `wss://` 下使用**（否则明文传输）。
- 服务器端建议只存储哈希（`HashingContext.HASH_SHA256`），不存明文。
- 服务端/客户端日志不得打印 token/password。

---

## 5. 防护与限流（最小集）

不做强对抗，但建议最小防护：

- 连接数限制：反向代理按 IP 限制并发连接数（防止恶意刷连接）。
- 请求频率限制：服务器端对 `ActionRequest/JoinRoom` 做节流（例如每 peer 每秒上限）。
- 超时踢出：长时间未进入房间或心跳缺失（如未来添加）可踢出。

---

## 6. 运维建议（阶段 1）

- 房间与对局状态默认在内存中维护；服务重启会丢失房间（符合阶段 1 需求）。
- 当前已实现同进程内自动断线重连：客户端会保留对局上下文，向平台后端申请新的 `connect_token`，并在原游戏场景内恢复 `ResyncArchive`。若重连失败，才回退到大厅。
