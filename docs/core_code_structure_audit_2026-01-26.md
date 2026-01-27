# core/ GDScript 结构问题清单（用于后续重构）

更新时间：2026-01-27  
审计范围：`core/**/*.gd`  
说明：本报告以“可维护性/层次边界/重复逻辑/过度耦合”为主，目的是为后续逐步重构提供抓手与文件定位；不在本次直接改代码。

## 快速指标（非测试脚本）

- 非测试脚本：177 个，约 26,421 行（`wc -l`）
- 其中：
  - `core/rules/`：47 文件 / 6,405 行
  - `core/engine/`：30 文件 / 5,777 行
  - `core/map/`：35 文件 / 4,521 行
  - `core/modules/`：19 文件 / 2,731 行
  - `core/state/`：14 文件 / 2,048 行
  - `core/data/`：14 文件 / 1,534 行
  - `core/debug/`：6 文件 / 1,439 行

> 注：`core/tests/**/*.gd` 共 103 个脚本（未作为本报告的重点整改对象；若后续要统一测试基建/fixture，可单独再做一次测试目录审计）。

---

## 整改日志

- 2026-01-26：移除 `ModuleManifest`/`WorkingFlow`/`DrinksProcurement` 中薄 `_parse_*` wrapper，直接调用 `DataParseHelpers`/`IntValueParseHelpers`（减少重复/样板）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：`RoadGraphBuilder` 的 external_cells 位置解析改为复用 `core/map/map_runtime/cells.gd`（新增 `sorted_positions_from_external_cells(...)`），并移除 builder 内自带 `_parse_*`（减少重复/样板）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：`GameStateSerialization` 移除自带 `_parse_*` wrapper，改为直接调用 `ParseHelpers`/`RoundStateParser`（收敛 state 解析样板）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：`BakedMap` 移除自带 `_parse_*` wrapper，改为直接调用 `MapParseHelpers`（继续收敛解析样板）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：`MapDef`/`MapOptionDef` 移除自带 `_parse_*` wrapper，改为直接调用 `MapParseHelpers`（减少重复解析样板）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：`TileDef` 移除自带 `_parse_*` wrapper，改为直接调用 `MapParseHelpers`（进一步收敛解析样板、缩短 TileDef）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：新增 `MapParseHelpers.parse_footprint_mask(...)` 并用于 `PieceDef`，移除 `PieceDef` 内自带 `_parse_*` 解析 helper（进一步收敛 map/piece 解析样板）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：`TileDef` 的 road_grid/drink_sources/printed_structures 解析改为委托 `MapParseHelpers`（新增 `parse_road_grid(...)`/`parse_drink_sources(...)`/`parse_printed_structures(...)`），继续收敛地图解析样板；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：为 `GameEngine` 增加可注入的 `event_sink`，并让 `emit_event(...)` 在缺少 EventBus 时可安全降级（默认行为不变）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：新增 `MapParseHelpers.parse_tile_placements(...)` 并用于 `MapDef`/`MapOptionDef`，收敛重复的 tiles placements 解析逻辑；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：为 `GameEngine` 增加 `emit_event(...)` wrapper，并替换 `CommandRunner`/`Initializer` 中对 `EventBus.emit_event(...)` 的直连；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：收敛 initializer/loader 中重复的 EventBus.history 清空逻辑到 `GameEngine.clear_event_history_for_new_session()`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：为 `GameEngine` 增加不变量 baseline 的公开 setter，并替换 `Initializer`/`Loader` 中对私有 `_initial_*` 字段的直接写入；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：`ActionSetup` 的 provider 路径改为从 `ProjectSettings.fcm/action_setup_provider_path` 读取（仍支持 `ActionSetup.set_provider_path(...)` 覆盖），避免 core 内硬编码 gameplay 路径；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：为 `Pathfinding`/`CashOps` 增加公开 wrapper（`get_nodes_at_pos`/`get_balance`/`modify_balance`），并替换 `RangeQuery`/`StateUpdater` 中跨文件调用私有 `_` 方法；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：移除 `ProductDef`/`ModuleManifest` 的“自 load 创建实例”写法，改为直接 `new()`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：新增 `ActionExecutor.apply_changes_in_place(...)` 并用于 `AutoAdvance`（避免跨文件调用私有 `_apply_changes`）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：为 `CommandRunner`/`PhaseManager` 增加公开 wrapper（`build_*`/`drain_auto_advances`/`is_settlement_scheduled`），并替换 `StepTimelineBuild`/`EventHistoryRebuild` 中跨文件调用私有 `_` 前缀方法；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：新增 `GameStartedEventBuild`，统一 `initializer`/`event_timeline_build`/`step_timeline_build` 构建 `GAME_STARTED` 的字段与 state_hash 计算方式（并在缺少初始 checkpoint 时降级为 warning）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：为 `GameEngine` 增加公开 wrapper（`ensure_initialized`/`truncate_future_history`），并替换 `CommandRunner`/`EventHistoryRebuild`/`EventTimelineBuild`/`StepTimelineBuild` 中跨文件调用私有 `_ensure_initialized`/`_truncate_future_history`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：为 `GameEngine` 增加公开 wrapper（`reset_modules_v2`/`apply_modules_v2`/`setup_action_registry`/`create_checkpoint`/`check_invariants`），并替换 `Initializer`/`Loader`/`CommandRunner` 中跨文件调用对应私有 `_` 前缀方法；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：为 `PhaseManager` 增加公开 wrapper（`run_settlement_triggers`/`run_working_sub_phase_hooks`/`run_named_sub_phase_hooks`），并替换 `advance_phase`/`advance_sub_phase` 中跨文件调用私有 `_run_*`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：移除 `MapOptionDef` 的自 preload 创建实例（`_SELF_SCRIPT.new()`），改为直接 `MapOptionDef.new()`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `debug_force` 的回放强制执行判定统一收敛到 `Replay.should_force_execute_in_replay(...)`，并用于 `StepTimelineBuild`/`EventHistoryRebuild`（移除重复 `_should_force_execute_in_replay`）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：扩展 `MapParseHelpers`（新增 `parse_vec2i_array`/`parse_rotation_array`），并用于 `TileDef`/`PieceDef`（移除重复 `_parse_vec2i_list`/`_parse_vec2i_array`/`_parse_rotation_array`）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将“内建动作注册”从 `core/engine/game_engine/action_setup.gd` 迁移到 `gameplay/action_setup.gd`；core `ActionSetup` 改为委托 provider（移除 core 内对 `gameplay/actions/*.gd` 的 preload）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：为 core `ActionSetup` 增加显式注入点 `set_provider_path(...)`，允许在不修改 core 的情况下替换动作注册 provider；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：引入 `Result.error_code`（含 `MISSING_PARAMS`），并在 `ActionExecutor.require_*`/`ActionRegistry.get_player_initiatable_actions` 中使用（保留旧字符串前缀兼容）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `MISSING_PARAMS` 错误码扩展到部分 gameplay actions/validators 以及 `core/rules/drinks_procurement.gd`，并让 UI 的缺参判断优先使用 `Result.error_code`（仍保留旧字符串前缀兼容）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：新增 `core/data/parse_helpers.gd`（`DataParseHelpers`）收敛 data JSON 解析样板代码，并替换 `ProductDef`/`MarketingDef`/`MilestoneDef`/`EmployeeDef.parser` 内自带 `_parse_*`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：新增 `core/utils/json_value_parse_helpers.gd`（`JsonValueParseHelpers`）收敛“JSON int 允许用整值 float 表示”的重复校验，并用于 `core/types/command.gd`/`core/engine/game_engine/loader.gd`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：扩展 `JsonValueParseHelpers`（新增 `parse_non_negative_int_value`），并用于 `core/engine/game_engine/replay.gd` 的 checkpoint.rng_calls 与 `core/rules/drinks_procurement/inputs.gd` 的 route 坐标解析；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：新增 `core/utils/int_value_parse_helpers.gd`（`IntValueParseHelpers`）收敛 rules/milestone effects 的整值解析，并替换 `core/rules/pricing_pipeline.gd`/`core/rules/phase/payday_settlement.gd` 内自带 `_parse_*`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `CleanupSettlement`/`DinnertimeSettlement` 的非负整数解析改为复用 `IntValueParseHelpers.parse_non_negative_int_value(...)`，并移除自带 `_parse_non_negative_int_value`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `ActionExecutor` 的整数参数解析改为复用 `IntValueParseHelpers.parse_int_value(...)`，并移除自带 `_parse_int_value`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `GameConfig` 的通用 `_parse_*` 改为复用 `core/state/serialization/parse_helpers.gd`，并仅保留业务专用 `_parse_reserve_cards`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `WorkingFlow` 的 `_parse_non_negative_int_value` 改为复用 `IntValueParseHelpers.parse_non_negative_int_value(...)`（保留 assert-based fail fast 语义）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `PoolBuilder` 的 `_parse_non_negative_int` 改为复用 `DataParseHelpers.parse_non_negative_int(...)`，并移除自带解析函数；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `ModuleManifest` 的 `_parse_*` 改为复用 `DataParseHelpers`（减少 manifest 解析样板代码）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `VisualCatalogLoader` 的整数解析改为复用 `DataParseHelpers.parse_int(...)`，并移除自带 `_parse_int_required`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：扩展 `IntValueParseHelpers`（新增 `parse_positive_int_value`），并用于 `DrinksProcurement` 的正整数解析（移除自带实现、改为 wrapper 调用）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：新增 `core/rules/milestone_effect_queries.gd`（`MilestoneEffectQueries`）收敛“遍历 milestones -> MilestoneDef.effects -> effects.type”样板，并用于 `PricingPipeline`/`DrinksProcurement`/`WorkingFlow`/`PaydaySettlement`/`CleanupSettlement`/`DinnertimeSettlement`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `CommandRunner` 的事件构建（report 拆分/marketing 到期/cleanup 丢弃等）抽离到 `gameplay/replay/command_runner_event_build.gd`，并为 `CommandRunner` 增加公开 `build_*` wrapper，替换 gameplay phase/skip actions 与 `MarketingDemandGeneratedEventTest` 中对私有 `_build_*` 的直接调用；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：新增 `gameplay/replay/timeline_event_helpers.gd` 收敛时间线事件 envelope（`sequence`/`timestamp`/`command_index`/`step_index`/`phase_segment`）；`event_timeline_build.gd`/`step_timeline_build.gd` 复用该 helper（减少重复/样板）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `MarketingSettlement` 内的 marketing_instances 校验/归一化逻辑抽离到 `core/rules/phase/marketing/marketing_instances_validation.gd`（减少单文件职责/缩短脚本）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：统一“缺少参数”判定走 `Result.error_code == Result.ErrorCode.MISSING_PARAMS`（`ActionRegistry`/UI 移除对旧字符串前缀的兼容），并为 `modules/rural_marketeers/actions/place_highway_offramp_action.gd` 补齐缺参 error_code；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `CommandRunner` 的派生事件构建移出 core（`gameplay/replay/command_runner_event_build.gd`），并通过 `ProjectSettings.fcm/command_runner_event_build_provider_path` 动态加载（减少 core 边界膨胀）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `EventTimelineBuild`/`StepTimelineBuild`/`TimelineEventHelpers` 移出 core 至 `gameplay/replay/`（回放/日志派生视图构建不再占用 core/engine）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：`GameEngine.clear_event_history_for_new_session()` 与 `rewind_to_command()` 在可用时优先调用注入的 `event_sink`（`clear_history_and_reset_sequence`/`record_event`），再回退到 EventBus（进一步降低硬依赖）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 debug command registry/commands 的实现移至 `ui/debug/`，core/debug 仅保留 class_name 兼容 shim（用于 global_script_class_cache/旧路径）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `TileDef` 的板块编辑器编辑方法（road/drink/printed/blocked）移出 `core/map/tile_def.gd`，放到 `ui/scenes/tools/tile_editor/tile_def_edit.gd`；core 仅保留 `ensure_road_grid()` 与数据/校验/查询逻辑（减少 core 与 tools 耦合）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `GameStateFactory` 的餐厅 Logo 分配逻辑外移到 `gameplay/setup/restaurant_logo_assignment.gd`，并通过 `ProjectSettings.fcm/restaurant_logo_assignment_provider_path` 动态加载（减少 core/state 的 UI/setup 语义）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：扩展 `MilestoneEffectQueries`（新增 sum/max helpers）并用于 `PricingPipeline`/`DrinksProcurement`/`WorkingFlow`/`PaydaySettlement`/`CleanupSettlement`/`DinnertimeSettlement` 收敛“entries->value 解析/累加/取最大”样板；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：将 `PerfTrace` 实现移至 `tools/perf_trace.gd`，core/debug 保留 shim（减少 core/debug 的工具逻辑负担）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：将 `ActionRegistry` 的“按阶段/玩家查询动作”逻辑抽离到 `core/actions/action_registry_queries.gd`，`ActionRegistry` 仅保留轻量 wrapper（降低单文件职责与体积）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：将 `AutoAdvance` 的实现抽离到 `core/engine/game_engine/auto_advance_impl.gd`，`auto_advance.gd` 保留 class_name + 轻量 wrapper（降低单文件职责与体积）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：将 `ModulesV2` 的 catalog/config 校验逻辑抽离到 `core/engine/game_engine/modules_v2_validations.gd`（降低 `modules_v2.gd` 单文件职责与体积）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：移除 `PhaseManager` 中未使用的 preload 依赖，并删除未被使用的私有 wrapper（降低耦合与噪音）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：拆分 `RangeUtils`：`core/utils/range_utils.gd` 保留对外 API wrapper，road/air 实现分别落在 `range_utils_road.gd`/`range_utils_air.gd`（降低单文件体积，便于后续进一步拆分/维护）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：拆分 `TrainSlotUsage`：`core/rules/employee_rules/train_slot_usage.gd` 保留对外 API wrapper，完整实现移至 `train_slot_usage_impl.gd`（降低单文件体积，便于按“round_state 存储/培训员选择/slot 分配”继续拆分）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：拆分 `MarketingSettlementHelpers`：`core/rules/phase/marketing/settlement_helpers.gd` 保留 class_name + 对外 API wrapper，完整实现移至 `settlement_helpers_impl.gd`（降低单文件体积，便于按“到期处理/需求写入/里程碑 effects”继续拆分）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：将 `PieceDef.from_dict(...)` 的“严格解析/校验”抽离到 `core/map/piece_def_parser.gd`，`piece_def.gd` 仅保留对象构建与核心方法（缩短超长脚本，降低 map 数据模型与解析耦合）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：将 `GameEngine` 的“阶段/玩家回合起点索引”推导逻辑抽离到 `core/engine/game_engine/command_index_queries.gd`，并复用 `Replay.should_force_execute_in_replay(...)`（缩短 `core/engine/game_engine.gd` 并减少重复判断）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：继续拆分 `MarketingSettlementHelpers`：将 `settlement_helpers_impl.gd` 的实现按职责拆到 `settlement_instance_expiration.gd`/`settlement_products.gd`/`settlement_house_demand.gd`/`settlement_demand_effects.gd`，impl 文件仅保留聚合转发（进一步降低单文件体积）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：继续拆分 `TrainSlotUsage`：将 `train_slot_usage_impl.gd` 的实现按职责拆到 `train_slot_usage_storage.gd`/`train_slot_usage_providers.gd`/`train_slot_usage_allocator.gd`，impl 文件仅保留聚合转发；同时引入 `round_state.train_slot_usage_instances` 记录“按培训员实例”的使用量并兼容旧版总计数（进一步降低单文件体积与耦合）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：拆分 `PaydaySettlement`：将“薪资 token 支付”与“薪资折扣容量推导”拆到 `core/rules/phase/payday/` 下的独立 helper（`payday_salary_token_payment.gd`/`payday_salary_discount.gd`），`payday_settlement.gd` 保留 orchestrator + round_state 报告写入；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：拆分 `DrinksProcurement`：`core/rules/drinks_procurement.gd` 保留对外 API wrapper；“采购计划解析/路线校验/来源筛选”下沉到 `core/rules/drinks_procurement/plan_resolver.gd`，“milestone bonus 计算”下沉到 `core/rules/drinks_procurement/milestone_bonuses.gd`（降低单文件体积与耦合）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：继续拆分 `AutoAdvance`：将 `auto_advance_impl.gd` 的推进决策/阻断检查/Working 强制动作补完/OOB 首轮 finalize 拆到 `auto_advance_try_step.gd`/`auto_advance_phase_blocking.gd`/`auto_advance_working_mandatory.gd`/`auto_advance_order_of_business_round1.gd`，impl 文件仅保留聚合转发（进一步降低单文件体积）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：将 `MapDef.from_dict(...)` 的“严格解析/校验”抽离到 `core/map/map_def_parser.gd`，`map_def.gd` 仅保留数据模型/查询/编辑/验证（缩短超长脚本，降低 map 数据模型与解析耦合）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：拆分 `DinnertimeSettlement`：`core/rules/phase/dinnertime_settlement.gd` 保留 class_name + 对外 API wrapper；完整结算实现迁移至 `core/rules/phase/dinnertime/dinnertime_settlement_impl.gd`；并保留 `_apply_*_effects_by_segment(...)` 薄委托供现有测试调用（降低单文件体积，便于继续按职责拆分）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：缩短 `PhaseManager`：移除未被使用的静态 defs wrapper（保留 `compute_timestamp(...)`），并将内部对 `get_sub_phase_enum(...)` 的调用改为直接调用 `DefsClass.get_sub_phase_enum(...)`（降低单文件体积与重复 API）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：缩短 `GameEngine`：将 `rewind_to_command(...)`/`full_replay()` 的实现抽离到 `core/engine/game_engine/rewind_ops.gd`，`game_engine.gd` 仅保留对外 wrapper（降低单文件体积，便于继续按职责拆分）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：继续拆分 `DinnertimeSettlement`：将“逐房屋售卖主循环”抽离到 `core/rules/phase/dinnertime/dinnertime_house_sales.gd`，`dinnertime_settlement_impl.gd` 聚焦 orchestrator（调用 house_sales + tips/CFO + round_state 报告写入）（进一步降低单文件耦合，便于后续按职责继续拆分）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：继续拆分 `RangeUtils`（road）：将 `range_utils_road.gd` 拆为 wrapper + 子模块（`core/utils/range_utils_road/adjacent_cells.gd`、`core/utils/range_utils_road/distance_queries.gd`），降低单文件体积并按职责聚焦；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：将 `TileDef.from_dict(...)` 的“严格解析/校验”抽离到 `core/map/tile_def_parser.gd`，`tile_def.gd` 更聚焦于数据模型/序列化/校验/查询（降低 map 数据模型与解析耦合）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：拆分 `EmployeeDef` 解析：`core/data/employee_def/parser.gd` 仅保留 orchestrator wrapper；核心字段与可选字段解析分别拆到 `core/data/employee_def/parser/core_fields.gd` 与 `core/data/employee_def/parser/optional_fields.gd`（降低单文件体积，便于维护字段组合约束）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：拆分 `RoundStateParser`：`round_state_parser.gd` 仅保留 orchestrator wrapper；required/optional 字段解析拆到 `round_state_parser_required_fields.gd`/`round_state_parser_optional_fields.gd`，并复用 `round_state_player_id_keys.gd` 收敛“玩家 id key 归一化”样板（降低单文件体积，便于维护 round_state 字段规则）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：`EmployeeRules` 的营销员免薪（`marketing_no_salary`）判定改为复用 `MilestoneEffectQueries.collect_effect_entries(...)`（收敛 milestones->effects 遍历样板）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：收敛 `Command.from_dict(...)` 的字段校验样板：新增 `_parse_required_*` helpers（required key/string/dict/int），并保持错误信息与语义不变（减少“字段存在性 + 类型校验”重复代码）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：新增 `core/utils/autoload_access.gd`（`AutoloadAccess`）并用于 core/engine：对 `EventBus`/`GameLog`/`DebugFlags` 的访问改为运行时按 `/root/<name>` 动态获取（减少对 Autoload 全局变量的硬依赖），同时将 `EventBus.EventType.*` 改为直接使用事件 type 字符串（行为不变）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：继续拆分 `gameplay/replay/command_runner_event_build.gd`：将 Dinnertime/Marketing/Cleanup 的事件推导分别抽离到 `gameplay/replay/command_runner_event_build/dinnertime_events.gd`、`gameplay/replay/command_runner_event_build/marketing_events.gd`、`gameplay/replay/command_runner_event_build/cleanup_events.gd`，主文件保留 orchestrator/wrapper（降低单文件体积，便于继续按 phase 拆分）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：复核并更新文档：2.1 `_parse_*` 重复实现已大幅收敛（core 内仅余 3 文件含 `func _parse_*`）；2.2 规则侧 milestones->effects 遍历已基本迁移到 `MilestoneEffectQueries`（仅保留 MilestoneSystem/模块校验等通用路径直接遍历 `def.effects`）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：继续拆分 `StepTimelineBuild`：将 step dict/事件封装/阶段归属等内部 helper 抽离到 `gameplay/replay/step_timeline_build/helpers.gd`，主文件保留 orchestrator（降低单文件体积，便于后续按职责继续拆分）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：继续拆分 `gameplay/replay/command_runner_event_build.gd`：将 OrderOfBusiness/Payday 的事件推导分别抽离到 `gameplay/replay/command_runner_event_build/order_of_business_events.gd`、`gameplay/replay/command_runner_event_build/payday_events.gd`，主文件继续聚焦 orchestrator/wrapper（进一步降低单文件体积）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：继续拆分 `StepTimelineBuild`：将 `_build_full_impl(...)` 的回放/分段主流程迁移到 `gameplay/replay/step_timeline_build/build_full_impl.gd`，`step_timeline_build.gd` 保留 trace toggling wrapper（进一步降低入口脚本复杂度，便于后续按职责继续拆分 build_full_impl）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：继续拆分 `gameplay/replay/command_runner_event_build.gd`：将 Dinnertime 的 `DINNERTIME_REPORT` 构建也下沉到 `gameplay/replay/command_runner_event_build/dinnertime_events.gd`，主文件进一步聚焦 orchestrator/wrapper（继续降低单文件体积）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：继续拆分 `gameplay/replay/command_runner_event_build.gd`：将 `ROUND_STARTED`/`ROUND_ENDED` 推导抽离到 `gameplay/replay/command_runner_event_build/round_events.gd`，主文件进一步聚焦 orchestrator/wrapper（继续降低残余特殊事件）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：复核并修正文档：3.2 中“事件历史重建桥接”实际位于 `core/engine/game_engine/rewind_ops.gd`（调用 `event_history_rebuild.gd`），而 `core/engine/game_engine.gd` 主要提供 `event_sink` 注入 + emit/clear wrapper；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：`ActionRegistry`/`SettlementRegistry` 不再直接引用 Autoload 全局 `GameLog`/`DebugFlags`，改为通过 `AutoloadAccess` 动态访问（继续降低 core 对日志/调试单例的硬依赖）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：以 `WorkingFlow.start_order_of_business(...)` 为例，将 OrderOfBusiness 相关 fail-fast 从 `assert` 改为返回 `Result.failure` 并在 base_rules/movie_stars hooks 中显式传播（release 下也能阻止坏数据继续跑）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：为 `WorkingFlow` 增加 `compute_order_of_business_empty_slots(...)` 公共 wrapper，并让 `movie_stars` 模块不再跨文件调用 `_compute_order_of_business_empty_slots(...)` 私有 helper（避免封装破坏）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：将 `CompanyStructureRules.get_empty_slots(...)`/`enforce_capacity(...)` 从 `assert` fail-fast 改为返回 `Result.failure`（并在 `WorkingFlow` 侧显式传播），避免 release 下 assert 失效导致坏状态继续跑；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：将 `HouseNumberManager` 与房屋排序相关 fail-fast 从 `assert` 改为返回 `Result.failure`，并在 Marketing/Dinnertime 相关调用链中显式传播（release 下也生效）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：将 `DinnertimeSelection` 内部校验（sale_breakdown/distance_info/candidate 比较）从 `assert` 改为返回 `Result.failure`（fail-fast 在 release 下也生效）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：将 `TileBaking` 中 printed_structures/drink_sources 的 fail-fast 从 `assert` 改为返回 `Result.failure`（fail-fast 在 release 下也生效）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-27：缩短 `MilestoneDef`：将 `from_dict(...)` 的严格解析/校验抽离到 `core/data/milestone_def_parser.gd`，并将 `trigger.filter` 的匹配逻辑抽离到 `core/data/milestone_trigger_filter.gd`（降低单文件体积与职责耦合）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）

