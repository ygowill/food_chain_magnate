# 回放与游戏日志融合（完整时间线）报告与重构开发计划

状态：提案 / 开发计划（基于当前仓库实现盘点）

## 1. 背景与目标

当前项目已经具备“命令时间线可回放”的核心能力（`GameEngine.command_history` + `rewind_to_command()`），也已经具备 UI 侧“事件日志面板”（`GameLogPanel` + `GameEventLogController`）。但“回放播放器（ReplayPlayer）”采用覆盖式独立面板，并且回放 seek 时日志不会随状态一起变化，导致体验割裂。

本计划的目标是把回放体验收敛为：

- 日志面板持有“完整时间线日志”（包含未来日志）。
- 回放只是移动“时间线指针”（cursor），地图/状态面板随 cursor 改变。
- 日志面板对未来日志置灰，并高亮当前 cursor 对应的日志/动作块。
- 玩家可点击日志跳转并进入回放/复盘态；回放/复盘时日志面板占用右侧动作面板区域（可覆盖 ActionPanel），左侧玩家信息保持可见。
- 在自动连锁步骤很多的回合内，日志支持“宏（命令）/微（事件）”层级展示与折叠（可增量实现）。
- 回放中“大阶段（phase）切分”必须可靠：例如 Working / Dinnertime / Payday / Marketing / Cleanup 等阶段切换不能因为 auto-advance 被合并成一个；Working 内的“小阶段（sub_phase）”尽可能打包，以玩家行动为分割，避免过度碎片化。

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

- 引擎 rewind 的粒度是“命令（Command）边界”。自动推进（auto-advance）会在一次命令执行内连锁推进多个阶段/子阶段，并以 EventBus 事件形式记录；若要在回放中按“大阶段切分”停在阶段边界，需要引入“语义步进点（step）+ 阶段边界快照”，或把部分 auto-advance 拆成可回放的系统步进（见 M4.2）。

### 2.2 UI 日志系统

- `ui/scenes/game/game_event_log_controller.gd`
  - 订阅 EventBus 的白名单事件类型，把事件转成 `GameLogPanel.add_*_log(...)`。
  - 支持 `setup(..., restore_history=true)`：从 `EventBus.history` 恢复日志（修复了“读档回放发生在进入 GameScene 之前导致日志为空”的问题）。
  - 支持 `rebuild_from_history()`：用于 undo/redo/rewind 后重建 UI 日志显示。

- `ui/components/game_log/game_log_panel.gd`
  - 在内存中维护 `_entries_all`（`[{id,type,message,timestamp,details,command_index?}]`），并将通过筛选的 entries 渲染为一组 `LogItem` 节点。
  - `timestamp`：运行时默认使用 `Time.get_datetime_string_from_system()`（非确定性，仅用于 UI 展示）；回放/时间线模式建议用确定性的 `event_seq`/`command.timestamp`。
  - 双击条目弹出 details（`details` 会以 JSON 形式展示）。

### 2.3 回放播放器（导致“覆盖主界面”的直接原因）

- `ui/components/replay_player/replay_player.gd`：可加载存档并 `seek_to(command_index)`（内部调用 `GameEngine.rewind_to_command`）。
- `ui/scenes/game/game.gd`：
  - `show_replay_player()`：实例化 `ReplayPlayer`，`z_index = 1000` 并居中显示（覆盖式）。
  - `_enter_replay_mode(engine)`：把 `game_engine` 指向回放引擎，更新 UI；并通过 `_replay_mode_active` 阻止执行命令。

### 2.4 “回放时日志不跟着变”的根因（旧 ReplayPlayer 路径）

当 `ReplayPlayer.seek_to()` 触发 `GameEngine.rewind_to_command()` 时：

- 引擎会重建 `EventBus.history`（仅 record，不触发订阅者）。
- 若 UI 不主动调用 `GameEventLogController.rebuild_from_history()`，日志面板不会从新的 `EventBus.history` 重建显示。

现状更新：

- 仓库已在 `ui/scenes/game/game.gd` 的 `_on_replay_state_changed()` 中补齐 `rebuild_from_history()`，可解决“seek 后日志不变”的短期问题。
- 但该路径本质仍只能得到“截至 cursor 的历史日志”，无法满足“看到未来日志”的产品目标（因为 `EventBus.history` 会被重建为截至 cursor 的子集）。

