# 联机 live command 日志与 UI 热路径长期优化计划（2026-05-03）

状态：**当前问题定位与长期修复计划**。

本文记录联机后半段出现“餐厅跳字弹出后卡住，其他 UI 无法点击 4-5 秒”的问题链路、当前已做的止血修复、以及后续长期优化顺序。

目标不是只减少一次卡顿，而是把 live command 后的日志 append、时间线构建、UI 同步从“随历史长度增长”改成“按新增内容增长”，并保留当前日志/回放/复盘/seek 语义。

相关文档：

- `docs/architecture/42-gameplay-replay-timelines.md`
- `docs/architecture/21-ui-game-scene.md`
- `docs/architecture/70-online-multiplayer.md`
- `docs/online/online_resume_single_full_engine_startup_2026-04-17.md`
- `docs/online/online_resume_hot_path_rebuild_plan_2026-04-16.md`
- `docs/design/archive/replay_log_timeline_refactor_plan.md`

---

## 1. 用户可见问题

联机对局后半段，玩家做出行动后，餐厅上方会弹出即时文字反馈。文字出现后经常停在上面，按钮、地图、其他 UI 控件都无法点击，需要等待数秒后才恢复。

表面现象像是“跳字动画卡住”，但根因不是单个文字动画本身。跳字只是主线程被占住前最后一次成功绘制的画面。

实际卡顿链路是：

1. live command 到达客户端。
2. 客户端执行 command，期间 EventBus 发出行动事件。
3. `WorkingActionFeedbackController` 收到事件，播放餐厅跳字。
4. 同一个回调继续做联机恢复进度同步、日志时间线刷新、整套 UI 同步。
5. 后半段历史变长后，日志时间线 append 与 UI sync 中存在多处 O(history) 或 fallback rebuild。
6. Godot 主线程被这些同步工作占住，动画 tween、输入事件、按钮 hover/click 都无法及时处理。

因此“文字卡在餐厅上”是主线程阻塞的症状，不是唯一的原因。

---

## 2. 当前 hotfix 已处理的范围

当前已经做了三类止血修复，目的是先把最明显的卡顿入口压住，同时不改变回放/日志语义。

### 2.1 餐厅跳字从节点动画改为单绘制层

涉及文件：

- `ui/scenes/game/overlay/working_action_feedback.gd`
- `ui/scenes/tests/working_action_feedback_test.gd`

调整内容：

- 原先每条跳字会创建 `Label`、`Tween` 和相关特效节点。
- 现在跳字文本由单个 `WorkingActionFeedbackBurst` 绘制层统一绘制。
- 对同时存在的文字 burst 和特效节点设置硬上限。
- 餐厅锚点不再把同一玩家所有餐厅合并成一个大 rect；优先使用事件中的 `restaurant_id`，否则选择玩家餐厅列表中的一个具体餐厅。

收益：

- 避免后半段事件密集时 UI 节点数量持续膨胀。
- 避免文字锚点跨度过大导致反馈位置异常。
- 避免大量 Label/Tween 节点参与 Godot 布局和生命周期管理。

边界：

- 这只解决“跳字自身堆积”的问题。
- 如果跳字之后的日志/UI 同步仍然阻塞主线程，动画仍可能短暂停住。

### 2.2 resync / pending / delta 回放不再通知 UI 订阅者

涉及文件：

- `core/engine/game_engine/record_only_event_sink.gd`
- `autoload/net_client/client_resync_service.gd`
- `ui/scenes/game/controllers/online_resync_controller.gd`
- `ui/scenes/tests/working_action_feedback_test.gd`

调整内容：

- 新增 `RecordOnlyEventSink`。
- 联机 resync、pending command 追赶、delta resync replay 命令时，只写入 `EventBus.history`，不通知实时 UI 订阅者。
- 避免历史追赶时再次触发餐厅跳字、音效、overlay 即时动效。

收益：

- 防止“追赶历史命令”被当作“玩家刚刚做出行动”重复播放动效。
- 减少恢复/追赶阶段的 UI 事件风暴。

边界：