---

## 1) 超长脚本 / 职责过载（维护成本高）

下列文件普遍存在“单文件承担多个职责”的情况，阅读与修改成本显著偏高（不仅是行数问题，更是职责边界问题）：

- `core/engine/game_engine/command_runner.gd`（~215 LOC） + `gameplay/replay/command_runner_event_build.gd`（~168 LOC；（已部分整改 2026-01-27）Dinnertime/Marketing/Cleanup/OrderOfBusiness/Payday 的事件推导已抽离到 `gameplay/replay/command_runner_event_build/`）
  - （已部分整改 2026-01-26）事件构建已下沉到 `command_runner_event_build.gd`；`CommandRunner` 主流程更聚焦于“命令执行 + auto-advance + 不变量/校验点 + EventBus 发射”。
  - `DINNERTIME_REPORT`/回合边界事件已拆到子模块；主文件主要保留 orchestrator + `PHASE_CHANGED`/`SUB_PHASE_CHANGED` 这类通用事件封装。
- `gameplay/replay/step_timeline_build/build_full_impl.gd`（~494 LOC；（已部分整改 2026-01-27）`step_timeline_build.gd` 已降为 wrapper；内部 helper 抽离到 `gameplay/replay/step_timeline_build/helpers.gd`）
  - 主要是“回放/日志时间线”的语义构建，逻辑复杂且强依赖事件归属规则（phase_segment、step_index、进入/离开阶段的事件归属等）。
  - 这类逻辑更像 UI/回放子系统的“派生视图构建”，放在 core/engine 内会让 engine 边界持续被拉宽。
