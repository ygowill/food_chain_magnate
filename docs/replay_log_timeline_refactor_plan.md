# 回放与游戏日志融合（完整时间线）报告与重构开发计划

状态：已实施（M0..M4.3 + M4 可选折叠）；0.1.1/0.1.2/0.1.4/0.1.5/0.1.6 已修复｜最后更新：2026-01-25

## 0. 当前进度（2026-01-25）

已落地（核心体验）：

- 完整时间线（含未来日志）：回放/复盘 seek 仅移动 cursor，高亮/置灰随 cursor 更新
- 大阶段可步进：时间线以 `step_index` 为粒度（phase 切分点可停留），并保留 `anchor_command_index` 追溯来源
- 统一时间线视图：`RoundHeader -> PhaseHeader -> ActionGroupHeader -> EventItem`（缩进展示；不暴露 step/cmd）
- 阶段/回合事件默认隐藏：提供 `显示阶段事件` 开关用于调试/查看
- 去噪/去重：隐藏流程性日志（回合开始/结束等），避免“标题与子项重复同一句动作摘要”
- 事件归属修正（含 Payday->Marketing exit+enter 结算叠加）：`PLAYER_CASH_CHANGED` / `MILESTONE_ACHIEVED` 按触发时刻与结算点归属到正确 `phase_segment`（见 0.1.2）
- 日志面板右侧化：覆盖 ActionPanel，左侧玩家信息保持可见；回放/复盘态默认打开日志
- M4（宏/微折叠）：新增 `折叠细节` 开关（默认关闭），可按动作组展开/收起微事件子项

仍待处理（非阻塞 / 可选）：

- M0.5：方案 B/C 未采用（方案 A 已解决读档历史 `command_index` 丢失问题）
- ReplayBar：倍速/自动播放（未实现）
- 性能优化：step_timeline 增量构建 / 虚拟列表（未实现；目前通过“折叠细节”缓解节点数爆炸）
- Restructuring 阶段更细粒度日志：按需求评估是否需要新增专用事件（当前已用摘要兜底缓解“看起来无效果”）

测试：

- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`

## 0.1 新发现问题（2026-01-25：来自日志面板截图）

下面两类问题会导致“阶段标题与事件顺序/归属看起来不一致”，并且会误导玩家对规则流程的理解。它们属于同一类底层问题：**事件生成顺序不符合语义** + **step_timeline 在跨阶段（且存在结算）时缺少可分割的归因点**。

### 0.1.1 阶段标题与日志顺序不一致（skip / end_turn 与阶段/子阶段事件错序）

现象（截图示例）：

- `Working -> Dinnertime` 出现在 `玩家2结束回合(skip)` 之前；按语义应为：玩家2结束回合 -> 系统推进到晚餐时间。
- 类似错序还包含 Working 内 `SUB_PHASE_CHANGED`（例如 `PlaceRestaurants -> Recruit`）在“玩家结束回合”之前出现，导致用户直觉上认为“系统先推进、玩家才结束”。

已定位根因（确定）：

1) `skip`/`skip_sub_phase` 的事件生成顺序不符合语义：
   - `gameplay/actions/skip_action.gd`：`_generate_specific_events()` 在 phase 变化时先 append `*_REPORT`/`PHASE_CHANGED`（以及可能的 `SUB_PHASE_CHANGED`），最后才 append `PLAYER_TURN_ENDED`/`PLAYER_TURN_STARTED`。
   - `gameplay/actions/skip_sub_phase_action.gd`：同样在 phase 变化时先 append `PHASE_CHANGED`，后 append `PLAYER_TURN_ENDED/STARTED`（仅最后子阶段场景）。
2) `step_timeline` 对“命令内跨阶段”的归属规则依赖 `PHASE_CHANGED` 的顺序：
   - `core/engine/game_engine/step_timeline_build.gd` 在 `phase_changed_in_command` 分支会按 `PHASE_CHANGED` 将事件切分为 before/after，并把 after 归属到新阶段 `phase_segment`。
   - 因为 `PLAYER_TURN_ENDED` 被放在 `PHASE_CHANGED` 之后，它会被归到新阶段，并出现在新阶段标题之后。

整改方向（建议优先修复源头）：

- 调整 `skip`/`skip_sub_phase` 的事件生成顺序，使其符合语义：
  - `PLAYER_TURN_ENDED` 必须发生在任何 `PHASE_CHANGED`/`SUB_PHASE_CHANGED` 之前（表示“玩家先结束/确认结束”）。
  - `PLAYER_TURN_STARTED` 应发生在阶段/子阶段确定之后（通常在 `SUB_PHASE_CHANGED` 之后；若阶段切换到非玩家交互阶段，则应避免产生误导性 turn_started）。
- 修复后应能自然消除大量“阶段标题与子项错位/错序”的问题（因为 step_timeline 的切分假设重新成立）。

### 0.1.2 里程碑显示时间点/阶段归属错误（first_burger_marketed 显示在 Payday）

现象（截图示例）：

- `first_burger_marketed`（首个营销汉堡）应在“广告行动（Marketing）阶段”内、在“生成需求（DEMAND_GENERATED）”之后出现；但当前显示在“发薪日（Payday）阶段”内。

已定位根因（确定 + 高概率）：

1) 结算触发点叠加导致 “exit+enter” 在一次相位推进中同时发生：
   - 默认结算触发：`Payday` 在 `EXIT` 结算、`Marketing` 在 `ENTER` 结算（见 `core/engine/phase_manager/settlement_triggers.gd`）。
   - 相位推进流程：`advance_phase` 先跑旧阶段 exit settlements，再切到新阶段，再跑新阶段 enter settlements（见 `core/engine/phase_manager/advance_phase.gd`）。
   - `first_burger_marketed` 的触发点来自 `MarketingSettlement` 的 `DemandMarked`（见 `core/rules/phase/marketing_settlement.gd`），本质是 **Marketing:enter 结算效果**。
2) `step_timeline_build` 目前用“单布尔”规则归因现金/里程碑：
   - `core/engine/game_engine/step_timeline_build.gd` 的 `_should_attribute_settlement_effects_to_old_phase()` 一旦检测到旧阶段存在 `EXIT` settlement，就把**全部** cash/milestone 归属到旧阶段。
   - 在 `Payday -> Marketing` 这种 exit+enter 叠加场景下，会把 Marketing:enter 的里程碑/现金变化误归到 Payday。
3) 里程碑排序可能仍不符合“生成需求后获得”的直觉：
   - `step_timeline_build` 当前在“命令本体”阶段就追加 `milestone_events_cmd`，而 `DEMAND_GENERATED` 事件通常在后续 auto-advance（Marketing->Cleanup）阶段才被追加。
   - 即使把里程碑归属到 Marketing 段落，依旧可能出现“里程碑早于生成需求摘要”的展示顺序。

整改方向（需要一次针对性的时间线归因增强）：

- 目标：在 `Payday -> Marketing` 这种“exit+enter 结算叠加”的推进中，把结算效果拆分归因：
  - `Payday:exit` 产生的薪资支付/现金变化仍归属 Payday。
  - `Marketing:enter` 产生的需求/里程碑/现金效果归属 Marketing，并且展示顺序应落在“生成需求（DEMAND_GENERATED）”之后。

推荐技术方案（A，正确性优先）：

1) 引入“相位推进 trace”（仅用于时间线构建/调试，不影响存档）：
   - 在 `PhaseManager.advance_phase/advance_sub_phase` 内部记录关键快照（至少：exit settlements 前/后、enter settlements 前/后；必要时包含 hooks 前后）。
   - trace 缓存在 `PhaseManager` 实例的临时字段中（例如 `_timeline_last_advance_trace`），由 `StepTimelineBuild` 在构建期间读取并消费。
2) `StepTimelineBuild` 在检测到旧阶段 `EXIT` + 新阶段 `ENTER` 同时存在时：
   - 使用 trace 的快照差异分别构建 `PLAYER_CASH_CHANGED` 与 `MILESTONE_ACHIEVED`，并分别归属到 old/new `phase_segment`。
   - 对于 auto-skip 的结算阶段（Marketing/Dinnertime/Cleanup），将 “enter settlement 的 cash/milestone” 延后到该阶段的汇总事件（如 `DEMAND_GENERATED`/`MARKETING_EXPIRED`）之后再输出，保证视觉顺序符合“先看到结算结果，再看到里程碑/现金奖励”。

备选方案（B，改动更小但风险更高）：

- 针对 `Payday -> Marketing` 特判：从 `PAYDAY_REPORT` 推导“薪资导致的现金变化”，剩余现金变化视为 Marketing:enter；里程碑按 milestone_id 白名单归属到 Marketing（`*_marketed`/`*_demand_*` 等）。
- 风险：模块/规则变化后容易失效；现金变化可能无法完全解释（例如同时存在其他奖励/惩罚）。

### 0.1.3 实施结果与回归（已完成）

确认结果（来自截图问题澄清）：

1) “无玩家操作阶段”需要抑制 `PLAYER_TURN_STARTED`（避免误导）。
2) Marketing 相关里程碑必须归属 Marketing 段内，且需出现在对应 `DEMAND_GENERATED` 之后（明确因果关系）。

已实施（核心改动）：

1) 修复 `skip`/`skip_sub_phase` 的事件顺序与“无玩家阶段抑制 turn_started”（见 0.1.1）：
   - `gameplay/actions/skip_action.gd`：先发射 `PLAYER_TURN_ENDED`，再发射 `SUB_PHASE_CHANGED/PHASE_CHANGED`；并在 `Dinnertime/Marketing/Cleanup/GameOver` 抑制 `PLAYER_TURN_STARTED`。
   - `gameplay/actions/skip_sub_phase_action.gd`：当从 Working 最后子阶段跳过时，同样保证 `PLAYER_TURN_ENDED` 先于 `SUB_PHASE_CHANGED/PHASE_CHANGED`；并抑制非玩家阶段 `PLAYER_TURN_STARTED`。
2) 修复 `Payday -> Marketing` 的 exit+enter 叠加归因 + Marketing 内里程碑顺序（见 0.1.2）：
   - `core/engine/phase_manager.gd`：增加 timeline trace 开关与快照存储（仅供时间线构建使用，默认关闭）。
   - `core/engine/phase_manager/advance_phase.gd`：在 trace 打开时记录 `after_exit_settlements` 快照，用于拆分 exit/enter 结算影响。
   - `core/engine/game_engine/step_timeline_build.gd`：当检测到旧阶段 `EXIT` + 新阶段 `ENTER` 同时存在时，基于快照差异分别生成 old/new 的 cash/milestone；并将 Marketing:enter 的 cash/milestone 延后到离开 Marketing 时、在 `DEMAND_GENERATED` 之后输出。

测试覆盖（已新增/扩展）：

- core：扩展 `core/tests/step_timeline_build_test.gd`（覆盖 skip 跨阶段/子阶段的顺序与归属）
- core：新增 `core/tests/step_timeline_marketing_milestone_order_test.gd`（断言 `first_burger_marketed` 归属 Marketing 且出现在对应 `DEMAND_GENERATED` 之后）
- ui：`ui/scenes/tests/all_tests.gd` 已接入上述测试

### 0.1.4 UI 展示回归（回合标题/重组阶段顺序）

来自日志面板截图的展示问题（已修复）：

1) 回合切换标题应显示具体回合号（例如“回合 2”），并且第 1 回合开头也应显示一次。
2) Restructuring 阶段日志顺序：应在玩家1/玩家2都“确认重组”之后，才进入 OrderOfBusiness（避免“阶段标题先跳转、确认日志后出现”的错序观感）。

实施要点：

- `ui/components/game_log/game_log_panel.gd`：RoundHeader 显示为“回合 N”，并在第一个可见回合（round>=1）的开头插入一次 RoundHeader。
- `gameplay/actions/submit_restructuring_action.gd` / `gameplay/actions/choose_turn_order_action.gd`：移除动作内的 `advance_phase()`，避免动作组被归到新阶段段落。
- `core/engine/game_engine/auto_advance.gd`：在 Restructuring finalized / OrderOfBusiness finalized 后自动推进到下一阶段，形成独立 phase step，保证日志顺序为“玩家动作 -> 阶段切换”。
- core：新增 `core/tests/step_timeline_phase_boundary_order_test.gd` 回归覆盖，并接入 `ui/scenes/tests/all_tests.gd`。

### 0.1.5 Cleanup 丢弃日志与里程碑顺序（first_throw_away / FOOD_DISCARDED）

来自日志面板截图的展示问题（已修复）：

1) Cleanup 阶段首个丢弃里程碑 `first_throw_away` 显示在“清理库存: 丢弃...”之前，且可能脱离动作组。
2) `choose_fridge_keep` 每次应输出一条 `FOOD_DISCARDED`（“清理库存: 丢弃...”）；但此前只在离开 Cleanup 时汇总输出，导致错序与重复。

根因（确定）：

- `FOOD_DISCARDED` 之前由 `CommandRunner._build_phase_change_events()` / `AdvancePhaseAction._generate_specific_events()` 在离开 Cleanup 时从 `round_state.cleanup.inventory_discarded` 汇总生成；而 `first_throw_away` 在 Cleanup:enter 或 `choose_fridge_keep` 时即时领取。
- 因为事件生成时刻不同，step_timeline 中会出现“里程碑先出现、丢弃日志后出现”的错序；并且离开 Cleanup 的汇总可能造成重复输出。

实施要点：

- `gameplay/actions/choose_fridge_keep_action.gd`：在 `_generate_specific_events()` 中对当前玩家输出 `FOOD_DISCARDED`（按丢弃发生时刻），保证每次 `choose_fridge_keep` 都有“清理库存: 丢弃...”。
- `core/engine/game_engine/command_runner.gd` + `gameplay/actions/advance_phase_action.gd`：把 `FOOD_DISCARDED` 的汇总输出点从“离开 Cleanup”改为“进入 Cleanup”（对应 Cleanup:enter 结算产生的自动丢弃），避免离开 Cleanup 时重复。
- `core/engine/game_engine/step_timeline_build.gd`：对 `first_throw_away` 延后输出：
  - 若进入 Cleanup 时无 pending（无 `choose_fridge_keep`），则在该 Cleanup phase step 末尾输出（确保在所有 `FOOD_DISCARDED` 之后）。
  - 若存在 pending（有 `choose_fridge_keep`），则延后到最后一次 `choose_fridge_keep` 命令 step 输出（确保在所有“清理库存”之后）。
- core：新增 `core/tests/step_timeline_cleanup_discard_order_test.gd` 回归覆盖，并接入 `ui/scenes/tests/all_tests.gd`。

### 0.1.6 玩家行动日志缺少关键细节（营销/餐厅/售出等）

现象（来自日志面板截图与复核）：

- 玩家放置营销时，仅显示员工与点位，缺少营销类型/品类/持续时间等关键信息。
- `DEMAND_GENERATED` 显示缺少影响房屋/品类/新增数量（字段读取不一致导致）。
- `RESTAURANT_PLACED/RESTAURANT_MOVED` 未显示餐厅编号（多餐厅时会产生歧义）。
- `FOOD_SOLD` 事件未格式化，导致面板出现 debug 噪音行。

根因（确定）：

- `GameEventLogFormatter` 与事件数据字段不一致：
  - `MARKETING_PLACED` 事件不包含 `marketing_type/remaining_duration`，formatter 也在读取不存在的字段（如 `range/houses`）。
  - `DEMAND_GENERATED` 实际字段为 `affected_house_numbers/product/demands_added/...`，但 formatter 读取 `houses/required`。
- 少数事件缺少专用格式化分支（如 `FOOD_SOLD`），回退到 debug 输出。

已实施（覆盖全部已发射的事件类型）：

- `gameplay/actions/initiate_marketing_action.gd`：为 `MARKETING_PLACED` 补齐 `marketing_type` 与 `remaining_duration`（里程碑导致的永久营销可正确显示为“永久”）。
- `ui/scenes/game/game_event_log_formatter.gd`：
  - `MARKETING_PLACED`：显示营销类型 + 品类（product）+ 持续时间（含永久）+ 点位（含飞机轴向）。
  - `DEMAND_GENERATED`：显示营销类型 + 品类 + 新增需求数量 + 影响房屋号（兼容旧字段）。
  - `MARKETING_EXPIRED`：补齐品类与剩余持续时间变化。
  - `RESTAURANT_PLACED/RESTAURANT_MOVED`：显示餐厅编号（`餐厅#n`）。
  - `FOOD_SOLD`：增加格式化输出，避免 debug 噪音。

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

