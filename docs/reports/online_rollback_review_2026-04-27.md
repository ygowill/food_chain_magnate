# 联机与回滚设计评估及修复记录

日期：2026-04-27

## 范围

本记录覆盖当前联机主链路、恢复房完整历史启动、客户端重放校验、回滚到回合开始、resync delta/snapshot 以及相关代码划分。

当前联机模型整体上采用“服务器权威 + 客户端确定性重放 + state hash 校验 + delta/snapshot 恢复”，适合本项目的回合制流程。这里的“回滚”主要是服务器权威回滚到当前玩家回合开始，并让客户端按 metadata 本地回滚后校验；它不是实时预测式 rollback netcode。

## 已确认问题

### P1：平台自动进入 InGame 恢复房时没有标记完整快照启动

- 位置：`autoload/net_client/server.gd`
- 影响：`_platform_auto_join()` 在 InGame 房间内发送 `rpc_game_started` 时没有附带 `resume_bootstrap_mode = "full_archive_snapshot"`。
- 风险：客户端可能按普通新局路径提前发出 `game_started`，绕过恢复房必须等待完整历史快照的约束。
- 处理状态：已修复。

### P2：完整快照分片恢复路径重复发出 `resync_archive_received`

- 位置：`autoload/net_client/client.gd`
- 影响：pending resume snapshot 分支内已经 emit `resync_archive_received`，函数末尾又无条件 emit 一次。
- 风险：UI/controller 可能重复加载 archive、重复刷新日志时间线或触发额外恢复流程。
- 处理状态：已修复。

### P2：客户端应用服务端命令失败后没有主动 resync

- 位置：`ui/scenes/game/controllers/online_resync_controller.gd`
- 影响：`engine.execute_command(cmd, true)` 失败时只记录日志并返回。
- 风险：客户端可能停留在落后或不一致状态，直到后续其他校验才发现。
- 处理状态：已修复。

### P3：旧 dual-engine / live-tail 恢复代码仍混在主路径附近

- 位置：`autoload/net_client_online_resume_support.gd`、`autoload/online_resume_session_state.gd`
- 影响：文档已经确定恢复房使用 single full-engine startup，但代码仍保留 `full_replay_engine`、`full_replay_live_tail_commands`、`runtime_anchor` 等迁移期模型。
- 风险：维护者需要同时理解新旧两套语义，后续修改容易误触旧路径。
- 处理状态：待改善。

### P3：联机 client/server 文件职责过宽

- 位置：`autoload/net_client/client.gd`、`autoload/net_client/server.gd`
- 影响：server 侧混合平台自动入房、启动、resync、回滚、断线、结算；client 侧混合启动、分片、delta、archive 加载与 index translation。
- 风险：文件膨胀会增加回归风险，测试定位也更困难。
- 处理状态：已做第一步低风险拆分，仍建议继续拆分 server/client 主文件。

### P3：过多动态兜底降低 fail-fast 能力

- 位置：`autoload/net_client.gd`、`autoload/net_client_internal.gd` 以及部分 client/server glue。
- 影响：大量 `has_method` 兼容检查适合迁移期，但对当前必须存在的协作者会掩盖 wiring 错误。
- 风险：真实接线问题可能退化成静默失败或延迟发现。
- 处理状态：待改善。

### P3：timeline refresh deferred callback 命名与实际行为不一致

- 位置：`ui/scenes/game/controllers/online_resync_controller.gd`
- 影响：`_request_live_log_timeline_refresh_deferred` 实际上和 `_request_live_log_timeline_refresh` 指向同一个 callback，并没有真正 deferred。
- 风险：读代码时会误以为存在两条刷新策略，实际只是重复分支。
- 处理状态：已清理。

## 修复原则

1. 先修会导致错误联机状态的行为问题。
2. 每次变更保持小范围，并在本文件记录变更。
3. 恢复房主链路以 single full-engine startup 为准，旧 dual-engine 仅作为明确隔离的兼容路径。
4. 涉及 GDScript 修改时保持 tab 缩进，不做无关格式化。

## 变更记录

### 2026-04-27：建立评估与修复跟踪

- 新增本报告，记录已确认问题、风险等级和后续修复原则。
- 验证：文档变更，无需运行 Godot 测试。

### 2026-04-27：修复 InGame 恢复房 platform auto-join 启动标记

- 修复 `autoload/net_client/server.gd` 中 `_platform_auto_join()` 的 InGame `rpc_game_started` payload：当房间是 `resume_archive` 时附带 `resume_bootstrap_mode = "full_archive_snapshot"`。
- 扩展 `core/tests/platform_connect_token_auto_join_test.gd`，覆盖恢复房已经进入 InGame 后同一玩家通过平台 token 重连的路径，断言收到 snapshot manifest/chunk 且 `rpc_game_started` 带完整快照启动标记。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：修复完整快照恢复重复信号

- 调整 `autoload/net_client/client.gd` 的 snapshot chunk 汇总逻辑：pending resume 分支完成 bootstrap 后只 emit 一次 `resync_archive_received`；普通 resync 分支在本地 archive bootstrap 后 emit。
- 扩展 `core/tests/online_resume_full_snapshot_bootstrap_test.gd`，断言完整快照 bootstrap 后 `resync_archive_received` 只发出一次。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：命令回放失败后主动 resync

- 修改 `ui/scenes/game/controllers/online_resync_controller.gd`：客户端应用服务端命令失败时立即触发 `_request_online_resync("command_apply_failed")`。
- 扩展 `core/tests/game_online_resync_request_rejection_test.gd`，用失败 engine 覆盖命令 replay 失败路径，断言 controller 会请求 resync 并进入同步中状态。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：抽出 GameStarted payload 构造 helper

- 新增 `autoload/net_client/game_started_payloads.gd`，集中构造 server 侧 `rpc_game_started` payload，并统一恢复房 `resume_bootstrap_mode = "full_archive_snapshot"` 标记。
- 调整 `autoload/net_client/server.gd` 的 platform auto-join、join in-game、start-game 三条路径使用同一个 helper，降低三条路径后续再次漂移的风险。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：清理 timeline refresh 冗余 callback

- 移除 `ui/scenes/game/controllers/online_resync_controller.gd` 中没有真实 deferred 语义的 `_request_live_log_timeline_refresh_deferred`。
- 保留原有刷新行为：命令 replay 成功后仍调用 `_request_live_log_timeline_refresh`。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。