- `core/rules/phase/dinnertime_settlement.gd`（~37 LOC；（已整改 2026-01-27）wrapper） + `core/rules/phase/dinnertime/dinnertime_settlement_impl.gd`（~212 LOC） + `core/rules/phase/dinnertime/dinnertime_house_sales.gd`（~281 LOC）
  - （已整改 2026-01-27）已将“逐房屋售卖主循环”从 impl 中抽离到 `dinnertime_house_sales.gd`；impl 仅保留 orchestrator（house_sales + tips/CFO + round_state 报告写入）；后续若继续拆分，可将 house_sales 内部再按“需求 variants 选择/route purchase/支付与报告”分层。
- `ui/debug/debug_commands/action_commands.gd`（~476 LOC）（已整改 2026-01-26：实现移出 core；core/debug 为 shim）
  - 将大量 debug 命令串在一个文件中；后续继续加 debug 命令时容易进一步膨胀。
- `core/engine/game_engine.gd`（~320 LOC；（已部分整改 2026-01-27）命令索引推导抽离到 `command_index_queries.gd`；回退/回放逻辑抽离到 `rewind_ops.gd`）
  - 引擎主体 + rewind/EventBus.history 重建桥接逻辑仍集中；可继续按职责拆分。
- `core/map/piece_def.gd`（~275 LOC；（已整改 2026-01-27）解析逻辑抽离到 `piece_def_parser.gd`）、`core/map/tile_def.gd`（~217 LOC；（已整改 2026-01-27）解析逻辑抽离到 `tile_def_parser.gd`）、`core/map/map_def.gd`（~260 LOC；（已整改 2026-01-27）解析逻辑抽离到 `map_def_parser.gd`）
  - 数据模型 + 严格解析 + 验证 +（部分文件还含编辑器/调试方法）揉在一起，导致“修改数据结构”和“修改解析/验证规则”互相影响。
- 其他超过 ~300 行的文件：
  - （已整改 2026-01-27）`core/rules/employee_rules/train_slot_usage_impl.gd` 已拆分为 `train_slot_usage_storage.gd`/`train_slot_usage_providers.gd`/`train_slot_usage_allocator.gd`
  - （已整改 2026-01-27）`core/rules/phase/payday_settlement.gd` 已按“token 支付/折扣推导”拆分到 `core/rules/phase/payday/`（主文件不再超长）
  - （已整改 2026-01-27）`core/rules/drinks_procurement.gd` 已拆分为 `drinks_procurement/plan_resolver.gd` + `drinks_procurement/milestone_bonuses.gd`（主文件不再超长）
  - （已整改 2026-01-27）`core/engine/game_engine/auto_advance_impl.gd` 已拆分到 `auto_advance_*.gd`（主文件不再超长）
  - （已整改 2026-01-27）`core/map/map_def.gd` 已拆分出 `map_def_parser.gd`（主文件不再超长）
  - （已整改 2026-01-27）`core/engine/phase_manager.gd` 已移除冗余静态 defs wrapper（主文件不再超长）

建议记录（后续重构方向）：
- 先从“职责剥离”入手，而不是单纯按行数拆文件：
  - 命令执行（state 转换） vs 事件构建（日志语义） vs 事件投递（EventBus） vs 自动推进（AutoAdvance）拆成独立组件/模块。
  - 规则文件中将“纯计算/选择”与“写 state/写 round_state 报告/触发 milestone”分层，以便更容易测试与复用。

---

## 2) 重复逻辑 / 重复 helper（难以统一修复）

### 2.1 `_parse_*` 家族重复实现（已大幅整改）

表现：
- （历史审计）曾在至少 25 个文件中出现 `static func _parse_*` 系列（int/string/bool/array 等）重复实现。
- 同时仓库已经存在可复用的解析 helper：
  - `core/state/serialization/parse_helpers.gd`
  - `core/map/parse_helpers.gd`
  - （已部分整改 2026-01-26）`core/data/parse_helpers.gd`
  - （已部分整改 2026-01-26）`core/utils/json_value_parse_helpers.gd`

现状（已复核 2026-01-27）：
- `core/` 中仅剩 3 个文件包含 `func _parse_*`（均为业务/局部 helper，不再是跨目录重复实现）：
  - `core/data/game_config.gd`：仅保留业务专用 `_parse_reserve_cards(...)`
  - `core/modules/v2/visual_catalog_loader.gd`：局部结构解析（vec2/vec2i/piece_visuals）
  - `core/types/command.gd`：required 字段解析 helper（用于减少 `from_dict(...)` 校验样板）

典型文件（不完全列举）：
- 数据定义解析重复：（已部分整改 2026-01-26）`core/data/product_def.gd`、`core/data/milestone_def.gd`、`core/data/employee_def/parser.gd`、`core/data/marketing_def.gd` 已改为共用 `core/data/parse_helpers.gd`；（已部分整改 2026-01-26）`core/data/game_config.gd` 已改为复用 `core/state/serialization/parse_helpers.gd`
- 命令/存档解析重复：（已部分整改 2026-01-26）`core/types/command.gd` 与 `core/engine/game_engine/loader.gd` 已共用 `core/utils/json_value_parse_helpers.gd`；（已部分整改 2026-01-26）`core/actions/action_executor.gd` 已改为共用 `core/utils/int_value_parse_helpers.gd`
- 规则内重复：`core/rules/pricing_pipeline.gd`、`core/rules/drinks_procurement.gd`、`core/rules/phase/payday_settlement.gd`、`core/rules/phase/cleanup_settlement.gd`、`core/rules/phase/dinnertime_settlement.gd`

风险：
- 修一个解析边界（例如“允许整值 float、禁止小数、字符串是否容错”）要改很多处，容易漏。
- 错误信息格式/一致性难以保证（影响测试稳定性与排障效率）。

### 2.2 里程碑 effects 解析散落（重复 “遍历 milestones -> def.effects -> type/value”）

表现：
- 多处通过遍历 `MilestoneDef.effects` 并按 `effect.type` 分支来实现效果（或叠加 bonus）。
- 典型文件（不完全列举）：
  - `core/rules/pricing_pipeline.gd`
  - `core/rules/drinks_procurement.gd`
  - `core/rules/phase/dinnertime_settlement.gd`
 - `core/rules/phase/payday_settlement.gd`
 - `core/rules/phase/cleanup_settlement.gd`
 - `core/engine/phase_manager/working_flow.gd`
 - `core/rules/phase/marketing/settlement_demand_effects.gd`（叠加 effect_registry 的 invoke）
  - （已整改 2026-01-27）规则侧相关 callsite 已基本迁移到 `core/rules/milestone_effect_queries.gd` 收敛 milestones->effects 遍历样板；目前仅保留 `MilestoneSystem`（应用效果）与模块内容校验等路径会直接遍历 `def.effects`（属通用/校验路径）

现状矛盾点：
- core 已经存在 `core/rules/milestone_effect_registry.gd`（effects.type -> handler），规则侧 effects.value 叠加/查询已基本收敛到 `MilestoneEffectQueries`；仍有少量按 `effect_id` segment 过滤并调用 `effect_registry.invoke(...)` 的路径（如 MarketingSettlement 相关逻辑），属于不同的 effect 表达方式，后续可按需要继续收敛。

风险：
- 新增/修改 milestone effect 时需要同步修改多个地方，容易出现“同一个 effect_type 在不同系统语义不一致”。

### 2.3 事件构建 / 时间线构建存在交叉引用与重复

表现：
- （已整改 2026-01-26）`gameplay/replay/step_timeline_build.gd` 曾直接调用 `CommandRunnerClass._build_*`（私有前缀函数）以及 `engine.phase_manager._is_settlement_scheduled(...)`（私有前缀方法）；现改为 `CommandRunnerClass.build_*` 与 `PhaseManager.is_settlement_scheduled(...)` 公共 wrapper。
- （已整改 2026-01-26）`gameplay/replay/event_timeline_build.gd`、`gameplay/replay/step_timeline_build.gd`、`core/engine/game_engine/initializer.gd` 统一使用 `GameStartedEventBuild` 构建/注入 `GAME_STARTED` 事件数据（避免字段/计算方式漂移）。

风险：
- “私有 API”被跨文件使用，意味着后续想重构 `CommandRunner` 或 `PhaseManager` 的内部实现会被迫同步改多个地方。

---

## 3) 过度耦合 / 层次边界泄漏（core 不够“可复用”）

### 3.1 core 反向依赖 gameplay（层次反转）

- `core/engine/game_engine/action_setup.gd`
  - （已整改 2026-01-26）不再直接 `preload("res://gameplay/actions/*.gd")`；改为委托 `gameplay/action_setup.gd` 提供“内建动作注册”。
  - （已整改 2026-01-26）provider 路径不再在 core 内硬编码；改为读取 `ProjectSettings.fcm/action_setup_provider_path`，并保留 `ActionSetup.set_provider_path(...)` 覆盖入口（从而把 gameplay 路径依赖移出 core）。

建议（方向）：
- 将 “内建 action wiring / action executor 注册” 移到 `gameplay/`（或更上层），core 只提供 `ActionRegistry` 的 API 与引擎执行能力。
- 或引入“动作提供者/注册回调”的注入点：由 app/gameplay 在初始化时向 engine 提供 executors。

### 3.2 core/engine 对 EventBus/DebugFlags/GameLog 等全局单例耦合偏高（已部分整改）

涉及文件（主要集中在 engine，另含 actions/rules）：
- `core/engine/game_engine/command_runner.gd`：（已整改 2026-01-27）对 `GameLog`/`DebugFlags`/`EventBus` 不再直接引用 Autoload 全局变量，改为统一通过 `AutoloadAccess` 动态获取；仍包含 `OS.has_feature` 的调试/发布差异分支；事件发射仍经 `engine.emit_event(...)` wrapper
- `core/engine/game_engine/loader.gd`、`core/engine/game_engine/initializer.gd`：（已整改 2026-01-27）日志/事件相关访问通过 `AutoloadAccess`/engine wrapper 动态获取；清空事件历史仍经 `engine.clear_event_history_for_new_session()` wrapper
- `core/engine/game_engine.gd`：（已整改 2026-01-26）增加 `event_sink` 注入点，并让 history clear 也优先走 sink；（已整改 2026-01-27）默认通过 `AutoloadAccess` 动态访问 EventBus，降低对 Autoload 全局变量的硬依赖
- `core/engine/game_engine/rewind_ops.gd`：（已整改 2026-01-27）回退时负责 EventBus.history 重建桥接（调用 `event_history_rebuild.gd` 推导事件列表，并以 `record_event` 回填历史），仍属于“引擎与日志系统”的耦合点
- `core/actions/action_registry.gd`：（已整改 2026-01-27）日志输出改为通过 `AutoloadAccess` 动态访问 `GameLog`（避免直接引用 Autoload 全局变量；行为不变）
- `core/rules/settlement_registry.gd`：（已整改 2026-01-27）warn/debug 判定改为通过 `AutoloadAccess` 动态访问 `GameLog`/`DebugFlags`（避免直接引用 Autoload 全局变量；行为不变）

风险：
- 引擎逻辑与 UI/日志系统绑死；做“纯逻辑回放”或“服务器侧模拟”会更难。

### 3.3 ActionRegistry 混入 UI 语义 + 字符串错误消息作为控制流

- `core/actions/action_registry.gd`
  - （已整改 2026-01-26）`get_player_initiatable_actions(...)` 统一按 `Result.error_code == Result.ErrorCode.MISSING_PARAMS` 判定缺参；并推动相关 actions/validators 返回结构化错误码（避免靠“缺少参数:*”文案做控制流）。

风险：
- 错误文案变更会破坏行为（隐式契约）；也会让 i18n/重构变难。

建议（方向）：
- 把“是否可启动”的判断从 core 移到 gameplay/ui；
- 或在 Result 中引入结构化错误码（而非靠字符串前缀）（已整改 2026-01-26）。

### 3.4 私有方法/私有 helper 的跨文件调用（封装破坏）

典型点：
- `gameplay/replay/step_timeline_build.gd` / `core/engine/game_engine/event_history_rebuild.gd`：
  - （已整改 2026-01-26）已改用 `CommandRunnerClass.build_*` / `CommandRunnerClass.drain_auto_advances(...)` 等公开 wrapper，不再跨文件调用 `_build_*` / `_drain_auto_advances`。
  - （已整改 2026-01-26）已改用 `PhaseManager.is_settlement_scheduled(...)`，不再跨文件调用 `_is_settlement_scheduled`。
- `core/engine/game_engine/command_runner.gd` / `core/engine/game_engine/event_history_rebuild.gd` / `gameplay/replay/event_timeline_build.gd` / `gameplay/replay/step_timeline_build.gd`：
  - （已整改 2026-01-26）改用 `engine.ensure_initialized()` / `engine.truncate_future_history()` 公开 wrapper，避免跨文件调用 `GameEngine._ensure_initialized` / `GameEngine._truncate_future_history`。