- 正常 live command 仍会发出实时 UI 事件，这是需要保留的。
- record-only 不解决日志 timeline 构建本身的复杂度。

### 2.3 联机 command 后 UI 刷新延迟并合并

涉及文件：

- `ui/scenes/game/controllers/online_resync_controller.gd`

调整内容：

- live command 执行完成后，不再立刻同步刷新日志和整套 UI。
- 改为 `call_deferred` 后等待 1 帧，再合并执行最新一次 UI refresh。
- resync/rollback/pending 成功后的刷新也接入同一个延迟合并队列。

收益：

- 让跳字和输入至少有机会先过一帧，避免文字刚出现就被重任务阻塞。
- 多条 command 在同一帧/短时间到达时，只触发一次 UI refresh。

边界：

- 这是调度优化，不是算法优化。
- 如果一次合并后的刷新本身仍然很重，仍会有单帧或多帧卡顿。
- 长期仍需要把日志 append 和 UI sync 改成真正增量。

---

## 3. 为什么“每个行动只增加一条日志”仍然会很卡

直觉上，一个行动只新增一条日志，应该是 O(1)。但当前实现不是“纯文本日志 append”，而是“从 command history 派生 step timeline，再渲染统一日志视图”。

当前日志系统承担了这些职责：

- 行动日志展示。
- 阶段标题、回合标题。
- 行动分组。
- 详情折叠。
- 回放/复盘 seek。
- command index 到 step index 的映射。
- 联机恢复房完整历史复用。

因此一次 live command 后，系统要维护的不只是一个字符串，而是 step timeline 与对应 UI 控件树。

### 3.1 一个 command 不一定只产生一个 event

命令执行后可能产生多类事件：

- action executor 自身事件，例如 `FOOD_PRODUCED`。
- 金钱变化事件。
- 里程碑事件。
- phase changed / sub phase changed 相关事件。
- auto-advance drain 产生的阶段切换与结算事件。
- `COMMAND_EXECUTED` 兼容事件。

相关代码：

- `core/engine/game_engine/command_runner.gd`
- `gameplay/replay/step_timeline_build/build_full_impl.gd`
- `gameplay/replay/step_timeline_build/build_append_impl.gd`

所以“一条玩家行动”在 step timeline 中可能追加多个 event、一个或多个 step。

### 3.2 现有 append 避免了全量回放，但不是 O(delta)

入口：

- `ui/scenes/game/timeline/step_timeline_build_helpers.gd`
- `gameplay/replay/step_timeline_build/build_append_impl.gd`

当前 `build_append_impl` 会：

1. 读取已有 timeline。
2. 复制已有 `steps`。
3. 复制已有 `events`。
4. 从已有 timeline 的尾部 state 恢复。
5. 只回放新增 command。
6. 把新增 step/event 追加到复制后的数组。

这比从第一条 command 全量重建好，但前两步复制已有 `steps/events` 仍然是 O(history)。

后期历史越长，即使只追加一个 command，也会先复制整条旧 timeline。

### 3.3 面板 append 前还有全量 prefix 校验

入口：

- `ui/components/game_log/game_log_panel.gd`

当前 `_can_append_step_timeline()` 会：

1. 比较旧 `initial_state_dict`。
2. 遍历旧 `steps`，确认新 timeline 的 prefix 完全相等。
3. 遍历旧 entries，确认新 entries 的 prefix 完全相等。

这同样是 O(history)。

设计目的合理：保证 append 不会把错的 timeline 接到旧 UI 后面。但实现方式太重，应该改成 metadata signature 校验。

### 3.4 append 失败会退回 rebuild

如果 append 条件不满足，`GameLogPanel.load_step_timeline()` 会退回 rebuild：

- 清空旧显示控件。
- 重新构建统一 timeline UI。
- 重新建立 step index 到 item 的索引。
- 重新应用 timeline cursor/head 状态。

后期日志项多时，这一步会非常重。

### 3.5 `_update_ui()` 会同步远超日志的内容

入口：

- `ui/scenes/game/controllers/ui_sync_controller.gd`

一次 `_update_ui()` 会同步：