当前主路径（M4.3）：

- `ui/scenes/game/game_event_log_formatter.gd`
  - 将 step_timeline 的 `events[]` 格式化为 UI entries（message/details/type）。
- `ui/components/game_log/game_log_panel.gd`
  - 持有 `{steps[], events[]}` + formatter entries，并渲染统一时间线视图：
    - `RoundHeader -> PhaseHeader -> ActionGroupHeader -> EventItem`
  - 支持 future 置灰 / cursor 高亮（以 `step_index` 为主索引）。
  - 支持 `显示阶段事件` 与 `折叠细节`（默认关闭折叠，符合 M4.3）。

保留的兜底/测试路径：

- `ui/scenes/game/game_event_log_controller.gd`
  - 仍支持从 `EventBus.history` 恢复日志（用于兜底与 `log_restore_after_load_test` 覆盖）。

### 2.3 回放控件（ReplayBar）与旧 ReplayPlayer

- `ui/components/game_log/replay_bar.*`：嵌入日志面板顶部的回放条（加载/步进/滑条/返回最新/退出）。
- `ui/components/replay_player/replay_player.gd`：保留为开发工具/临时入口（不再作为主用户路径，避免覆盖式体验割裂）。

### 2.4 “回放时日志不跟着变”的根因（旧 ReplayPlayer 路径）