- `core/engine/game_engine/initializer.gd` / `core/engine/game_engine/loader.gd` / `core/engine/game_engine/command_runner.gd`：
  - （已整改 2026-01-26）改用 `engine.reset_modules_v2()` / `engine.apply_modules_v2(...)` / `engine.setup_action_registry(...)` / `engine.create_checkpoint(...)` / `engine.check_invariants()` 公开 wrapper，避免跨文件调用对应 `GameEngine._*` 私有方法。
- `core/engine/phase_manager/advance_phase.gd` / `core/engine/phase_manager/advance_sub_phase.gd`：
  - （已整改 2026-01-26）改用 `PhaseManager.run_settlement_triggers(...)` / `PhaseManager.run_*_sub_phase_hooks(...)` 公开 wrapper，避免跨文件调用 `PhaseManager._run_settlement_triggers` / `PhaseManager._run_*_sub_phase_hooks`。
- gameplay phase/skip actions 与相关测试：
  - （已整改 2026-01-26）不再调用 `CommandRunnerClass._build_*` 私有静态方法，改为调用 `CommandRunnerClass.build_*` wrapper。
- `core/engine/game_engine/auto_advance.gd` 调用：
  - （已整改 2026-01-26）原先调用 `executor._apply_changes(...)`；已改为 `executor.apply_changes_in_place(...)`（行为不变，但避免跨文件访问私有方法）
- `core/map/road_graph/range_query.gd`：
  - （已整改 2026-01-26）改用 `Pathfinding.get_nodes_at_pos(...)` 公开 wrapper，避免跨文件调用 `Pathfinding._get_nodes_at_pos(...)`。
- `core/state/state_updater.gd`：
  - （已整改 2026-01-26）改用 `CashOps.get_balance(...)`/`CashOps.modify_balance(...)` 公开 wrapper，避免跨文件调用 `CashOps._get_balance(...)`/`CashOps._modify_balance(...)`。
- `modules/movie_stars/rules/entry.gd` / `core/engine/phase_manager/working_flow.gd`：
  - （已整改 2026-01-27）改用 `WorkingFlow.compute_order_of_business_empty_slots(...)` 公开 wrapper，不再跨文件调用 `_compute_order_of_business_empty_slots(...)`。

风险：
- 后续想重构接口时，无法在不改调用方的情况下替换内部实现。

---

## 4) “应该放在 module / gameplay / ui / tools 的逻辑”混入 core 的例子

这里不讨论“绝对正确的唯一答案”，只记录目前可见的边界不清晰点（会持续制造耦合）：

- UI/日志派生数据构建在 core/engine：
  - （已整改 2026-01-26）原 `command_runner_event_build.gd` 已移至 `gameplay/replay/command_runner_event_build.gd`（由 `ProjectSettings.fcm/command_runner_event_build_provider_path` 提供）。
  - （已整改 2026-01-26）`gameplay/replay/step_timeline_build.gd` 的 step_index/phase_segment 偏“展示/回放定位”，不像“引擎最小内核”。
- Debug 命令系统在 core：
  - （已整改 2026-01-26）实现已移至 `ui/debug/`，core/debug 仅保留 class_name 兼容 shim（用于 global_script_class_cache/旧路径）。
- GameStateFactory 含“Logo 分配”等偏展示/前端选择的确定性逻辑：
  - （已整改 2026-01-26）`core/state/game_state_factory.gd` 中 `restaurant_logo_id` 分配策略已外移到 `gameplay/setup/restaurant_logo_assignment.gd`，并由 `ProjectSettings.fcm/restaurant_logo_assignment_provider_path` 注入（core/state 不再内置具体分配逻辑）。
- MapDef/TileDef/PieceDef 内含“编辑方法/调试 dump”：
  - （已整改 2026-01-26）`TileDef` 的板块编辑器编辑方法已移至 `ui/scenes/tools/tile_editor/tile_def_edit.gd`，core `TileDef` 不再包含 tools 专用 API。

---

## 5) 代码风格 / 设计层面的可维护性问题（零散但值得统一）

- phase/action 等大量字符串驱动：
  - 例如多个地方直接比较 `"Marketing" / "Dinnertime" / "Working" ...`，容易产生拼写/重命名成本与难以全局替换的问题。
  - 建议逐步迁移到集中定义（constants/enum），并提供转换与校验入口。
- `assert` 与 `Result.failure` 混用导致“release 下校验失效”的风险：
  - （已部分整改 2026-01-27）以 `core/engine/phase_manager/working_flow.gd` 为例，里程碑 effects 解析与 OrderOfBusiness 排序相关的 fail-fast 已从 `assert` 改为返回 `Result.failure`，并在 base_rules/movie_stars hooks 中显式传播（release 下也生效）。
  - 仍有少量 `assert`（多为初始化/内部不变量/模块校验）；关键路径（`WorkingFlow`/`CompanyStructureRules`/`HouseNumberManager`/`DinnertimeSelection`/`TileBaking`）已改为 `Result.failure` fail-fast，后续可继续统一策略。
- 大量 `Dictionary` 结构的手工深层读取/写入：
  - 多文件重复出现 `if not (x is Dictionary)`、`get(..., null)`、`duplicate(true)` 组合，属于结构性样板代码。
  - 已有 `TypeHelpers` / `ParseHelpers` / 若干 query helper（例如 `CatalogRegistryHelpers`、`MarketingPlacementQuery`）但使用不一致，导致全局风格不统一。
- 少量“自加载创建实例”的奇怪模式：
  - （已整改 2026-01-26）`core/data/product_def.gd`、`core/modules/v2/module_manifest.gd` 已从 `load(自身脚本路径).new()` 改为直接 `new()`。

---

## 6) 建议的后续修复顺序（可选路线图）

为降低风险，建议按“先切边界、再收敛重复、最后做结构升级”的顺序推进：

1. **解耦 core ↔ gameplay**：已开始处理 `core/engine/game_engine/action_setup.gd` 的反向依赖（动作注册迁移到 `gameplay/action_setup.gd`，并提供 `ActionSetup.set_provider_path(...)` 注入点）；（已整改 2026-01-26）provider 来源改为 `ProjectSettings.fcm/action_setup_provider_path`（避免默认写死 gameplay 路径）。
2. **抽离事件/日志语义**：把 `CommandRunner` 中的“事件构建/归属/拆分”拆到独立组件（可放在 gameplay 或 ui 的回放子系统），core 保留最小执行路径。
3. **统一解析/校验工具链**：收敛 `_parse_*` 重复实现，优先统一数据/存档/命令解析路径。
4. **收敛 milestone effects 处理**：明确“effects.type 的唯一解释器”与“effects/effect_ids 的边界”，尽量走 registry/handler 体系，减少散落的手写解析。
5. **逐步减少 Dictionary 裸写**：在高频/高风险结构（player、round_state、map 子结构）上引入更明确的 query/mutation API，减少手工深层访问。

---

## 附录 A：非测试脚本清单（快速定位）

字段说明：
- `preloads`：文件内 `preload(...)` 出现次数（粗略耦合指标）
- `loads`：文件内 `load(...)` 出现次数（动态加载/反射倾向）
- `flags`：快速标记（例如依赖 gameplay、使用 EventBus、定义 `_parse_*` 等）

