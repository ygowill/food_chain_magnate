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

#### 2026-04-18 性能补充

基于真实联机恢复房日志，当前卡顿已不再主要来自网络或 `GameEngine.execute_command()`，而主要来自：

- `ui.timeline.build_info_from_timeline`
- `ui.game_log.load_step_timeline`
- `ui.game_log.append_step_timeline`
- `ui.timeline.apply_live_log`
- `ui.online_sync.timeline_ui`
- `ui.online_sync.panel_controller`

已确认的现象：

- 启动期 `client.resume_single_full.prepare` 约 2.7s，属于已接受的冷启动成本；
- 进入游戏后第一次显示详细日志时，仍可能触发一次 700ms~900ms 级别的 live log 挂载；
- 对局进行中，命令应用本体通常只有 3ms~5ms，但日志/时间线 UI 更新仍可把整帧拉高到 25ms~40ms；
- Web 日志中已出现 `Blocking on the main thread is very dangerous`，说明当前“后台日志 descriptor job”在结果回收阶段仍会阻塞主线程。

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

### 5.3 等待态自动打开日志，但必须采用“轻量显示 + 分帧挂载”

用户明确要求保留：

- 当进入“等待其他玩家操作”状态时，自动打开详细日志。

因此新的实现约束不是“取消自动打开”，而是：

1. 自动打开日志时，先把右侧日志壳体显示出来；
2. 同一帧内只做轻量 state 同步；
3. 详细 timeline / descriptor / items 改为 deferred 或后台结果提交；
4. 若日志结果尚未准备好，允许短暂显示空壳或旧内容，但不能把主线程卡住。

另外，实时命令流若在短时间内连续到达（如重组结构拖拽产生的一串命令）：

- 允许把多次 live log refresh 合并为一次 delayed refresh；
- 也就是“每条命令都更新引擎状态，但日志 timeline append 可以做短窗口合帧”。

### 5.4 日志隐藏态要退出热路径

在详细日志面板不可见时：

- 允许继续维护 `_history_step_timeline` / cached timeline / cached entries；
- 但 `sync_timeline_ui(...)` 不应再把整套 `GameLogPanel` items 逐项做 timeline state 更新；
- `set_timeline_head_cursor(...)` 这类 UI 方法在隐藏态应降级为“仅更新内部 index / cursor/head 状态，不更新 item”。

目标是把当前每条联机命令都要承担的 `ui.online_sync.timeline_ui` 18ms~23ms 先打下来。

### 5.5 Web 下的 descriptor 后台任务必须避免主线程阻塞回收

当前 `GameLogPanel` 已使用后台 descriptor worker，但结果回收阶段仍通过 `wait_to_finish()` 阻塞主线程。

后续实现要求：

- Web 平台下避免 `wait_to_finish()` 直接阻塞当前帧；
- 优先改成“仅在线程已结束后非阻塞取结果 + 下一帧提交 UI”；
- 至少要保证日志自动打开和 live append 时，不再触发浏览器控制台的主线程阻塞警告。

### 5.6 descriptor 结果提交也必须分帧

即使 descriptor 已经在后台算完，如果主线程仍一次性把整份 descriptor 全部转成 Control 并 append：

- `ui.game_log.apply_descriptor_rebuild`
- `ui.game_log.apply_descriptor_append`

仍然会在“等待态自动打开详细日志”或“大时间线 live append”时形成新的卡顿峰值。

因此实现上还需要补一层约束：

- 后台 worker 只负责产出 descriptor 数据；
- 主线程提交 descriptor 时，必须采用 slice/chunk 方式分帧挂载；
- 日志面板在 commit 完成前允许先显示“部分已挂载内容 + 空壳”，不能要求同帧完整可见；
- commit 结束后再统一：
  - 刷新 timeline state
  - 刷新 entry count
  - 执行 auto scroll 收尾

这一步的目标不是减少总工作量，而是把 1 帧 100ms+ 的尖峰拆成多帧可接受的 5ms~15ms 小块。

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
- 等待态自动打开日志时，只请求 deferred timeline refresh，不做同步 heavy rebuild
- 日志隐藏态更新 cursor/head 时，不应触发全量 item timeline state 刷新
- 大时间线在 append / rebuild 场景下仍可后台完成，并正确提交 UI

## 8. 参考

- `docs/decisions/0004-online-resume-single-full-engine-startup.md`
- `docs/architecture/70-online-multiplayer.md`
- `docs/architecture/42-gameplay-replay-timelines.md`
- `docs/testing.md`
