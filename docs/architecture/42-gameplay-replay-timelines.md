# 模块：gameplay/replay（派生时间线：StepTimeline / EventTimeline）

`gameplay/replay/` 属于 gameplay 层：它不负责改变规则与执行命令，而是从 `GameEngine` 的“命令历史 + 状态”派生出 **UI / 回放 / 复盘 / 日志** 需要的稳定时间线视图。

核心目标：

- 把“命令（Command）时间线”提升为“可停留的语义 step 时间线”（跨 phase 的切分点）
- 构建一条“完整事件时间线”，用于日志面板稳定排序与回放展示
- 保持确定性：时间线构建不依赖实时信号订阅，而是以引擎内部事实来源重建
- 在联机恢复房中支持：
  - **prebuilt timeline 复用**
  - **prebuilt timeline entries 复用**
  - **增量 append**

## 模块关系图（从引擎事实来源派生时间线）

```mermaid
flowchart TB
  Engine["GameEngine"]
  Facts["事实来源\n(command_history + checkpoints + state)"]
  PMTrace["PhaseManager trace\n(set_timeline_trace_enabled)"]

  Step["StepTimelineBuild\n(gameplay/replay/step_timeline_build.gd)"]
  EventTL["EventTimelineBuild\n(gameplay/replay/event_timeline_build.gd)"]
  Rebuild["EventHistoryRebuild.build\n(core/engine/game_engine/event_history_rebuild.gd)"]

  Helpers["ui/scenes/game/timeline/step_timeline_build_helpers.gd"]
  ResumeAdapter["ui/scenes/game/timeline/online_resume_full_history_adapter.gd"]
  Panel["ui/components/game_log/game_log_panel.gd"]
  UI["UI 日志 / 回放 / 复盘视图"]

  Engine --> Facts
  Engine --> PMTrace
  Facts --> Step
  PMTrace --> Step
  Engine --> Rebuild --> EventTL
  Step --> Helpers
  EventTL --> Helpers
  Helpers --> ResumeAdapter
  Helpers --> Panel
  ResumeAdapter --> Panel
  Panel --> UI
```

## StepTimeline：语义步进时间线（step_index）

入口：`gameplay/replay/step_timeline_build.gd`

返回结构（以当前实现为准）：

```text
{
  initial_state_dict,
  steps: Array[Dictionary],
  events: Array[Dictionary]
}
```

关键约定（摘要，详见实现文件头注释）：

- `step_index = -1` 表示初始状态（来自 `checkpoints[0].state_dict`），不计入 `steps`
- phase 变化会插入新的 step；Working 内的 sub_phase 自动推进尽量“打包”到同一个 step（只更新快照）
- 事件会被标注 `command_index` 与 `step_index`，并带 `sequence/timestamp` 以便 UI 稳定排序
- 部分“离开阶段时发射”的事件（例如 `*_REPORT`）会归属到旧阶段（`phase_segment`），避免显示落在新阶段标题下

step 的基本字段由 helper 构建（`gameplay/replay/step_timeline_build/helpers.gd`）：

- `kind`：step 类型（例如 `"command"` / `"phase"`）
- `anchor_command_index`：该 step 锚定的命令 index
- `round / phase / sub_phase`
- `state_dict`：该 step 的状态快照（`GameState.to_dict()`）

## EventTimeline：完整事件时间线（command_index）

入口：`gameplay/replay/event_timeline_build.gd`

语义：

- 永远包含初始化事件（`command_index = -1`，`GAME_STARTED`）
- 其余事件通过 `EventHistoryRebuild` 按命令重建，并为每条事件补齐 `command_index`
- 为 UI 提供稳定的 `sequence/timestamp`（纯确定性序号），避免依赖 `real_time_msec`

相关实现：

- 事件重建：`core/engine/game_engine/event_history_rebuild.gd`
- 初始化事件数据：`core/engine/game_engine/game_started_event_build.gd`

## StepTimelineBuildHelpers：UI 侧装配层

代码：`ui/scenes/game/timeline/step_timeline_build_helpers.gd`

它负责把 gameplay 层构建出的 `timeline` 装配成 UI 可直接消费的结构：

```text
{
  timeline,
  entries,
  appended_entries,
  append_applied,
  steps,
  head_step_index,
}
```

当前支持三条主要路径：

### 1. 全量构建

- `build_step_timeline(engine, previous_timeline, false)`
- `build_info_from_timeline(timeline)`

用途：

- 普通对局初次构建
- 无可复用 baseline 时的 fallback

### 2. 预构建 timeline + entries 直载

- `load_prebuilt_timeline(timeline, ...)`
- `load_prebuilt_timeline_with_entries(timeline, entries, ...)`

用途：

- 恢复房完整历史已经预构建完成
- 避免再次从 `events` 重新格式化整份日志 entries

### 3. 增量 append

- `build_step_timeline(engine, previous_timeline, true)`
- 内部调用 `StepTimelineBuild.append_from_existing(...)`

输出：

- `append_applied = true`
- `appended_entries`

用途：