当 `ReplayPlayer.seek_to()` 触发 `GameEngine.rewind_to_command()` 时：

- 引擎会重建 `EventBus.history`（仅 record，不触发订阅者）。
- 若 UI 不主动调用 `GameEventLogController.rebuild_from_history()`，日志面板不会从新的 `EventBus.history` 重建显示。

现状更新：

- 旧路径已补齐 `rebuild_from_history()`，可解决“seek 后日志不变”的短期问题。
- 当前主路径（ReplayBar + step_timeline）不再依赖 `EventBus.history` 作为日志数据源：加载时一次性构建完整时间线，seek 仅移动 cursor 并应用 step 快照，因此该问题在主路径下不再出现。

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

修复方向（已实施：方案 A；备选：方案 B/C）：

1) 在事件产生源头补齐（已实施）：`CommandRunner.execute_command()` 在发射每条事件前把 `command_index` 写入 event `data`（additive 字段）。
   - 优点：`EventBus.history` 天然可用于恢复日志与时间线；读档/运行时一致；不会引入二次回放成本。
   - 风险：会改变事件 payload（增加字段）；若有测试/逻辑对 event data 做严格相等断言，需要同步调整。
2) 备选（未采用）：在读档后重建 EventBus.history：`Loader.load_from_archive()` 结束时用 `EventHistoryRebuild.build(engine, engine.current_command_index)` 重新生成事件并用 `EventBus.record_event()` 回填（替换掉 load 时 emit 产生的 history）。
   - 优点：改动集中在读档路径；不改运行时事件 payload。
   - 风险：读档成本增加（再跑一遍事件构建）；若未来支持“游戏内读档”且当时已有订阅者，需要确保不会触发重复副作用（应使用 record + clear）。
3) 备选（未采用）：UI 恢复时推导：`GameEventLogController` 在 restore_history 时以 `COMMAND_EXECUTED` 为边界进行两段式映射（缓存直到遇到该命令的 `COMMAND_EXECUTED` 再回填 `command_index`）。
   - 优点：不改引擎/事件 payload。
   - 风险：实现复杂且依赖事件顺序假设；当 `COMMAND_EXECUTED` 被过滤或未来有“跨命令事件”时容易出错。

## 3. 目标体验规格（在本项目中的落地定义）

### 3.1 时间线的两个指针

引入两个概念（UI 层）：

- `head_index`：该时间线已知的“最新时间线索引”（M4.2 后为 `step_index`；-1 表示初始状态）。
- `cursor_index`：当前正在查看/回放的时间线索引（同为 `step_index`）。

补充约定：

- 每条日志 entry 同时保留 `step_index`（用于 seek/highlight）与 `command_index`（用于详情追溯/兼容旧逻辑）。

渲染规则：

- `step_index <= cursor_index`：正常亮度（已发生，相对 cursor）。
- `step_index > cursor_index`：未来日志置灰。
- `step_index == cursor_index`：高亮“当前指针”对应的动作组（并可滚动定位）。

模式规则：

- `cursor_index == head_index`：非回放态（若是对局引擎则允许操作；若是存档回放引擎则仍应提示“回放只读”，但可弱化提示）。
- `cursor_index < head_index`：回放态（禁用 ActionPanel，提供“步进/回退/返回最新”）。

### 3.2 宏/微层级（适配“自动连锁步骤很多”）

推荐的展示层级：

- 宏：动作组（step）。通常一条玩家命令对应一个 command step；auto-advance 的大阶段切分点对应 phase step（在 UI 中由 PhaseHeader 承担锚点）。
- 微：该 step 归属的事件序列（EventBus 事件、结算摘要事件等）。

注意：本实现不追求“事件级中间态”。点击微步骤会跳转到其所属 step 的快照状态，并在日志中定位/高亮（不尝试显示事件执行过程中的中间状态）。

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
2. 构建 “step 时间线”（一次性）：`StepTimelineBuild.build_full(engine)` 输出 `{initial_state_dict, steps[], events[]}`。
   - `steps[]` 提供 `step_index` 级别的阶段切分点与状态快照（用于 seek 与 UI 高亮）。
   - `events[]` 提供每条事件的 `step_index/phase_segment/command_index` 等归属信息（用于渲染内容）。
3. 用统一 formatter 把 `events[]` 转为日志 entries：
   - 当前实现：`ui/scenes/game/game_event_log_formatter.gd` + `ui/scenes/game/game.gd:_build_log_entries_from_timeline_events()`。
4. `GameLogPanel.load_step_timeline(timeline, entries)` 写入完整日志（包含未来）。
5. seek 时：
   - 只更新 cursor（`GameLogPanel.set_timeline_cursor`），并用对应 step 的 `state_dict` 快照覆盖 UI 所需状态（只读回放/复盘允许直接覆盖 `game_engine.state`）。
   - 不清空、不重建完整日志（除非 head/cursor 被改写，例如执行新命令导致未来被截断）。

对局内（非存档回放）推荐流程：

- 当前实现（M4.3）：实时对局也统一用 `StepTimelineBuild.build_full(engine)` 全量重建时间线视图（在日志面板可见/打开时触发），确保与回放/复盘保持同一套结构与归属规则。
- `GameEventLogController` 仍保留为“从 EventBus.history 恢复日志”的兜底机制与测试覆盖（例如读档进入 GameScene 前的历史恢复）。

### 4.3 UI 结构建议（不再弹出覆盖式 ReplayPlayer）

把回放控件做成日志面板顶部的“ReplayBar”：

- 文件：加载（可复用现有 SaveLoadDialog 或 ReplayPlayer 的文件枚举逻辑）。
- 控件：`<< < > >>`、滑条、`返回最新`、`退出`（可选：倍速/自动播放）。
- 状态提示：`只读回放：cursor / head` 或 `时间线：cursor / head`，extra 仅显示“阶段：xxx”（不展示 step/cmd）。

回放条在 `cursor_index < head_index` 或处于回放态时自动显现。

日志面板位置（布局调整建议）：

