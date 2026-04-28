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
- 影响：文档已经确定恢复房使用 single full-engine startup，但早期代码仍保留过 archive-payload dual-engine / live-tail 迁移模型。
- 风险：维护者需要同时理解新旧两套语义，后续修改容易误触旧路径。
- 处理状态：已删除旧 archive-payload / live-tail 可执行路径；snapshot 中仍保留固定为 0/false 的兼容诊断字段。

### P3：联机 client/server 文件职责过宽

- 位置：`autoload/net_client/client.gd`、`autoload/net_client/server.gd`
- 影响：server 侧混合平台自动入房、启动、resync、回滚、断线、结算；client 侧混合启动、分片、delta、archive 加载与 index translation。
- 风险：文件膨胀会增加回归风险，测试定位也更困难。
- 处理状态：已做多步低风险拆分，server 侧 GameStarted payload、resync transfer/service、断线 grace service、结算 payload builder 已独立；client 侧 resync snapshot/delta service 已独立；剩余大文件继续拆分属于后续架构演进。

### P3：过多动态兜底降低 fail-fast 能力

- 位置：`autoload/net_client.gd`、`autoload/net_client_internal.gd` 以及部分 client/server glue。
- 影响：大量 `has_method` 兼容检查适合迁移期，但对当前必须存在的协作者会掩盖 wiring 错误。
- 风险：真实接线问题可能退化成静默失败或延迟发现。
- 处理状态：已收敛 `NetClientInternal`、恢复历史 adapter 和 match bootstrap 对固定 `NetClient` API 的动态方法检查；跨 autoload 协调器与 Room/RoomManager 可选能力仍保留显式检查。

### P3：timeline refresh deferred callback 命名与实际行为不一致

- 位置：`ui/scenes/game/controllers/online_resync_controller.gd`
- 影响：`_request_live_log_timeline_refresh_deferred` 实际上和 `_request_live_log_timeline_refresh` 指向同一个 callback，并没有真正 deferred。
- 风险：读代码时会误以为存在两条刷新策略，实际只是重复分支。
- 处理状态：已清理。

## 修复原则

1. 先修会导致错误联机状态的行为问题。
2. 每次变更保持小范围，并在本文件记录变更。
3. 恢复房主链路以 single full-engine startup 为准，旧 dual-engine 不再作为可执行恢复路径。
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

### 2026-04-27：隔离 legacy dual-engine / live-tail 语义

- 在 `autoload/online_resume_session_state.gd` 中新增 full-history source mode 常量，并标注 `full_archive` / live-tail 字段为 legacy dual-engine 兼容状态。
- 移除 `OnlineResumeSessionState` 中未被代码引用的 `has_full_archive_payload()` 和 `get_pending_full_history_live_tail_commands()`。
- 将 `autoload/net_client_online_resume_support.gd` 中旧 archive-payload full replay 构建、live-tail replay 和命令应用 helper 重命名为 `legacy` 路径，明确当前恢复房主链路应使用 `single_full_engine_mode`。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：删除旧 dual-engine / live-tail 执行路径

- 删除 `autoload/net_client_online_resume_support.gd` 中旧 archive-payload full replay 构建、live-tail 缓存、live-tail replay 和 delta `_full_history_entries` 记录路径。
- 精简 `autoload/online_resume_session_state.gd`，移除 `full_archive`、`full_history_generation`、live-tail 命令数组及相关 mutator。
- 保留 `snapshot()` 中 `full_history_live_tail_*` 与 `has_full_archive_payload` 诊断 key，但固定返回 `0` / `false`，避免外部诊断读取立即断裂。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：收敛 full-history 清理命名

- 新增 `clear_online_resume_full_history_state()` 作为恢复历史状态清理主 API，并更新内部调用与测试引用。
- 后续清理已删除旧 `clear_online_resume_dual_engine_state()` 兼容别名。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：收敛 NetClient 恢复历史 facade 兜底

- 移除 `autoload/net_client.gd` 中恢复历史相关 facade 对固定 `_internal` 方法的 `has_method` 检查。
- 保留 `_internal` 实例有效性检查；固定内部 API 缺失时应 fail-fast。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：抽出 server resync transfer 构造

- 新增 `autoload/net_client/server_resync_transfer_builder.gd`，集中构造 full snapshot、archive snapshot 和 delta resync transfer。
- `autoload/net_client/server.gd` 保留策略选择、发送和日志职责，transfer 具体构造委托给 helper，减少 server 主文件中的纯构造逻辑。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：收敛 NetClientInternal 动态兜底

- 移除 `autoload/net_client_internal.gd` 中对固定 `_client` / `_server` 模块方法的 `has_method` 检查。
- 保留实例有效性检查；模块由 preload 创建，缺方法应在开发期直接暴露，而不是静默跳过。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：迁移恢复历史命名到 full-history

- 将联机恢复房缓存 API、状态字段、snapshot key 和相关测试从 `full_replay_*` 迁移到 `full_history_*`。
- 保留核心回放 API `GameEngine.full_replay()` 及本地 timeline controller 的 replay 术语，不把引擎回放语义误改成联机恢复历史语义。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：删除 dual-engine 清理兼容别名

- 删除 `NetClient`、`NetClientInternal`、client 模块和恢复历史 support 中的 `clear_online_resume_dual_engine_state()` 别名。
- 当前代码只暴露 `clear_online_resume_full_history_state()`，避免新代码继续引用旧 dual-engine 术语。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：抽出 server resync service

- 新增 `autoload/net_client/server_resync_service.gd`，承接 server 侧 resync snapshot/delta 构造、发送、best-effort fallback 和 resync 限流状态。
- 新增 `autoload/net_client/server_log_format.gd`，让 server 主文件和 resync service 共享 request/room/hash 日志格式。
- `autoload/net_client/server.gd` 保留业务决策和 RPC handler，减少主文件中的 resync 细节代码。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：收敛恢复历史固定 NetClient API 兜底

