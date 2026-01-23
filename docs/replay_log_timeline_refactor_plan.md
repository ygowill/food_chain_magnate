# 回放与游戏日志融合（完整时间线）报告与重构开发计划

状态：提案 / 开发计划（基于当前仓库实现盘点）

## 1. 背景与目标

当前项目已经具备“命令时间线可回放”的核心能力（`GameEngine.command_history` + `rewind_to_command()`），也已经具备 UI 侧“事件日志面板”（`GameLogPanel` + `GameEventLogController`）。但“回放播放器（ReplayPlayer）”采用覆盖式独立面板，并且回放 seek 时日志不会随状态一起变化，导致体验割裂。

本计划的目标是把回放体验收敛为：

- 日志面板持有“完整时间线日志”（包含未来日志）。
- 回放只是移动“时间线指针”（cursor），地图/状态面板随 cursor 改变。
- 日志面板对未来日志置灰，并高亮当前 cursor 对应的日志/动作块。
- 玩家可点击日志跳转并进入回放态；回放态禁用右侧动作面板。
- 在自动连锁步骤很多的回合内，日志支持“宏（命令）/微（事件）”层级展示与折叠（可增量实现）。

## 2. 现有实现盘点（关键链路与问题根因）

### 2.1 引擎时间线与回放能力

- `core/engine/game_engine.gd`
  - `command_history` / `current_command_index`：线性时间线指针。
  - `rewind_to_command(target_index)`：从 checkpoint 恢复并重放到目标命令（命令粒度）。
  - rewind 之后会重建 `EventBus.history`（通过 `EventHistoryRebuild.build` 生成事件并 `EventBus.record_event` 写回），确保“事件历史与当前指针一致”。

相关文件：

- `core/engine/game_engine/replay.gd`：checkpoint + executor 方式的 rewind/full_replay。
- `core/engine/game_engine/event_history_rebuild.gd`：从初始状态重放命令，生成事件数组，用于重建 `EventBus.history`（不会通知订阅者）。
- `autoload/event_bus.gd`：`emit_event()`（通知订阅者并记录历史）与 `record_event()`（仅记录历史、不通知订阅者）。

关键约束：

- 引擎 rewind 的粒度是“命令（Command）边界”。自动连锁结算目前以 EventBus 事件形式存在，但没有“事件级中间态”的状态指针。

### 2.2 UI 日志系统

- `ui/scenes/game/game_event_log_controller.gd`
  - 订阅 EventBus 的白名单事件类型，把事件转成 `GameLogPanel.add_*_log(...)`。
  - 支持 `setup(..., restore_history=true)`：从 `EventBus.history` 恢复日志（修复了“读档回放发生在进入 GameScene 之前导致日志为空”的问题）。
  - 支持 `rebuild_from_history()`：用于 undo/redo/rewind 后重建 UI 日志显示。

- `ui/components/game_log/game_log_panel.gd`
  - 在内存中维护 `_entries`（`[{id,type,message,timestamp,details}]`），并将通过筛选的 entries 渲染为一组 `LogItem` 节点。
  - `timestamp` 当前使用 `Time.get_datetime_string_from_system()`（非确定性，仅用于 UI 展示）。
  - 双击条目弹出 details（`details` 会以 JSON 形式展示）。

### 2.3 回放播放器（导致“覆盖主界面”的直接原因）

- `ui/components/replay_player/replay_player.gd`：可加载存档并 `seek_to(command_index)`（内部调用 `GameEngine.rewind_to_command`）。
- `ui/scenes/game/game.gd`：
  - `show_replay_player()`：实例化 `ReplayPlayer`，`z_index = 1000` 并居中显示（覆盖式）。
  - `_enter_replay_mode(engine)`：把 `game_engine` 指向回放引擎，更新 UI；并通过 `_replay_mode_active` 阻止执行命令。

### 2.4 “回放时日志不跟着变”的根因