- 将 `GameLogPanel` 从“左侧信息区的二选一视图”调整为“右侧动作面板区域的可切换视图”（可覆盖 ActionPanel）。
- 目的：玩家信息（左侧）与日志（右侧）可同时查看；查看日志时通常不需要执行动作，因此覆盖 ActionPanel 的影响较小。

ActionPanel 禁用策略：

- 进入回放态时，ActionPanel 所有按钮 disabled，并显示固定提示（例如“回放中不可操作”）。
- 保留“退出回放/返回最新”的入口在 ReplayBar。

## 5. 增量重构开发计划（里程碑进度）

说明：

- 本节按“里程碑”汇总当前仓库已落地内容，并标注仍保留的可选项/备选方案。
- 从 M4.2 起，时间线主索引为 `step_index`；UI 仍保留 `command_index` 作为追溯字段。

### M0：最小可用（已完成）

目标：

- seek 后日志/高亮能同步更新（先止血）。

已实施：

- [x] seek 时补齐 `rebuild_from_history()`（旧 ReplayPlayer 路径止血）
- [x] `GameLogPanel.set_timeline_head/set_timeline_cursor`
- [x] `GameLogPanel.set_entry_command_index`

### M0.5：读档后 `command_index` 丢失导致跳转/高亮异常（已完成：方案 A）

已实施（方案 A）：

- [x] 在事件发射源头补齐 `event.data.command_index`（运行/回放/读档一致）
- [x] 自动化覆盖：`core/tests/manual_log_save_test.gd`

备选方案（未采用；保留文档记录）：

- 方案 B：读档结束后用 `EventHistoryRebuild.build()` 重建带 `command_index` 的事件，再 `EventBus.record_event()` 覆盖 history
- 方案 C：UI 恢复时以 `COMMAND_EXECUTED` 为边界做两段式推导回填

### M1：完整日志数据源（已完成）

已实施：

- [x] `core/engine/game_engine/event_timeline_build.gd`（用于逻辑/测试：构建完整事件流并补齐 `command_index`）
- [x] `ui/scenes/game/game_event_log_formatter.gd`（统一 event -> entries）
- [x] `GameLogPanel` 取消 `max_entries` 上限，并支持 future 置灰/当前高亮

备注：

- UI 主路径目前以 `StepTimelineBuild.build_full()` 为数据源（结构与归属更完整）；`EventTimelineBuild` 主要用于测试与独立校验。

### M2：替换覆盖式 ReplayPlayer 为嵌入式 ReplayBar（已完成）

已实施：

- [x] 新增 `ui/components/game_log/replay_bar.*`
- [x] `GameScene` 接线：加载存档 -> 进入回放引擎 -> 构建时间线 -> 展示 ReplayBar
- [x] `ReplayPlayer` 保留为开发工具/临时入口（避免一次性删除导致测试/工作流中断）

### M2.5：日志面板右侧化（与玩家信息同屏）（已完成）

已实施：

- [x] `dock_popup_into_right_panel()` 将 `GameLogPanel` 覆盖到 RightPanel（ActionPanel 区域）
- [x] 回放/复盘态默认打开日志；关闭日志可恢复默认动作区

### M3：回放态 UI 约束完善（已完成）

已实施：

- [x] 回放/查看历史态禁用 ActionPanel（并给出原因文案）
- [x] 顶部提示条明确 “回放/复盘”
- [x] 回放/复盘态屏蔽强制弹窗/强提示面板，避免阻塞步进

### M4.1：Phase 视觉切分 + Working 打包展示（里程碑已演化 / 被 M4.3 取代）

说明：

- 原里程碑曾尝试用 `StepHeaderItem` 做 Working 段折叠，但在 M4.3 “统一时间线视图（默认全展开）” 约束下，该实现已被移除/替代。
- 当前 phase 分段由 `PhaseHeaderItem` 承担；“折叠细节/宏微可读性”由 M4 提供可选开关实现。

### M4.2：大阶段可步进（step_index + 阶段边界快照）（已完成）

已实施：

- [x] `core/engine/game_engine/step_timeline_build.gd` 构建 `step_index` 时间线（phase step + command step）与 `state_dict` 快照
- [x] 回放/复盘 seek 使用 step 快照覆盖 `game_engine.state`（只读允许），并同步日志高亮/置灰
- [x] `*_REPORT` 等离开阶段事件归属到离开前阶段（避免显示到新阶段段落）
- [x] ReplayBar 滑条范围：`[-1, head_step]`；状态 extra 仅显示“阶段：xxx”（不展示 step/cmd）

### M4.3：统一时间线视图（已完成；默认不折叠）

核心约束（用户确认；已落地）：

- 统一展示：日志面板即时间线视图；ReplayBar 仅负责导航
- 统一适用范围：回放/复盘/实时对局共用同一结构
- 阶段可见 + 回合分隔：RoundHeader + PhaseHeader
- 默认不展示阶段/回合事件子项：提供 `显示阶段事件` 开关
- 去噪/去重：隐藏流程性日志；避免标题与子项重复同一句动作摘要
- 事件归属正确：里程碑/现金变化等归属到实际触发阶段段落

#### M4.3.1 视图结构（落地实现）

- `RoundHeaderItem`：回合分隔（点击跳转到该回合的第一条 ActionGroup）
- `PhaseHeaderItem`：阶段标题（点击跳转到该阶段 start_step；cursor 落在范围内高亮）
- `ActionGroupHeaderItem`：动作组标题（command step；点击 seek；双击打开 primary 详情）
- `EventItem`：动作组子项（缩进；点击 seek 到所属 step；双击看详情）

#### M4.3.2 数据映射规则（落地实现）

- 结构来自 `steps[]`（phase/round 变化也必须可见、可点）
- 内容来自 `events[]` 经 formatter 生成 entries，并按 `step_index` 归属到动作组
- phase step 不再渲染 “进入X” ActionGroup（PhaseHeader 已承担锚点）

#### M4.3.3 实时对局统一（已落地）

- 日志面板打开/可见时，全量 `StepTimelineBuild.build_full(engine)` 重建时间线视图（避免后台无意义重建）
- undo/redo/restore/load 等会改写时间线的操作，触发刷新

