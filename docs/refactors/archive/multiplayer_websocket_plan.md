# 联机改造计划（Dedicated Server + WebSocket）

目标：在保留现有 Hotseat 本地模式的前提下，新增“联机模式”（独立入口/独立流程）。联机采用**独立服务器（不作为玩家）** + **WebSocket**。阶段 1 的“保密”要求为：**玩家无法从 UI 或日志中看到其他玩家的银行储备卡选择**（不要求客户端无法获取该数据/抗作弊）。

本文是改造落地的工程计划（含模块划分、协议、改动点、测试与里程碑）。

补充文档：
- 实现指南（按文件与 RPC 列表）：`docs/refactors/multiplayer_implementation_guide.md`
- 公网部署（`wss://` / TLS / 反向代理示例）：`docs/refactors/multiplayer_public_deployment.md`
- 联机大厅 UI 改版（配置/模块选择复用）：`docs/refactors/archive/multiplayer_lobby_ui_redesign.md`

---

## 0. 约束与决策

### 0.1 必须满足

- 保留 Hotseat：仍可本地多玩家同屏游玩，逻辑与 UX 不被联机改动破坏。
- 新增联机模式：从主菜单进入独立的“联机大厅/房间”，并进入联机对局。
- Dedicated server：服务器不占用玩家席位；玩家全部通过客户端连接。
- 传输层：使用 Godot 4 自带 `WebSocketMultiplayerPeer`（`create_server/create_client`）。
- 公网部署：支持 `wss://`（TLS）。生产环境采用 **反向代理终止 TLS（Nginx）**（见第 2.3 节与 `docs/refactors/multiplayer_public_deployment.md`）。
- 房间加入鉴权：默认使用 **room_password**（房主设置、加入者输入；允许为空字符串=无密码）；敏感字段不得写入日志（见第 4.2 节）。
- “保密”范围：仅限制 **UI/日志/导出** 不泄露其它玩家的储备卡选择；不做强加密/反作弊（但服务器仍应校验所有请求）。
- 断线重连：阶段 1 不要求（断线后的 UX 以“明确提示 + 返回大厅/重新加入”为主）。
- 掉线处理（InGame）：其余玩家继续。掉线玩家视为 **弃权**：其棋子/占位从对局中移除，且该玩家不参与最终胜利判定（详见第 4.2.2/第 6/第 11）。

### 0.2 推荐的执行模型（阶段 1）

**服务器权威执行 + 广播已落地命令 + 客户端本地回放同一套 GameEngine**。

理由：
- 现有架构已是“Command 驱动 + 可回放 + 哈希校验”（`core/engine/game_engine/command_runner.gd`、`core/types/command.gd`、`core/tests/replay_determinism_test.gd`），适配成本最低。
- 保密只要求 UI 不展示，因此无需做“按玩家裁剪状态”（那会对 UI/规则层造成更大入侵）。
- 服务器仍能做到：映射 peer→player_id，忽略客户端伪造 actor，统一校验/执行，避免基础作弊与状态分叉。

---

## 1. 现状切入点（关键代码位置）

### 1.1 单机执行入口（Hotseat）

- `ui/scenes/game/game.gd:793`：`_execute_command(command)` 直接调用 `game_engine.execute_command(command)` 并刷新 UI。
- `core/engine/game_engine/command_runner.gd:6`：命令执行主流程（填充 phase/sub_phase/timestamp、校验、生成事件、auto-advance、记录历史）。

联机模式的目标是把 `_execute_command()` 的“直接执行”替换为“发送请求 → 等 server 广播命令 → 本地回放”。

### 1.2 Hotseat 相关耦合点（联机必须改）

- 动作面板构造命令默认用 `current_player_id`（Hotseat 语义）：
  - `ui/scenes/game/game_panel_controller.gd:480` 中 `current_player_id = state.get_current_player_id()`，大多数动作用它创建命令。
- 重组拖拽/内部动作使用 `_view_player_id` 作为 actor（允许 Hotseat 改别人）：
  - `ui/scenes/game/game_panel_controller.gd:548` 起 `_on_hand_card_dropped()`。