当 `ReplayPlayer.seek_to()` 触发 `GameEngine.rewind_to_command()` 时：

- 引擎会重建 `EventBus.history`（仅 record，不触发订阅者）。
- `Game._on_replay_state_changed()` 只调用 `_update_ui()`，不会调用 `GameEventLogController.rebuild_from_history()`，因此日志面板不会从新的 `EventBus.history` 重建显示。

即便补上 rebuild，也只能得到“截至 cursor 的历史日志”，无法满足“看到未来日志”的产品目标（因为 EventBus.history 被重建为截至 cursor 的子集）。

结论：要支持“未来日志可见”，必须把“完整日志”作为独立数据源持久持有，而不是每次 seek 都从 `EventBus.history` 重建。

## 3. 目标体验规格（在本项目中的落地定义）

### 3.1 时间线的两个指针

引入两个概念（UI 层）：

- `head_index`：该时间线已知的“最新命令索引”（回放：存档末尾；对局中：当前已执行末尾）。
- `cursor_index`：当前正在查看/回放的命令索引（-1 表示初始状态）。

渲染规则：

- `command_index <= cursor_index`：正常亮度（已发生，相对 cursor）。
- `command_index > cursor_index`：未来日志置灰。
- `command_index == cursor_index`：高亮“当前指针”对应的宏步骤块，并可滚动定位。

模式规则：

- `cursor_index == head_index`：非回放态（若是对局引擎则允许操作；若是存档回放引擎则仍应提示“回放只读”，但可弱化提示）。
- `cursor_index < head_index`：回放态（禁用 ActionPanel，提供“步进/回退/返回最新”）。

### 3.2 宏/微层级（适配“自动连锁步骤很多”）

推荐的展示层级：

- 宏：命令（Command）。每条命令显示：`#index actor action_id` + 可选 human-readable 文案。
- 微：该命令引发的事件序列（EventBus 事件、结算摘要事件等）。

注意：由于引擎只有“命令边界状态”，点击微步骤默认跳转到其所属命令的状态，并在日志中定位/高亮该微步骤（不尝试显示事件中间态）。

## 4. 推荐技术方案（完整时间线日志：数据与 UI 解耦）

### 4.1 建立“时间线日志存储”（独立于 EventBus.history）

新增一个 UI 层（或 core/ 可序列化层）的数据模型，用于持有完整日志：

建议字段（`LogEntry`）：

- `entry_id`：UI 内部唯一 ID（稳定用于选中/高亮）。
- `command_index`：该日志所属命令索引（-1 表示初始/系统启动类）。
- `event_seq`：该条日志在“完整事件流”中的顺序号（用于稳定排序）。
- `kind`：宏/微、阶段类/玩家类/结算类等（用于图标/筛选/折叠）。
- `message`：短摘要文本（列表展示）。
- `details`：结构化细节（双击查看/未来可展开）。
- `tags`：例如 `phase=Marketing`、`player_id=0`、`house_id=...`（用于过滤与跳转）。

`GameLogPanel` 不再把 `_entries` 当作“只能追加且必须跟随 EventBus.history”的集合，而是：

- `_entries_all`：完整时间线 entries（不会因 seek 而丢失）。
- `cursor_index/head_index`：决定渲染态（置灰/高亮/滚动定位）。

### 4.2 完整事件流的构建方式（回放加载一次，后续只移动 cursor）

回放（从存档加载）推荐流程：

1. 加载存档得到 replay engine（已存在：`GameEngine.load_from_file()`）。
2. 构建“完整事件流”（一次性）：
   - 复用 `core/engine/game_engine/event_history_rebuild.gd` 的逻辑，但目标是“构建到最后一条命令”，并为每条事件补齐 `command_index`。
   - 关键点：不要依赖 `EventBus.history`，而是直接拿到 events 数组作为“完整日志源”。
