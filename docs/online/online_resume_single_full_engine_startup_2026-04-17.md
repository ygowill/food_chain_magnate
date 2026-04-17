# 联机恢复房：单 full-engine 启动方案（2026-04-17）

## 1. 目标

本方案用于替代“快启动 runtime + 后台 full-history 双轨”的恢复房客户端启动模型。

新目标明确为：

- **恢复房允许更慢地进入**；
- **进入后即持有完整历史**；
- **日志 / timeline / seek / replay 都基于同一套历史真相**；
- **启动阶段必须有更可读的进度反馈**。

## 2. 设计结论

### 2.1 启动模型

恢复房客户端不再优先构建短链 `runtime_engine`。

而是：

1. 收到 `game_started`（仅作为“开始本地 bootstrap”的控制信号）。
2. 等待完整 archive snapshot 分块到达。
3. 本地执行完整 `load_from_archive()`。
4. 启动前预构建 timeline / log cache。
5. bootstrap 完成后再发出本地 `game_started` / ready。

### 2.2 单引擎语义

恢复房常态改为：

- `live engine == full history engine`
- `runtime_anchor.global_command_start_index = 0`
- 不再维护短链局部坐标
- 不再维护启动期 `live_tail` / deferred full replay build

为了兼容现有调用点：

- `OnlineResumeSessionState.full_replay_engine` 暂时仍保留
- 但在恢复房单引擎模式下，它与当前 live engine 指向同一实例

### 2.3 日志与时间线

#### 启动期

启动期在本地 archive replay 完成后，立即构建：

- `full_replay_step_timeline`
- `full_replay_step_timeline_entries`

#### 进入游戏后

- live 日志默认仍标记为 `runtime` source
- 但其底层 engine 已经是完整历史 engine
- 首次 `apply_live_log_timeline_from_engine()` 应优先复用 prebuilt timeline / entries cache
- 后续 live 命令继续走 **单 timeline 增量 append**，而不是 full rebuild

### 2.4 历史查看

虽然常态只有一个 full engine，但历史查看仍保留只读语义：

- 日志点击 / Replay / History View
- 都进入只读显示态
- 不允许联机客户端在历史点继续本地分叉执行

## 3. 传输与客户端时序

### 3.1 服务端

恢复房 `start_game` / `join_room(InGame)` 时：

- `rpc_game_started(payload)` 中标记 `resume_bootstrap_mode = "full_archive_snapshot"`
- 通过 `rpc_resync_snapshot_manifest/chunk` 下发完整 archive snapshot
- 不再下发 `resume_fast_start_bundle`

### 3.2 客户端

`NetClient.client.gd` 的恢复房时序收敛为：

1. 收到 `game_started(payload.resume_bootstrap_mode == full_archive_snapshot)`
   - 仅记录待完成 bootstrap 的 payload
   - 不立即向 UI 发出 `game_started`
2. 接收 snapshot manifest / chunk
3. assemble 完整 archive
4. 本地 archive replay
5. 预构建 timeline / entries cache
6. 发出：
   - `resume_full_history_ready`
   - `resync_archive_received`
   - 延迟释放的 `game_started`

这保证：

- 进入场景前，完整历史和日志缓存都已就绪
- `OnlineMatchBootstrap` 只会在本地 bootstrap 真正完成后再发送 ready ack

## 4. 进度反馈设计

恢复房本地 bootstrap 统一发出 `local_bootstrap_progress(payload)`。

推荐阶段：

1. `waiting_snapshot`
   - 正在接收恢复快照
2. `snapshot_download`
   - 正在接收完整存档快照分片：`x / y`
3. `archive_prepare`
   - 正在校验恢复存档 / 装配规则模块
4. `archive_replay`
   - 正在回放历史：`current / total`
   - detail 附带：`第 N 回合 / Phase`
5. `timeline_cache`
   - 正在整理历史日志 / 时间线
6. `bootstrap_ready`
   - 本地恢复已完成，等待进入对局

`payload` 直接复用 `LoadingCoordinator` / `LoadingOverlay` 可识别格式：

- `title`
- `stage`
- `detail`
- `progress_value`
- `progress_max`
- `show_progress`
- `room_code`

## 5. 性能约束

虽然接受启动变慢，但仍需保证：

### 5.1 启动期成本集中，一次付费

允许：

- archive replay
- timeline full build
- entries full build

但只允许在 bootstrap 阶段发生一次。

### 5.2 启动后热路径仍然必须增量

启动完成后，收到新的 `command_applied` 时：

- 只更新当前单一 full engine
- `record_online_resume_runtime_command_applied()` 在单引擎模式下不得再积累 `live_tail`
- `ensure_online_resume_full_history_timeline_current(true)` 应基于现有 cached timeline 做 append / refresh
- 禁止重新回到“双轨同步推进 full_replay_engine”的旧模式

## 6. 兼容与过渡

本轮重构优先收敛**实际运行路径**，并保留部分兼容 API：

- `get_online_resume_full_replay_engine()`
- `ensure_online_resume_full_history_current()`
- `ensure_online_resume_full_history_timeline_current()`

这些 API 在单引擎模式下继续存在，但语义变为：

- full replay engine == 当前 live engine
- full timeline cache == 当前 full engine 的预构建 / 增量 cache

后续若继续收敛，可再删除显式“双轨命名”。

## 7. 自动化验证重点

本方案至少需要覆盖以下自动化回归：

- 恢复房 bootstrap 改为完整 snapshot，不再走 fast-start signal
- `game_started` 延迟到 archive + timeline cache 完成后再发出
- session snapshot 标记 `single_full_engine_mode = true`
- `full_replay_engine == runtime_engine`
- `record_online_resume_runtime_command_applied()` 不再积累 live tail
- cached timeline 能在单引擎模式下继续增量追平
- 恢复房 bootstrap gate 只有在 full engine + timeline cache 完成后才放行

## 8. 参考

- `docs/decisions/0004-online-resume-single-full-engine-startup.md`
- `docs/architecture/70-online-multiplayer.md`
- `docs/architecture/42-gameplay-replay-timelines.md`
- `docs/testing.md`