- 储备卡选择弹窗会在 Setup/ReserveCards 阶段对所有客户端打开（联机将泄露 UI）：
  - `ui/scenes/game/game_panel_controller.gd:805` → `:_sync_modals()` → `:_show_reserve_card_modal()`。
- Debug 历史标签页会直接打印 `cmd.params`，会泄露 `select_reserve_card.selected_index`：
  - `ui/scenes/debug/tabs/history_tab.gd:65` 与 `:110`。

---

## 2. 联机总体架构

### 2.1 进程与职责

**Server（Godot headless）**
- 维护房间/大厅、玩家列表、房间配置（由房主提交）。
- 为每个房间维护一份权威 `GameEngine`（full state）。
- 接收客户端动作请求：只接收 `action_id + params`，服务器根据连接映射填充 actor，再执行 `engine.execute_command()`。
- 广播已落地命令：把 `Command.to_dict()` 发给房间内所有客户端，并附带 `state_hash`（用于快速检测分叉）。
- 支持重同步：客户端请求 resync 时返回 `engine.create_archive()` 结果（或 initial + commands）。

**Client（普通游戏客户端）**
- 在联机模式下也维护本地 `GameEngine`（用于 UI 预览/本地回放/复用大量现有 UI 绑定逻辑）。
- 不直接执行玩家输入产生的命令：只发送请求，等待服务器广播命令后再 `execute_command(cmd, is_replay=true)`。
- UI 层基于本地 state 渲染，但在联机模式中：
  - actor 永远是 `local_player_id`（不允许通过 UI 代操其它玩家）。
  - reserve card 的“选择细节”永远不在 UI/日志泄露（详见第 5 节）。

### 2.2 WebSocket 选型

使用 Godot 4 内置：
- `WebSocketMultiplayerPeer.create_server(port, bind_address, tls_server_options?)`
- `WebSocketMultiplayerPeer.create_client(url, tls_client_options?)`

配合 `SceneTree.multiplayer`（高层 Multiplayer API）承载 RPC/消息分发。

### 2.3 公网部署（wss://）与 TLS

公网部署下建议把 **TLS 作为硬要求**（避免房间 password/令牌明文传输）。

两种落地方式：

1) **反向代理终止 TLS（推荐）**
- Dedicated server 监听 `ws://127.0.0.1:<port>`（或内网地址）。
- 由 Nginx/Caddy/Cloudflare Tunnel 等对外提供 `wss://<domain>` 并转发 WebSocket。
- 优点：证书管理/续期成熟；可顺便做限流、黑白名单、访问日志与健康检查。

2) **Godot 直启 TLS（`TLSOptions`）**
- 使用 `TLSOptions.server(key, certificate)` 作为 `create_server(..., tls_server_options)` 参数。
- 客户端使用 `TLSOptions.client(trusted_chain, common_name_override)`（或系统信任链）作为 `create_client(..., tls_client_options)` 参数。
- 注意：证书需要包含完整链（中间证书可拼接到同一个 crt 文件）。

部署示例与注意事项：`docs/refactors/multiplayer_public_deployment.md`（本项目选型：Nginx）。

---

## 3. 文件/模块组织（建议）

> 目标：不污染 `core/`（保持纯逻辑），把网络与会话编排放在 `autoload/` + `ui/`/`tools/`。

### 3.1 新增目录建议

- `autoload/net_context.gd`
  - 保存当前模式：`hotseat/online_client`，以及 `local_player_id`、房间信息、玩家档案（name/color）等。
  - 作为 UI 层判断“联机/本地”的统一开关，避免到处散落 `if online`。
- `autoload/net_client.gd`（联机客户端）
  - 连接/断线处理（阶段 1 不要求重连）、RPC 请求封装、收包派发。
  - 暴露信号：`connected`、`room_updated`、`game_started`、`command_applied`、`resync_received`。
