# 联机开局 Bootstrap / 统一 Loading 重构方案

## 背景

当前联机开局存在两个明显体验问题：

1. 房主点击“开始游戏”后，会先在大厅等待，再进入 Game 场景后继续等待，存在“两段加载”的割裂感。
2. 普通玩家通常要等到房间已变为 `InGame`、甚至本地引擎已完成 bootstrap 后，才看到反馈或直接被切进游戏，缺少及时可见的过程提示。

本方案的目标是将“开始联机对局”改造成一条端到端的 Bootstrap 流程：

- 房主和玩家都要尽快进入统一 Loading 状态；
- 进度条要由真实流程驱动，而不是纯伪动画；
- 进入 Game 场景前后必须保持同一条 Loading 生命周期，不再出现双重等待；
- 服务端与客户端对“是否可进入对局”达成一致，避免有人已进场景、有人仍在加载的分裂状态。

## 目标体验

### 用户视角

1. 房主点击开始游戏；
2. 房主与玩家在 1 帧内进入统一 Loading 页面；
3. 页面展示：
	- 标题；
	- 当前阶段说明；
	- 主进度条；
	- 必要时展示“等待其他玩家 x/y”；
4. 本地 bootstrap 完成后，若仍需等待其他玩家，进度条停在等待区间并显示等待状态；
5. 所有玩家都 ready 后，再一起进入 Game；
6. Game 场景首轮 UI 完成后，Loading 才真正消失。

### 技术目标

- 新增房间状态 `Starting`；
- 开局拆成 `prepare -> local bootstrap -> ready ack -> commit` 四段；
- 引入全局 `LoadingCoordinator`，统一管理 loading session；
- 新增 `OnlineMatchBootstrapCoordinator`，统一管理联机开局 bootstrap 状态；
- 客户端 bootstrap 支持分阶段汇报；
- 兼容现有 `SceneManager.show_loading()/hide_loading()` 调用，逐步迁移到 session 化接口。

## 设计总览

### 状态机

房间状态扩展为：

- `Lobby`
- `Starting`
- `InGame`
- `Ended`

其中 `Starting` 表示：

- 房主已发起开局；
- 服务端正在准备权威对局或等待客户端本地 bootstrap；
- 不允许继续编辑配置；
- 不允许重复点击开始游戏；
- 不允许新玩家/观战者加入本次启动中的对局。

### 服务端开局生命周期

1. `handle_rpc_start_game()` 通过房间校验；
2. 房间进入 `Starting`；
3. 服务端准备权威 engine / resume payload；
4. 向每个 peer 下发本地 bootstrap 所需数据；
5. 各客户端本地 bootstrap 完成后回传 `ready`；
6. 全员 ready 后，服务端 commit：
	- 安装权威 engine；
	- 房间状态切换到 `InGame`；
	- 广播正式 room_state；
7. 客户端确认 `InGame + 本地 bootstrap ready` 后进入 Game。

若任一关键路径失败：

- 服务端 abort 本次 bootstrap；
- 房间回退到 `Lobby`；
- 所有客户端结束 loading 并展示错误。

## 模块拆分

### 1. LoadingCoordinator（新增 autoload）

职责：

- 管理多个 loading session；
- 选择当前生效的 session；
- 将 session 状态投射到 `SceneManager` / `LoadingOverlay`；
- 提供 begin/update/finish/fail API；
- 保持跨场景连续的 loading 生命周期。

建议 API：

- `begin_session(session_id: String, options: Dictionary = {})`
- `update_session(session_id: String, patch: Dictionary)`
- `finish_session(session_id: String)`
- `fail_session(session_id: String, message: String = "")`
- `has_session(session_id: String) -> bool`
- `get_session(session_id: String) -> Dictionary`

### 2. SceneManager（扩展）

保留旧接口：

- `show_loading()`
- `hide_loading()`

新增底层状态应用接口：

- `apply_loading_state(state: Dictionary)`
- `clear_loading_state()`

`LoadingCoordinator` 通过这组接口驱动 LoadingOverlay。

### 3. LoadingOverlay（扩展）

现有进度条组件继续保留，但升级展示能力：

- 标题；
- 详细说明；
- 阶段标签；
- 主进度条；
- 可选等待人数文本；
- 错误态说明。

### 4. OnlineMatchBootstrapCoordinator（新增 autoload）

职责：

- 管理当前联机开局 bootstrap session；
- 汇总服务端阶段、本地 bootstrap 阶段、玩家 ready 进度；
- 驱动 `LoadingCoordinator`；
- 判断何时允许从 Lobby 进入 Game；
- 让 Game 场景继续接管同一条 session，直到首轮 UI ready。

### 5. OnlineRoom（重构）

新增：

- `STATUS_STARTING`
- pending bootstrap session 字段
- `prepare_start_game()`
- `commit_prepared_start_game()`
- `abort_prepared_start_game()`
- `mark_pending_start_peer_ready()`