- 顶部回合/阶段/bank 标签。
- timeline head/cursor。
- 地图视图 `map_view.set_game_state(state)`。
- 右侧 panel controller。
- overlay controller。
- action flow controls。
- toast。
- debug panel。

所以卡顿不是“日志一条文本很重”，而是“日志 timeline 维护 + 地图/面板/overlay 同步”叠加在同一个主线程回调中。

---

## 4. 长期目标

长期优化目标：

1. 正常 live command 热路径不再执行 O(history) 的 timeline 复制或 prefix 校验。
2. 正常 live command 热路径不再同步整套 UI。
3. 日志面板 append 只创建新增 step/event 对应的控件。
4. rollback、resync、读档、seek 等非普通尾部追加场景仍能安全走 full rebuild。
5. 保留 step timeline 的回放/复盘/seek 语义，不退回纯文本日志。

### 4.1 性能目标

建议目标值：

- 500 条 command 后追加 1 条 command，timeline append 不应明显随历史长度线性增长。
- 1000 条 command 后追加 1 条 command，正常 live UI 不应出现 1 秒级主线程阻塞。
- 单次 live command UI settle 应稳定在可交互范围内；理想情况下普通行动低于一帧预算，复杂阶段切换允许更高但必须可追踪。
- resync / rollback / load 可以较重，但必须显示 loading 或分帧/后台处理，不能伪装成普通 live action。

具体阈值需要在本机和目标设备上用 `OnlinePerfTrace` 建立基线后确定。

---

## 5. 修复顺序

建议按以下顺序实施。不要先做虚拟列表，也不要先大拆 UI；先解决 append 数据结构的 O(history) 问题。

### 阶段 0：建立可重复性能基线

目标：

- 有稳定场景证明后半段 live command 卡顿。
- 可以量化每一阶段改动的收益。

工作项：

- 增加或复用性能 trace：
  - `client.command_applied.apply_done`
  - `client.command_applied.ui_update`
  - `client.command_applied.ui_settled`
  - `ui.timeline.apply_live_log`
  - `ui.timeline.build_info_from_timeline`
  - `ui.game_log.append_step_timeline`
  - `ui.game_log.append_step_range`
  - `ui.game_log.rebuild_display`
  - `ui.online_sync.map_view`
  - `ui.online_sync.panel_controller`
  - `ui.online_sync.overlay_controller`
- 增加一个 synthetic late-game replay/perf 场景：
  - 构造 200 / 500 / 1000 条 command history。
  - 打开日志面板。
  - 追加 1 条普通 Working action。
  - 记录 append、UI sync、settled 时间。
- 输出机器可读日志，便于回归比较。

验收：

- 能复现“历史越长 append 越慢”的趋势。
- 能区分时间花在 timeline build、log panel、map view、panel controller 还是 overlay。

### 阶段 1：保留当前 hotfix，并补齐回归测试

状态：已完成主要实现，后续可补更多性能断言。

工作项：

- 保留 `WorkingActionFeedbackBurst` 单绘制层。
- 保留 `RecordOnlyEventSink`。
- 保留在线 command UI refresh 延迟合并。
- 补充测试：
  - 大量 feedback 不创建大量节点。
  - replay record-only 不通知 EventBus subscriber。
  - resync/pending 追赶后只触发一次 UI refresh。

验收：

- `CheckCompile` 通过。
- `AllTests` 通过。
- `GameSmokeTest` 通过。
- 大量 feedback 场景中 burst/effect 节点数量有硬上限。

### 阶段 2：StepTimeline append 改成真正 O(delta)

状态：**进行中**。

2026-05-03 增量更新：

- 新增 `StepTimelineBuild.append_tail_delta_owned(engine, owned_timeline)`，供明确拥有 timeline 的 live/cache 热路径原地追加尾部 delta。
- 保留 `append_from_existing(engine, existing_timeline)` 的非变异契约，避免影响共享/只读调用方。
- live history refresh 与 full-history timeline cache refresh 已改用 owned append 路径，append 成功时不再复制旧 `steps/events`。
- 补充 `StepTimelineIncrementalAppendTest` 覆盖 owned append 成功原地更新、旧 API 不变异、以及 malformed event append 失败后回滚旧 timeline。