结论：要支持“未来日志可见”，必须把“完整日志”作为独立数据源持久持有，而不是每次 seek 都从 `EventBus.history` 重建。

### 2.5 “点击日志跳转时整回合同时高亮 / 状态跳到回合末”的根因（读档恢复日志丢失 command_index）

现象（来自手工复核存档 `res://.savings/manual_cases/logs/event_log_review.json`）：

- 复现路径：主菜单「载入游戏」加载该存档。
- 日志里能看到多个玩家操作（例如“玩家1 放置营销 / 采购饮料”）。
- 点击其中某一条（例如“玩家1 放置营销”）时，整回合的日志同时高亮，并且状态跳到“该回合玩家行动都结束之后”的时间点。
- 使用单步后退可以进入到“放置营销之后”的状态，但此时日志没有正确高亮到对应条目。

根因链路（核心是：日志条目缺少稳定的 `command_index` 映射）：

- `core/engine/game_engine/loader.gd` 读档时通过 `engine.execute_command(cmd, true)` 回放命令来恢复状态。
- `core/engine/game_engine/command_runner.gd` 在回放/运行时发射事件时，除 `COMMAND_EXECUTED` 外，事件 `data` 默认不包含 `command_index`。
- `autoload/event_bus.gd` 会原样把 `{type,data,sequence,timestamp}` 写入 `EventBus.history`（不会自动补齐 `command_index`）。
- `ui/scenes/game/game_event_log_controller.gd` 在 “restore_history/rebuild_from_history” 时，`_infer_command_index()` 若读不到 `data.command_index`，会 fallback 到 `Globals.current_game_engine.current_command_index`。
  - 读档完成后 `current_command_index` 通常等于存档的 `current_index`（常见为 head），因此“所有历史事件”会被误判为同一个 `command_index`。
- `ui/components/game_log/game_log_panel.gd` 的时间线高亮规则是 `entry.command_index == cursor_index`，因此会出现“整回合同时高亮”；
  点击日志跳转时也会 seek 到同一个 `command_index`，看起来像“点击任意条目都跳到回合末/回合结束后”。

结论：

- 时间线（点击跳转/高亮/置灰）必须依赖“每条日志稳定绑定到正确的 `command_index`”；不能在恢复历史时用 `Globals.current_game_engine.current_command_index` 兜底，否则会把整段历史压扁成一个点。

修复方向（采用方案 A；已实施）：

1) 在事件产生源头补齐（已实施）：`CommandRunner.execute_command()` 在发射每条事件前把 `command_index` 写入 event `data`（additive 字段）。
   - 优点：`EventBus.history` 天然可用于恢复日志与时间线；读档/运行时一致；不会引入二次回放成本。
   - 风险：会改变事件 payload（增加字段）；若有测试/逻辑对 event data 做严格相等断言，需要同步调整。
2) 在读档后重建 EventBus.history：`Loader.load_from_archive()` 结束时用 `EventHistoryRebuild.build(engine, engine.current_command_index)` 重新生成事件并用 `EventBus.record_event()` 回填（替换掉 load 时 emit 产生的 history）。
   - 优点：改动集中在读档路径；不改运行时事件 payload。
   - 风险：读档成本增加（再跑一遍事件构建）；若未来支持“游戏内读档”且当时已有订阅者，需要确保不会触发重复副作用（应使用 record + clear）。
3) UI 恢复时推导：`GameEventLogController` 在 restore_history 时以 `COMMAND_EXECUTED` 为边界进行两段式映射（缓存直到遇到该命令的 `COMMAND_EXECUTED` 再回填 `command_index`）。
   - 优点：不改引擎/事件 payload。
   - 风险：实现复杂且依赖事件顺序假设；当 `COMMAND_EXECUTED` 被过滤或未来有“跨命令事件”时容易出错。

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

### 3.3 大阶段切分 + Working 打包（新增整改目标）

术语约定（以本项目状态字段为准）：

- 大阶段：`state.phase`（例如 `Working` / `Dinnertime` / `Payday` / `Marketing` / `Cleanup` …）。
- 小阶段：`state.sub_phase`（主要发生在 `Working` 内，例如 `Recruit/Train/Marketing/GetFood/GetDrinks/...`）。

整改目标（回放/时间线）：