- `server/dedicated_server.gd`（联机服务器入口脚本）
  - headless 运行，创建 WebSocket server peer，维护 rooms。
- `server/room.gd`（纯逻辑/RefCounted 或 Node，按实现偏好）
  - 管理房间状态：玩家列表、房主、配置、对局引擎、命令广播。
- `ui/scenes/online/online_lobby.tscn` + `online_lobby.gd`
  - 创建房间/加入房间、显示玩家列表与房间配置、房主开始游戏。

> 以上是组织建议；落地时也可以放进 `ui/network/` 或 `gameplay/network/`，但要避免 `core/` 引入 Node 依赖。

---

## 4. 协议设计（最小可用）

### 4.1 身份与版本握手

客户端连接后立即发：
- `ClientHello`
  - `protocol_version`（联机协议版本，独立于 game_version；建议从 1 开始）
  - `game_version`（`ProjectSettings.application/config/version`）
  - `schema_version`（`GameState.SCHEMA_VERSION`）
  - `player_profile`：`{name, color_index}`

服务器校验版本/协议；不匹配则断开并返回原因。

### 4.2 房间流（房主创建）

客户端→服务器：
- `ListRooms { request_id }`
- `RoomListSubscribe { request_id, subscribe: bool }`（可选：若用 server push，可用此开关；最小可用可不做）
- `CreateRoom { request_id, desired_player_count, seed_mode, seed?, enabled_modules_v2, modules_v2_base_dir, join_policy, room_password?, allow_spectators=true }`
  - `join_policy` 建议支持：
    - `"password"`（默认）：房主设置 `room_password`；加入者需提供同一密码；**允许为空字符串（空=无密码）**。
    - `"token"`（可选）：创建房间时由服务器生成高熵 `join_token`，只回传给房主；加入者需提供该 token。
  - 安全建议：服务器只存储 `join_token_hash`/`password_hash`，不存明文（`Crypto.generate_random_bytes` + `HashingContext.HASH_SHA256`）。
- `JoinRoom { request_id, room_code, join_token?, room_password? }`
- `LeaveRoom { request_id }`
- `UpdateRoomConfig { ... }`（仅房主允许；可包含 `allow_spectators`）
- `StartGame {}`（仅房主允许；校验人数达到 player_count）

服务器→客户端：
- `RoomList { request_id, rooms: Array[RoomSummary] }`
- `RoomState { room_code, host_peer_id, players:[{peer_id, seat_index?, name, color_index}], config, status, password_required, allow_spectators }`
- `GameStarted { player_id_by_peer_id: {peer_id:int}, config }`
- `GameEnded { reason_code, message }`（广播；例如房主中断/玩家断线/服务器关闭房间）
- `RequestRejected { request_id, code, message }`

说明：
- `request_id`：客户端生成的唯一请求标识（字符串/整数均可），用于把 `RequestRejected` 对应回 UI 交互（Toast/弹窗）。
- 服务器不得在日志/RoomState 广播中泄露 `join_token`/`room_password`。

补充（公开房间列表）：
- RoomSummary 建议字段与 UI 方案见 `docs/refactors/archive/multiplayer_lobby_ui_redesign.md`（第 7 节）。
- 观战策略（已确认）：InGame 房间允许观战，但满足：
  - `allow_spectators == true`（房主可关闭）
  - 若 `room_password` 非空：观战与加入一致，都需要提供正确 `room_password` 鉴权

### 4.2.1 room_code 与 join_token 生成建议（实现细节）

- `room_code`：
  - 目标：短、可手动输入、可分享；**不作为安全凭据**。
  - 建议：5–6 位 Base32（全大写）并剔除易混淆字符（例如 `I/O/0/1`），服务端保证唯一性（冲突则重试生成）。
- `join_token`（推荐）：
  - 目标：作为安全凭据，必须高熵、难猜测。
  - 建议：使用 `Crypto.generate_random_bytes(N)` 生成随机字节（例如 32 bytes），再编码为可复制字符串（hex 或 base64url）。
  - 存储：服务端只存 `HashingContext.HASH_SHA256` 哈希（`join_token_hash`），不存明文；比较时对输入做同样哈希再比对。
