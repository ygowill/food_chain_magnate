# 联机实现指南（按文件与 RPC 列表）

本文是 `docs/refactors/multiplayer_websocket_plan.md` 的落地补充：把“要做什么”进一步拆成“每个文件要提供什么接口/信号/消息”，降低实现时的来回对齐成本。

范围：阶段 1（Hotseat 保留 + Dedicated server + WebSocket + 公网 `wss://` + 房间鉴权 + 储备卡 UI/日志保密；不做断线重连）。

---

## 1. 新增/改动的模块边界

### 1.1 `core/`

- 不引入任何网络/Node 依赖。
- 继续保持：server 与 client 都运行同一套 `GameEngine`，以 `Command` 作为唯一同步单位。

### 1.2 `autoload/`

建议新增两个 autoload（均为 Node）：

- `autoload/net_context.gd`
  - 运行模式：`hotseat` / `online_client` / `online_server`
  - `local_player_id`（仅 online_client 有意义）
  - 当前连接状态、房间信息、玩家 profile（name/color）
  - 提供 UI 判定：是否允许输入、是否启用隐私脱敏、是否显示 DebugPanel 等

- `autoload/net_client.gd`
  - online_client 会话层：连接/断线、RPC 请求封装、消息分发、状态机（Lobby → Room → InGame）
  - 输出信号建议：
    - `connected()`, `disconnected(reason: String)`
    - `room_state_updated(room_state: Dictionary)`
    - `game_started(payload: Dictionary)`
    - `command_applied(cmd_dict: Dictionary, state_hash: String)`
    - `resync_received(archive: Dictionary)`
    - `request_rejected(request_id: String, code: String, message: String)`
    - `game_ended(reason_code: String, message: String)`

### 1.3 `server/`

建议新增：

- `server/dedicated_server.gd`（Node，headless 入口）
  - 解析命令行参数（port/bind/tls 等）
  - 创建 `WebSocketMultiplayerPeer` 并写入 `get_tree().multiplayer.multiplayer_peer`
  - 提供 RPC 方法（见第 2 节）
  - 把“房间/引擎管理”委托给 `RoomManager`

- `server/room_manager.gd`（RefCounted 或 Node）
  - `rooms: Dictionary`（room_code → Room）
  - `peer_to_room: Dictionary`（peer_id → room_code）
  - `peer_to_profile: Dictionary`（peer_id → player_profile）
  - 负责：create/join/leave、房主迁移、start_game、engine 创建与广播

- `server/room.gd`（RefCounted）
  - 负责：房间配置、座位分配、对局 engine、命令广播、resync archive
  - 不直接暴露网络 API；只接收“来自 peer 的请求”并返回结果

部署建议见：`docs/refactors/multiplayer_public_deployment.md`。

### 1.4 `ui/`

建议新增联机场景：

- `ui/scenes/online/online_lobby.tscn` + `online_lobby.gd`
  - 输入 server URL（`ws://` 或 `wss://`）
  - 创建/加入房间（输入 room_code + token/password）
  - 显示 RoomState（玩家列表/房主/配置）
  - 房主可开始游戏

并改造对局 UI：

- `ui/scenes/game/game.gd` 与 `ui/scenes/game/game_panel_controller.gd`
  - Hotseat：保持现有 `_execute_command()` 逻辑
  - Online：把所有“会产生规则变更”的输入改为 `net_client.request_*`，等待 `CommandApplied` 再回放更新 UI
  - 对储备卡选择弹窗/历史导出做脱敏（详见 plan 文档第 5 节）

---

## 2. RPC 方法列表（建议最小集）

说明：
- server 侧对“客户端发来的请求”使用 `@rpc("any_peer", "reliable")`。
- client 侧对“服务器广播的事件”使用 `@rpc("authority", "reliable")`（默认 node authority 为 server）。
- 所有 client→server 请求建议包含 `request_id`，以便把拒绝原因回显到 UI。

### 2.1 Client → Server（RPC）

- `rpc_client_hello(request: Dictionary)`
  - `{ request_id, protocol_version, game_version, schema_version, player_profile }`
- `rpc_create_room(request: Dictionary)`
  - `{ request_id, desired_player_count, seed_mode, seed?, enabled_modules_v2, modules_v2_base_dir, join_policy="password", room_password }`
- `rpc_join_room(request: Dictionary)`
  - `{ request_id, room_code, room_password }`
- `rpc_leave_room(request: Dictionary)`
  - `{ request_id }`
- `rpc_update_room_config(request: Dictionary)`
  - `{ request_id, ... }`（仅房主）
- `rpc_start_game(request: Dictionary)`
  - `{ request_id }`（仅房主）
- `rpc_action_request(request: Dictionary)`
  - `{ request_id, action_id, params }`
- `rpc_resync_request(request: Dictionary)`
  - `{ request_id }`

### 2.2 Server → Client（RPC）

- `rpc_room_state(payload: Dictionary)`
  - `RoomState { room_code, host_peer_id, players, config, status }`
- `rpc_game_started(payload: Dictionary)`
  - `{ player_id_by_peer_id, config }`
- `rpc_command_applied(payload: Dictionary)`
  - `{ cmd, state_hash }`
- `rpc_resync_archive(payload: Dictionary)`
  - `{ archive }`
- `rpc_request_rejected(payload: Dictionary)`
  - `{ request_id, code, message }`
- `rpc_game_ended(payload: Dictionary)`
  - `{ reason_code, message }`

---

## 3. 对局回放链路（Online）

1) UI 产生输入：`action_id + params`
2) client 调用 `rpc_action_request({request_id, action_id, params})`
3) server：
   - 用 `MultiplayerAPI.get_remote_sender_id()` 获取 peer_id
   - peer_id → player_id（actor）映射
   - 执行 `GameEngine.execute_command(Command.create(action_id, actor, params), is_replay=false)`
4) server 广播 `rpc_command_applied({cmd: cmd.to_dict(), state_hash})`
5) client：
   - `Command.from_dict()` 严格解析
   - `engine.execute_command(cmd, true)` 回放
   - 对比 `engine.state.compute_hash()` 与 `state_hash`，不一致发起 `rpc_resync_request`

---

## 4. 必须处理的边界条件（阶段 1）

- 房主离开/断线（Lobby）：迁移房主并广播 RoomState。
- 任意玩家断线（InGame）：其余玩家继续；服务器对掉线玩家执行一次 `forfeit_player` 并广播（移除其棋子/占位，且该玩家不参与胜利判定）。
- 限流：对 JoinRoom/ActionRequest 做节流，避免刷请求拖垮 server。
- 敏感字段脱敏：token/password 不写日志；`select_reserve_card.selected_index` 在 UI/导出对非本人且未揭示时脱敏。