- 大阶段切换必须可“切分/停留”：即使阶段切换由 auto-advance 触发、且发生在同一条命令内部，时间线也必须出现独立的阶段步进点（否则会被用户感知为“合并成一个”）。
- Working 内的小阶段（sub_phase）默认不引入额外的步进点：尽可能打包在“玩家行动块”里（玩家行动 = 命令/Command），日志里仍可见 sub_phase 变化，但归入最近的玩家行动块（可折叠），以避免时间线过度碎片化。

实现落地方向（推荐）：引入“语义步进点 step_index”，将回放步进从纯 `command_index` 扩展为：

- `cursor_step` / `head_step`：回放条（ReplayBar）滑块与高亮以 step 为单位。
- 每个 step 绑定一个可恢复的 `GameState` 快照（仅用于查看/回放，动作面板仍保持禁用），并保留其“锚点命令索引”（`anchor_command_index`）用于追溯来源与与旧逻辑兼容。
- step 的生成规则：
  - 玩家命令：每条命令至少生成一个 step（“玩家行动步”）。
  - auto-advance：仅在 `phase` 发生变化时额外生成 step（“阶段切换步”），且阶段 step 的 state 以“进入该阶段后的状态（含 enter settlement/enter hooks）”为准；`sub_phase` 变化仅更新当前 step 的状态与日志归属，不额外生成 step（满足“Working 小阶段尽可能打包”）。

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

`GameLogPanel` 不再把 `_entries_all` 当作“只能追加且必须跟随 EventBus.history”的集合，而是：

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

日志面板位置（布局调整建议）：

- 将 `GameLogPanel` 从“左侧信息区的二选一视图”调整为“右侧动作面板区域的可切换视图”（可覆盖 ActionPanel）。
- 目的：玩家信息（左侧）与日志（右侧）可同时查看；查看日志时通常不需要执行动作，因此覆盖 ActionPanel 的影响较小。

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

### M0.5：修复“读档后日志跳转/高亮异常”（command_index 丢失）

目标：

- 加载存档后（尤其是 `.savings/manual_cases/logs/event_log_review.json` 这类用于复核日志的存档），日志条目的 `command_index` 能正确映射到各自命令。
- 点击日志跳转只高亮该命令对应的日志块，且状态停在该命令执行后的时间点；单步前进/后退时高亮同步更新。

工作项（与 2.5 的修复方向对应）：

- [x] 方案 A（已实施）：在 `CommandRunner.execute_command()` 发射事件前为每条事件 `data` 补齐 `command_index`（并评估是否同时补齐 `command_timestamp`）。
- [ ] 方案 B：读档完成后用 `EventHistoryRebuild.build()` 生成带 `command_index` 的事件，并用 `EventBus.record_event()` 覆盖 history（避免 UI 从“无 command_index 的 history”恢复）。
- [ ] 方案 C：在 `GameEventLogController` 的 restore_history 路径做两段式推导（以 `COMMAND_EXECUTED` 为边界回填）。

验收（建议按手工步骤验证）：

- 载入 `res://.savings/manual_cases/logs/event_log_review.json`，打开日志并点击“玩家1 放置营销”：
  - 只高亮该动作所属命令的日志（不应整回合同时高亮）。
  - 画面状态停在该命令执行后（可从地图/阶段/玩家状态验证）。
- 使用 ReplayBar 单步后退/前进：日志高亮与状态一致。

自动化回归：

- `core/tests/manual_log_save_test.gd`：载入 `event_log_review.json` 后，断言关键事件存在且具备 `data.command_index`（避免回归到“整段历史压扁为一个索引”）。

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

- [x] 新增 `ui/components/game_log/replay_bar.*`。
- [x] `Game` 场景接线：从菜单/开始页面进入回放：加载存档 -> 进入 GameScene -> 进入 replay engine -> 构建完整日志 -> 显示 ReplayBar。
- [x] `ReplayPlayer` 保留为开发工具/临时入口（可隐藏/标记为 debug-only），避免一次性删掉导致测试/工作流中断。

验收：

- 不出现遮挡主界面的回放窗口。
- ReplayBar 在日志面板顶部可用，步进/跳转/返回最新可用。

### M2.5：日志面板右侧化（与玩家信息同屏）

目标：

- 查看日志时不再隐藏左侧玩家信息面板。
- 日志面板占用右侧动作面板区域（可覆盖/替换 ActionPanel），符合“看日志时通常不操作”的使用习惯。

工作项：