目标：

- live append 不再复制整条 `steps/events`。
- 增量构建只处理新增 command 和新增事件。

建议设计：

新增一个明确的 append API，例如：

```text
StepTimelineBuild.append_tail_delta(engine, owned_timeline) -> Result
```

或：

```text
StepTimelineBuild.append_from_existing_mutating(engine, owned_timeline) -> Result
```

关键约束：

- 只允许在调用方明确拥有 `owned_timeline` 时使用。
- 函数内部直接引用并追加 `steps/events`。
- 进入函数时记录：
  - `old_step_count`
  - `old_event_count`
  - `old_processed_command_count`
  - `old_last_event_sequence`
  - pending phase/cleanup meta
- 如果新增 command 回放失败：
  - 截断 `steps` 到 `old_step_count`。
  - 截断 `events` 到 `old_event_count`。
  - 恢复旧 `_build_meta`。
  - 返回 failure。
- 成功时返回：
  - `timeline`
  - `appended_steps`
  - `appended_events`
  - `old_step_count`
  - `old_event_count`
  - `head_step_index`
  - `processed_command_count`
  - `append_applied = true`

需要避免：

- 不要在 append 开头 `duplicate(true)` 整个 timeline。
- 不要复制旧 `steps/events`。
- 不要为了安全把 O(history) 复制藏到 helper 里。

实现注意：

- 当前 `build_append_impl` 从最后一个 step 的 `state_dict` 恢复尾部 state。这个可以保留，因为它不要求扫描全历史。
- 如果 timeline 被其他缓存共享，不能直接 mutating。需要明确 ownership：
  - live panel 持有的 `_history_step_timeline` 可以作为 owned timeline。
  - NetClient cached timeline 若要共享给其他消费者，应在边界处 duplicate，而不是每次 append duplicate。
- read-only replay timeline 不应走 mutating live append，除非它也有明确 ownership。

测试：

- 对同一 command history：
  - full build 结果。
  - 从 N-1 append 1 条的结果。
  - 从 N-k append k 条的结果。
  - 比较最终 `steps/events/_build_meta` 语义一致。
- append 失败时验证旧 timeline 长度和 meta 被回滚。
- `processed_command_count == total_command_count` 时不应复制旧数组。
- rollback/resync 后旧 timeline 不应被错误 append。

验收：

- append 1 条 command 时，StepTimeline 构建端不再有随旧 `steps/events` 长度增长的复制。
- `appended_steps/appended_events` 正确。
- full build 与 append build 结果保持一致。

### 阶段 3：GameLogPanel append 校验从 prefix scan 改成 signature

状态：**进行中**。

2026-05-03 增量更新：

- `GameLogPanel` 在提交 step timeline 状态时保存轻量 timeline/entries signature。
- `_can_append_step_timeline()` 已从逐项比较旧 `steps`/`entries` prefix，改为 O(1) 校验 initial hash、旧尾部 step/entry hash、counts、processed command count 与新增 entry sequence 起点。
- 补充 `GameLogPanelStepTimelineAppendTest` 覆盖正常 signature append，以及 initial state、旧 tail step、旧 tail entry、entry sequence 不一致时拒绝 append。
- append 显示成功后的状态提交改为直接追加新增 timeline entries；不再复制已有 `_timeline_entries` 后整体提交。后台 append job 也复用同一增量提交路径。
- append 新增控件由 builder 创建时应用当前 timeline cursor/head；同步 append 和后台分片 append 收尾不再对已有 `_log_items` 做全量 timeline state 刷新。`GameLogPanelStepTimelineAppendTest` 增加 spy 覆盖，防止 append 收尾重新扫描旧 item。

目标：

- 面板 append 前不再遍历旧 `steps/entries`。
- 正常 live append 只校验 O(1) metadata。
- append 成功收尾不再为了 timeline state 扫描完整日志控件列表。

建议新增或完善 timeline signature：