- `room_password`：
  - 允许为空字符串，表示“无密码房间”。
  - 阶段 1 可先按“明文输入 → SHA256 存储”落地；后续若需要更强口令学（salt/迭代），可再升级。

### 4.2.2 房间生命周期与断线处理（阶段 1）

阶段 1 不要求断线重连，但仍需明确“断线后发生什么”，避免客户端卡死在游戏场景。

建议约定：
- 房间状态：`Lobby`（未开始）/ `InGame`（对局中）/ `Ended`（已结束，等待返回）。
- Lobby 断线：
  - 玩家断开：从房间移除并广播 `RoomState`。
  - 房主断开：自动转移房主到剩余玩家中的第一个（或 seat 最小者），并广播 `RoomState`。
- InGame 断线（本项目阶段 1 约定）：
  - 任意玩家断开：其余玩家继续进行对局；掉线玩家视为 **弃权**：
    - 服务器对该玩家执行一次 `forfeit_player`（系统内部动作，见第 6.6），并广播命令给所有客户端回放，以保证一致性。
    - `forfeit_player` 的效果是：移除该玩家的棋子/占位（例如餐厅、营销板件；房屋/花园不移除，见第 6.6），并确保该玩家不参与最终胜利判定。
  - 客户端 UX：对局内显示该玩家“已掉线/弃权”；该玩家后续不再出现在 `turn_order` 中，不会卡住回合推进。
- 空房间回收：
  - 最简单：房间无玩家时立刻销毁。
  - 可选：保留 N 分钟 TTL，方便短暂掉线后重新加入（即便不做自动重连，也可能有价值）。

### 4.3 对局消息

客户端→服务器：
- `ActionRequest { request_id, action_id, params }`
  - **不允许客户端指定 actor**；服务器基于 `peer_id -> player_id` 映射填充。

服务器→客户端：
- `CommandApplied { cmd: CommandDict, state_hash: String }`
  - `cmd` 使用 `Command.to_dict()` 完整字段（含 `phase/sub_phase/timestamp/index`），便于客户端用 `Command.from_dict()` 严格解析。
- `RequestRejected { request_id, code, message }`

### 4.4 重同步（阶段 1 必做）

客户端在以下场景触发 resync：
- 收到 `CommandApplied` 但本地 `command_history.size() != cmd.index`。
- 本地执行后 `state.compute_hash() != state_hash`。

客户端→服务器：
- `ResyncRequest {}`

服务器→客户端：
- `ResyncArchive { archive: Dictionary }`（来自 `GameEngine.create_archive()`）

客户端收到后：
- `engine.load_from_archive(archive)`，并继续接收后续 `CommandApplied`。

### 4.5 错误码（建议约定）

最小集合（示例）：
- `ERR_VERSION_MISMATCH`：game_version/schema_version/protocol_version 不匹配
- `ERR_ROOM_NOT_FOUND`：room_code 不存在
- `ERR_ROOM_AUTH_FAILED`：join_token/password 不正确
- `ERR_ROOM_FULL`：房间已满
- `ERR_NOT_HOST`：非房主调用 UpdateRoomConfig/StartGame
- `ERR_INVALID_CONFIG`：配置非法（玩家数/seed/modules_v2 等）
- `ERR_SPECTATE_NOT_ALLOWED`：不允许观战（例如房主关闭观战）
- `ERR_GAME_NOT_STARTED`：对局未开始就发送 ActionRequest
- `ERR_ACTION_REJECTED`：动作校验失败（可把 `Result.error` 转为 message）
- `ERR_RATE_LIMITED`：请求过于频繁
- `ERR_INTERNAL`：服务器内部错误

---

## 5. UI/日志“储备卡保密”落点（阶段 1）

保密规则：在银行第一次破产前（`player.reserve_card_revealed == false`），其它玩家的 `reserve_card_selected/selected_index` 不得出现在 UI/日志/导出中。