| path | loc | preloads | loads | flags |
|---|---:|---:|---:|---|
| `core/actions/action_availability_registry.gd` | 267 | 0 | 0 |  |
| `core/actions/action_executor.gd` | 199 | 1 | 0 | uses:IntValueParseHelpers |
| `core/actions/action_registry.gd` | 235 | 2 | 0 | uses:AutoloadAccess |
| `core/data/employee_def/debug.gd` | 22 | 0 | 0 |  |
| `core/data/employee_def/parser.gd` | 13 | 2 | 0 | helper:employee_def_parser_wrapper |
| `core/data/employee_def/parser/core_fields.gd` | 115 | 1 | 0 | helper:employee_def_parser_core,uses:DataParseHelpers |
| `core/data/employee_def/parser/optional_fields.gd` | 106 | 1 | 0 | helper:employee_def_parser_optional,uses:DataParseHelpers |
| `core/data/employee_def/serialization.gd` | 47 | 0 | 0 |  |
| `core/data/employee_def.gd` | 184 | 3 | 0 |  |
| `core/data/employee_registry.gd` | 93 | 2 | 0 |  |
| `core/data/game_config.gd` | 208 | 1 | 0 | uses:ParseHelpers |
| `core/data/game_data.gd` | 109 | 3 | 0 |  |
| `core/data/marketing_def.gd` | 104 | 0 | 0 | uses:DataParseHelpers |
| `core/data/marketing_registry.gd` | 71 | 1 | 0 |  |
| `core/data/milestone_def.gd` | 219 | 0 | 0 | uses:DataParseHelpers |
| `core/data/milestone_registry.gd` | 59 | 2 | 0 |  |
| `core/data/parse_helpers.gd` | 65 | 0 | 0 |  |
| `core/data/product_def.gd` | 66 | 0 | 0 | uses:DataParseHelpers |
| `core/data/product_registry.gd` | 82 | 2 | 0 |  |
| `core/debug/debug_command_registry.gd` | 6 | 0 | 0 | shim->ui |
| `core/debug/debug_commands/action_commands.gd` | 10 | 0 | 0 | shim->ui |
| `core/debug/debug_commands/game_commands.gd` | 10 | 0 | 0 | shim->ui |
| `core/debug/debug_commands/state_commands.gd` | 10 | 0 | 0 | shim->ui |
| `core/debug/debug_commands/util_commands.gd` | 10 | 0 | 0 | shim->ui |
| `core/debug/perf_trace.gd` | 146 | 0 | 0 | shim->tools |
| `core/engine/game_constants.gd` | 9 | 0 | 0 |  |
| `core/engine/game_defaults.gd` | 22 | 0 | 0 |  |
| `core/engine/game_engine/action_setup.gd` | 37 | 0 | 1 | delegates:gameplay,uses:GameLog,uses:ProjectSettings |
| `core/engine/game_engine/action_wiring.gd` | 100 | 2 | 0 |  |
| `core/engine/game_engine/archive.gd` | 127 | 1 | 0 | uses:GameLog |
| `core/engine/game_engine/auto_advance.gd` | 14 | 1 | 0 |  |
| `core/engine/game_engine/auto_advance_impl.gd` | 34 | 1 | 0 |  |
| `core/engine/game_engine/auto_advance_order_of_business_round1.gd` | 51 | 0 | 0 | helper:auto_advance_oob_round1 |
| `core/engine/game_engine/auto_advance_phase_blocking.gd` | 36 | 1 | 0 | helper:auto_advance_phase_blocking |
| `core/engine/game_engine/auto_advance_try_step.gd` | 145 | 3 | 0 | helper:auto_advance_try_step |
| `core/engine/game_engine/auto_advance_working_mandatory.gd` | 53 | 0 | 0 | helper:auto_advance_working_mandatory |
| `core/engine/game_engine/checkpoints.gd` | 55 | 0 | 0 | uses:GameLog,uses:DebugFlags |
| `core/engine/game_engine/command_runner.gd` | 215 | 2 | 0 | uses:EventBus,uses:GameLog,uses:DebugFlags,uses:OS.has_feature |
| `gameplay/replay/command_runner_event_build.gd` | 168 | 6 | 0 | moved:gameplay,uses:EventBus |
| `core/engine/game_engine/diagnostics.gd` | 48 | 0 | 0 |  |
| `core/engine/game_engine/event_history_rebuild.gd` | 96 | 2 | 0 | uses:EventBus |
| `gameplay/replay/event_timeline_build.gd` | 99 | 3 | 0 | moved:gameplay,uses:EventBus |
| `core/engine/game_engine/game_started_event_build.gd` | 34 | 0 | 0 |  |
| `core/engine/game_engine/initializer.gd` | 264 | 9 | 0 | uses:EventBus,uses:GameLog |
| `core/engine/game_engine/invariants.gd` | 259 | 1 | 0 |  |
| `core/engine/game_engine/loader.gd` | 155 | 3 | 0 | uses:EventBus,uses:GameLog,uses:JsonValueParseHelpers |
| `core/engine/game_engine/modules_v2.gd` | 231 | 23 | 0 |  |
| `core/engine/game_engine/replay.gd` | 188 | 2 | 0 | uses:GameLog,uses:OS.has_feature,uses:JsonValueParseHelpers |
| `core/engine/game_engine/rewind_ops.gd` | 82 | 2 | 0 | helper:rewind_ops |
| `gameplay/replay/step_timeline_build.gd` | 35 | 1 | 0 | moved:gameplay |
| `gameplay/replay/step_timeline_build/build_full_impl.gd` | 494 | 7 | 0 | moved:gameplay,uses:EventBus |
| `gameplay/replay/step_timeline_build/helpers.gd` | 139 | 0 | 0 | helper:step_timeline_build |
| `gameplay/replay/timeline_event_helpers.gd` | 75 | 0 | 0 | moved:gameplay,helper:timeline_event |
| `core/engine/game_engine/command_index_queries.gd` | 168 | 2 | 0 | helper:command_index_queries |
| `core/engine/game_engine.gd` | 320 | 14 | 0 | uses:EventBus |
| `core/engine/phase_manager/advance_phase.gd` | 239 | 2 | 0 | uses:GameLog |
| `core/engine/phase_manager/advance_sub_phase.gd` | 278 | 2 | 0 | uses:GameLog |
| `core/engine/phase_manager/advancement.gd` | 13 | 2 | 0 |  |
| `core/engine/phase_manager/definitions.gd` | 218 | 0 | 0 |  |
| `core/engine/phase_manager/hooks.gd` | 220 | 1 | 0 | uses:GameLog,uses:DebugFlags |
| `core/engine/phase_manager/order_config.gd` | 152 | 1 | 0 |  |
| `core/engine/phase_manager/settlement_triggers.gd` | 127 | 2 | 0 |  |
| `core/engine/phase_manager/working_flow.gd` | 185 | 3 | 0 | uses:IntValueParseHelpers,uses:MilestoneEffectQueries |
| `core/engine/phase_manager.gd` | 266 | 6 | 0 |  |
| `core/map/house_number_manager.gd` | 233 | 0 | 0 |  |
| `core/map/map_baker/bake.gd` | 80 | 3 | 0 |  |
| `core/map/map_baker/boundary_index.gd` | 22 | 0 | 0 |  |
| `core/map/map_baker/cells.gd` | 22 | 0 | 0 |  |
| `core/map/map_baker/debug.gd` | 41 | 0 | 0 |  |
| `core/map/map_baker/queries.gd` | 43 | 0 | 0 |  |
| `core/map/map_baker/tile_baking.gd` | 280 | 0 | 0 |  |
| `core/map/map_context_builder.gd` | 21 | 1 | 0 |  |
| `core/map/map_def.gd` | 260 | 2 | 0 |  |
| `core/map/map_def_parser.gd` | 73 | 1 | 0 | helper:map_def_parser |
| `core/map/map_option_def.gd` | 130 | 3 | 0 |  |
| `core/map/map_runtime/baked_map.gd` | 153 | 2 | 0 |  |
| `core/map/map_runtime/cells.gd` | 117 | 1 | 0 |  |
| `core/map/map_runtime/coords.gd` | 59 | 0 | 0 |  |
| `core/map/map_runtime/road_graph_cache.gd` | 42 | 2 | 0 |  |
| `core/map/map_runtime/structures.gd` | 61 | 1 | 0 |  |
| `core/map/map_runtime/tile_edit.gd` | 215 | 3 | 0 |  |
| `core/map/map_utils.gd` | 239 | 0 | 0 |  |
| `core/map/marketing_placement_query.gd` | 250 | 1 | 0 |  |
| `core/map/parse_helpers.gd` | 215 | 0 | 0 |  |
| `core/map/piece_def.gd` | 275 | 2 | 0 |  |
| `core/map/piece_def_parser.gd` | 125 | 2 | 0 |  |
| `core/map/piece_registry.gd` | 67 | 2 | 0 |  |
| `core/map/placement_validator/garden_attachment.gd` | 124 | 2 | 0 |  |
| `core/map/placement_validator/map_access.gd` | 40 | 0 | 0 |  |
| `core/map/placement_validator/placement.gd` | 95 | 1 | 0 |  |
| `core/map/placement_validator/restaurant_placement.gd` | 79 | 2 | 0 |  |
| `core/map/placement_validator/road_utils.gd` | 51 | 0 | 0 |  |
| `core/map/placement_validator/validators.gd` | 286 | 1 | 0 |  |
| `core/map/road_graph/blocks.gd` | 75 | 0 | 0 |  |
| `core/map/road_graph/builder.gd` | 100 | 2 | 0 |  |
| `core/map/road_graph/node_keys.gd` | 18 | 0 | 0 |  |
| `core/map/road_graph/pathfinding.gd` | 159 | 1 | 0 |  |
| `core/map/road_graph/range_query.gd` | 45 | 2 | 0 |  |
| `core/map/road_graph.gd` | 147 | 4 | 0 |  |
| `core/map/tile_def.gd` | 217 | 2 | 0 |  |
| `core/map/tile_def_parser.gd` | 77 | 2 | 0 | helper:tile_def_parser |
| `core/map/tile_registry.gd` | 63 | 2 | 0 |  |
| `core/modules/v2/content_catalog.gd` | 68 | 0 | 0 |  |
| `core/modules/v2/content_catalog_loader.gd` | 274 | 9 | 0 |  |
| `core/modules/v2/module_dir_spec.gd` | 36 | 0 | 0 |  |
| `core/modules/v2/module_manifest.gd` | 108 | 1 | 0 | uses:DataParseHelpers |
| `core/modules/v2/module_package_loader.gd` | 82 | 1 | 0 |  |
| `core/modules/v2/module_plan_builder.gd` | 124 | 0 | 0 |  |
| `core/modules/v2/pool_builder.gd` | 86 | 4 | 0 | uses:DataParseHelpers |
| `core/modules/v2/ruleset/action_registration.gd` | 146 | 0 | 0 |  |
| `core/modules/v2/ruleset/content_validation.gd` | 141 | 2 | 0 |  |
| `core/modules/v2/ruleset/patches.gd` | 166 | 2 | 0 |  |
| `core/modules/v2/ruleset/phase_hooks.gd` | 267 | 1 | 0 |  |
| `core/modules/v2/ruleset/provider_registration.gd` | 136 | 0 | 0 |  |
| `core/modules/v2/ruleset/state_and_order.gd` | 269 | 1 | 0 |  |
| `core/modules/v2/ruleset/sub_phase_registration.gd` | 137 | 0 | 0 |  |
| `core/modules/v2/ruleset.gd` | 245 | 12 | 0 |  |
| `core/modules/v2/ruleset_builder.gd` | 128 | 1 | 0 |  |
| `core/modules/v2/ruleset_loader.gd` | 48 | 1 | 1 |  |
| `core/modules/v2/visual_catalog.gd` | 20 | 0 | 0 |  |
| `core/modules/v2/visual_catalog_loader.gd` | 266 | 5 | 0 | uses:DataParseHelpers |
| `core/random/random_manager.gd` | 235 | 0 | 0 |  |
| `core/rules/bankruptcy_registry.gd` | 69 | 0 | 0 |  |
| `core/rules/company_structure_rules.gd` | 186 | 2 | 0 | uses:IntValueParseHelpers |
| `core/rules/dinnertime_demand_registry.gd` | 186 | 0 | 0 |  |
| `core/rules/dinnertime_route_purchase_registry.gd` | 174 | 0 | 0 |  |
| `core/rules/drinks_procurement/default_route_builder.gd` | 165 | 4 | 0 |  |
| `core/rules/drinks_procurement/inputs.gd` | 58 | 1 | 0 | uses:JsonValueParseHelpers |
| `core/rules/drinks_procurement/milestone_bonuses.gd` | 136 | 2 | 0 | uses:IntValueParseHelpers,uses:MilestoneEffectQueries |
| `core/rules/drinks_procurement/picked_sources_finder.gd` | 45 | 2 | 0 |  |
| `core/rules/drinks_procurement/plan_resolver.gd` | 162 | 6 | 0 | helper:drinks_procurement_plan |
| `core/rules/drinks_procurement/route_validator.gd` | 121 | 5 | 0 |  |
| `core/rules/drinks_procurement/start_restaurant_resolver.gd` | 89 | 3 | 0 |  |
| `core/rules/drinks_procurement/tile_route_utils.gd` | 83 | 1 | 0 |  |
| `core/rules/drinks_procurement.gd` | 32 | 2 | 0 |  |
| `core/rules/economy/bankruptcy_rules.gd` | 270 | 3 | 0 |  |
| `core/rules/effect_registry.gd` | 67 | 0 | 0 |  |
| `core/rules/employee_pool_patch_registry.gd` | 113 | 0 | 0 |  |
| `core/rules/employee_rules/action_counts.gd` | 55 | 0 | 0 |  |
| `core/rules/employee_rules/counts.gd` | 58 | 3 | 0 |  |
| `core/rules/employee_rules/employee_array_helpers.gd` | 24 | 1 | 0 |  |
| `core/rules/employee_rules/immediate_train_pending.gd` | 149 | 0 | 0 |  |
| `core/rules/employee_rules/limits.gd` | 46 | 2 | 0 |  |
| `core/rules/employee_rules/salary.gd` | 65 | 4 | 0 |  |
| `core/rules/employee_rules/train_slot_usage.gd` | 30 | 1 | 0 |  |
| `core/rules/employee_rules/train_slot_usage_allocator.gd` | 163 | 2 | 0 |  |
| `core/rules/employee_rules/train_slot_usage_impl.gd` | 31 | 2 | 0 |  |
| `core/rules/employee_rules/train_slot_usage_providers.gd` | 55 | 2 | 0 |  |
| `core/rules/employee_rules/train_slot_usage_storage.gd` | 123 | 1 | 0 |  |
| `core/rules/employee_rules/working_multiplier.gd` | 29 | 0 | 0 |  |
| `core/rules/employee_rules.gd` | 105 | 7 | 0 |  |
| `core/rules/global_effect_list.gd` | 112 | 0 | 0 |  |
| `core/rules/map_generation_registry.gd` | 32 | 0 | 0 |  |
| `core/rules/marketing_initiation_registry.gd` | 104 | 0 | 0 |  |
| `core/rules/marketing_range_calculator.gd` | 31 | 1 | 0 |  |
| `core/rules/marketing_rules.gd` | 16 | 0 | 0 |  |
| `core/rules/marketing_type_registry.gd` | 85 | 0 | 0 |  |
| `core/rules/milestone_effect_queries.gd` | 53 | 2 | 0 |  |
| `core/rules/milestone_effect_registry.gd` | 71 | 0 | 0 |  |
| `core/rules/milestone_system.gd` | 120 | 4 | 0 |  |
| `core/rules/phase/cleanup_settlement.gd` | 243 | 5 | 0 | uses:IntValueParseHelpers,uses:MilestoneEffectQueries |
| `core/rules/phase/dinnertime/dinnertime_distance.gd` | 176 | 1 | 0 |  |
| `core/rules/phase/dinnertime/dinnertime_effects.gd` | 153 | 3 | 0 |  |
| `core/rules/phase/dinnertime/dinnertime_events.gd` | 46 | 0 | 0 |  |
| `core/rules/phase/dinnertime/dinnertime_inventory.gd` | 81 | 1 | 0 |  |
| `core/rules/phase/dinnertime/dinnertime_selection.gd` | 202 | 4 | 0 |  |
| `core/rules/phase/dinnertime/dinnertime_settlement_impl.gd` | 212 | 4 | 0 | uses:DinnertimeHouseSales,uses:DinnertimeEffects |
| `core/rules/phase/dinnertime/dinnertime_house_sales.gd` | 281 | 8 | 0 | helper:dinnertime_house_sales,uses:DinnertimeSelection |
| `core/rules/phase/dinnertime_settlement.gd` | 37 | 2 | 0 |  |
| `core/rules/phase/marketing/marketing_instances_validation.gd` | 96 | 1 | 0 |  |
| `core/rules/phase/marketing/settlement_demand_effects.gd` | 160 | 2 | 0 |  |
| `core/rules/phase/marketing/settlement_house_demand.gd` | 96 | 1 | 0 |  |
| `core/rules/phase/marketing/settlement_helpers.gd` | 31 | 1 | 0 |  |
| `core/rules/phase/marketing/settlement_helpers_impl.gd` | 33 | 4 | 0 |  |
| `core/rules/phase/marketing/settlement_instance_expiration.gd` | 52 | 1 | 0 |  |
| `core/rules/phase/marketing/settlement_products.gd` | 35 | 0 | 0 |  |
| `core/rules/phase/marketing_settlement.gd` | 228 | 4 | 0 |  |
| `core/rules/phase/payday/payday_salary_discount.gd` | 52 | 1 | 0 | helper:payday_salary_discount |
| `core/rules/phase/payday/payday_salary_token_payment.gd` | 91 | 1 | 0 | helper:payday_salary_token_payment |
| `core/rules/phase/payday_settlement.gd` | 204 | 6 | 0 | uses:MilestoneEffectQueries |
| `core/rules/placement_conflict_registry.gd` | 133 | 0 | 0 |  |
| `core/rules/pricing_pipeline.gd` | 180 | 3 | 0 | uses:IntValueParseHelpers,uses:MilestoneEffectQueries |
| `core/rules/settlement_registry.gd` | 159 | 1 | 0 | uses:AutoloadAccess |
| `core/rules/working/mandatory_actions_rules.gd` | 169 | 1 | 0 |  |
| `core/state/game_state.gd` | 230 | 2 | 0 |  |
| `core/state/game_state_factory.gd` | 209 | 5 | 0 |  |
| `core/state/game_state_serialization.gd` | 226 | 5 | 0 |  |
| `core/state/serialization/json_safe.gd` | 25 | 0 | 0 |  |
| `core/state/serialization/parse_helpers.gd` | 70 | 0 | 0 |  |
| `core/state/serialization/round_state_parser.gd` | 37 | 3 | 0 | helper:round_state_parser_wrapper |
| `core/state/serialization/round_state_parser_optional_fields.gd` | 214 | 2 | 0 | helper:round_state_parser_optional,uses:ParseHelpers |
| `core/state/serialization/round_state_parser_required_fields.gd` | 80 | 2 | 0 | helper:round_state_parser_required,uses:ParseHelpers |
| `core/state/serialization/round_state_player_id_keys.gd` | 10 | 0 | 0 | helper:round_state_player_id_keys |
| `core/state/serialization/value_decoder.gd` | 92 | 1 | 0 |  |
| `core/state/state_schema_registry.gd` | 263 | 0 | 0 |  |
| `core/state/state_updater/batch.gd` | 103 | 2 | 0 |  |
| `core/state/state_updater/cash.gd` | 162 | 0 | 0 |  |
| `core/state/state_updater/collections.gd` | 72 | 0 | 0 |  |
| `core/state/state_updater/employees_and_milestones.gd` | 118 | 1 | 0 |  |
| `core/state/state_updater/inventory.gd` | 91 | 0 | 0 |  |
| `core/state/state_updater.gd` | 102 | 5 | 0 |  |
| `core/types/command.gd` | 184 | 1 | 0 | uses:JsonValueParseHelpers |
| `core/types/result.gd` | 131 | 0 | 0 |  |
| `core/utils/catalog_registry_helpers.gd` | 40 | 0 | 0 |  |
| `core/utils/int_value_parse_helpers.gd` | 37 | 0 | 0 |  |
| `core/utils/json_value_parse_helpers.gd` | 23 | 0 | 0 |  |
| `core/utils/range_utils.gd` | 67 | 2 | 0 |  |
| `core/utils/range_utils_air.gd` | 94 | 0 | 0 |  |
| `core/utils/range_utils_road.gd` | 38 | 2 | 0 | helper:range_utils_road_wrapper |
| `core/utils/range_utils_road/adjacent_cells.gd` | 58 | 1 | 0 | helper:range_utils_road_adjacent |
| `core/utils/range_utils_road/distance_queries.gd` | 205 | 3 | 0 | helper:range_utils_road_distance |
| `core/utils/round_state_counters.gd` | 146 | 0 | 0 |  |
| `core/utils/type_helpers.gd` | 34 | 0 | 0 |  |