- 只在尾部新增了少量命令时，避免 full rebuild

## 联机恢复房：完整历史适配层

代码：`ui/scenes/game/timeline/online_resume_full_history_adapter.gd`

当前适配层已经进入**兼容收敛阶段**。新的恢复房启动模型不再长期维护双实例，而是：

- 常态 live engine 直接使用完整历史 engine
- `full_replay_engine` 字段保留为兼容命名，但在恢复房单引擎模式下与 live engine 指向同一实例
- 适配层更多承担：
  - 复用 prebuilt timeline / entries cache
  - 保持现有 Replay / History View / seek API 不必一次性全部改名

当前实现要点：

1. 从 `OnlineResumeSessionState` 读取：
  - `full_replay_step_timeline`
  - `full_replay_step_timeline_entries`
2. 在 `previous_timeline` 与 `cached_timeline` 之间选择更合适的 baseline
3. 当 processed command count 一致时，优先复用 prebuilt entries
4. 当只新增尾部命令时，优先走 incremental append
5. 在兼容模式下仍支持命令索引映射；但在单引擎恢复房里，坐标通常已不再需要短链换算

### 当前实现边界（2026-04-17）

新的恢复房方案改为：

- 启动期一次性完成完整 archive replay
- 启动期一次性完成 full timeline / entries cache 预构建
- 进入游戏后，`build_live_history_view(...)` 优先复用这份 prebuilt cache
- 后续 live 命令只做**单 timeline 增量 append / refresh**

因此现在的关键边界变成：

- 允许在 bootstrap 冷路径做一次 full build
- 不允许在 `command_applied` 热路径重新回到“双轨同步维护 + full rebuild”

## 日志面板如何消费 timeline

代码：

- `ui/components/game_log/game_log_panel.gd`
- `ui/components/game_log/game_log_unified_timeline_builder.gd`
- `ui/components/game_log/game_log_timeline_background_worker.gd`

当前日志面板支持两种时间线消费模式：

### 1. `load_step_timeline(...)`

- 用于首次载入 timeline
- 可走同步 rebuild，也可走后台 descriptor rebuild

### 2. `append_step_timeline(...)`

- 用于尾部 append
- 当前实现已支持：
  - 只传 **新增 timeline entries**
  - descriptor append
  - 后台 append job
  - item pool 复用
  - visible entry count cache

### 3. timeline state 局部刷新

`GameLogPanel` 当前还会维护一层轻量 UI index，用于把“日志项结构构建”和“cursor/head 状态刷新”拆开：

- `timeline_index -> exact items`
- `timeline_index -> first visible item`
- 小规模 `phase_header / round_header` 缓存

这样在常见的 live 场景里：

- `cursor/head: n -> n+1`
  - 不再全量扫描所有日志项
  - 只刷新受影响的 exact items 与少量 headers
- 历史视图停留在旧 cursor 时，若只是 `head` 前进且 future/past 关系未变化
  - `apply_timeline_state` 可直接 skip
- `scroll_to_cursor`
  - 也优先复用 first visible item index，而不是重新线性扫描整列日志

这意味着时间线层与日志 UI 层现在是显式分离的：

- timeline / entries 负责“数据语义”
- descriptor / items 负责“展示结构”

## UI 如何使用

`ui/scenes/game/timeline/controller.gd` 会在以下场景中消费这些派生时间线：

- 回放（Replay）
- 复盘（History view）
- 联机恢复房完整历史查看
- 实时日志视图（`apply_live_log_timeline_from_engine()`）

恢复房当前的常态数据源已经收敛为：

- **live action / authoritative client view**：单一 full-history engine
- **history timeline / replay / on-demand history log**：同一 engine + cached timeline / entries

也就是说，UI 仍然允许区分“live source”和“history source”，但这个区分现在更多是**交互模式差异**，而不是“双实例历史真相差异”。

### 当前演进方向

当前阶段的重点已经从“双轨切分”转向：

- 保持恢复房启动后的**单引擎语义**
- 让 `build_live_history_view(...)` 首次装配优先命中 prebuilt cache
- 保留 `append_from_existing(...)` / `append_step_timeline(...)` 的单时间线增量能力
- 避免因“已接受更慢启动”而在启动后再次引入每步 full rebuild

## 测试

基础时间线构建测试：

- `core/tests/event_timeline_build_test.gd`
- `core/tests/step_timeline_build_test.gd`
- `core/tests/step_timeline_incremental_append_test.gd`

恢复房单引擎 / cache / append 相关测试：

- `core/tests/online_resume_full_snapshot_bootstrap_test.gd`
- `core/tests/online_resume_single_full_engine_cache_test.gd`
- `core/tests/net_client_online_resume_cached_timeline_forwarding_test.gd`
- `ui/scenes/tests/game_log_panel_step_timeline_append_test.gd`

这些测试覆盖：

- 完整 snapshot bootstrap
- single full-engine session snapshot
- prebuilt timeline / entries cache 预构建与复用
- 启动后单 timeline cache append
- 日志面板同步 / 异步 append