### 5.1 储备卡选择弹窗：只允许本人操作 + 他人不可见选择

现状：
- Setup/ReserveCards 阶段，`GamePanelController._sync_modals()` 会打开 `ReserveCardSelectionModal`（`ui/scenes/game/game_panel_controller.gd:805`）。

改造：
- 引入 `local_player_id`（来自 `autoload/net_context.gd`）。
- 当 `state.phase == "Setup" && state.sub_phase == "ReserveCards"`：
  - 若 `local_player_id == current_player_id`：显示并可交互（现有 modal）。
  - 否则：显示“等待玩家X选择”的遮罩（两种实现选其一）：
    1) 复用 `ReserveCardSelectionModal` 增加 `set_interactive(false)`，隐藏按钮/禁用按钮，只显示等待文案。
    2) 新增 `WaitingModal`（最简单：只一行文本 + 不可取消）。

### 5.2 命令历史/导出：脱敏 `select_reserve_card`

现状：
- `ui/scenes/debug/tabs/history_tab.gd` 会打印 `cmd.params`（`selected_index` 会泄露）。

改造：
- 增加一个统一的格式化工具（建议在 UI 层）：
  - `ui/utils/command_privacy.gd`：`sanitize_params(cmd: Command, viewer_id: int, state: GameState) -> Dictionary`
- 规则：
  - 若 `cmd.action_id == "select_reserve_card"` 且 `cmd.actor != viewer_id` 且该玩家 `reserve_card_revealed == false`：
    - 展示 `{selected_index: "?"}` 或 `{}` 或 `{selected_index: "***"}`（建议保留 key 但隐藏值，便于调试）。
  - 当 `reserve_card_revealed == true` 后允许展示。
- 同时覆盖：
  - HistoryTab 列表展示（`_format_params`）。
  - HistoryTab 导出（`_on_export_pressed`）。
  - 任何可能打印 `Command.params` 的 debug 工具（后续扫描 `rg "cmd\\.params"`）。

### 5.3 其它 UI 点（建议纳入 checklist）

- Debug StateTab 目前会 `str(round_state[key])`（`ui/scenes/debug/tabs/state_tab.gd:194`），若未来把 reserve card 信息塞进 round_state，可能泄露；建议联机模式默认隐藏 DebugPanel，或在联机模式下对 `players[*].reserve_card_selected` 打码。

---

## 6. 输入权限与 actor 语义（联机必须修正）

联机模式下，“一个客户端只控制一个玩家”。现有 Hotseat 允许代操/切视角，必须隔离。

### 6.1 统一引入 local_player_id

- `autoload/net_context.gd` 维护 `local_player_id`，由 `GameStarted` 消息确定。
- UI 层所有“会发出动作请求”的地方都必须使用 `local_player_id` 作为 actor（或根本不带 actor，把 actor 放到 server）。

### 6.2 ActionPanel：可点击动作应基于 local_player_id

现状：
- `ActionPanel` 用 `_current_player_id` 生成 `Command.create(action_id, _current_player_id)` 做 validate（`ui/components/action_panel/action_panel.gd:598`）。

改造建议：
- 拆分两个概念：
  - `turn_player_id`：当前回合行动玩家（用于高亮/标题）。
  - `input_player_id`：本机可操作玩家（联机=local_player_id；hotseat=turn_player_id）。
- 接口建议：
  - `set_turn_player(player_id)`
  - `set_input_player(player_id)`
- 联机模式下：
  - 大多数阶段 `input_player_id != turn_player_id` 时应显示“等待中”并禁用按钮。
  - Restructuring 等“同时阶段”可放开：`input_player_id` 仍为 local，但允许发起自己的动作。

### 6.3 GamePanelController：创建命令的 actor 改为 input_player_id

现状：
- `ui/scenes/game/game_panel_controller.gd:484` 使用 `current_player_id` 作为 actor 构造绝大多数命令。