## 附录 B：逐文件备注（非测试）

说明：每个文件只记录 1-3 条“值得关注的结构性点”；若未见明显问题则标注为职责单一。

### actions/

- `core/actions/action_availability_registry.gd`：中等体量；后续可按重构优先级处理
- `core/actions/action_executor.gd`：（已部分整改 2026-01-26）移除自带 `_parse_int_value`，改用 `IntValueParseHelpers`；中等体量；后续可按重构优先级处理
- `core/actions/action_registry.gd`：包含 UI 语义：`get_player_initiatable_actions(...)` 判定“可启动动作”（隐式契约）；（已整改 2026-01-26）缺参判定统一走 `Result.ErrorCode.MISSING_PARAMS`（避免错误文案做控制流）；（已整改 2026-01-27）查询/过滤逻辑已抽离到 `action_registry_queries.gd`（ActionRegistry 主体更聚焦于注册/校验器）；（已整改 2026-01-27）日志输出改为通过 `AutoloadAccess` 动态访问 `GameLog`（避免直接引用 Autoload 全局变量）
- `core/actions/action_registry_queries.gd`：（已新增 2026-01-27）ActionRegistry 查询/过滤辅助（按 phase/player 过滤动作），用于降低 `ActionRegistry` 单文件职责与体积

### data/

- `core/data/employee_def.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/employee_def/debug.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/employee_def/parser.gd`：（已整改 2026-01-27）orchestrator wrapper；核心字段与可选字段解析分别在 `parser/core_fields.gd` 与 `parser/optional_fields.gd`（降低单文件体积，便于维护字段组合约束）
- `core/data/employee_def/parser/core_fields.gd`：（已新增 2026-01-27）核心字段解析（id/name/role/range/train/tags/usage_tags/recruit_capacity 组合约束），依赖 `DataParseHelpers`
- `core/data/employee_def/parser/optional_fields.gd`：（已新增 2026-01-27）可选字段解析（mandatory/can_be_fired/marketing_max_duration/produces/pool/effect_ids），依赖 `DataParseHelpers`
- `core/data/employee_def/serialization.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/employee_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/game_config.gd`：（已部分整改 2026-01-26）通用 `_parse_*` 已改为复用 `ParseHelpers`，仅保留业务专用 `_parse_reserve_cards`；中等体量；后续可按重构优先级处理
- `core/data/game_data.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/marketing_def.gd`：（已整改 2026-01-26）移除自带 `_parse_*`，改用 `DataParseHelpers`
- `core/data/marketing_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/milestone_def.gd`：（已整改 2026-01-27）`from_dict(...)` 严格解析/校验抽离到 `core/data/milestone_def_parser.gd`；`trigger.filter` 匹配抽离到 `core/data/milestone_trigger_filter.gd`；本文件更聚焦于数据模型/序列化/匹配 API
- `core/data/milestone_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/parse_helpers.gd`：（已新增 2026-01-26）用于收敛 `core/data/*` 内重复解析样板
- `core/data/product_def.gd`：（已整改 2026-01-26）移除自带 `_parse_*`，改用 `DataParseHelpers`
- `core/data/product_registry.gd`：未发现明显结构问题（小文件/职责相对单一）

### debug/

- `core/debug/debug_command_registry.gd`：（已整改 2026-01-26）class_name 兼容 shim（用于 global_script_class_cache/旧路径）；实际实现位于 `ui/debug/debug_command_registry.gd`
- `core/debug/debug_commands/action_commands.gd`：（已整改 2026-01-26）兼容 shim；实际实现位于 `ui/debug/debug_commands/action_commands.gd`
- `core/debug/debug_commands/game_commands.gd`：（已整改 2026-01-26）兼容 shim；实际实现位于 `ui/debug/debug_commands/game_commands.gd`
- `core/debug/debug_commands/state_commands.gd`：（已整改 2026-01-26）兼容 shim；实际实现位于 `ui/debug/debug_commands/state_commands.gd`
- `core/debug/debug_commands/util_commands.gd`：（已整改 2026-01-26）兼容 shim；实际实现位于 `ui/debug/debug_commands/util_commands.gd`
- `core/debug/perf_trace.gd`：（已整改 2026-01-26）实现已移至 `tools/perf_trace.gd`；core/debug 保留 shim（用于稳定引用路径）

### engine/

- `core/engine/game_constants.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/game_defaults.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/game_engine.gd`：偏长脚本；建议按职责拆分；preload 依赖较多（耦合偏高）；（已整改 2026-01-27）EventBus 访问改为通过 `AutoloadAccess` 动态获取（并保留可注入 `event_sink`），降低对 Autoload 全局变量的硬依赖；（已整改 2026-01-26）为不变量 baseline 增加公开 setter，避免外部直接写私有 `_initial_*`；（已整改 2026-01-26）提供 `clear_event_history_for_new_session()` 收敛“新对局清空 EventBus.history”样板；（已整改 2026-01-26）提供 `emit_event(...)` wrapper 收敛 `EventBus.emit_event(...)` 直连；（已整改 2026-01-26）增加可注入 `event_sink`，并让 history clear/rebuild 也优先走 sink，降低对 EventBus 的硬依赖；（已整改 2026-01-27）命令索引推导逻辑已抽离到 `core/engine/game_engine/command_index_queries.gd`；（已整改 2026-01-27）回退/回放主流程已抽离到 `core/engine/game_engine/rewind_ops.gd`
- `core/engine/game_engine/command_index_queries.gd`：（已新增 2026-01-27）抽离 UI 回退相关的命令索引推导（phase_start / player_turn_start / replay 推导），用于缩短 `game_engine.gd` 并减少重复逻辑
- `core/engine/game_engine/action_setup.gd`：已改为委托 `gameplay/action_setup.gd`（移除 core 内对 gameplay/actions 的 preload）；（已整改 2026-01-26）provider 来源改为 `ProjectSettings.fcm/action_setup_provider_path`（仍可用 `ActionSetup.set_provider_path(...)` 覆盖），避免 core 内硬编码 gameplay 路径
- `core/engine/game_engine/action_wiring.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/game_engine/archive.gd`：（已整改 2026-01-27）日志输出改为通过 `AutoloadAccess` 动态访问 `GameLog`（降低对 Autoload 全局变量的硬依赖）
- `core/engine/game_engine/auto_advance.gd`：（已整改 2026-01-27）class_name + 对外 API wrapper；实现委托 `auto_advance_impl.gd`
- `core/engine/game_engine/auto_advance_impl.gd`：（已整改 2026-01-27）聚合转发（对外仍通过 `AutoAdvance.drain/try_advance_one` 调用）；推进决策拆分到 `auto_advance_try_step.gd`/`auto_advance_phase_blocking.gd`/`auto_advance_working_mandatory.gd`/`auto_advance_order_of_business_round1.gd`
- `core/engine/game_engine/auto_advance_try_step.gd`：（已新增 2026-01-27）AutoAdvance 决策主流程：按 phase 判定并调用 PhaseManager 执行推进；依赖 action_registry 查询/执行强制动作
- `core/engine/game_engine/auto_advance_phase_blocking.gd`：（已新增 2026-01-27）推进阻断检查：读取 `round_state.pending_phase_actions` 并判断是否阻断；包含“结算阶段是否默认跳过”的判定
- `core/engine/game_engine/auto_advance_working_mandatory.gd`：（已新增 2026-01-27）Working 阶段强制动作补完：可无参自动执行的定价/折扣/奢侈品（避免阻断 auto-advance）
- `core/engine/game_engine/auto_advance_order_of_business_round1.gd`：（已新增 2026-01-27）首轮 OrderOfBusiness 自动 finalize：基于 `previous_turn_order` 写入 picks 并落地 turn_order
- `core/engine/game_engine/checkpoints.gd`：（已整改 2026-01-27）日志/verbose 开关读取改为通过 `AutoloadAccess` 动态访问 `GameLog`/`DebugFlags`（降低对 Autoload 全局变量的硬依赖）；仍含调试/发布差异分支（OS.has_feature）
- `core/engine/game_engine/command_runner.gd`：（已部分整改 2026-01-26）事件构建已下沉到 `gameplay/replay/command_runner_event_build.gd`（并由 `ProjectSettings.fcm/command_runner_event_build_provider_path` 提供），主流程更聚焦于命令执行/auto-advance/invariants/checkpoint/emit；（已整改 2026-01-27）对 `EventBus`/`GameLog`/`DebugFlags` 的访问改为通过 `AutoloadAccess` 动态获取（并将 `EventBus.EventType.*` 改为字符串常量），降低对 Autoload 全局变量的硬依赖；仍含调试/发布差异分支（OS.has_feature）；（已整改 2026-01-26）事件发射改为调用 `engine.emit_event(...)` wrapper，避免直连 `EventBus.emit_event(...)`
- （已移出 core 2026-01-26）`gameplay/replay/command_runner_event_build.gd`：从 `CommandRunner` 抽离的派生事件构建（report/拆分事件/marketing 到期/cleanup 丢弃等，偏日志/展示语义）；（已部分整改 2026-01-27）已将 Dinnertime/Marketing/Cleanup/OrderOfBusiness/Payday 的事件推导按 phase 拆到 `gameplay/replay/command_runner_event_build/`；（已部分整改 2026-01-27）`DINNERTIME_REPORT` 已下沉到 `gameplay/replay/command_runner_event_build/dinnertime_events.gd`；（已部分整改 2026-01-27）`ROUND_STARTED`/`ROUND_ENDED` 已下沉到 `gameplay/replay/command_runner_event_build/round_events.gd`；后续若仍需继续拆分，可考虑将 `SUB_PHASE_CHANGED` 也独立为子模块
- `core/engine/game_engine/diagnostics.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/game_engine/event_history_rebuild.gd`：（已整改 2026-01-27）`EventBus.EventType.*` 改为使用事件 type 字符串，降低对 Autoload 全局变量的硬依赖；（已部分整改 2026-01-26）debug_force 判定统一复用 `Replay.should_force_execute_in_replay(...)`（移除本文件内重复/分支判断）
- （已移出 core 2026-01-26）`gameplay/replay/event_timeline_build.gd`：`GAME_STARTED` 事件数据统一由 `GameStartedEventBuild` 构建（缺少初始 checkpoint 时仅 warning，不阻塞时间线构建）；复用 `timeline_event_helpers.gd` 统一写入 `sequence/timestamp/command_index`（减少重复/样板）；依赖 EventBus（日志/UI 耦合）
- `core/engine/game_engine/game_started_event_build.gd`：（已新增 2026-01-26）抽离 `GAME_STARTED` 事件字段构建（initializer/event_timeline_build/step_timeline_build 共用），避免字段/计算方式漂移
- `core/engine/game_engine/initializer.gd`：（已部分整改 2026-01-26）`GAME_STARTED` 事件数据统一由 `GameStartedEventBuild` 构建；中等体量；存在一定数量的 preload 依赖；（已整改 2026-01-27）日志/事件类型改为通过 `AutoloadAccess`/字符串常量处理，降低对 Autoload 全局变量的硬依赖；（已整改 2026-01-26）不再直接写 `engine._initial_*`，改用公开 setter；（已整改 2026-01-26）EventBus.history 清空逻辑改为调用 `engine.clear_event_history_for_new_session()`；（已整改 2026-01-26）`GAME_STARTED` 事件发射改为调用 `engine.emit_event(...)` wrapper
- `core/engine/game_engine/invariants.gd`：中等体量；后续可按重构优先级处理
- `core/engine/game_engine/loader.gd`：（已部分整改 2026-01-26）移除自带 `_parse_int_value`，改用 `JsonValueParseHelpers`；（已整改 2026-01-27）日志输出改为通过 `AutoloadAccess` 动态访问 `GameLog`（降低对 Autoload 全局变量的硬依赖）；含调试/发布差异分支（OS.has_feature）；（已整改 2026-01-26）不再直接写 `engine._initial_*`，改用公开 setter；（已整改 2026-01-26）EventBus.history 清空逻辑改为调用 `engine.clear_event_history_for_new_session()`
- `core/engine/game_engine/modules_v2.gd`：中等体量；preload 依赖较多（耦合偏高）；（已整改 2026-01-27）catalog/config 校验逻辑已抽离到 `modules_v2_validations.gd`
- `core/engine/game_engine/modules_v2_validations.gd`：（已新增 2026-01-27）ModulesV2 校验辅助（catalog/config 结构校验），用于降低 `modules_v2.gd` 单文件职责与体积
- `core/engine/game_engine/replay.gd`：中等体量；后续可按重构优先级处理；含调试/发布差异分支（OS.has_feature）；（已部分整改 2026-01-26）checkpoint.rng_calls 解析共用 `JsonValueParseHelpers`
- （已移出 core 2026-01-26）`gameplay/replay/step_timeline_build.gd`（wrapper） + `gameplay/replay/step_timeline_build/build_full_impl.gd`：`GAME_STARTED` 事件数据统一由 `GameStartedEventBuild` 构建；debug_force 判定统一复用 `Replay.should_force_execute_in_replay(...)`；复用 `timeline_event_helpers.gd` 统一写入事件 envelope（`sequence/timestamp/command_index/step_index/phase_segment`）（减少重复/样板）；时间线/日志“派生视图”构建逻辑很重；（已部分整改 2026-01-27）将 step dict/事件封装/阶段归属等内部 helper 抽离到 `gameplay/replay/step_timeline_build/helpers.gd`；（已部分整改 2026-01-27）将 `_build_full_impl(...)` 的回放/分段主流程迁移到 `gameplay/replay/step_timeline_build/build_full_impl.gd` 并让 `step_timeline_build.gd` 保留 wrapper；后续仍可继续按“命令回放/auto-advance 分段/flush pending”拆分 build_full_impl；依赖 EventBus（日志/UI 耦合）；（已整改 2026-01-26：不再跨文件调用 CommandRunner/PhaseManager 的私有 `_` 前缀方法）
- （已移出 core 2026-01-26）`gameplay/replay/timeline_event_helpers.gd`：收敛时间线事件 envelope 字段写入（`sequence`/`timestamp`/`command_index`/`step_index`/`phase_segment`），供 `event_timeline_build.gd`/`step_timeline_build.gd` 等复用（减少重复/样板）
- `core/engine/phase_manager.gd`：（已整改 2026-01-27）移除未使用的 preload 依赖（减少耦合/噪音）；移除未被使用的静态 defs wrapper（保留 `compute_timestamp(...)`），减少重复 API，降低单文件体积
- `core/engine/phase_manager/advance_phase.gd`：中等体量；后续可按重构优先级处理；（已整改 2026-01-27）日志输出改为通过 `AutoloadAccess` 动态访问 `GameLog`（降低对 Autoload 全局变量的硬依赖）
- `core/engine/phase_manager/advance_sub_phase.gd`：中等体量；后续可按重构优先级处理；（已整改 2026-01-27）日志输出改为通过 `AutoloadAccess` 动态访问 `GameLog`（降低对 Autoload 全局变量的硬依赖）
- `core/engine/phase_manager/advancement.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/phase_manager/definitions.gd`：中等体量；后续可按重构优先级处理
- `core/engine/phase_manager/hooks.gd`：中等体量；后续可按重构优先级处理；（已整改 2026-01-27）日志/调试开关读取改为通过 `AutoloadAccess` 动态访问 `GameLog`/`DebugFlags`（降低对 Autoload 全局变量的硬依赖）
- `core/engine/phase_manager/order_config.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/phase_manager/settlement_triggers.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/phase_manager/working_flow.gd`：（已整改 2026-01-26）移除 `_parse_non_negative_int_value` wrapper，直接调用 `IntValueParseHelpers`；（已整改 2026-01-26）里程碑 effects 的 value 求和改用 `MilestoneEffectQueries.sum_non_negative_int_values(...)`（减少重复/样板）；（已部分整改 2026-01-27）OrderOfBusiness 相关 fail-fast 改为返回 `Result.failure`（不再依赖 assert；release 下也生效）