#### M4.3.4 验收要点（对用户可见）

- 载入 `res://.savings/manual_cases/logs/event_log_review.json`：
  - 可见 round/phase 分隔；阶段标题点击跳转正确；日志高亮与状态一致
  - 默认不出现“确认结束/开始回合/结束回合”等流程性噪声
  - 同一条玩家动作摘要不重复出现
  - 里程碑/现金变化出现在正确阶段段落

#### M4.3.5 关键代码位置

- `ui/components/game_log/game_log_panel.gd`
- `ui/components/game_log/game_log_panel.tscn`
- `ui/scenes/game/game.gd`（回放/复盘/实时刷新与 seek 接线）
- `core/engine/game_engine/step_timeline_build.gd`

### M4：宏/微分组与折叠（已完成；默认关闭）

目标：

- 在大量微事件（结算链路较长）时提高可读性，并缓解节点数爆炸风险。

已实施（路径 2：扁平列表折叠）：

- [x] `GameLogPanel` 新增 `折叠细节` 开关（默认关闭；开启后可按动作组展开/收起微事件子项）
- [x] ActionGroupHeader 左侧 `>`/`v` 折叠按钮；折叠时以 `(+N)` 提示隐藏条目数

验收：

- 大量事件回合时仍可扫读，且不影响 seek/highlight 语义。

## 6. 测试与验收计划（建议新增/调整）

现有相关测试：

- `ui/scenes/tests/log_restore_after_load_test.gd`：验证从 `EventBus.history` 恢复日志（仍应保留，作为“订阅缺失时的兜底机制”）。
- `ui/scenes/tests/replay_player_smoke_test.gd`：验证 ReplayPlayer 能加载并 seek（若 M2 后 ReplayPlayer 降级为工具，可调整测试目标或新增 ReplayBar 测试）。

已新增（覆盖关键能力）：

- [x] `core/tests/event_timeline_build_test.gd`：
  - 构造 20+ 命令的确定性用例，build_full() 返回 events 不为空且每条含 `command_index`（单调不减），并与命令数量一致性可验。
- [x] `core/tests/step_timeline_build_test.gd`：
  - 载入 `res://.savings/manual_cases/logs/event_log_review.json`，build_full() 返回 steps/events 且 events.step_index 单调不减，并包含至少一个 `phase` step（验证阶段切分）。
- [x] `ui/scenes/tests/replay_log_future_visibility_test.gd`（无需渲染）：
  - 加载回放并构建完整日志后，seek 到较早 cursor：
    - `GameLogPanel.get_entries()` 数量不变（仍包含未来）。
    - `GameLogPanel` 的内部（或暴露测试 API）能区分 future/past（例如 `get_future_entry_count(cursor)`）。

## 7. 风险与注意事项

- 性能：当前 `GameLogPanel` 用 `VBoxContainer + 大量节点`，完整时间线可能很长；已通过 `折叠细节` 开关缓解，但长期仍需考虑虚拟列表/增量构建。
- 确定性/排序：UI 展示时间不要依赖系统时间；当前统一视图以 `event_seq` 作为稳定序号（UI-only 日志仍可能使用系统时间）。
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

### 2026-01-24：重组（Restructuring）阶段“单步推进无效果”的风险点（已缓解；按需补强）

- 用户反馈：重组结构阶段缺少必要日志，导致对应 step 单步推进看起来没有效果。
- 缓解现状：已通过“无可见事件 step 的动作摘要兜底”（显示 `玩家X: {action_display_name}`）降低“看起来没发生任何事”的空感。
- 后续按需补强：若仍需要更细粒度的重组日志（例如员工移动/槽位调整细节），再考虑在对应 action 发射专用事件并由 formatter 映射成 EventItem 子项。

### 2026-01-24：step 时间线未激活导致“大阶段仍被打包”的触发条件（已修复）

- 复现触发条件（来自截图/行为推断）：当对局已处于历史态（`cursor < head`，ReplayBar 显示“时间线：x / y”），且用户点击/seek 的目标命令索引恰好等于当前 `current_command_index` 时，旧逻辑会直接 `_update_ui()` 并 return，导致不会切换到 step 时间线；于是 Payday/Marketing/Cleanup 等 auto-advance 大阶段仍以“命令粒度”被打包在一个位置。
- 修复：在 `_on_replay_bar_seek_requested()` 中，即使 `target == current_command_index`，只要 `target < head_index` 且尚未激活 step 时间线，也会触发 `_enter_history_step_timeline_for_command(target)` 并切换到 step 视图（`ui/scenes/game/game.gd`）。

### 2026-01-24：过滤器导致 step “看起来无效果”的 UI 根因（已修复）

- 用户反馈：部分 step 单步推进时“看起来没有效果”（尤其是只包含 PHASE 类型日志的阶段切分点）。
- 根因：`GameLogPanel` 的 grouped view 之前完全基于“过滤后的可见 entries”构建；当某个 step 的所有事件都被过滤器隐藏时，StepHeader/PhaseHeader 也会消失，导致该 step 视觉上不存在。
- 修复：grouped view 的结构（PhaseHeader/StepHeader）基于 `_entries_all` 构建，子项（LogItem）再按过滤器决定是否渲染；从而 step 作为“可步进点”始终可见（`ui/components/game_log/game_log_panel.gd`）。

### 2026-01-24：开始实施 M4.3（统一时间线视图骨架：去过滤/加阶段事件开关/缩进层级）

- UI（`ui/components/game_log/game_log_panel.tscn`）：
  - 移除 PlayerFilter / 搜索框 / 类型过滤按钮。
  - 新增 `显示阶段事件` 开关（默认关闭），用于控制是否展示 `PHASE_CHANGED/ROUND_*/*_REPORT` 等阶段/回合事件子项。