3. 用一个“事件→日志”格式化器（从 `GameEventLogController._on_eventbus_event` 抽出来）把 events 转为 `LogEntry` 列表写入 `GameLogPanel`。
4. seek 时：
   - 只调用 replay engine `rewind_to_command(cursor_index)` 来更新地图/面板。
   - 只更新 `GameLogPanel.cursor_index` 来刷新置灰/高亮；不清空、不重建完整日志。

对局内（非存档回放）推荐流程：

- 继续订阅 EventBus.emit_event 来追加新日志（自然增长）。
- 当玩家把 cursor 拉回历史时：
  - 允许进入“查看历史”态：禁用 ActionPanel，日志出现未来置灰。
- 若玩家在历史态执行新命令（当前引擎会截断 future command_history）：
  - 同步截断 `_entries_all` 中 `command_index > new_head_index` 的 entries，避免“显示不存在的未来”。

### 4.3 UI 结构建议（不再弹出覆盖式 ReplayPlayer）

把回放控件做成日志面板顶部的“ReplayBar”：

- 文件：加载/刷新/浏览（可复用现有 SaveLoadDialog 或 ReplayPlayer 的文件枚举逻辑）。
- 控件：`<< < > >>`、`返回最新`、（可选）倍速、（可选）自动播放。
- 状态提示：`回放中：#cursor / #head`，以及“只读回放”提示。

回放条在 `cursor_index < head_index` 时自动显现（或始终显现但弱化）。

ActionPanel 禁用策略：

- 进入回放态时，ActionPanel 所有按钮 disabled，并显示固定提示（例如“回放中不可操作”）。
- 保留“退出回放/返回最新”的入口在 ReplayBar。

## 5. 增量重构开发计划（可执行、可回滚）

### M0：最小可用（修复同步与铺路）

目标：

- 回放 seek 时 UI 不再“日志不变”。
- 引入 cursor/head 概念，并为未来日志置灰预留接口（先不做完整日志）。

工作项：

- [x] 在 `ui/scenes/game/game.gd` 的回放 seek 回调中补齐日志刷新调用（短期止血）。
- [x] `GameLogPanel`：增加 `set_timeline_head(head_index: int)`
- [x] `GameLogPanel`：增加 `set_timeline_cursor(cursor_index: int)`
- [x] `GameLogPanel`：增加 `set_entry_command_index(entry_id, command_index)`（或通过 details 写入并在 LogItem 渲染时读取）

验收：

- 回放步进时日志能跟着变化（即使暂时只有“截至 cursor 的历史”）。

### M1：完整日志数据源（支持“未来日志可见”）

目标：

- 回放加载时一次性生成“完整日志”，seek 仅移动 cursor，不重建日志。
- 日志面板在回放态能看到未来日志并置灰。

工作项：

- [x] 新增构建器 `core/engine/game_engine/event_timeline_build.gd`：`build_full(engine: GameEngine) -> Result(events)`（包含每条事件的 `command_index`，并补齐 `GAME_STARTED` 等初始化事件）。
- [x] 抽离日志格式化：新增 `ui/scenes/game/game_event_log_formatter.gd`，并让 `GameEventLogController` 变为“订阅者 + 调用 formatter”。
- [x] `GameLogPanel` 改为持有 `_entries_all`，并能根据 `cursor/head` 更新每条 `LogItem` 的“未来置灰/当前高亮”样式（取消 `max_entries` 上限）。

验收：

- 回放加载后，日志总条目数固定不变；seek 到过去时未来日志仍在、但置灰。
- 点击“返回最新”后全部恢复正常亮度。

### M2：替换覆盖式 ReplayPlayer 为嵌入式 ReplayBar

目标：

- 不再显示覆盖主界面的 `ReplayPlayer` 面板。
- 回放控制与日志面板融合。

工作项：

- 新增 `ui/components/game_log/replay_bar.*`（或放在 `ui/components/replay_player/` 内重命名拆分）。
- `Game` 场景接线：
  - 从菜单/开始页面进入回放：加载存档 -> 进入 GameScene -> 进入 replay engine（现有能力）-> 构建完整日志 -> 显示 ReplayBar。