### map/

 - `core/map/house_number_manager.gd`：（已整改 2026-01-27）将多处 `assert` fail-fast 改为返回 `Result.failure` 并在调用链中显式传播（release 下也生效）；中等体量；后续仍可按重构优先级继续拆分
- `core/map/map_baker/bake.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_baker/boundary_index.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_baker/cells.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_baker/debug.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_baker/queries.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_baker/tile_baking.gd`：（已整改 2026-01-27）将 printed_structures/drink_sources 的多处 `assert` fail-fast 改为返回 `Result.failure`（fail-fast 在 release 下也生效）；中等体量；后续仍可按重构优先级处理
- `core/map/map_context_builder.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_def.gd`：（已整改 2026-01-27）`from_dict(...)` 解析/校验已抽离到 `map_def_parser.gd`（降低 map 数据模型与解析耦合）；其余查询/编辑/验证仍在本文件
- `core/map/map_def_parser.gd`：（已新增 2026-01-27）MapDef 严格解析/校验（复用 `MapParseHelpers`）；供 `MapDef.from_dict(...)` 调用
- `core/map/map_option_def.gd`：（已部分整改 2026-01-26）移除 `_SELF_SCRIPT.new()` 自 preload 创建实例，改为直接 `MapOptionDef.new()`；（已整改 2026-01-26）tiles placements 解析改为复用 `MapParseHelpers.parse_tile_placements(...)`（减少重复解析样板）；（已整改 2026-01-26）移除自带 `_parse_*` wrapper，改为直接调用 `MapParseHelpers`（继续收敛解析样板）
- `core/map/map_runtime/baked_map.gd`：（已整改 2026-01-26）移除自带 `_parse_*` wrapper，改为直接调用 `MapParseHelpers`（继续收敛解析样板）
- `core/map/map_runtime/cells.gd`：（已整改 2026-01-26）补充 `try_parse_pos_key(...)`/`sorted_positions_from_external_cells(...)`，用于收敛 external_cells 的 key->pos 解析；小文件/职责相对单一
- `core/map/map_runtime/coords.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_runtime/road_graph_cache.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_runtime/structures.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_runtime/tile_edit.gd`：中等体量；后续可按重构优先级处理
- `core/map/map_utils.gd`：中等体量；后续可按重构优先级处理
- `core/map/marketing_placement_query.gd`：中等体量；后续可按重构优先级处理
- `core/map/parse_helpers.gd`：（已部分整改 2026-01-26）扩展 `parse_vec2i_array`/`parse_rotation_array` 并用于 `TileDef`/`PieceDef`；（已整改 2026-01-26）新增 `parse_tile_placements(...)` 并用于 `MapDef`/`MapOptionDef`；（已整改 2026-01-26）新增 `parse_road_grid(...)`/`parse_drink_sources(...)`/`parse_printed_structures(...)` 并用于 `TileDef`；（已整改 2026-01-26）新增 `parse_footprint_mask(...)` 并用于 `PieceDef`，进一步收敛地图解析样板代码
- `core/map/piece_def.gd`：（已部分整改 2026-01-26）解析样板已开始收敛到 `MapParseHelpers`；（已整改 2026-01-27）将 `from_dict(...)` 的严格解析抽离到 `piece_def_parser.gd`，本文件更聚焦于数据模型/查询/校验；体积已下降但仍可继续按“工厂方法/序列化/调试方法”等职责拆分
- `core/map/piece_def_parser.gd`：（已新增 2026-01-27）PieceDef 的 Dictionary 严格解析/校验（用于缩短 `piece_def.gd` 并集中维护错误信息与字段规则）
- `core/map/piece_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/placement_validator/garden_attachment.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/placement_validator/map_access.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/placement_validator/placement.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/placement_validator/restaurant_placement.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/placement_validator/road_utils.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/placement_validator/validators.gd`：中等体量；后续可按重构优先级处理
- `core/map/road_graph.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/road_graph/blocks.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/road_graph/builder.gd`：（已整改 2026-01-26）external_cells 的 key->pos 解析下沉至 `core/map/map_runtime/cells.gd`，本文件不再自带 `_parse_*`
- `core/map/road_graph/node_keys.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/road_graph/pathfinding.gd`：（已整改 2026-01-26）补充 `get_nodes_at_pos(...)` 公开 wrapper，用于避免外部调用私有 `_get_nodes_at_pos(...)`
- `core/map/road_graph/range_query.gd`：（已整改 2026-01-26）改用 `Pathfinding.get_nodes_at_pos(...)`，避免跨文件调用私有 `_get_nodes_at_pos(...)`
- `core/map/tile_def.gd`：（已部分整改 2026-01-26）blocked_cells/allowed_rotations/road_grid/drink_sources/printed_structures 解析已改为复用 `MapParseHelpers`（减少重复解析样板）；（已整改 2026-01-26）板块编辑器的编辑方法（road/drink/printed/blocked）移至 `ui/scenes/tools/tile_editor/tile_def_edit.gd`，core 不再包含 tools 专用 API；（已整改 2026-01-27）将 `from_dict(...)` 的严格解析抽离到 `tile_def_parser.gd`，本文件更聚焦于数据模型/序列化/校验/查询；体积已下降但仍可按“工厂方法/序列化/调试方法”等职责继续拆分
- `core/map/tile_def_parser.gd`：（已新增 2026-01-27）TileDef 的 Dictionary 严格解析/校验（用于缩短 `tile_def.gd` 并集中维护错误信息与字段规则）
- `core/map/tile_registry.gd`：未发现明显结构问题（小文件/职责相对单一）

### modules/

- `core/modules/v2/content_catalog.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/content_catalog_loader.gd`：中等体量；后续可按重构优先级处理；存在一定数量的 preload 依赖
- `core/modules/v2/module_dir_spec.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/module_manifest.gd`：（已整改 2026-01-26）移除薄 `_parse_*` wrapper，直接调用 `DataParseHelpers`（仍保持 module.json 语义）
- `core/modules/v2/module_package_loader.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/module_plan_builder.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/pool_builder.gd`：（已部分整改 2026-01-26）移除自带 `_parse_non_negative_int`，改用 `DataParseHelpers`
- `core/modules/v2/ruleset.gd`：中等体量；后续可按重构优先级处理；preload 依赖较多（耦合偏高）；函数数量较多，可能包含多职责/可考虑拆 helper
- `core/modules/v2/ruleset/action_registration.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/ruleset/content_validation.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/ruleset/patches.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/ruleset/phase_hooks.gd`：中等体量；后续可按重构优先级处理
- `core/modules/v2/ruleset/provider_registration.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/ruleset/state_and_order.gd`：中等体量；后续可按重构优先级处理
- `core/modules/v2/ruleset/sub_phase_registration.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/ruleset_builder.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/ruleset_loader.gd`：使用动态 load（可能影响静态分析/可替换性）
- `core/modules/v2/visual_catalog.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/visual_catalog_loader.gd`：（已部分整改 2026-01-26）移除自带 `_parse_int_required`，改用 `DataParseHelpers`；中等体量；后续可按重构优先级处理

### random/

- `core/random/random_manager.gd`：中等体量；后续可按重构优先级处理；函数数量较多，可能包含多职责/可考虑拆 helper

### rules/