```text
timeline_signature = {
  engine_id,
  source,
  initial_state_hash,
  processed_command_count,
  step_count,
  event_count,
  last_event_sequence,
  head_step_index,
}
```

entries signature：

```text
entries_signature = {
  timeline_event_count,
  entry_count,
  first_event_sequence,
  last_event_sequence,
  processed_command_count,
}
```

`GameLogPanel` 当前状态保存：

- `_step_timeline_signature`
- `_timeline_entries_signature`
- `_timeline_entries_count`
- `_step_count`
- `_event_count`

append 时只检查：

- 当前 panel 已加载 step timeline。
- incoming previous counts 与 panel counts 一致。
- initial state hash 一致。
- processed command count 是向前增长。
- old `last_event_sequence` 与 panel 记录一致。
- incoming appended entries 的 sequence 起点在旧 sequence 之后。

失败时：

- 不尝试“半 append”。
- 直接返回 false，让上层决定 full rebuild。

需要避免：

- 不要再比较所有旧 step dictionary。
- 不要再比较所有旧 entry dictionary。
- 不要用 `Dictionary == Dictionary` 扫 prefix 来保证一致性。

测试：

- 正常 append 走 signature path。
- 修改 initial state hash 后 append 被拒绝。
- 修改 old counts 后 append 被拒绝。
- rollback 后 append 被拒绝并 full rebuild。
- entries sequence 不连续时 append 被拒绝。

验收：

- `_can_append_step_timeline()` 或其替代实现不再 O(history)。
- late-game append 不再因为 prefix 校验随历史长度线性增长。
- append 成功后 timeline state 应只随新增控件数量增长，旧日志项不被全量重刷。

### 阶段 4：UI 同步从 full update 改为 dirty sync

目标：

- 普通 live command 不再调用“整套 UI 同步”。
- 只刷新受影响的 UI 子系统。

建议引入 dirty flags：

```text
GameUiDirtyFlags:
  TOP_STATUS
  TIMELINE_CURSOR
  LOG_APPEND
  MAP_VIEW
  PANEL_STATE
  ACTION_CONTROLS
  OVERLAYS
  DEBUG_PANEL
  FULL
```

live command 后根据 action/event 标记 dirty：

- 普通 Working action：
  - `TOP_STATUS`（如果 bank/round/phase 变化）
  - `LOG_APPEND`
  - `PANEL_STATE`
  - `ACTION_CONTROLS`
  - 必要时 `MAP_VIEW`
  - 必要时 `OVERLAYS`
- 阶段切换：
  - `FULL` 或接近 full 的组合。
- resync / rollback / load：
  - `FULL`。

实现路径：

- `GameUiSyncController.update_ui()` 保留作为 full sync。
- 新增 `sync_dirty(state, dirty_flags, context)`。
- `GameOnlineResyncController` 的 delayed refresh 改为传 dirty context。
- 先支持最常见 live action，再逐步扩展。
- 未识别 action 默认 full sync，保证正确性优先。

需要拆分的现有同步点：

- timeline UI：head/cursor 与 log append 分离。
- map view：不要每次 command 都 `set_game_state`，只有地图/库存显示依赖变化时调用。
- panel controller：提供 action-scoped sync，避免所有 working panels 都同步。
- overlay controller：demand/dinnertime/marketing overlay 按 phase/action 拆分。
- debug panel：仅 visible 时同步，且可以延后。

测试：

- 每类 action 的 dirty flags 覆盖测试。
- 普通 action 后 UI 仍显示正确可用动作。
- phase change 后 full sync 正确。
- timeline read-only / replay 模式仍禁用交互。
- online waiting 状态不会短暂放开按钮。

验收：

- 普通 live command 不再无条件调用 `map_view.set_game_state + panel_controller.sync + overlay_controller.sync`。
- 未覆盖 action 仍走 full sync，不牺牲正确性。
- UI 状态与 engine state 一致。

### 阶段 5：日志面板虚拟化 / 窗口化

目标：

- 日志很长时，已有 Control 节点数量不再等于完整历史可见项数量。
- 滚动和 timeline state 更新只影响可见窗口附近的控件。