### 6. NetClient / 协议扩展

建议新增信号：

- `match_bootstrap_started(payload: Dictionary)`
- `match_bootstrap_progress(payload: Dictionary)`
- `match_bootstrap_ready_waiting(payload: Dictionary)`
- `match_bootstrap_committed(payload: Dictionary)`
- `match_bootstrap_aborted(payload: Dictionary)`

新增请求：

- `request_match_bootstrap_ready(bootstrap_id: String)`
- `request_match_bootstrap_failed(bootstrap_id: String, reason: String)`

可复用现有 `game_started` 作为“本地 runtime engine ready”信号，但不再直接等价于“允许进 Game”。

## 进度模型

统一进度区间建议如下：

- `0% ~ 10%`：房主点击开始 / 玩家收到 `Starting`
- `10% ~ 30%`：服务端准备权威对局
- `30% ~ 80%`：客户端本地 bootstrap
- `80% ~ 95%`：等待其他玩家 ready
- `95% ~ 100%`：进入 Game 场景并完成首轮 UI sync

### 文案建议

房主：

- 正在同步房间配置…
- 服务器正在准备对局…
- 正在初始化本地对局…
- 正在等待其他玩家…
- 正在进入对局…

玩家：

- 房主正在开始游戏…
- 服务器正在准备对局…
- 正在初始化本地对局…
- 正在等待其他玩家…
- 正在进入对局…

## 本地 bootstrap 分阶段设计

### 新局初始化

拆分出可逐帧汇报的 runner，阶段包括：

1. 加载 GameConfig
2. 应用模块计划
3. 校验 starting inventory
4. 构建 GameData
5. 装配 ActionRegistry
6. 创建初始 GameState
7. 应用 reserve / option override
8. 选地图
9. 生成地图
10. bake 地图
11. 写入地图
12. 应用 state initializers
13. 计算 invariants
14. 创建 checkpoint
15. 发出 `GAME_STARTED`

### 存档 / snapshot 恢复

拆分 runner，阶段包括：

1. 校验 archive/schema
2. 装配 modules_v2
3. 解析 initial_state
4. 恢复 RNG
5. 重建 GameData / ActionRegistry
6. 分批回放命令
7. rewind 到 current_index
8. finalize

`commands replay` 必须按批次推进，并在批次间 `await process_frame`，否则 UI 仍会卡死。

## 失败处理

### Starting 阶段掉线

v1 策略：

- 任一正式玩家在 `Starting` 期间掉线，直接 abort 本次开局；
- 房间回到 `Lobby`；
- UI 展示“有玩家掉线，本次开局已取消”。

### 客户端 bootstrap 失败

- 客户端上报失败；
- 服务端 abort；
- 其他玩家停止等待并回 Lobby。

### Stale / 重复消息

所有 bootstrap 相关 payload 必须携带：

- `room_code`
- `bootstrap_id`

客户端仅处理当前活动 session 的消息，旧消息直接忽略。

## 持久化策略

`Starting` 不做长期可恢复持久化：

- 持久化时若房间处于 `Starting`，应先丢弃 pending bootstrap session，再按 `Lobby` 语义保存；
- 不恢复半截 bootstrap 状态。

## 测试计划

### 新增测试

1. `online_room_starting_bootstrap_test.gd`
2. `online_lobby_starting_loading_test.gd`
3. `loading_coordinator_session_test.gd`
4. `game_engine_initialize_runner_test.gd`
5. `game_engine_archive_load_runner_test.gd`
6. `online_match_bootstrap_commit_waits_for_all_ready_test.gd`
7. `online_match_bootstrap_abort_on_failure_test.gd`

### 回归重点

- 现有 `online_lobby_in_game_entry_fallback_test`
- `online_client_game_started_reconnect_test`
- `online_resume_full_snapshot_bootstrap_test`
- `platform_connect_token_auto_join_test`

## 实施顺序

### Phase 1：基础设施

1. 新增 `LoadingCoordinator`
2. 升级 `LoadingOverlay`
3. 扩展 `SceneManager` 支持 session 化状态应用

### Phase 2：服务端状态机

4. 新增 `Starting`
5. OnlineRoom prepare/commit/abort
6. 扩展 bootstrap 协议

### Phase 3：客户端协同

7. 新增 `OnlineMatchBootstrapCoordinator`
8. Lobby 接入 `Starting` / ready / commit 流程
9. Game 接入 bootstrap session 收尾

### Phase 4：真实进度

10. 新增新局 initialize runner
11. 新增 archive load runner
12. 接入 snapshot chunk 进度

### Phase 5：测试与回归

13. 编译检查
14. `game_smoke_test`
15. `all_tests`

## 当前实施状态

本文档对应的实现工作将按上述顺序推进。  
当前分支的第一阶段目标是先落地：

- 文档；
- loading session 基础设施；
- `Starting` 状态与 bootstrap 协调骨架；
- Lobby / Game 的首批接入点。