改造：
- 在联机模式下，`on_action_requested()` 不直接构造 `Command` 执行；而是调用 Session 的 `request_action(action_id, params)`。
- Hotseat 模式保持原路径（直接 `_execute_command(Command.create(...))`）。

### 6.4 重组拖拽：禁止代操其它玩家

现状：
- `_on_hand_card_dropped()` 会用 `_view_player_id` 当 actor（`ui/scenes/game/game_panel_controller.gd:563`）。

改造：
- 联机模式强制 `actor_id = local_player_id`。
- 同时，当 `view_player_id != local_player_id` 时禁用拖拽（`hand_area.set_drag_enabled(false)` / `company_structure.set_drag_enabled(false)`），避免 UI 误导。

### 6.5 服务器侧的基础防护（仍需要）

即使“保密不要求抗作弊”，仍应做到：
- server 永远忽略客户端提供的 actor（客户端请求不带 actor）。
- server 对每个请求执行 `ActionRegistry.run_validators` + `executor.validate`（通过 `engine.execute_command` 已包含）。

### 6.6 掉线/弃权：`forfeit_player`（阶段 1 新增内部动作）

为满足“掉线玩家不再参与 + 棋子从对局移除 + 其余玩家继续”，建议增加一个系统内部动作：

- `action_id`: `forfeit_player`
- `actor`: `-1`（系统）
- `params`: `{ "player_id": int }`
- 执行时机：server 检测到 peer 断线，映射到 player_id 后立即执行并广播。

建议的状态变更（需要落地时再细化/写测试）：

1) **回合推进层**
   - 从 `state.turn_order` / `state.selection_order` 中移除该 player_id。
   - 若 `state.current_player_index` 指向被移除玩家，修正到下一个可行动玩家，避免卡死。
2) **地图与棋子**
   - 移除该玩家拥有的餐厅：清理 `state.map.restaurants`、`players[player_id].restaurants`，并清空 `state.map.cells[*].structure` 中对应 `piece_id=restaurant` 的占用（匹配 `restaurant_id`/`owner`）。
   - 移除该玩家拥有的营销：清理 `state.marketing_instances`（owner==player_id），并同步清理 `state.map.marketing_placements`（owner==player_id）。
   - 明确：**不移除**该玩家放置的房屋/花园及其需求标记（这些作为地图结构保留，会继续影响其它玩家）。
   - 修改地图结构后必须 `RoadGraphCache.invalidate_road_graph(state)`，避免距离缓存错误。
3) **玩家资产与胜负**
   - 清空/冻结该玩家资源（员工/库存/忙碌营销员/里程碑等）以避免后续规则误用。
   - 增加 `player.forfeited=true`（或 `player.status="forfeited"`）字段，用于：
     - UI 标记“已弃权”
     - GameOver 排名与赢家判定时排除弃权玩家（本项目需求：弃权玩家不可获胜）

落地时需要同步更新：
- `ui/components/game_over/game_over_panel.gd`：排名时排除/标注弃权玩家，且冠军不应授予弃权玩家。
- 任何“遍历 players.size() 计算赢家/奖励”的规则点：若语义上应排除弃权玩家，需要加过滤（否则会产生边界 bug）。

---

## 7. 对局启动与初始化一致性

### 7.1 初始化策略

推荐：在 `GameStarted` 里广播完整 config，让客户端本地 `GameEngine.initialize(...)`。
- `player_count/seed/enabled_modules_v2/modules_v2_base_dir` 全部来自房主配置、由 server 广播。
- 客户端初始化后，等待 server 广播第一条命令（通常是 ReserveCards 阶段由当前玩家选择）。

### 7.2 一致性风险与应对

风险：跨平台资源枚举顺序、浮点解析等导致初始 state 不一致。

应对：
- 客户端初始化后，server 立刻下发一次 `state_hash`（或 `ResyncArchive`）用于对齐。
- 若 mismatch，客户端直接走 resync。

---

## 8. 里程碑拆分（建议按“可验证最小增量”）