- [x] 调整 GameScene 布局：通过 `dock_popup_into_right_panel()` 将 `GameLogPanel` 嵌入 RightPanel 抽屉区域显示（覆盖 ActionPanel）。
- [x] 更新“日志”入口：从“左侧二选一切换”改为“右侧显示/关闭日志面板”（左侧信息保持可见）。
- [ ] 回放/复盘态：右侧默认显示日志面板（并保持 ReplayBar 可用），ActionPanel 隐藏或置灰。
- [x] 退出日志视图：关闭日志后恢复默认右侧动作区；保持时间线 cursor/head 不丢失（关闭方式：日志面板自身 Close 或 RightPanel Back）。

验收：

- 左侧玩家信息 + 右侧日志可同时显示。
- 打开日志会覆盖右侧动作区；若已有其它 docked 面板则先关闭以避免焦点竞争；关闭日志后回到默认动作区，RightPanel Back/日志 Close 行为符合预期。

### M3：回放态 UI 约束完善（动作面板禁用 + 明确信号）

目标：

- 回放态不会误操作，玩家一眼能理解“只读回放/查看历史”。

工作项：

- [x] ActionPanel 增加公共 API（例如 `set_globally_disabled(reason: String)`），由 Game 在回放态/查看历史态调用。
- [x] 顶部/右侧增加“回放中”提示条（复用 TopBar 文案：回放 `（回放）` / 复盘 `（复盘）`）。
- [x] 回放/复盘（只读时间线）时：禁止强制交互弹窗与强提示面板（Restructuring/TurnOrder/ReserveCards/FridgeKeep/BankBreak/GameOver），避免阻塞时间线回放。

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

### M4.3：合并“回放控制 + 日志”为统一时间线视图（缩进展示动作/事件；不折叠）

用户确认的目标（本里程碑的设计约束）：

- **统一展示**：日志面板本身就是“时间线视图”，顶部 ReplayBar 仅负责导航；不再让用户感知为两个系统。
- **统一适用范围**：不仅回放/复盘，**正常对局实时日志也使用同一种展示结构**。
- **阶段可见**：列表按“大阶段（phase）”展示分段标题（Working/晚餐/发薪日/广告/清理/重组…），且阶段切分必须与 M4.2 的 step 语义一致。
- **回合分隔**：不需要在阶段标题显示回合号；但两回合之间必须插入一个“回合分隔标题块”。
- **层级缩进**：阶段内按“玩家动作/系统动作”分组；组内事件以缩进子项展示；不需要折叠/展开（默认全部展开）。
- **不暴露内部索引**：UI 不显示 `step xx`、`cmd xx`；内部仍保留稳定索引用于 seek/highlight。
- **去掉 PlayerFilter**：日志面板默认展示完整日志（不提供按玩家过滤）。
- **阶段事件默认不显示**：`PHASE_CHANGED/ROUND_*/*_REPORT` 等“阶段/回合事件”作为结构依据即可，不作为子项默认展示。
- **阶段标题点击跳转**：点击阶段标题 seek 到该阶段段落的开始。

#### M4.3.1 统一视图结构（UI 规格）

列表结构（从上到下）：

1) RoundHeaderItem（回合分隔标题块）
   - 触发：当时间线检测到 `round` 发生变化时，在两段日志之间插入一条分隔标题。
   - 文案：不显示回合号；使用稳定文案即可（例如“进入新回合”/“回合切换”）。
   - 点击行为（可选）：seek 到该回合的第一条 ActionGroup（若实现简单可先不做）。
2) PhaseHeaderItem（阶段标题行）
   - 文案：仅显示阶段名（建议做本地化映射：Payday->发薪日，Marketing->广告阶段等）。
   - 高亮规则：当 cursor 落在该阶段段落范围内时，高亮该标题行。
   - 点击行为：seek 到该阶段段落的开始 timeline_index。
3) ActionGroupHeaderItem（动作组标题行）
   - 文案：优先使用“玩家动作摘要”（例如“玩家1：放置营销 ……”）；若该组没有玩家动作，则显示系统摘要（例如“进入发薪日”“进入广告阶段”“进入清理阶段”“进入重组阶段”）。
   - 高亮规则：当 cursor == 该组 timeline_index 时高亮。
   - 点击行为：seek 到该组 timeline_index。
4) EventItem（动作组子项，缩进显示）
   - 文案：事件摘要（沿用 formatter 文案）。
   - 视觉：缩进 + 更小字号/更淡颜色，明确“属于上一条动作组”。
   - 点击行为：seek 到所属动作组 timeline_index（本里程碑不做事件级 seek）。