- GameLogPanel（`ui/components/game_log/game_log_panel.gd`）：
  - 新增 `load_step_timeline(timeline, entries)`：由 step_timeline（结构）+ formatter entries（内容）驱动渲染。
  - 新增统一层级渲染：`RoundHeaderItem -> PhaseHeaderItem -> ActionGroupHeaderItem -> EventItem`（缩进展示，不做折叠/展开；UI 不显示 step/cmd 内部索引）。
  - 阶段名使用本地化映射（Working/Setup/... -> 中文）。
  - “阶段事件子项”默认隐藏（开关打开后显示），结构仍然始终基于 steps 构建，避免“某步只有阶段事件导致看起来无效果”。
  - UI-only 日志（例如动作失败提示）在 step_timeline 模式下会自动挂到当前 cursor step（避免丢失/无法定位）。
- GameScene（`ui/scenes/game/game.gd`）：
  - 回放/复盘（step_timeline）日志加载路径切换为 `GameLogPanel.load_step_timeline(...)`。
  - `_build_log_entries_from_timeline_events` 补充 `event_type`/`is_stage_event` 字段，供 M4.3 的“阶段事件开关”判断使用。
  - ReplayBar 的状态 extra 调整为仅显示“阶段：xxx”（不再展示 step/cmd/kind）。
- 备注：正常对局实时模式的“每次命令后重建 step_timeline 并刷新日志视图”已在 2026-01-25 接入（见下条记录）。

### 2026-01-24：M4.3 实施中遇到的 GDScript 编译约束（已修复，SmokeTest 通过）

- 现象：headless 运行 `ui/scenes/tests/game_smoke_test.tscn` 时报 `Parse error`，导致 `GameLogPanel` 全局类无法加载，`game.gd` 也连带无法解析。
- 根因 1：`ui/components/game_log/game_log_panel.gd` 的 `PhaseHeaderItem` 里因缩进错误把 `func _update_text()` 写成了嵌套函数（编译直接失败）。
- 根因 2：Godot 4.5 的“Warning treated as error”模式下，`var x := dict.get(...)` 这种从 Variant 推导类型的写法会触发编译错误；需要改为 `var x = ...` 或显式类型注解。
- 修复：
  - 修正 `PhaseHeaderItem._update_text()` 的缩进层级，确保不是嵌套函数。
  - 将 `:=` 推导写法改为普通赋值（避免 Variant 推导警告）。
  - ReplayBar extra 文案已按 M4.3 收敛为“阶段：xxx”（不再暴露 step/cmd）。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` 通过。

### 2026-01-25：M4.3 接入“实时对局” step_timeline 日志刷新（SmokeTest 通过）

- 目标对齐：按 M4.3.4 让“正常对局实时日志”也使用同一套 Round/Phase/Action/Event 结构（不再依赖 EventBus 订阅追加日志）。
- 实现：在 `ui/scenes/game/game.gd` 增加 `_apply_live_log_timeline_from_engine()`，用 `StepTimelineBuild.build_full(game_engine)` 全量重建 step_timeline，并 `GameLogPanel.load_step_timeline(...)` 刷新列表。
- 触发时机（尽量减少开销）：
  - 打开日志面板时强制刷新（保证首次打开可见完整结构）。
  - 命令执行成功后，仅在日志面板可见时刷新（避免后台每步全量回放）。
  - undo/redo/restore/load、回退到阶段开始成功后刷新（时间线被改写时必须同步）。
- cursor 定位策略：以 `current_command_index` 对应的 `anchor_command_index` 的“最后一个 step”作为稳定落点；在最新时 cursor=head_step。
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` 通过。

### 2026-01-25：补强“无可见事件 step”的动作摘要（缓解重组阶段看起来无效果）

- 现象回顾：用户反馈重组（Restructuring）阶段缺少必要日志，导致某些 step 单步推进时列表中几乎没有可见信息，观感像“没发生任何事”。
- 策略选择（保守）：不强行在 core 侧新增事件类型，而是在 step_timeline 的 step 快照里补齐最少的“命令元信息”，用于 UI 摘要兜底展示。
- 实现：
  - `core/engine/game_engine/step_timeline_build.gd`：对 `kind=="command"` 的 step 写入 `action_id/actor/action_display_name`。
  - `ui/components/game_log/game_log_panel.gd`：当一个 step 没有任何可见事件子项时，`ActionGroupHeaderItem` 的摘要从 step 元信息兜底为 `玩家X: {action_display_name}`，避免回退到“系统推进”。
- 备注：若后续仍需要更细粒度的重组日志（例如“移动了哪个员工/调整到哪个槽位”），再考虑在对应 action 的 `_generate_specific_events()` 增加专用事件并由 formatter 映射成子项。

### 2026-01-25：实现 M4 “宏/微折叠”（可选开关；默认保持 M4.3 全展开）

- 背景：完整时间线在结算链路较长时会产生大量 EventItem，影响扫读与性能（节点数爆炸风险）。
- 实现（路径 2：扁平列表折叠）：
  - `GameLogPanel` 顶部新增 `折叠细节` 开关；默认关闭（符合 M4.3 的“不折叠/默认全展开”约束）。
  - 开启后：ActionGroup 默认仅显示标题行，微事件子项可按动作组逐个展开/收起（标题行左侧 `>` / `v`）。
  - 折叠状态仅影响渲染，不改变时间线 seek/highlight 语义与事件归属规则。
- 代码位置：
  - `ui/components/game_log/game_log_panel.tscn`
  - `ui/components/game_log/game_log_panel.gd`
- 验证：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` 通过。

### 2026-01-25：event_log_review 日志手验（log_screenshot1/2）发现的问题与根因（已整改）

复现材料：

- 存档：`res://.savings/manual_cases/logs/event_log_review.json`
- 截图：`demo_image/log_screenshot1.png`、`demo_image/log_screenshot2.png`

用户反馈问题（概括）：

- 不需要展示“玩家确认结束 / 玩家开始回合 / 玩家结束回合”等流程性日志。
- 多条“玩家动作”在列表中出现两次（例如“玩家1：采购饮料”“玩家1：放置营销”“玩家1：清理库存”）。
- 部分事件出现的阶段顺序不正确：
  - Working 结束应在所有玩家结束后才进入 Dinnertime，但日志显示为“玩家1结束 -> 进入晚餐 -> 玩家2才结束”（顺序不合理）。
  - 里程碑获得出现在 Restructuring，但语义上应在更早阶段触发（Payday/Cleanup/Marketing 等）。