建议设计：

- 数据层保留完整 `entries`、`steps`、索引。
- UI 层只实例化：
  - 当前 viewport 内项目。
  - 上下 buffer 区域项目。
- item pooling 复用已有 `GameLogEventItem / HeaderItem / ActionGroupHeaderItem`。
- scroll position 通过估算高度或缓存高度映射到 item range。
- timeline cursor/head 状态只更新：
  - 可见项目。
  - 当前 cursor/head 附近必要 header。

注意：

- 这是长期收益最大但实现风险最高的阶段。
- 不建议放在阶段 2/3 前做，因为如果 append 数据结构仍 O(history)，虚拟化无法解决根因。

测试：

- 1000+ 日志项滚动。
- fold/unfold。
- seek 到历史中间。
- append 后保持滚动到底部行为。
- read-only replay。
- phase/round header 边界。

验收：

- 1000+ entries 时 Control 数量保持在窗口级别。
- append、scroll、seek 都不会因完整日志长度线性变慢到秒级。

### 阶段 6：resync / rollback / load 的重任务显式化

目标：

- 非普通 live append 的重任务不能伪装成普通一帧更新。
- 用户看到的是明确的同步状态，而不是 UI 假死。

工作项：

- rollback/resync/load 明确进入 loading 或 blocking overlay。
- full rebuild 可后台或分帧执行。
- full rebuild 完成后一次性替换 panel state。
- 取消/新一代 job 到达时丢弃旧 job。

验收：

- resync 大历史时 UI 不表现为“文字卡住”。
- 用户能看到正在同步/恢复，而不是普通 UI 无响应。

---

## 6. 建议的数据与接口边界

### 6.1 StepTimeline ownership

需要明确区分两种 timeline：

- owned mutable timeline：
  - live game scene 当前使用。
  - 可以原地 append。
  - append 失败必须回滚。
- shared/cached timeline：
  - NetClient cache、archive、replay import 等共享数据。
  - 对外暴露前可以 duplicate。
  - 进入 owned live path 时再明确转为 owned。

建议不要继续让所有 API 都随手 `duplicate(true)`，否则无法保证性能。

### 6.2 Append result contract

append API 应返回足够的信息，让 UI 不必再反推：

```text
{
  timeline,
  append_applied,
  old_step_count,
  old_event_count,
  appended_steps,
  appended_events,
  appended_entries,
  head_step_index,
  cursor_step_index,
  timeline_signature,
  entries_signature,
}
```

UI 面板 append 不应再重新扫描已有 history 来确认这些信息。

### 6.3 Dirty sync context

live command 后应传递最少上下文：

```text
{
  action_id,
  actor_id,
  command_index,
  old_phase,
  new_phase,
  old_sub_phase,
  new_sub_phase,
  event_types,
  affected_player_ids,
  affected_restaurant_ids,
  affected_map_cells,
}
```

这些上下文可以来自 command executor 事件、old/new state diff、或 executor 提供的 action metadata。

---

## 7. 风险与边界

### 7.1 不能破坏回放/复盘语义

日志 timeline 不是普通文本日志。它和 replay/seek 绑定，因此不能简单替换成 `EventBus.emit_event -> add one Label`。

必须保留：

- step_index。
- command_index。
- phase/round header。
- action group。
- state snapshot。
- timeline cursor/head。

### 7.2 rollback/resync 不能错误 append

以下场景必须强制 rebuild 或重建 owned timeline：

- command history 缩短。
- engine instance 改变。
- initial checkpoint/hash 改变。
- timeline source 从 runtime 切到 full history 或反向切换。
- cursor detached from live head。
- read-only replay。
- load archive。

### 7.3 append 失败必须可恢复

mutating append 一旦开始写入数组，失败时必须回滚，否则会污染 live timeline。

建议所有 append 单元测试都覆盖失败回滚。

### 7.4 背景线程不是根治

GameLogPanel 已有 background timeline job 阈值，但这不能替代真正增量：

- append 构建端的复制可能已经发生在进入 background job 之前。
- prefix 校验仍可能发生在主线程。
- background job 完成后仍需要主线程提交 UI 控件。