#### M4.3.2 统一数据映射规则（round/phase/action 三层切分）

核心原则：**结构来自 steps，内容来自 events**（避免“某个 step 没有可见事件就消失”导致单步无效果）。

输入数据源（所有模式统一）：

- 统一以 step 时间线为主（M4.2 的 `StepTimelineBuild.build_full()` 输出）：
  - `steps[]`：提供每个 timeline_index 的快照字段（至少包含 round/phase/sub_phase/state_dict）。
  - `events[]`：提供每条事件归属（至少包含 step_index/phase_segment/command_index/type/data）。

结构构建算法（概念描述）：

1) 遍历 timeline 的 step（`-1` 初始 + `0..head_step`）：
   - 若与上一个 step 的 `round` 不同：插入 RoundHeaderItem。
   - 若与上一个 step 的 `phase` 不同（或 round 刚变）：插入 PhaseHeaderItem，并记录该阶段段落的 `start_step_index`。
   - 为每个 step 创建一个 ActionGroupHeaderItem（保证“每步都可见可点”）。
2) 将 events 按 `step_index` 挂到对应 ActionGroup 下，作为 EventItem 子项：
   - 默认过滤掉“阶段事件子项”（`PHASE_CHANGED/SUB_PHASE_CHANGED/ROUND_STARTED/ROUND_ENDED/*_REPORT` 等），但这些事件仍可用于调试详情窗口。
   - 其余事件作为缩进子项展示（例如营销产生需求、采购路线、现金变化、丢弃库存、里程碑等）。

动作组摘要（ActionGroupHeaderItem.text）决策：

- 优先：从该 step 的“非阶段事件子项”里找第一条 `LogType.PLAYER` 的 formatted message 作为摘要。
- 否则：用 step 快照生成系统摘要：
  - phase step：`进入{phase_display_name}`（不显示 from/to 内部字段也可；若你更偏好 from/to 文案可替换）。
  - command step：`系统结算/系统推进`（仅在确实没有玩家动作时兜底）。

#### M4.3.3 ReplayBar 状态显示（不展示 step/cmd）

保留 `cursor / head` 的数字（滑块位置），但 extra 仅显示“当前阶段”：

- `阶段：{phase_display_name}`（Working 内 sub_phase 默认不显示，避免噪声）。
- 不显示 `step xx`、`cmd xx`。

#### M4.3.4 对正常对局（实时）如何做到“同一视图”

建议实现路径（计划）：

1) **日志面板渲染统一走“时间线视图”组件**（Round/Phase/Action/Event 四类行）。
2) **实时数据源也走同一套 step_timeline 构建**：
   - 在打开日志面板、或每次命令执行后（可做 debounce/throttle）调用 `StepTimelineBuild.build_full(engine)`，用其输出重建列表（结构稳定且阶段切分一致）。
   - 进入“查看历史”时仍复用同一份 step_timeline（只移动 cursor）。
3) 性能风险与缓解（先写入计划，后续实现时再按需要落地）：
   - 若全量重建成本过高：增量扩展 step_timeline（只追加最新命令链路）作为优化项，不影响首版正确性目标。

#### M4.3.5 验收标准（对用户可见）

- 载入 `.savings/manual_cases/logs/event_log_review.json`：
  - 能看到“回合分隔标题块”出现在回合切换处。
  - 能看到“晚餐时间/发薪日/广告/清理/重组”等阶段标题分段（不再揉成一段）。
  - 阶段标题点击会跳到该阶段段落的开始（状态与日志高亮一致）。
  - “阶段事件子项”默认不显示，但阶段标题与系统摘要能让用户看懂阶段推进。
- 正常对局实时进行中：
  - 日志以同样的 Round/Phase/Action/Event 结构增长（不再是另一套扁平日志视图）。

#### M4.3.6 实施步骤（仅计划；未获允许不改代码）

1) UI：移除 PlayerFilter（日志默认完整展示）
2) UI：将现有 grouped view 重塑为“缩进层级视图”
   - StepHeaderItem -> ActionGroupHeaderItem（不显示 step/cmd）
   - LogItem 作为 EventItem（缩进）
   - 新增 RoundHeaderItem（回合分隔）
3) 事件显示策略：阶段事件子项默认隐藏（但仍可在详情窗口查看）
4) PhaseHeader 点击跳转：seek 到该阶段段落 start_step_index
5) 实时模式统一：打开日志/命令执行后用 StepTimelineBuild 重建时间线视图（必要时加 debounce）
6) 回归验证：`event_log_review.json` + `demo_image/log_demo.png` + `AllTests`