- `ReplayPlayer` 保留为开发工具/临时入口（可隐藏/标记为 debug-only），避免一次性删掉导致测试/工作流中断。

验收：

- 不出现遮挡主界面的回放窗口。
- ReplayBar 在日志面板顶部可用，步进/跳转/返回最新可用。

### M3：回放态 UI 约束完善（动作面板禁用 + 明确信号）

目标：

- 回放态不会误操作，玩家一眼能理解“只读回放/查看历史”。

工作项：

- ActionPanel 增加公共 API（例如 `set_globally_disabled(reason: String)`），由 Game 在回放态调用。
- 顶部/右侧增加“回放中”提示条（可复用现有 UI 体系）。

验收：

- 回放态 ActionPanel 不可点击且有明确提示。
- 退出回放/返回最新后恢复可操作。

### M4：宏/微分组与折叠（应对“自动连锁步骤很多”）

目标：

- 日志默认以“命令块”展示，每块可展开查看自动连锁细节。

工作项（两种实现路径二选一）：

1) Tree/List 结构：
   - 改用 `Tree` 或自定义虚拟列表，节点结构：CommandHeader -> EventItems。
2) 仍用扁平列表但加折叠行：
   - 插入“折叠摘要行”（例如“该动作包含 7 条结算，点击展开”），展开后插入/显示子项。

验收：

- 回合结算大量事件时日志仍可读，不淹没关键信息。

## 6. 测试与验收计划（建议新增/调整）

现有相关测试：

- `ui/scenes/tests/log_restore_after_load_test.gd`：验证从 `EventBus.history` 恢复日志（仍应保留，作为“订阅缺失时的兜底机制”）。
- `ui/scenes/tests/replay_player_smoke_test.gd`：验证 ReplayPlayer 能加载并 seek（若 M2 后 ReplayPlayer 降级为工具，可调整测试目标或新增 ReplayBar 测试）。

建议新增：

- `core/tests/event_timeline_build_test.gd`：
  - 构造 20+ 命令的确定性用例，build_full() 返回 events 不为空且每条含 `command_index`（单调不减），并与命令数量一致性可验。
- `ui/scenes/tests/replay_log_future_visibility_test.gd`（无需渲染）：
  - 加载回放并构建完整日志后，seek 到较早 cursor：
    - `GameLogPanel.get_entries()` 数量不变（仍包含未来）。
    - `GameLogPanel` 的内部（或暴露测试 API）能区分 future/past（例如 `get_future_entry_count(cursor)`）。

## 7. 风险与注意事项

- 性能：当前 `GameLogPanel` 用 `VBoxContainer + 大量 LogItem 节点`，完整时间线可能变得很长；需要尽早规划虚拟列表/分组折叠，避免节点爆炸。
- 确定性/排序：UI 展示时间不要依赖系统时间；建议用 `command.timestamp`（游戏内确定性时间）或 `event_seq` 作为排序/展示主依据。
- 兼容现有“从 EventBus.history 恢复日志”的逻辑：它仍有价值（读档进入 GameScene 前的事件回放），但在“完整日志”方案落地后，应明确其定位为兜底，而不是 replay seek 的数据源。
- 微步骤中间态：如果未来要支持“事件级步进回放”，需要引擎支持更细粒度的状态快照/重放点（超出本计划范围）。

## 8. 待确认问题（建议你给出偏好，以便定稿）

1) “回放态”的定义：仅对“从存档加载的回放引擎”生效，还是对局内也允许把 cursor 拉回历史进行复盘？
2) 点击“未来日志”时的行为：是否允许直接跳到该日志所属命令（即快进），还是仅提示“未来内容”？
3) 宏步骤（命令）的人类可读文本来源：先用 `action_id` + params 生成简易文案，还是引入 `ActionExecutor.display_name`/本地化表来生成？