- `core/rules/bankruptcy_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/company_structure_rules.gd`：（已整改 2026-01-27）将 `assert` fail-fast 改为返回 `Result.failure`（release 下也生效）；仍为小文件/职责相对单一
- `core/rules/dinnertime_demand_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/dinnertime_route_purchase_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/drinks_procurement.gd`：（已整改 2026-01-27）对外 API wrapper；主流程拆到 `drinks_procurement/plan_resolver.gd`，milestone bonus 计算拆到 `drinks_procurement/milestone_bonuses.gd`（主文件体量下降，耦合更集中/可维护）
- `core/rules/drinks_procurement/default_route_builder.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/drinks_procurement/inputs.gd`：（已整改 2026-01-26）移除自带 `_parse_int`，改用 `JsonValueParseHelpers`
- `core/rules/drinks_procurement/milestone_bonuses.gd`：（已新增 2026-01-27）milestone bonus 计算：`procure_plus_one`/`drinks_per_source_delta`/`distance_plus_one`（延续使用 `MilestoneEffectQueries`/`IntValueParseHelpers` 收敛解析样板）
- `core/rules/drinks_procurement/picked_sources_finder.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/drinks_procurement/plan_resolver.gd`：（已新增 2026-01-27）采购计划解析：餐厅/路线/选点校验，起点餐厅推导，route 校验，沿路线拾取 sources 并按 selected_sources 过滤
- `core/rules/drinks_procurement/route_validator.gd`：存在一定数量的 preload 依赖
- `core/rules/drinks_procurement/start_restaurant_resolver.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/drinks_procurement/tile_route_utils.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/economy/bankruptcy_rules.gd`：中等体量；后续可按重构优先级处理
- `core/rules/effect_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/employee_pool_patch_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/employee_rules.gd`：存在一定数量的 preload 依赖
- `core/rules/employee_rules/action_counts.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/employee_rules/counts.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/employee_rules/employee_array_helpers.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/employee_rules/immediate_train_pending.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/employee_rules/limits.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/employee_rules/salary.gd`：（已整改 2026-01-27）营销员免薪（`marketing_no_salary`）判定改为复用 `MilestoneEffectQueries`（减少 milestones->effects 遍历样板）；其余未发现明显结构问题（小文件/职责相对单一）
- `core/rules/employee_rules/train_slot_usage.gd`：（已整改 2026-01-27）对外 API wrapper；完整实现移至 `train_slot_usage_impl.gd`（降低单文件体积，便于维护/进一步拆分）
- `core/rules/employee_rules/train_slot_usage_impl.gd`：（已整改 2026-01-27）TrainSlotUsage 聚合转发（对外 API 仍保持稳定）；实现拆分到 storage/providers/allocator，便于分别维护 round_state 存储/培训员扫描/分配策略
- `core/rules/employee_rules/train_slot_usage_storage.gd`：（已新增 2026-01-27）round_state 存储层：读写 `train_slot_usage_instances` 并兼容旧版 `train_slot_usage` 总用量（Fail Fast 校验结构）
- `core/rules/employee_rules/train_slot_usage_providers.gd`：（已新增 2026-01-27）培训员来源扫描：从玩家在岗员工中筛出具备 train_capacity 且包含 `use:train` 的员工，并按容量排序
- `core/rules/employee_rules/train_slot_usage_allocator.gd`：（已新增 2026-01-27）分配策略：计算 max_steps、选择可用培训员实例、写回 round_state；用于支持“同一员工必须由同一名培训员继续培训”的偏好参数
- `core/rules/employee_rules/working_multiplier.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/global_effect_list.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/map_generation_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/marketing_initiation_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/marketing_range_calculator.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/marketing_rules.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/marketing_type_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/milestone_effect_queries.gd`：（已新增 2026-01-26）用于收敛“遍历 milestones -> MilestoneDef.effects”样板，供 pricing/settlement/drinks 等复用；（已整改 2026-01-26）新增 sum/max helpers 收敛 `effects[*].value` 的解析/聚合样板
- `core/rules/milestone_effect_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/milestone_system.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/phase/cleanup_settlement.gd`：（已部分整改 2026-01-26）移除自带 `_parse_non_negative_int_value`，改用 `IntValueParseHelpers`；（已整改 2026-01-26）`gain_fridge` 的 “取最大 capacity” 逻辑改用 `MilestoneEffectQueries.max_non_negative_int_value(...)`（减少重复/样板）；中等体量；后续可按重构优先级处理
- `core/rules/phase/dinnertime/dinnertime_distance.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/phase/dinnertime/dinnertime_effects.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/phase/dinnertime/dinnertime_events.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/phase/dinnertime/dinnertime_inventory.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/phase/dinnertime/dinnertime_selection.gd`：（已整改 2026-01-27）将多处 `assert` fail-fast 改为返回 `Result.failure`（fail-fast 在 release 下也生效）；中等体量；后续仍可按重构优先级处理
- `core/rules/phase/dinnertime_settlement.gd`：（已整改 2026-01-27）class_name + 对外 API wrapper；结算实现迁移至 `core/rules/phase/dinnertime/dinnertime_settlement_impl.gd`；并保留 `_apply_*_effects_by_segment(...)` 薄委托供现有测试调用
- `core/rules/phase/dinnertime/dinnertime_settlement_impl.gd`：（已新增 2026-01-27）晚餐结算 orchestrator（调用 `dinnertime_house_sales.gd` + tips/CFO + round_state 报告写入）；体量已下降，后续可按需要继续拆分
- `core/rules/phase/dinnertime/dinnertime_house_sales.gd`：（已新增 2026-01-27）逐房屋售卖主循环（variants 选择/选店/route purchase/扣库存/支付/写入 sales&skipped 报告）；中等体量但职责更聚焦，后续可按需要继续拆分
- `core/rules/phase/marketing/marketing_instances_validation.gd`：（已新增 2026-01-26）抽离 MarketingSettlement 的 marketing_instances 校验/归一化逻辑（减少单文件职责/缩短脚本）
- `core/rules/phase/marketing/settlement_helpers.gd`：（已整改 2026-01-27）class_name + 对外 API wrapper；完整实现移至 `settlement_helpers_impl.gd`（降低单文件体积，便于维护/进一步拆分）
- `core/rules/phase/marketing/settlement_helpers_impl.gd`：（已整改 2026-01-27）实现已进一步拆分到 `settlement_instance_expiration.gd`/`settlement_products.gd`/`settlement_house_demand.gd`/`settlement_demand_effects.gd`；本文件仅保留聚合转发（降低单文件体积）
- `core/rules/phase/marketing/settlement_instance_expiration.gd`：（已新增 2026-01-27）营销实例到期处理（回收板件/释放 busy_marketers）；职责单一
- `core/rules/phase/marketing/settlement_products.gd`：（已新增 2026-01-27）营销实例的产品序列解析（primary + products）；职责单一
- `core/rules/phase/marketing/settlement_house_demand.gd`：（已新增 2026-01-27）需求写入（cap/花园/倍增）与房屋排序；职责单一
- `core/rules/phase/marketing/settlement_demand_effects.gd`：（已新增 2026-01-27）营销需求数量/现金奖金 effects 计算（遍历 milestones -> effect_registry.invoke）；后续可考虑进一步收敛“milestone 扫描”样板
- `core/rules/phase/marketing_settlement.gd`：（已整改 2026-01-26）将 marketing_instances 校验/归一化抽离到 `marketing_instances_validation.gd`（减少单文件职责/缩短脚本）；其余结算/需求生成/到期清理仍可按职责继续拆分
- `core/rules/phase/payday_settlement.gd`：（已整改 2026-01-27）将“薪资 token 支付”与“薪资折扣容量推导”拆到 `core/rules/phase/payday/`，主文件更聚焦在 orchestrator（按玩家结算/写入 round_state.payday 报告/触发里程碑）；仍包含较多 Payday 规则分支，但体量已下降
- `core/rules/phase/payday/payday_salary_discount.gd`：（已新增 2026-01-27）薪资折扣容量推导：遍历在岗员工 effect_ids 并通过 effect_registry.invoke 累计 `salary_discount_recruit_capacity`
- `core/rules/phase/payday/payday_salary_token_payment.gd`：（已新增 2026-01-27）薪资 token 支付：基于 ProductDef tags 统计/扣减可用 food/drink token（排除 `salary_token_ineligible`）
- `core/rules/placement_conflict_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/pricing_pipeline.gd`：（已部分整改 2026-01-26）移除自带 `_parse_*`，改用 `IntValueParseHelpers`；（已整改 2026-01-26）`base_price_delta` 的 value 求和改用 `MilestoneEffectQueries.sum_int_values(...)`（减少重复/样板）；中等体量；后续可按重构优先级处理
- `core/rules/settlement_registry.gd`：（已整改 2026-01-27）warn/debug 判定改为通过 `AutoloadAccess` 动态访问 `GameLog`/`DebugFlags`（避免直接引用 Autoload 全局变量；行为不变）；含调试/发布差异分支（AutoloadAccess.is_debug_mode -> DebugFlags/OS.has_feature）
- `core/rules/working/mandatory_actions_rules.gd`：未发现明显结构问题（小文件/职责相对单一）

### state/

- `core/state/game_state.gd`：中等体量；后续可按重构优先级处理
- `core/state/game_state_factory.gd`：（已整改 2026-01-26）logo 分配已委托 provider（`gameplay/setup/restaurant_logo_assignment.gd`），并由 `ProjectSettings.fcm/restaurant_logo_assignment_provider_path` 注入，减少 core/state 的 UI/setup 语义；中等体量；存在一定数量的 preload 依赖
- `core/state/game_state_serialization.gd`：（已整改 2026-01-26）移除自带 `_parse_*` wrapper，改为直接调用 `ParseHelpers`/`RoundStateParser`（收敛 state 解析样板）；中等体量；后续可按重构优先级处理；存在一定数量的 preload 依赖
- `core/state/serialization/json_safe.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/serialization/parse_helpers.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/serialization/round_state_parser.gd`：（已整改 2026-01-27）orchestrator wrapper；required/optional 字段解析拆到 `round_state_parser_required_fields.gd`/`round_state_parser_optional_fields.gd`；玩家 id key 归一化收敛到 `round_state_player_id_keys.gd`
- `core/state/serialization/round_state_parser_required_fields.gd`：（已新增 2026-01-27）round_state 必须字段解析（mandatory_actions_completed/sub_phase_passed/action_counts）；复用 `ParseHelpers` 与 player_id key 归一化 helper
- `core/state/serialization/round_state_parser_optional_fields.gd`：（已新增 2026-01-27）round_state 可选字段解析（price_modifiers/immediate_train_pending/counters/train_* 等）；复用 `ParseHelpers` 与 player_id key 归一化 helper
- `core/state/serialization/round_state_player_id_keys.gd`：（已新增 2026-01-27）player_id key 解析/归一化辅助（字符串 int -> int，统一错误信息）
- `core/state/serialization/value_decoder.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/state_schema_registry.gd`：中等体量；后续可按重构优先级处理
- `core/state/state_updater.gd`：存在一定数量的 preload 依赖；（已整改 2026-01-26）改用 `CashOps.get_balance/modify_balance` wrapper，避免跨文件调用私有 `_get_balance/_modify_balance`
- `core/state/state_updater/batch.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/state_updater/cash.gd`：（已整改 2026-01-26）补充 `get_balance(...)`/`modify_balance(...)` 公开 wrapper，用于避免外部调用私有 `_get_balance/_modify_balance`
- `core/state/state_updater/collections.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/state_updater/employees_and_milestones.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/state_updater/inventory.gd`：未发现明显结构问题（小文件/职责相对单一）

### types/

- `core/types/command.gd`：（已部分整改 2026-01-26）移除自带 `_parse_int_value`，改用 `JsonValueParseHelpers`；（已整改 2026-01-27）required 字段解析收敛到 `_parse_required_*` helpers，减少“字段存在性 + 类型校验”样板
- `core/types/result.gd`：未发现明显结构问题（小文件/职责相对单一）

### utils/

- `core/utils/autoload_access.gd`：（已新增 2026-01-27）Autoload 访问/日志/DebugFlags 查询辅助（可选依赖），用于让 core/engine 避免直接引用 Autoload 全局变量
- `core/utils/catalog_registry_helpers.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/utils/int_value_parse_helpers.gd`：（已新增 2026-01-26）用于收敛 rules/milestone effects 的整值解析样板
- `core/utils/json_value_parse_helpers.gd`：（已新增 2026-01-26）用于收敛存档/回放/命令解析中的 JSON 数值校验样板
- `core/utils/range_utils.gd`：（已整改 2026-01-27）对外 API wrapper；road/air 实现分别落在 `range_utils_road.gd`/`range_utils_air.gd`（降低单文件体积，便于维护）
- `core/utils/range_utils_road.gd`：（已新增 2026-01-27）对外 wrapper；实现已拆分至 `core/utils/range_utils_road/adjacent_cells.gd` 与 `core/utils/range_utils_road/distance_queries.gd`（便于维护/复用）
- `core/utils/range_utils_road/adjacent_cells.gd`：（已新增 2026-01-27）邻接道路格计算（支持 external_cells）；小文件/职责单一
- `core/utils/range_utils_road/distance_queries.gd`：（已新增 2026-01-27）道路距离/范围查询（min_distance/within_range，含 drive_thru 入口点扩展）；中等体量；后续若继续拆分可按“目标点归一化/餐厅入口点计算/距离查询”分层
- `core/utils/range_utils_air.gd`：（已新增 2026-01-27）空中范围实现（Manhattan 距离）；小文件/职责单一
- `core/utils/round_state_counters.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/utils/type_helpers.gd`：未发现明显结构问题（小文件/职责相对单一）