### M4.1：Phase 视觉切分 + Working 打包展示（不改 seek 粒度）

目标：

- 日志视图按“大阶段（phase）”做明显的分段（Working / Dinnertime / Payday / Marketing / Cleanup…），便于扫读。
- Working 段内以“玩家行动（命令）”为分割进行打包；子阶段（sub_phase）变化与自动连锁事件作为微项归入动作块（默认可折叠）。
- 该里程碑仅改变“如何展示/折叠”，不改变回放 seek 的粒度（仍以 command_index 为主）。

工作项：

- [x] UI 分组：按 `phase_segment` 渲染“阶段标题行”（`ui/components/game_log/game_log_panel.gd`：PhaseHeaderItem）。
- [x] Working 打包：按 `step_index`（fallback `command_index`）分组；Working 段默认折叠，仅展开当前 cursor step（`ui/components/game_log/game_log_panel.gd`：StepHeaderItem + _collapsed_step_groups）。
- [x] 点击交互：点击阶段/step 标题触发 seek（`timeline_seek_requested`）；step 标题在 Working 内点击可展开/折叠（展开时同时 seek）。

验收：

- 回放中从 Working 进入 Dinnertime/Payday 等阶段时，日志列表视觉上不会“揉成一团”，用户可明显看到阶段分段。
- Working 内 sub_phase 连续变化不会把日志切得过碎；默认视图以玩家行动为主。

### M4.2：大阶段可步进（step_index + 阶段边界快照）

目标：

- 回放时间线可以停在每一次大阶段切换处（Working/Dinnertime/Payday/Marketing/Cleanup…），即使该切换由 auto-advance 触发且发生在同一条命令内部。
- Working 内的小阶段仍保持“尽可能打包”：`sub_phase` 变化不额外生成 step（只作为动作块的微事件）。

工作项（核心是“在 command 粒度之外补一个 step 粒度”）：

- [x] 新增 step 时间线构建器（`core/engine/game_engine/step_timeline_build.gd`）：
  - 从初始 checkpoint state 起，按命令重放；
  - 对每条命令：应用命令 -> 记录“玩家行动 step”；
  - 若命令本身触发 `phase` 切换（例如 `advance_phase`），则以 `PHASE_CHANGED` 为边界拆分事件归属：
    - `PHASE_CHANGED` 之前（含 `*_REPORT`）归属到旧阶段的最后一个 step（避免 Payday/Marketing/Cleanup 被压到同一步）
    - `PHASE_CHANGED` 及之后归属到新阶段（玩家行动 step）
  - 对 auto-advance：逐步执行 `AutoAdvance.try_advance_one`，仅当 `phase` 变化时记录“阶段切换 step”，并且快照取 `advance_phase()` 之后的 state（已包含 enter settlement / enter hooks / 自动进入首个子阶段等）；`sub_phase` 变化仅更新当前 step 的状态与日志归属；
  - 为每个 step 保存 `state_dict`（或 `GameState` 深拷贝）作为快照，并保存 `anchor_command_index`。
- [x] ReplayBar 改为 step 粒度：滑块范围改为 `[-1, head_step]`；状态栏显示 `step` 且附带锚点信息（`ui/components/game_log/replay_bar.gd` + `ui/scenes/game/game.gd`）。
- [x] Seek 实现：回放 seek 不再只调用 `rewind_to_command(command_index)`；而是从 step 快照直接恢复 UI 所需状态（只读回放中允许使用 step 快照直接覆盖 `game_engine.state`，并同步 `cursor_step/cursor_index` 显示）（`ui/scenes/game/game.gd:_seek_to_replay_step`）。
- [x] 复盘（非回放）同样使用 step 时间线：首次 seek 到历史命令时构建 step_timeline 并替换日志为“完整时间线日志”，seek 使用 step 快照覆盖 `game_engine.state`；返回最新时恢复实时日志（`ui/scenes/game/game.gd:_enter_history_step_timeline_for_command/_exit_history_step_timeline`）。
- [x] 日志高亮/置灰改为 step 粒度：为每条日志条目补充 `step_index`（构建时写入），置灰/高亮按 `step_index` 判断；保留 `command_index` 作为详情追溯与“按命令过滤”的基础字段（`ui/components/game_log/game_log_panel.gd` + `ui/scenes/game/game.gd`）。
  - 事件归属规则补充：`*_REPORT`（在离开阶段时发射）归属到“离开前阶段”（即旧阶段的最后一个 step/段），避免被显示在新阶段段落里。

