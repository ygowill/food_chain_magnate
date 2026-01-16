# 联机改造计划（Dedicated Server + WebSocket）

目标：在保留现有 Hotseat 本地模式的前提下，新增“联机模式”（独立入口/独立流程）。联机采用**独立服务器（不作为玩家）** + **WebSocket**。阶段 1 的“保密”要求为：**玩家无法从 UI 或日志中看到其他玩家的银行储备卡选择**（不要求客户端无法获取该数据/抗作弊）。

本文是改造落地的工程计划（含模块划分、协议、改动点、测试与里程碑）。

---

## 0. 约束与决策

### 0.1 必须满足

- 保留 Hotseat：仍可本地多玩家同屏游玩，逻辑与 UX 不被联机改动破坏。
- 新增联机模式：从主菜单进入独立的“联机大厅/房间”，并进入联机对局。
- Dedicated server：服务器不占用玩家席位；玩家全部通过客户端连接。
- 传输层：使用 Godot 4 自带 `WebSocketMultiplayerPeer`（`create_server/create_client`）。
- “保密”范围：仅限制 **UI/日志/导出** 不泄露其它玩家的储备卡选择；不做强加密/反作弊（但服务器仍应校验所有请求）。

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

---

## 3. 文件/模块组织（建议）

> 目标：不污染 `core/`（保持纯逻辑），把网络与会话编排放在 `autoload/` + `ui/`/`tools/`。

### 3.1 新增目录建议

- `autoload/net_context.gd`
  - 保存当前模式：`hotseat/online_client`，以及 `local_player_id`、房间信息、玩家档案（name/color）等。
  - 作为 UI 层判断“联机/本地”的统一开关，避免到处散落 `if online`。
- `autoload/net_client.gd`（联机客户端）
  - 连接/断线重连、RPC 请求封装、收包派发。
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
  - `game_version`（`ProjectSettings.application/config/version`）
  - `schema_version`（`GameState.SCHEMA_VERSION`）
  - `player_profile`：`{name, color_index}`

服务器校验版本/协议；不匹配则断开并返回原因。

### 4.2 房间流（房主创建）

客户端→服务器：
- `CreateRoom { desired_player_count, seed_mode, seed?, enabled_modules_v2, modules_v2_base_dir }`
- `JoinRoom { room_code }`
- `UpdateRoomConfig { ... }`（仅房主允许）
- `StartGame {}`（仅房主允许；校验人数达到 player_count）

服务器→客户端：
- `RoomState { room_code, host_peer_id, players:[{peer_id, seat_index?, name, color_index}], config, status }`
- `GameStarted { player_id_by_peer_id: {peer_id:int}, config }`

### 4.3 对局消息

客户端→服务器：
- `ActionRequest { action_id, params }`
  - **不允许客户端指定 actor**；服务器基于 `peer_id -> player_id` 映射填充。

服务器→客户端：
- `CommandApplied { cmd: CommandDict, state_hash: String }`
  - `cmd` 使用 `Command.to_dict()` 完整字段（含 `phase/sub_phase/timestamp/index`），便于客户端用 `Command.from_dict()` 严格解析。

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

客户端配置 `ws://<host>:<port>`，在联机大厅输入并连接。

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