- 移除 `OnlineResumeFullHistoryAdapter` 对固定 `NetClient` 恢复历史方法的 `has_method` 检查；缺方法时应 fail-fast，而不是静默返回空 timeline。
- 移除 `OnlineMatchBootstrap` 对固定 `NetClient` bootstrap / resync 清理方法的 `has_method` 检查。
- 保留 `NetClient == null` 防护，避免非联机或测试上下文直接崩溃。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：标注旧恢复房双轨文档为历史归档

- 更新 `docs/online/README.md`、`online_resume_fastload_full_history_design_2026-04-14.md` 和 `online_resume_hot_path_rebuild_plan_2026-04-16.md`。
- 明确旧 `full_replay_*` / dual-engine / fast-start 文档只保留历史上下文，不再作为当前实现依据；当前实现以单 full-engine 与 `full_history_*` API 为准。
- 验证：文档变更，无需运行 Godot 测试。

### 2026-04-27：抽出 server match finalize payload builder

- 新增 `autoload/net_client/server_match_finalize_payload_builder.gd`，集中构造结算 summary、participant score 和统计 payload。
- `autoload/net_client/server.gd` 保留结算状态推进、后端提交和重试流程，具体 payload 构造迁出主文件。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：抽出 server disconnect grace service

- 新增 `autoload/net_client/server_disconnect_grace_service.gd`，集中管理断线 grace ticket、定时器、Lobby 重连席位释放和 InGame 超时自动 forfeit。
- `autoload/net_client/server.gd` 保留 peer disconnect / reconnect 入口与业务回调，断线 grace 内部状态迁出主文件。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：抽出 client resync service

- 新增 `autoload/net_client/client_resync_service.gd`，集中处理客户端 resync snapshot manifest/chunk 拼装、archive pending 状态、delta 缓存与 deterministic replay 应用。
- `autoload/net_client/client.gd` 保留 RPC 入口、恢复房 bootstrap 回调和 engine lifecycle，resync 细节迁入独立 service。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过，`386/386`。

### 2026-04-27：抽象通用联机回滚元数据通道

- 新增 `OnlineRoom.rollback_to_command_index()`，把 server 权威 rewind/truncate、state hash、history size 与 recovery store reset 收敛为通用回滚入口。
- 将原 `rewind_to_turn_start_meta` 链路迁移到 `rollback_meta`，保留旧 RPC/helper 作为兼容别名，后续“回退上一步”和“提议回滚”可复用同一客户端应用逻辑。
- 更新 `GameOnlineResyncController`、client/server RPC glue 与联机 resync guard 测试，确保回滚元数据不再复用 `rpc_resync_archive`。
- 验证：`git diff --check` 通过；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180` 通过，`386/386`。

### 2026-04-27：新增联机回退上一步

- 新增 `rpc_rollback_last_command` / `request_rollback_last_command`，由 server 权威校验并复用 `rollback_meta` 广播给全房间客户端。
- `OnlineRoom.rollback_last_command_for_player()` 只回退当前时间线最后一条命令；server 要求上一条命令属于发起玩家，并拒绝 `end_turn` / `skip` 这类已经结束回合的操作，避免绕过后续“提议回滚”权限模型。
- 在 `ActionFlowControls` 增加“回退上一步”按钮；`GameCommandController` 负责确认弹窗、联机请求与本地兜底回退。
- 扩展 `ServerResyncGuardTest` 与 `ActionFlowControlsNoopTest`，覆盖 server rollback meta 广播和新增按钮配置的 noop 行为。
- 验证：`git diff --check` 通过；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180` 通过，`386/386`。

### 2026-04-27：新增玩家提议回滚投票

- 新增 `rpc_request_rollback_proposal` / `rpc_vote_rollback_proposal`：玩家在发起提议时选择明确 `target_index`，server 将该目标点写入 `room_state.rollback_proposal` 并广播给所有客户端。
- 投票规则为“除提议者外的全部玩家同意”：任一 required voter 拒绝会清空 pending proposal；全部同意后 server 自动执行 `rollback_to_command_index()`，并通过 `rollback_meta` 广播实际回滚结果。
- 提议待投票期间 server 拒绝新的普通动作请求，避免投票目标点在确认过程中被后续命令污染；如果时间线已经漂移，批准阶段也会拒绝 stale proposal。
- UI 上所有玩家都显示“提议回退”入口，弹出目标时间点列表；其他玩家收到 `rollback_proposal` room state 后弹出“同意回滚/拒绝”确认框，弹窗中明确目标命令索引与撤销步数。
- 扩展 `ServerResyncGuardTest`、`GameOnlineResyncRequestRejectionTest` 与 `ActionFlowControlsNoopTest`，覆盖非房主提议、pending 期间动作拒绝、投票后 meta 广播、投票弹窗目标文案以及新增按钮 noop 行为。
- 验证：`git diff --check` 通过；`godot --headless --script res://tools/check_compile.gd` 通过，`files=1100`；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180` 通过，`386/386`。

### 2026-04-28：修正提议回退入口与弹窗溢出

- 移除 server / ActionPanel / CommandController 对“仅房主可提议回滚”的限制，改为任意在线玩家都可发起提议，投票仍要求除提议者外的其他玩家全员同意。
- 缩短回滚目标列表文本为固定格式（如“回滚到命令 #N 后”），并扩大提议弹窗宽度与说明文本横向约束，避免长 action id 造成选项文字溢出容器。
- 验证：`git diff --check` 通过；`godot --headless --script res://tools/check_compile.gd` 通过，`files=1100`；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180` 通过，`386/386`。