验收（建议用用户提供的复现场景手验）：

- 回放中当一个命令触发 auto-advance 连续跨越多个大阶段时（例如 Working -> Dinnertime -> Payday -> ...）：
  - 时间线滑块/步进可以逐个停在这些大阶段上（不再被合并成一个位置）。
  - 每一步对应的日志高亮与画面状态一致。
- Working 内的小阶段（sub_phase）切换不会导致时间线产生大量额外 step；默认步进以“玩家行动”为主。

## 6. 测试与验收计划（建议新增/调整）

现有相关测试：

- `ui/scenes/tests/log_restore_after_load_test.gd`：验证从 `EventBus.history` 恢复日志（仍应保留，作为“订阅缺失时的兜底机制”）。
- `ui/scenes/tests/replay_player_smoke_test.gd`：验证 ReplayPlayer 能加载并 seek（若 M2 后 ReplayPlayer 降级为工具，可调整测试目标或新增 ReplayBar 测试）。

建议新增：

- [x] `core/tests/event_timeline_build_test.gd`：
  - 构造 20+ 命令的确定性用例，build_full() 返回 events 不为空且每条含 `command_index`（单调不减），并与命令数量一致性可验。
- [x] `core/tests/step_timeline_build_test.gd`：
  - 载入 `res://.savings/manual_cases/logs/event_log_review.json`，build_full() 返回 steps/events 且 events.step_index 单调不减，并包含至少一个 `phase` step（验证阶段切分）。
- [x] `ui/scenes/tests/replay_log_future_visibility_test.gd`（无需渲染）：
  - 加载回放并构建完整日志后，seek 到较早 cursor：
    - `GameLogPanel.get_entries()` 数量不变（仍包含未来）。
    - `GameLogPanel` 的内部（或暴露测试 API）能区分 future/past（例如 `get_future_entry_count(cursor)`）。

## 7. 风险与注意事项

- 性能：当前 `GameLogPanel` 用 `VBoxContainer + 大量 LogItem 节点`，完整时间线可能变得很长；需要尽早规划虚拟列表/分组折叠，避免节点爆炸。
- 确定性/排序：UI 展示时间不要依赖系统时间；建议用 `command.timestamp`（游戏内确定性时间）或 `event_seq` 作为排序/展示主依据。
- 兼容现有“从 EventBus.history 恢复日志”的逻辑：它仍有价值（读档进入 GameScene 前的事件回放），但在“完整日志”方案落地后，应明确其定位为兜底，而不是 replay seek 的数据源。
- 微步骤中间态：本计划拟在 M4.2 支持“按大阶段切分”的 step 粒度（阶段边界快照），但仍不追求“任意事件级步进回放”；若要做到真正的事件级中间态，需要更细粒度的状态快照/重放点（超出本计划范围）。

## 8. 已确认约定

1) “回放态”的定义：对局内也允许把 cursor 拉回历史进行复盘（并禁用 ActionPanel）。
2) 点击“未来日志”时的行为：允许直接跳到该日志所属命令（快进）。
3) 宏步骤（命令）的人类可读文本来源：使用 `ActionExecutor.display_name`/本地化表。
4) 计划需包含 M2（嵌入式 ReplayBar）以及后续增量项（M3/M4）。
5) 以“每个 work item 子条目”为粒度更新计划与提交 commit。
6) 取消日志 `max_entries` 上限（完整时间线可能很长）。
7) 完整时间线需纳入 `GAME_STARTED` 等初始化事件。
8) 日志面板位置调整：日志占用右侧动作面板区域；左侧玩家信息保持可见（ActionPanel 可被覆盖）。
9) “读档后日志高亮/跳转异常”的修复方向：采用方案 A（在事件源头补齐 `command_index`）。
10) 大阶段切分的 step 语义：阶段 step 以“进入该阶段后的状态（含 enter settlement）”为准；日志中 `*_REPORT`（在离开阶段时发射）归属到“离开前阶段”。
11) step seek 的实现方式：只读回放下允许用 step 快照直接覆盖 `game_engine.state`（不要求扩展引擎 `rewind_to_step(...)`）。
12) 复盘（非回放）同样允许用 step 快照直接覆盖 `game_engine.state`；退出复盘/返回最新后恢复实时日志与可操作状态。