- 阶段已有标题，因此“进入发薪日/进入重组结构/进入广告行动”等“进入X”类行不需要展示。

根因定位（当前实现的结构性原因）：

1) 重复动作的根因：统一视图中 `ActionGroupHeaderItem` 的摘要直接复用该 step 的第一条玩家日志（formatted message），但该条日志同时又作为 `EventItem` 子项渲染一次，导致“同一句话在标题与子项重复出现”。该重复是 UI 渲染策略造成的，不一定意味着底层事件重复发射。
2) “确认结束/回合开始结束”噪声的根因：
   - `skip/end_turn/skip_sub_phase` 等流程性命令会生成 `PLAYER_TURN_STARTED/PLAYER_TURN_ENDED` 事件（见 `gameplay/actions/skip_action.gd` 等）。
   - `GameEventLogFormatter` 当前会把这些事件格式化为可见日志（`ui/scenes/game/game_event_log_formatter.gd`），且 `GameLogPanel` 的“阶段事件隐藏”规则并未将其识别为阶段/结构事件，因此默认会显示。
   - 同时，command step 的兜底摘要会显示 `action_display_name`，从而把 `skip` 命令以“玩家X：确认结束”暴露出来。
3) 阶段顺序/归属不匹配的根因（两类）：
   - **事件分段规则过于机械**：当前 step_timeline 在“命令触发 phase 切换”时按 `PHASE_CHANGED` 将事件一刀切分为“旧阶段事件/新阶段事件”；但部分事件在 action 内的追加顺序与用户语义不一致（例如 `PLAYER_TURN_ENDED/STARTED` 在某些实现中出现在 `PHASE_CHANGED` 之后），会被归到新阶段，从而产生“先进入晚餐时间再结束回合”的观感。
   - **里程碑事件生成时机偏晚**：`MILESTONE_ACHIEVED` 当前通过对比“命令前 old_state”与“命令链路结束后的 final_state”一次性 diff 生成，因此事件自带的 `phase/sub_phase` 与 step_timeline 的 `phase_segment` 都会落在链路末端阶段（常见为 Restructuring），导致里程碑在日志中被“推迟”到错误阶段。
   - **现金变化也可能被归到错误阶段**：例如 Payday 的“支付薪水”结算发生在 `Payday EXIT settlement`（见 `modules/base_rules/rules/phase_and_map.gd` 注册点），但 step_timeline 目前在 `phase_changed` 分支里把 `PLAYER_CASH_CHANGED` 一律归到“新阶段 step”，会导致“薪水支付/银行变化”出现在 Marketing 段落而非 Payday。
4) “进入X”类行的根因：phase step 会创建一个动作组标题行，并使用 `kind=="phase"` 的兜底摘要 `进入{phase}`；但此信息已由 `PhaseHeaderItem` 提供，属于重复展示。

整改目标（与用户反馈逐条对齐）：

- 默认不展示流程性日志（确认结束/回合开始结束等）。
- 去掉“标题与子项重复的玩家动作”。
- 修正事件归属：阶段顺序与里程碑出现阶段应符合实际发生时机。
- 移除“进入X”类行（阶段标题已足够）。

#### 已实施整改（对应问题 1-4；已落地）

已实施（按用户确认执行）：

- UI：默认隐藏 `PLAYER_TURN_STARTED/PLAYER_TURN_ENDED` 等流程性事件；`skip/end_turn/skip_sub_phase` 不再以“玩家X:确认结束/结束回合”作为兜底摘要（`ui/scenes/game/game.gd`、`ui/components/game_log/game_log_panel.gd`）。
- UI：`ActionGroupHeaderItem` 选定 `primary_entry_id` 并在子项中跳过该条，消除“同一句话标题+子项重复”；Header 双击可打开 primary 的详情（`ui/components/game_log/game_log_panel.gd`）。
- UI：phase step 不再渲染“进入X”类 ActionGroup 行；PhaseHeader 在 `cursor==start_step_index` 时更强高亮（`ui/components/game_log/game_log_panel.gd`）。
- Core：`StepTimelineBuild` 对 `PLAYER_CASH_CHANGED/MILESTONE_ACHIEVED` 改为增量 diff，并按 settlement trigger 把 `Payday EXIT settlement` 的变化归属到 Payday 段落，同时同步 `data.phase/sub_phase/round`（`core/engine/game_engine/step_timeline_build.gd`）。
- Tests：`core/tests/step_timeline_build_test.gd` 增加 Payday 段落现金变化断言，并补充 milestone 的非 Restructuring 兜底断言；`AllTests` 通过。

范围：同时覆盖“只读回放 + 复盘 + 实时对局”，保持同一套视图规则（M4.3 的核心要求）。

回归验证（建议）：

- 手工回归：主菜单载入 `res://.savings/manual_cases/logs/event_log_review.json`，对照 `demo_image/log_screenshot1.png/2.png` 确认 4 项问题消失且阶段切分正确。
- 自动化保护（现状）：`core/tests/step_timeline_build_test.gd`、`core/tests/manual_log_save_test.gd`、`ui/scenes/tests/replay_log_future_visibility_test.gd`，以及 `AllTests`。
- 自动化增强（可选）：补充一个“确定性触发 MILESTONE_ACHIEVED 并断言 phase_segment”的核心测试用例（Payday/Cleanup/Marketing 至少覆盖 1 个）。

#### 当前实现选择（已落地；后续如需调整可再迭代）

1) `PLAYER_TURN_STARTED/PLAYER_TURN_ENDED`：归类为“结构/噪声事件”，默认隐藏；仅在“显示阶段事件”打开时显示。
2) `skip(确认结束)`：时间线仍保留为可点 step（保证 ReplayBar 单步有落点）；其中 `skip_sub_phase` 在 Working 且非最后子阶段时会合并进上一 step，减少空步数。