所以 background 只能作为 full rebuild 的降级策略，不能作为普通 live append 的主路径。

---

## 8. 建议优先改动文件

阶段 2：

- `gameplay/replay/step_timeline_build.gd`
- `gameplay/replay/step_timeline_build/build_append_impl.gd`
- `gameplay/replay/step_timeline_build/helpers.gd`
- `ui/scenes/game/timeline/step_timeline_build_helpers.gd`
- `ui/scenes/game/timeline/online_resume_full_history_adapter.gd`

阶段 3：

- `ui/components/game_log/game_log_panel.gd`
- `ui/components/game_log/game_log_unified_timeline_builder.gd`
- `ui/scenes/game/timeline/step_timeline_build_helpers.gd`

阶段 4：

- `ui/scenes/game/controllers/ui_sync_controller.gd`
- `ui/scenes/game/controllers/online_resync_controller.gd`
- `ui/scenes/game/panel/controller.gd`
- `ui/scenes/game/map/*`
- `ui/scenes/game/overlay/*`

阶段 5：

- `ui/components/game_log/game_log_panel.gd`
- `ui/components/game_log/game_log_unified_timeline_builder.gd`
- `ui/components/game_log/game_log_*_item.gd`

---

## 9. 推荐测试矩阵

### 9.1 逻辑一致性

- full build 与 append build 结果一致。
- append 1 条、append 多条都一致。
- phase change command append 正确。
- auto-advance append 正确。
- milestone/cash/settlement events 顺序正确。
- command_index 和 step_index 单调且可 seek。

### 9.2 UI 行为

- 日志面板打开时 append 正确。
- 日志面板关闭时不做可见 UI rebuild，重新打开后正确。
- cursor 在历史中间时 live append 不强行刷新可见历史。
- replay/read-only 模式不受 live append 影响。
- fold/unfold 状态在 append 后保留。
- 滚动到底部行为保持。

### 9.3 联机场景

- 正常 live command。
- 多条 command 连续到达。
- pending queue 追赶。
- delta resync。
- full resync archive。
- rollback last command。
- rewind to turn start。
- 重连恢复。

### 9.4 性能

- 100 / 500 / 1000 commands 后 append 1 条。
- 日志面板可见与不可见两种状态。
- phase change command 与普通 Working command 分开测。
- UI dirty sync 与 full sync 分开测。

---

## 10. 不建议的方案

### 10.1 不建议只加 debounce

debounce 能减少刷新次数，但不能减少单次刷新成本。后期一次刷新如果仍是 O(history)，卡顿仍会存在。

### 10.2 不建议把日志退化成纯文本 append

这会破坏 replay/seek/phase grouping 的一致性。短期看能快，长期会制造更多状态不一致问题。

### 10.3 不建议先做大规模 UI 重写

当前明确热点在 timeline append 和 full UI sync。先从数据增量和 sync dirty 化做起，收益更确定，风险更低。

### 10.4 不建议把所有重活都丢到后台线程

Godot UI 控件创建和树操作仍在主线程。后台线程可以构建 descriptor，但不能解决主线程节点提交成本，也不能替代 O(delta) 数据路径。

---

## 11. 当前结论

当前卡顿不是一个单点 bug，而是 live command 热路径中多个“历史长度相关”的工作被串在同一帧：

- 跳字节点曾经会堆积。
- resync/pending replay 曾经会重复触发 UI 动效。
- live command 后曾经立刻刷新日志和整套 UI。
- timeline append 当前仍然会复制旧 `steps/events`。
- GameLogPanel append 当前仍然会扫旧 prefix 校验。
- `_update_ui()` 当前仍然偏 full sync。

已落地的 hotfix 解决前三项。长期改善应按以下主线继续：

1. 真正 O(delta) 的 StepTimeline append。
2. signature-based GameLogPanel append。
3. dirty UI sync。
4. 日志虚拟化。
5. resync/rollback/load 重任务显式化。

这条顺序能先消除普通 live command 的 O(history) 成本，再处理 UI 控件数量与复杂恢复场景。