## 9. 实施过程记录（发现/问题定位）

### 2026-01-24：event_log_review 复现与阶段切分定位

- 复现存档：`.savings/manual_cases/logs/event_log_review.json`（archive schema_version=3，commands=7，current_index=6）。
- 现象（用户反馈）：点击“玩家1 放置营销”时整回合日志同时高亮，且状态跳到整回合行动之后；可单步后退到正确状态，但日志高亮不同步。
- 根因归类：日志条目缺少稳定的时间线索引（`command_index/step_index`），或 step 事件归属未在 phase 边界处拆分，导致多个阶段/整段 auto-advance 被压到同一个时间线点。
- 额外观察（截图 `demo_image/log_demo.png`）：发薪日/广告/清理等大阶段在日志高亮上被“打包到一个 step”，提示 phase 边界仍存在归属/拆分缺口（需要用该截图持续回归验证）。

### 2026-01-24：StepTimelineBuild 的关键补强点

- `core/engine/game_engine/step_timeline_build.gd`：
  - Working 内“被跳过子阶段”的 `skip_sub_phase` 命令，若不是最后子阶段且上一 step 存在，则合并到上一 step（避免出现“单步推进无变化”的空感）。
  - 引入 `_update_step_snapshot(step, state)`：sub_phase 变化/合并 step 时只更新快照字段（round/phase/sub_phase/state_dict），保留 step 的元信息（kind/from_phase/to_phase/anchor_command_index）。
  - 仍保持约定：`*_REPORT` 归属离开前阶段；phase step 的快照以“进入该阶段后的 state（含 enter settlement）”为准。

### 2026-01-24：回放中“晚餐时间结束弹出面板”的来源（已修复）

- 该面板来自 `DinnerTimeOverlay`（`ui/components/dinner_time/dinner_time_overlay.tscn` / `ui/scenes/game/game_overlay_dinnertime.gd`），其显示条件是 `state.phase == "Dinnertime"`。
- 用户需求：回放/复盘（只读时间线）时不需要该面板，会干扰回放步进与观察。
- 修复：只读时间线激活时由 `GameOverlayController.sync_dinnertime_overlay()` 直接 `hide()`（`ui/scenes/game/game_overlay_controller.gd`）。

### 2026-01-24：重组（Restructuring）阶段“单步推进无效果”的风险点（待补齐验证）

- 用户反馈：重组结构阶段缺少必要日志，导致对应 step 单步推进看起来没有效果。
- 初步判断：可能是“进入/离开 Restructuring”缺少可视化日志事件，或该阶段的关键 state 变化未映射成日志条目；需要在 formatter 与事件发射点两侧核对覆盖面，并补齐最少必要的事件/日志（在保证回放确定性的前提下）。

### 2026-01-24：step 时间线未激活导致“大阶段仍被打包”的触发条件（已修复）

- 复现触发条件（来自截图/行为推断）：当对局已处于历史态（`cursor < head`，ReplayBar 显示“时间线：x / y”），且用户点击/seek 的目标命令索引恰好等于当前 `current_command_index` 时，旧逻辑会直接 `_update_ui()` 并 return，导致不会切换到 step 时间线；于是 Payday/Marketing/Cleanup 等 auto-advance 大阶段仍以“命令粒度”被打包在一个位置。
- 修复：在 `_on_replay_bar_seek_requested()` 中，即使 `target == current_command_index`，只要 `target < head_index` 且尚未激活 step 时间线，也会触发 `_enter_history_step_timeline_for_command(target)` 并切换到 step 视图（`ui/scenes/game/game.gd`）。

### 2026-01-24：过滤器导致 step “看起来无效果”的 UI 根因（已修复）

- 用户反馈：部分 step 单步推进时“看起来没有效果”（尤其是只包含 PHASE 类型日志的阶段切分点）。
- 根因：`GameLogPanel` 的 grouped view 之前完全基于“过滤后的可见 entries”构建；当某个 step 的所有事件都被过滤器隐藏时，StepHeader/PhaseHeader 也会消失，导致该 step 视觉上不存在。
- 修复：grouped view 的结构（PhaseHeader/StepHeader）基于 `_entries_all` 构建，子项（LogItem）再按过滤器决定是否渲染；从而 step 作为“可步进点”始终可见（`ui/components/game_log/game_log_panel.gd`）。
