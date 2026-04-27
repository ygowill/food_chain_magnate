# ADR 0004：联机恢复房改为单 full-engine 启动

- 状态：已采纳
- 日期：2026-04-17

## 背景

恢复房此前采用“`runtime_engine` 快启动 + `full_history_engine` 后台补齐”的双轨方案，目标是缩短进入对局时间。

该方案虽解决了部分启动卡顿，但也持续带来以下问题：

- 启动、日志、时间线、seek、resync 需要同时维护两套历史坐标。
- `runtime_anchor`、`live_tail`、`full_history_step_timeline`、`full_history_step_timeline_entries` 之间存在一致性维护成本。
- 尽管 P0 已把 live 读源切回 `runtime_engine`，但恢复房链路仍长期保留“双轨兼容层”，隐藏复杂度较高。
- 用户明确接受：恢复房进入可更慢，但需要进度可读、日志完整、行为简单稳定。

因此，本轮决定放弃“恢复房快启动优先”的设计目标，转向**单 full-engine 启动**。

## 决策

### D4.1 恢复房客户端启动统一改为完整 archive 本地回放

恢复房客户端在 `game_started` 后不再使用短链 `runtime_archive` 快启动。

改为：

1. 接收服务端下发的完整 archive snapshot（分块传输）。
2. 本地执行完整 `load_from_archive()` 回放。
3. 启动前完成 step timeline / log entries cache 预构建。
4. 本地 bootstrap 完成后，再向上层发出 `game_started` / ready 信号。

### D4.2 `live == full`

恢复房常态下不再维护独立的 `runtime_engine` / `full_history_engine` 双实例。

当前实现收敛为：

- 常态 live engine：完整历史 engine。
- `OnlineResumeSessionState` 仍保留 `full_history_*` 字段，用于兼容现有调用点；但在恢复房单引擎模式下，它们与当前 live engine 指向同一实例。
- `runtime_anchor.global_command_start_index = 0`，恢复房命令坐标不再做短链映射。

### D4.3 启动时预构建日志 / timeline cache，避免进场后二次大 rebuild

完整 archive 本地回放完成后，立即预构建：

- `full_history_step_timeline`
- `full_history_step_timeline_entries`

进入游戏场景后，live 日志优先复用这份 prebuilt cache，而不是再次 full rebuild。

### D4.4 历史查看仍保留“只读显示态”语义

虽然常态只保留一个 full engine，但历史查看 / replay / seek 仍然必须保持只读。

也就是说：

- 常态 live engine：完整历史最新态
- 历史查看：仍使用 timeline / snapshot 恢复到只读显示态
- 不允许联机客户端在历史点本地分叉继续执行

### D4.5 以更可读的启动进度替代快启动

恢复房启动允许更慢，但必须提供更强的进度反馈。

最低要求：

- 快照分片接收进度
- archive 校验 / 模块装配阶段
- 历史命令回放进度（命令数 + 回合 / 阶段）
- timeline / log cache 构建阶段

### D4.6 等待态仍自动打开详细日志，但详细日志必须分帧挂载

用户仍然要求“等待其他玩家操作时自动打开详细日志”，因此不采用“等待态不自动打开日志”的产品取舍。

新约束改为：

- 等待态可以自动打开右侧详细日志面板；
- 但打开日志后，**不得在同一帧同步完成完整 timeline / descriptor / UI item 重建**；
- 日志面板应先显示轻量壳体与已有状态，再通过 deferred / background job / 分帧结果提交把详细 timeline 挂上；
- 自动打开日志属于体验功能，不能反向把 `command_applied` 热路径重新拖回 700ms~900ms 级别卡顿。

### D4.7 日志隐藏态不再承担整套 timeline item 状态刷新

恢复房与普通联机对局都遵守：

- 当详细日志面板当前不可见时，允许内部只维护最新的 head/cursor/timeline dirty 标记；
- 不再对 `GameLogPanel` 的所有 timeline items 做逐项 `apply_timeline_state(...)`；
- 等日志真正显示时，再一次性把当前状态应用到面板。

这样可以避免“日志没在看，但每条联机命令仍要花 15~25ms 更新日志 UI 状态”的隐性热路径成本。

## 影响

### 优点

- 恢复房常态只维护一套历史真相，坐标体系显著简化。
- 旧日志、点击跳转、完整历史 seek 不再需要双源转换。
- `command_applied` 热路径不再承担“双轨同步维护”复杂度。
- 恢复房行为更接近“完整读档后继续联机”，更容易验证与排错。

### 代价

- 恢复房进入对局时间会变长。
- 启动阶段需要更细粒度的进度 UI 和性能打点。
- 之前围绕 fast-start / dual-engine 的部分测试与文档需要收敛或退役。
- 等待态自动打开详细日志的实现必须改为“轻量显示 + 分帧挂载”，不能继续依赖伪异步主线程回收。

## 实施约束

- 分块 archive 传输能力继续保留；只是客户端不再用它构造短链快启动。
- `StepTimelineBuild.append_from_existing(...)`、`GameLogPanel.append_step_timeline(...)` 等**单时间线增量能力必须保留**，避免启动后每步全量重建。
- `GameLogPanel` 的后台 descriptor job 在 Web 下不得通过 `wait_to_finish()` 把主线程阻塞成卡顿源。
- 任何恢复房启动失败，都必须通过 `match_bootstrap_local_failed` 及时上报，不得静默降级到不完整历史。

## 参考

- `docs/online/online_resume_single_full_engine_startup_2026-04-17.md`
- `docs/architecture/70-online-multiplayer.md`
- `docs/architecture/42-gameplay-replay-timelines.md`
- `docs/online/online_resume_fastload_full_history_design_2026-04-14.md`
- `docs/online/online_resume_hot_path_rebuild_plan_2026-04-16.md`