### M1：网络骨架 + 单房间大厅（不进游戏）
- server：WebSocket server 起得来；支持 create/join；同步 RoomState；房主能设置 config。
- client：联机大厅 UI；能创建/加入；能看到玩家列表与房间配置同步。
- 验证：两客户端加入同一房间，房主修改配置，另一端实时更新。

### M2：启动对局 + 命令广播回放（无保密细节）
- server：`StartGame` 后创建 `GameEngine`；建立 peer→player_id；广播 GameStarted。
- client：收到 GameStarted 后初始化本地 engine；进入 game 场景；仅接收 CommandApplied 并回放。
- 验证：能走完 Setup/ReserveCards（先不做 UI 保密门禁）、进入放置餐厅、推进回合。

### M3：输入权限收口 + “储备卡 UI/日志保密”
- client：引入 local_player_id；只有本机玩家能操作；其它阶段正确显示等待状态。
- client：ReserveCards 弹窗只对本人可交互；HistoryTab/导出脱敏。
- 验证：两客户端联机，A 选储备卡时 B 端不会看到选择结果；B 的历史/导出不含 A 的 selected_index。

### M4：resync + 稳定性（断线/重连/丢包）
- server：支持 ResyncArchive；（可选）支持 Join mid-game（观战或重连）。
- client：检测 index/hash 不一致自动请求 resync；手动按钮触发 resync（便于测试）。
- 验证：人为让客户端丢弃一条 CommandApplied 后能自愈恢复到一致状态。

---

## 9. 测试计划

### 9.1 逻辑一致性测试（推荐新增）

新增一个纯逻辑测试：模拟 “server 执行命令序列 → client 回放命令序列”，逐条对比 `state.compute_hash()`。
- 复用 `core/tests/replay_determinism_test.gd` 的命令序列生成器。
- 目标：在不启动真实网络的情况下，验证“广播命令回放模型”成立。

### 9.2 Headless 冒烟

- server headless 启动 + 两个 client headless 连接（可先不做；阶段 2 之后再补）。

### 9.3 手工验证清单（阶段 3 必跑）

- 两客户端：
  - 房主创建房间、设置玩家数/种子/模块、开始游戏。
  - Setup/ReserveCards：B 端只能看到“等待 A 选择”，看不到 A 选的是哪张；HistoryTab/导出无泄露。
  - 银行第一次破产后：储备卡被揭示（`reserve_card_revealed=true`）后，允许在日志/面板显示。

---

## 10. 运行方式（建议约定）

### 10.1 Dedicated server

建议用同一项目运行 headless server（示例命令，具体脚本路径以实现为准）：

```bash
godot --headless --path . --script res://server/dedicated_server.gd -- --port 8080
```

### 10.2 Client 连接

开发/局域网：
- 客户端配置 `ws://<host>:<port>` 并连接（例如 `ws://127.0.0.1:8080`）。

公网部署：
- 客户端配置 `wss://<domain>/<path>` 并连接（例如 `wss://example.com/ws`，由反向代理转发到内网 `ws://127.0.0.1:<port>`）。
- 房间 password/令牌应作为消息字段发送（不放在 URL/querystring；且不得写入日志）。

---

## 11. 风险清单（阶段 1）

- **一致性依赖**：客户端本地回放要求初始化与执行完全确定性；虽已有 determinism 测试，但跨平台仍可能踩坑 → 必须做 resync。
- **UI 入侵面较大**：当前 Hotseat 的“view_player 可代操”贯穿多个 UI 控制器 → 必须引入“模式开关 + local_player_id”，并逐点收口。
- **Debug 面板泄露**：开发期很容易从 DebugPanel 看到储备卡选择 → 联机模式应默认关闭 DebugPanel 或做统一脱敏。

---

## 12. 后续可选增强（不在阶段 1）

- 真正的“强保密/抗作弊”：按玩家裁剪 state、加密/承诺-揭示（commit-reveal）等。
- 观战模式：不给 input 权限，仅接收命令回放。
- 断线重连带身份令牌：避免 peer_id 变化导致占座丢失。
