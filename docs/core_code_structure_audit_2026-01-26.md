# core/ GDScript 结构问题清单（用于后续重构）

更新时间：2026-01-26  
审计范围：`core/**/*.gd`  
说明：本报告以“可维护性/层次边界/重复逻辑/过度耦合”为主，目的是为后续逐步重构提供抓手与文件定位；不在本次直接改代码。

## 快速指标（非测试脚本）

- 非测试脚本：169 个，约 26,683 行（`wc -l`）
- 其中：
  - `core/rules/`：45 文件 / 6,505 行
  - `core/engine/`：27 文件 / 5,655 行
  - `core/map/`：35 文件 / 4,615 行
  - `core/modules/`：19 文件 / 2,798 行
  - `core/state/`：14 文件 / 2,063 行
  - `core/data/`：13 文件 / 1,686 行
  - `core/debug/`：6 文件 / 1,439 行

> 注：`core/tests/**/*.gd` 共 103 个脚本（未作为本报告的重点整改对象；若后续要统一测试基建/fixture，可单独再做一次测试目录审计）。

---

## 整改日志

- 2026-01-26：移除 `ProductDef`/`ModuleManifest` 的“自 load 创建实例”写法，改为直接 `new()`；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：新增 `ActionExecutor.apply_changes_in_place(...)` 并用于 `AutoAdvance`（避免跨文件调用私有 `_apply_changes`）；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
- 2026-01-26：为 `CommandRunner`/`PhaseManager` 增加公开 wrapper（`build_*`/`drain_auto_advances`/`is_settlement_scheduled`），并替换 `StepTimelineBuild`/`EventHistoryRebuild` 中跨文件调用私有 `_` 前缀方法；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）
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
- 2026-01-26：将 `CommandRunner` 的事件构建（report 拆分/marketing 到期/cleanup 丢弃等）抽离到 `core/engine/game_engine/command_runner_event_build.gd`，并为 `CommandRunner` 增加公开 `build_*` wrapper，替换 gameplay phase/skip actions 与 `MarketingDemandGeneratedEventTest` 中对私有 `_build_*` 的直接调用；`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60` PASS；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` PASS（119/119）

---

## 1) 超长脚本 / 职责过载（维护成本高）

下列文件普遍存在“单文件承担多个职责”的情况，阅读与修改成本显著偏高（不仅是行数问题，更是职责边界问题）：

- `core/engine/game_engine/command_runner.gd`（~215 LOC） + `core/engine/game_engine/command_runner_event_build.gd`（~464 LOC）
  - （已部分整改 2026-01-26）事件构建已下沉到 `command_runner_event_build.gd`；`CommandRunner` 主流程更聚焦于“命令执行 + auto-advance + 不变量/校验点 + EventBus 发射”。
  - 事件构建逻辑仍包含大量 phase 特例（如 Dinnertime/Payday/Marketing 的 report 与拆分事件），属于“日志/展示语义”，后续可继续按 phase 拆分或外移到 UI/回放子系统。
- `core/engine/game_engine/step_timeline_build.gd`（~630 LOC）
  - 主要是“回放/日志时间线”的语义构建，逻辑复杂且强依赖事件归属规则（phase_segment、step_index、进入/离开阶段的事件归属等）。
  - 这类逻辑更像 UI/回放子系统的“派生视图构建”，放在 core/engine 内会让 engine 边界持续被拉宽。
- `core/rules/phase/dinnertime_settlement.gd`（~536 LOC）
  - 规则编排（房屋遍历/候选餐厅/胜负判定/库存扣减/收入/里程碑/破产）集中在一个文件里，虽然拆了一些子 helper（`dinnertime_*`），但“主 orchestrator”仍然较大。
- `core/debug/debug_commands/action_commands.gd`（~478 LOC）
  - 将大量 debug 命令串在一个文件中；后续继续加 debug 命令时容易进一步膨胀。
- `core/engine/game_engine.gd`（~465 LOC）
  - 引擎主体 + rewind 辅助查询 + EventBus.history 重建桥接逻辑都在一起。
- `core/map/piece_def.gd`（~418 LOC）、`core/map/tile_def.gd`（~417 LOC）、`core/map/map_def.gd`（~354 LOC）
  - 数据模型 + 严格解析 + 验证 +（部分文件还含编辑器/调试方法）揉在一起，导致“修改数据结构”和“修改解析/验证规则”互相影响。
- 其他超过 ~300 行的文件：
  - `core/engine/game_engine/modules_v2.gd`、`core/rules/phase/payday_settlement.gd`、`core/rules/drinks_procurement.gd`、`core/utils/range_utils.gd`、`core/rules/phase/marketing/settlement_helpers.gd`、`core/rules/employee_rules/train_slot_usage.gd`、`core/actions/action_registry.gd`、`core/rules/phase/marketing_settlement.gd`、`core/engine/game_engine/auto_advance.gd`

建议记录（后续重构方向）：
- 先从“职责剥离”入手，而不是单纯按行数拆文件：
  - 命令执行（state 转换） vs 事件构建（日志语义） vs 事件投递（EventBus） vs 自动推进（AutoAdvance）拆成独立组件/模块。
  - 规则文件中将“纯计算/选择”与“写 state/写 round_state 报告/触发 milestone”分层，以便更容易测试与复用。

---

## 2) 重复逻辑 / 重复 helper（难以统一修复）

### 2.1 `_parse_*` 家族重复实现（至少 25 个文件）

表现：
- 在 25 个文件中出现 `static func _parse_*` 系列（int/string/bool/array 等）重复实现。
- 同时仓库已经存在可复用的解析 helper：
  - `core/state/serialization/parse_helpers.gd`
  - `core/map/parse_helpers.gd`
  - （已部分整改 2026-01-26）`core/data/parse_helpers.gd`
  - （已部分整改 2026-01-26）`core/utils/json_value_parse_helpers.gd`

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
 - `core/rules/phase/marketing/settlement_helpers.gd`（叠加 effect_registry 的 invoke）
  - （已部分整改 2026-01-26）上述多数文件已改为复用 `core/rules/milestone_effect_queries.gd` 收敛 milestones->effects 遍历样板（仍有零散 callsite 可继续迁移）

现状矛盾点：
- core 已经存在 `core/rules/milestone_effect_registry.gd`（effects.type -> handler），但仍有大量“手写解析 + 叠加”的路径。

风险：
- 新增/修改 milestone effect 时需要同步修改多个地方，容易出现“同一个 effect_type 在不同系统语义不一致”。

### 2.3 事件构建 / 时间线构建存在交叉引用与重复

表现：
- （已整改 2026-01-26）`core/engine/game_engine/step_timeline_build.gd` 曾直接调用 `CommandRunnerClass._build_*`（私有前缀函数）以及 `engine.phase_manager._is_settlement_scheduled(...)`（私有前缀方法）；现改为 `CommandRunnerClass.build_*` 与 `PhaseManager.is_settlement_scheduled(...)` 公共 wrapper。
- `core/engine/game_engine/event_timeline_build.gd`、`core/engine/game_engine/step_timeline_build.gd`、`core/engine/game_engine/initializer.gd` 都会构建/注入 `GAME_STARTED` 等事件数据（相近但不完全一致）。

风险：
- “私有 API”被跨文件使用，意味着后续想重构 `CommandRunner` 或 `PhaseManager` 的内部实现会被迫同步改多个地方。

---

## 3) 过度耦合 / 层次边界泄漏（core 不够“可复用”）

### 3.1 core 反向依赖 gameplay（层次反转）

- `core/engine/game_engine/action_setup.gd`
  - （已整改 2026-01-26）不再直接 `preload("res://gameplay/actions/*.gd")`；改为委托 `gameplay/action_setup.gd` 提供“内建动作注册”。
  - 仍存在默认 provider 路径对 `gameplay/` 的运行时依赖；（已整改 2026-01-26）已提供 `ActionSetup.set_provider_path(...)` 用于注入/覆盖 provider 路径。

建议（方向）：
- 将 “内建 action wiring / action executor 注册” 移到 `gameplay/`（或更上层），core 只提供 `ActionRegistry` 的 API 与引擎执行能力。
- 或引入“动作提供者/注册回调”的注入点：由 app/gameplay 在初始化时向 engine 提供 executors。

### 3.2 core/engine 对 EventBus/DebugFlags/GameLog 等全局单例有硬依赖

涉及文件（集中在 engine）：
- `core/engine/game_engine/command_runner.gd`（EventBus.emit_event + DebugFlags/OS.has_feature）
- `core/engine/game_engine/loader.gd`、`core/engine/game_engine/initializer.gd`、`core/engine/game_engine.gd`（清空/重建 EventBus.history）

风险：
- 引擎逻辑与 UI/日志系统绑死；做“纯逻辑回放”或“服务器侧模拟”会更难。

### 3.3 ActionRegistry 混入 UI 语义 + 字符串错误消息作为控制流

- `core/actions/action_registry.gd`
  - （已部分整改 2026-01-26）`get_player_initiatable_actions(...)` 优先判断 `Result.error_code == Result.ErrorCode.MISSING_PARAMS`，并保留旧字符串前缀兼容；并同步在常见 gameplay actions/validators 与 UI 缺参判断处逐步推广 error_code（减少对文案的依赖）。

风险：
- 错误文案变更会破坏行为（隐式契约）；也会让 i18n/重构变难。

建议（方向）：
- 把“是否可启动”的判断从 core 移到 gameplay/ui；
- 或在 Result 中引入结构化错误码（而非靠字符串前缀）（已部分整改 2026-01-26）。

### 3.4 私有方法/私有 helper 的跨文件调用（封装破坏）

典型点：
- `core/engine/game_engine/step_timeline_build.gd` / `core/engine/game_engine/event_history_rebuild.gd`：
  - （已整改 2026-01-26）已改用 `CommandRunnerClass.build_*` / `CommandRunnerClass.drain_auto_advances(...)` 等公开 wrapper，不再跨文件调用 `_build_*` / `_drain_auto_advances`。
  - （已整改 2026-01-26）已改用 `PhaseManager.is_settlement_scheduled(...)`，不再跨文件调用 `_is_settlement_scheduled`。
- gameplay phase/skip actions 与相关测试：
  - （已整改 2026-01-26）不再调用 `CommandRunnerClass._build_*` 私有静态方法，改为调用 `CommandRunnerClass.build_*` wrapper。
- `core/engine/game_engine/auto_advance.gd` 调用：
  - （已整改 2026-01-26）原先调用 `executor._apply_changes(...)`；已改为 `executor.apply_changes_in_place(...)`（行为不变，但避免跨文件访问私有方法）

风险：
- 后续想重构接口时，无法在不改调用方的情况下替换内部实现。

---

## 4) “应该放在 module / gameplay / ui / tools 的逻辑”混入 core 的例子

这里不讨论“绝对正确的唯一答案”，只记录目前可见的边界不清晰点（会持续制造耦合）：

- UI/日志派生数据构建在 core/engine：
  - `core/engine/game_engine/command_runner_event_build.gd` 内的大量事件拆分与报告事件（`*_REPORT`、`FOOD_SOLD`、`DEMAND_GENERATED`、`MARKETING_EXPIRED` 等）明显服务于日志/展示语义。
  - `core/engine/game_engine/step_timeline_build.gd` 的 step_index/phase_segment 也偏“展示/回放定位”，不像“引擎最小内核”。
- Debug 命令系统在 core：
  - `core/debug/debug_commands/*.gd` 是应用层调试工具逻辑；如果未来希望 core 作为纯规则库，这一层建议外移或至少隔离成可选模块。
- GameStateFactory 含“Logo 分配”等偏展示/前端选择的确定性逻辑：
  - `core/state/game_state_factory.gd` 中 `restaurant_logo_id` 分配策略（含随机/显式选择合并）更像 game setup/前端选择的结果落盘；放在 core 会让 core 牵涉 UI 资源/规则变化。
- MapDef/TileDef/PieceDef 内含“编辑方法/调试 dump”：
  - 例如 `core/map/tile_def.gd` 明确标注了“用于板块编辑器”的编辑方法，这类逻辑可考虑移到 tools 或 ui/editor 辅助层，避免数据结构类变得“既是模型又是编辑器”。

---

## 5) 代码风格 / 设计层面的可维护性问题（零散但值得统一）

- phase/action 等大量字符串驱动：
  - 例如多个地方直接比较 `"Marketing" / "Dinnertime" / "Working" ...`，容易产生拼写/重命名成本与难以全局替换的问题。
  - 建议逐步迁移到集中定义（constants/enum），并提供转换与校验入口。
- `assert` 与 `Result.failure` 混用导致“release 下校验失效”的风险：
  - 例如 `core/engine/phase_manager/working_flow.gd` 在里程碑 effects 解析与数值解析中大量使用 `assert` 来保证输入合法；若 release 构建关闭 assert，会出现“坏数据变成默认值继续跑”的可能。
  - 依赖“模块系统 strict validation”可以降低风险，但这属于隐式前置条件，建议在关键路径显式说明或统一处理策略。
- 大量 `Dictionary` 结构的手工深层读取/写入：
  - 多文件重复出现 `if not (x is Dictionary)`、`get(..., null)`、`duplicate(true)` 组合，属于结构性样板代码。
  - 已有 `TypeHelpers` / `ParseHelpers` / 若干 query helper（例如 `CatalogRegistryHelpers`、`MarketingPlacementQuery`）但使用不一致，导致全局风格不统一。
- 少量“自加载创建实例”的奇怪模式：
  - （已整改 2026-01-26）`core/data/product_def.gd`、`core/modules/v2/module_manifest.gd` 已从 `load(自身脚本路径).new()` 改为直接 `new()`。

---

## 6) 建议的后续修复顺序（可选路线图）

为降低风险，建议按“先切边界、再收敛重复、最后做结构升级”的顺序推进：

1. **解耦 core ↔ gameplay**：已开始处理 `core/engine/game_engine/action_setup.gd` 的反向依赖（动作注册迁移到 `gameplay/action_setup.gd`，并提供 `ActionSetup.set_provider_path(...)` 注入点）；下一步把 provider 来源做成配置/模块化（避免默认写死 gameplay 路径）。
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
| `core/actions/action_registry.gd` | 324 | 0 | 0 | uses:GameLog |
| `core/data/employee_def/debug.gd` | 22 | 0 | 0 |  |
| `core/data/employee_def/parser.gd` | 213 | 0 | 0 | uses:DataParseHelpers |
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
| `core/debug/debug_command_registry.gd` | 181 | 0 | 0 | uses:GameLog |
| `core/debug/debug_commands/action_commands.gd` | 478 | 0 | 0 | uses:DebugFlags |
| `core/debug/debug_commands/game_commands.gd` | 186 | 0 | 0 | uses:DebugFlags |
| `core/debug/debug_commands/state_commands.gd` | 234 | 0 | 0 |  |
| `core/debug/debug_commands/util_commands.gd` | 220 | 0 | 0 | uses:DebugFlags |
| `core/debug/perf_trace.gd` | 146 | 0 | 0 |  |
| `core/engine/game_constants.gd` | 9 | 0 | 0 |  |
| `core/engine/game_defaults.gd` | 22 | 0 | 0 |  |
| `core/engine/game_engine/action_setup.gd` | 23 | 0 | 1 | delegates:gameplay,uses:GameLog |
| `core/engine/game_engine/action_wiring.gd` | 100 | 2 | 0 |  |
| `core/engine/game_engine/archive.gd` | 127 | 1 | 0 | uses:GameLog |
| `core/engine/game_engine/auto_advance.gd` | 304 | 1 | 0 |  |
| `core/engine/game_engine/checkpoints.gd` | 55 | 0 | 0 | uses:GameLog,uses:DebugFlags |
| `core/engine/game_engine/command_runner.gd` | 215 | 2 | 0 | uses:EventBus,uses:GameLog,uses:DebugFlags,uses:OS.has_feature |
| `core/engine/game_engine/command_runner_event_build.gd` | 464 | 0 | 0 | uses:EventBus |
| `core/engine/game_engine/diagnostics.gd` | 48 | 0 | 0 |  |
| `core/engine/game_engine/event_history_rebuild.gd` | 104 | 1 | 0 | uses:EventBus,uses:OS.has_feature |
| `core/engine/game_engine/event_timeline_build.gd` | 113 | 1 | 0 | uses:EventBus |
| `core/engine/game_engine/initializer.gd` | 266 | 9 | 0 | uses:EventBus,uses:GameLog |
| `core/engine/game_engine/invariants.gd` | 259 | 1 | 0 |  |
| `core/engine/game_engine/loader.gd` | 159 | 3 | 0 | uses:EventBus,uses:GameLog,uses:JsonValueParseHelpers |
| `core/engine/game_engine/modules_v2.gd` | 413 | 22 | 0 |  |
| `core/engine/game_engine/replay.gd` | 188 | 2 | 0 | uses:GameLog,uses:OS.has_feature,uses:JsonValueParseHelpers |
| `core/engine/game_engine/step_timeline_build.gd` | 630 | 4 | 0 | uses:EventBus,uses:OS.has_feature |
| `core/engine/game_engine.gd` | 465 | 13 | 0 | uses:EventBus,uses:OS.has_feature |
| `core/engine/phase_manager/advance_phase.gd` | 240 | 2 | 0 | uses:GameLog |
| `core/engine/phase_manager/advance_sub_phase.gd` | 279 | 2 | 0 | uses:GameLog |
| `core/engine/phase_manager/advancement.gd` | 13 | 2 | 0 |  |
| `core/engine/phase_manager/definitions.gd` | 218 | 0 | 0 |  |
| `core/engine/phase_manager/hooks.gd` | 220 | 1 | 0 | uses:GameLog,uses:DebugFlags |
| `core/engine/phase_manager/order_config.gd` | 152 | 1 | 0 |  |
| `core/engine/phase_manager/settlement_triggers.gd` | 127 | 2 | 0 |  |
| `core/engine/phase_manager/working_flow.gd` | 149 | 3 | 0 | uses:IntValueParseHelpers,uses:MilestoneEffectQueries |
| `core/engine/phase_manager.gd` | 301 | 10 | 0 |  |
| `core/map/house_number_manager.gd` | 233 | 0 | 0 |  |
| `core/map/map_baker/bake.gd` | 80 | 3 | 0 |  |
| `core/map/map_baker/boundary_index.gd` | 22 | 0 | 0 |  |
| `core/map/map_baker/cells.gd` | 22 | 0 | 0 |  |
| `core/map/map_baker/debug.gd` | 41 | 0 | 0 |  |
| `core/map/map_baker/queries.gd` | 43 | 0 | 0 |  |
| `core/map/map_baker/tile_baking.gd` | 280 | 0 | 0 |  |
| `core/map/map_context_builder.gd` | 21 | 1 | 0 |  |
| `core/map/map_def.gd` | 354 | 2 | 0 | defines:_parse_* |
| `core/map/map_option_def.gd` | 177 | 3 | 0 | defines:_parse_* |
| `core/map/map_runtime/baked_map.gd` | 160 | 2 | 0 | defines:_parse_* |
| `core/map/map_runtime/cells.gd` | 95 | 1 | 0 |  |
| `core/map/map_runtime/coords.gd` | 59 | 0 | 0 |  |
| `core/map/map_runtime/road_graph_cache.gd` | 42 | 2 | 0 |  |
| `core/map/map_runtime/structures.gd` | 61 | 1 | 0 |  |
| `core/map/map_runtime/tile_edit.gd` | 215 | 3 | 0 |  |
| `core/map/map_utils.gd` | 239 | 0 | 0 |  |
| `core/map/marketing_placement_query.gd` | 250 | 1 | 0 |  |
| `core/map/parse_helpers.gd` | 52 | 0 | 0 |  |
| `core/map/piece_def.gd` | 418 | 2 | 0 | defines:_parse_* |
| `core/map/piece_registry.gd` | 67 | 2 | 0 |  |
| `core/map/placement_validator/garden_attachment.gd` | 124 | 2 | 0 |  |
| `core/map/placement_validator/map_access.gd` | 40 | 0 | 0 |  |
| `core/map/placement_validator/placement.gd` | 95 | 1 | 0 |  |
| `core/map/placement_validator/restaurant_placement.gd` | 79 | 2 | 0 |  |
| `core/map/placement_validator/road_utils.gd` | 51 | 0 | 0 |  |
| `core/map/placement_validator/validators.gd` | 286 | 1 | 0 |  |
| `core/map/road_graph/blocks.gd` | 75 | 0 | 0 |  |
| `core/map/road_graph/builder.gd` | 119 | 1 | 0 | defines:_parse_* |
| `core/map/road_graph/node_keys.gd` | 18 | 0 | 0 |  |
| `core/map/road_graph/pathfinding.gd` | 158 | 1 | 0 |  |
| `core/map/road_graph/range_query.gd` | 47 | 2 | 0 |  |
| `core/map/road_graph.gd` | 147 | 4 | 0 |  |
| `core/map/tile_def.gd` | 417 | 2 | 0 | defines:_parse_* |
| `core/map/tile_registry.gd` | 63 | 2 | 0 |  |
| `core/modules/v2/content_catalog.gd` | 68 | 0 | 0 |  |
| `core/modules/v2/content_catalog_loader.gd` | 274 | 9 | 0 |  |
| `core/modules/v2/module_dir_spec.gd` | 36 | 0 | 0 |  |
| `core/modules/v2/module_manifest.gd` | 127 | 1 | 0 | uses:DataParseHelpers |
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
| `core/rules/company_structure_rules.gd` | 137 | 1 | 0 |  |
| `core/rules/dinnertime_demand_registry.gd` | 186 | 0 | 0 |  |
| `core/rules/dinnertime_route_purchase_registry.gd` | 174 | 0 | 0 |  |
| `core/rules/drinks_procurement/default_route_builder.gd` | 165 | 4 | 0 |  |
| `core/rules/drinks_procurement/inputs.gd` | 58 | 1 | 0 | uses:JsonValueParseHelpers |
| `core/rules/drinks_procurement/picked_sources_finder.gd` | 45 | 2 | 0 |  |
| `core/rules/drinks_procurement/route_validator.gd` | 121 | 5 | 0 |  |
| `core/rules/drinks_procurement/start_restaurant_resolver.gd` | 89 | 3 | 0 |  |
| `core/rules/drinks_procurement/tile_route_utils.gd` | 83 | 1 | 0 |  |
| `core/rules/drinks_procurement.gd` | 325 | 7 | 0 | uses:IntValueParseHelpers,uses:MilestoneEffectQueries |
| `core/rules/economy/bankruptcy_rules.gd` | 270 | 3 | 0 |  |
| `core/rules/effect_registry.gd` | 67 | 0 | 0 |  |
| `core/rules/employee_pool_patch_registry.gd` | 113 | 0 | 0 |  |
| `core/rules/employee_rules/action_counts.gd` | 55 | 0 | 0 |  |
| `core/rules/employee_rules/counts.gd` | 58 | 3 | 0 |  |
| `core/rules/employee_rules/employee_array_helpers.gd` | 24 | 1 | 0 |  |
| `core/rules/employee_rules/immediate_train_pending.gd` | 149 | 0 | 0 |  |
| `core/rules/employee_rules/limits.gd` | 46 | 2 | 0 |  |
| `core/rules/employee_rules/salary.gd` | 65 | 4 | 0 |  |
| `core/rules/employee_rules/train_slot_usage.gd` | 326 | 3 | 0 |  |
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
| `core/rules/phase/dinnertime_settlement.gd` | 510 | 16 | 0 | uses:IntValueParseHelpers,uses:MilestoneEffectQueries |
| `core/rules/phase/marketing/settlement_helpers.gd` | 338 | 4 | 0 |  |
| `core/rules/phase/marketing_settlement.gd` | 309 | 4 | 0 |  |
| `core/rules/phase/payday_settlement.gd` | 350 | 7 | 0 | uses:IntValueParseHelpers,uses:MilestoneEffectQueries |
| `core/rules/placement_conflict_registry.gd` | 133 | 0 | 0 |  |
| `core/rules/pricing_pipeline.gd` | 180 | 3 | 0 | uses:IntValueParseHelpers,uses:MilestoneEffectQueries |
| `core/rules/settlement_registry.gd` | 158 | 0 | 0 | uses:GameLog,uses:DebugFlags |
| `core/rules/working/mandatory_actions_rules.gd` | 169 | 1 | 0 |  |
| `core/state/game_state.gd` | 230 | 2 | 0 |  |
| `core/state/game_state_factory.gd` | 209 | 5 | 0 |  |
| `core/state/game_state_serialization.gd` | 248 | 5 | 0 | defines:_parse_* |
| `core/state/serialization/json_safe.gd` | 25 | 0 | 0 |  |
| `core/state/serialization/parse_helpers.gd` | 70 | 0 | 0 |  |
| `core/state/serialization/round_state_parser.gd` | 296 | 2 | 0 |  |
| `core/state/serialization/value_decoder.gd` | 92 | 1 | 0 |  |
| `core/state/state_schema_registry.gd` | 263 | 0 | 0 |  |
| `core/state/state_updater/batch.gd` | 103 | 2 | 0 |  |
| `core/state/state_updater/cash.gd` | 157 | 0 | 0 |  |
| `core/state/state_updater/collections.gd` | 72 | 0 | 0 |  |
| `core/state/state_updater/employees_and_milestones.gd` | 118 | 1 | 0 |  |
| `core/state/state_updater/inventory.gd` | 91 | 0 | 0 |  |
| `core/state/state_updater.gd` | 103 | 5 | 0 |  |
| `core/types/command.gd` | 184 | 1 | 0 | uses:JsonValueParseHelpers |
| `core/types/result.gd` | 131 | 0 | 0 |  |
| `core/utils/catalog_registry_helpers.gd` | 40 | 0 | 0 |  |
| `core/utils/int_value_parse_helpers.gd` | 37 | 0 | 0 |  |
| `core/utils/json_value_parse_helpers.gd` | 23 | 0 | 0 |  |
| `core/utils/range_utils.gd` | 352 | 2 | 0 |  |
| `core/utils/round_state_counters.gd` | 146 | 0 | 0 |  |
| `core/utils/type_helpers.gd` | 34 | 0 | 0 |  |

## 附录 B：逐文件备注（非测试）

说明：每个文件只记录 1-3 条“值得关注的结构性点”；若未见明显问题则标注为职责单一。

### actions/

- `core/actions/action_availability_registry.gd`：中等体量；后续可按重构优先级处理
- `core/actions/action_executor.gd`：（已部分整改 2026-01-26）移除自带 `_parse_int_value`，改用 `IntValueParseHelpers`；中等体量；后续可按重构优先级处理
- `core/actions/action_registry.gd`：包含 UI 语义：`get_player_initiatable_actions(...)` 判定“可启动动作”（隐式契约）；（已部分整改 2026-01-26）引入 `Result.error_code` 并优先按错误码判断、保留旧前缀兼容，并开始向常见调用链（含部分 gameplay 与 UI）扩散；偏长脚本；建议关注职责边界/可读性；依赖 GameLog 全局单例（耦合）

### data/

- `core/data/employee_def.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/employee_def/debug.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/employee_def/parser.gd`：（已部分整改 2026-01-26）移除自带 `_parse_*`，改用 `DataParseHelpers`；仍偏长，且含较多“字段组合约束”（建议后续按子结构拆分校验逻辑）
- `core/data/employee_def/serialization.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/employee_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/game_config.gd`：（已部分整改 2026-01-26）通用 `_parse_*` 已改为复用 `ParseHelpers`，仅保留业务专用 `_parse_reserve_cards`；中等体量；后续可按重构优先级处理
- `core/data/game_data.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/marketing_def.gd`：（已整改 2026-01-26）移除自带 `_parse_*`，改用 `DataParseHelpers`
- `core/data/marketing_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/milestone_def.gd`：（已部分整改 2026-01-26）移除自带 `_parse_*`，改用 `DataParseHelpers`；仍含较多 effects/filter 解析（对应 2.2 的后续收敛方向）
- `core/data/milestone_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/data/parse_helpers.gd`：（已新增 2026-01-26）用于收敛 `core/data/*` 内重复解析样板
- `core/data/product_def.gd`：（已整改 2026-01-26）移除自带 `_parse_*`，改用 `DataParseHelpers`
- `core/data/product_registry.gd`：未发现明显结构问题（小文件/职责相对单一）

### debug/

- `core/debug/debug_command_registry.gd`：依赖 GameLog 全局单例（耦合）；调试/开发工具逻辑；若 core 目标更纯，可考虑外移或作为可选层
- `core/debug/debug_commands/action_commands.gd`：超长脚本（维护成本高）；建议按职责拆分；含调试/发布差异分支（DebugFlags/OS.has_feature）；调试/开发工具逻辑；若 core 目标更纯，可考虑外移或作为可选层
- `core/debug/debug_commands/game_commands.gd`：含调试/发布差异分支（DebugFlags/OS.has_feature）；调试/开发工具逻辑；若 core 目标更纯，可考虑外移或作为可选层
- `core/debug/debug_commands/state_commands.gd`：中等体量；后续可按重构优先级处理；调试/开发工具逻辑；若 core 目标更纯，可考虑外移或作为可选层
- `core/debug/debug_commands/util_commands.gd`：中等体量；后续可按重构优先级处理；含调试/发布差异分支（DebugFlags/OS.has_feature）；调试/开发工具逻辑；若 core 目标更纯，可考虑外移或作为可选层
- `core/debug/perf_trace.gd`：调试/开发工具逻辑；若 core 目标更纯，可考虑外移或作为可选层

### engine/

- `core/engine/game_constants.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/game_defaults.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/game_engine.gd`：超长脚本（维护成本高）；建议按职责拆分；preload 依赖较多（耦合偏高）；依赖 EventBus（引擎与日志/UI 耦合）
- `core/engine/game_engine/action_setup.gd`：已改为委托 `gameplay/action_setup.gd`（移除 core 内对 gameplay/actions 的 preload）；已提供 `ActionSetup.set_provider_path(...)` 注入点，后续可进一步把 provider 来源做成配置/模块化
- `core/engine/game_engine/action_wiring.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/game_engine/archive.gd`：依赖 GameLog 全局单例（耦合）
- `core/engine/game_engine/auto_advance.gd`：通过 `ActionExecutor.apply_changes_in_place` 直接 in-place 改 state（需明确该 API 的契约/适用范围）；偏长脚本；建议关注职责边界/可读性
- `core/engine/game_engine/checkpoints.gd`：依赖 GameLog 全局单例（耦合）；含调试/发布差异分支（DebugFlags/OS.has_feature）
- `core/engine/game_engine/command_runner.gd`：（已部分整改 2026-01-26）事件构建已下沉到 `command_runner_event_build.gd`，主流程更聚焦于命令执行/auto-advance/invariants/checkpoint/emit；仍依赖 EventBus（引擎与日志/UI 耦合）；依赖 GameLog 全局单例（耦合）；含调试/发布差异分支（DebugFlags/OS.has_feature）
- `core/engine/game_engine/command_runner_event_build.gd`：（已新增 2026-01-26）从 `CommandRunner` 抽离的事件构建（report/拆分事件/marketing 到期/cleanup 丢弃等，偏日志/展示语义）；偏长脚本；后续可按 phase 拆分
- `core/engine/game_engine/diagnostics.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/game_engine/event_history_rebuild.gd`：依赖 EventBus（引擎与日志/UI 耦合）；含调试/发布差异分支（DebugFlags/OS.has_feature）
- `core/engine/game_engine/event_timeline_build.gd`：依赖 EventBus（引擎与日志/UI 耦合）
- `core/engine/game_engine/initializer.gd`：中等体量；后续可按重构优先级处理；存在一定数量的 preload 依赖；依赖 EventBus（引擎与日志/UI 耦合）
- `core/engine/game_engine/invariants.gd`：中等体量；后续可按重构优先级处理
- `core/engine/game_engine/loader.gd`：（已部分整改 2026-01-26）移除自带 `_parse_int_value`，改用 `JsonValueParseHelpers`；依赖 EventBus（引擎与日志/UI 耦合）；依赖 GameLog 全局单例（耦合）；含调试/发布差异分支（DebugFlags/OS.has_feature）
- `core/engine/game_engine/modules_v2.gd`：超长脚本（维护成本高）；建议按职责拆分；preload 依赖较多（耦合偏高）；函数数量较多，可能包含多职责/可考虑拆 helper
- `core/engine/game_engine/replay.gd`：中等体量；后续可按重构优先级处理；含调试/发布差异分支（OS.has_feature）；（已部分整改 2026-01-26）checkpoint.rng_calls 解析共用 `JsonValueParseHelpers`
- `core/engine/game_engine/step_timeline_build.gd`：时间线/日志“派生视图”构建逻辑很重；超长脚本（维护成本高）；建议按职责拆分；依赖 EventBus（引擎与日志/UI 耦合）；含调试/发布差异分支（DebugFlags/OS.has_feature）；（已整改 2026-01-26：不再跨文件调用 CommandRunner/PhaseManager 的私有 `_` 前缀方法）
- `core/engine/phase_manager.gd`：偏长脚本；建议关注职责边界/可读性；preload 依赖较多（耦合偏高）；函数数量较多，可能包含多职责/可考虑拆 helper
- `core/engine/phase_manager/advance_phase.gd`：中等体量；后续可按重构优先级处理；依赖 GameLog 全局单例（耦合）
- `core/engine/phase_manager/advance_sub_phase.gd`：中等体量；后续可按重构优先级处理；依赖 GameLog 全局单例（耦合）
- `core/engine/phase_manager/advancement.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/phase_manager/definitions.gd`：中等体量；后续可按重构优先级处理
- `core/engine/phase_manager/hooks.gd`：中等体量；后续可按重构优先级处理；依赖 GameLog 全局单例（耦合）；含调试/发布差异分支（DebugFlags/OS.has_feature）
- `core/engine/phase_manager/order_config.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/phase_manager/settlement_triggers.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/engine/phase_manager/working_flow.gd`：（已部分整改 2026-01-26）`_parse_non_negative_int_value` 改为复用 `IntValueParseHelpers`；（已部分整改 2026-01-26）里程碑 effects 遍历改为复用 `MilestoneEffectQueries`；仍大量使用 assert 做 fail-fast（需注意 release 下 assert 行为）

### map/

- `core/map/house_number_manager.gd`：中等体量；后续可按重构优先级处理；存在较多 assert；注意与 Result/fail-fast 策略一致性
- `core/map/map_baker/bake.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_baker/boundary_index.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_baker/cells.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_baker/debug.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_baker/queries.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_baker/tile_baking.gd`：中等体量；后续可按重构优先级处理；存在较多 assert；注意与 Result/fail-fast 策略一致性
- `core/map/map_context_builder.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_def.gd`：偏长脚本；建议关注职责边界/可读性；自带 _parse_* 解析函数（重复实现可收敛）
- `core/map/map_option_def.gd`：自带 _parse_* 解析函数（重复实现可收敛）
- `core/map/map_runtime/baked_map.gd`：自带 _parse_* 解析函数（重复实现可收敛）
- `core/map/map_runtime/cells.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_runtime/coords.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_runtime/road_graph_cache.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_runtime/structures.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/map_runtime/tile_edit.gd`：中等体量；后续可按重构优先级处理
- `core/map/map_utils.gd`：中等体量；后续可按重构优先级处理
- `core/map/marketing_placement_query.gd`：中等体量；后续可按重构优先级处理
- `core/map/parse_helpers.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/piece_def.gd`：超长脚本（维护成本高）；建议按职责拆分；自带 _parse_* 解析函数（重复实现可收敛）
- `core/map/piece_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/placement_validator/garden_attachment.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/placement_validator/map_access.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/placement_validator/placement.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/placement_validator/restaurant_placement.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/placement_validator/road_utils.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/placement_validator/validators.gd`：中等体量；后续可按重构优先级处理
- `core/map/road_graph.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/road_graph/blocks.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/road_graph/builder.gd`：自带 _parse_* 解析函数（重复实现可收敛）
- `core/map/road_graph/node_keys.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/road_graph/pathfinding.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/road_graph/range_query.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/map/tile_def.gd`：超长脚本（维护成本高）；建议按职责拆分；自带 _parse_* 解析函数（重复实现可收敛）
- `core/map/tile_registry.gd`：未发现明显结构问题（小文件/职责相对单一）

### modules/

- `core/modules/v2/content_catalog.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/content_catalog_loader.gd`：中等体量；后续可按重构优先级处理；存在一定数量的 preload 依赖
- `core/modules/v2/module_dir_spec.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/modules/v2/module_manifest.gd`：（已部分整改 2026-01-26）`_parse_*` 改为复用 `DataParseHelpers`（仍保留薄 wrapper 以维持 module.json 语义）
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
- `core/rules/company_structure_rules.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/dinnertime_demand_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/dinnertime_route_purchase_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/drinks_procurement.gd`：规则编排较大；与 inputs/validator/finder 等已拆分但主流程仍偏重；偏长脚本；建议关注职责边界/可读性；存在一定数量的 preload 依赖；（已部分整改 2026-01-26）`_parse_positive_int_value` 改为复用 `IntValueParseHelpers`；（已部分整改 2026-01-26）里程碑 effects 遍历改为复用 `MilestoneEffectQueries`
- `core/rules/drinks_procurement/default_route_builder.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/drinks_procurement/inputs.gd`：（已整改 2026-01-26）移除自带 `_parse_int`，改用 `JsonValueParseHelpers`
- `core/rules/drinks_procurement/picked_sources_finder.gd`：未发现明显结构问题（小文件/职责相对单一）
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
- `core/rules/employee_rules/salary.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/employee_rules/train_slot_usage.gd`：偏长脚本；建议关注职责边界/可读性
- `core/rules/employee_rules/working_multiplier.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/global_effect_list.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/map_generation_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/marketing_initiation_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/marketing_range_calculator.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/marketing_rules.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/marketing_type_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/milestone_effect_queries.gd`：（已新增 2026-01-26）用于收敛“遍历 milestones -> MilestoneDef.effects”样板，供 pricing/settlement/drinks 等复用
- `core/rules/milestone_effect_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/milestone_system.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/phase/cleanup_settlement.gd`：（已部分整改 2026-01-26）移除自带 `_parse_non_negative_int_value`，改用 `IntValueParseHelpers`；（已部分整改 2026-01-26）里程碑 effects 遍历改为复用 `MilestoneEffectQueries`；中等体量；后续可按重构优先级处理
- `core/rules/phase/dinnertime/dinnertime_distance.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/phase/dinnertime/dinnertime_effects.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/phase/dinnertime/dinnertime_events.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/phase/dinnertime/dinnertime_inventory.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/phase/dinnertime/dinnertime_selection.gd`：中等体量；后续可按重构优先级处理；存在较多 assert；注意与 Result/fail-fast 策略一致性
- `core/rules/phase/dinnertime_settlement.gd`：（已部分整改 2026-01-26）移除自带 `_parse_non_negative_int_value`，改用 `IntValueParseHelpers`；（已部分整改 2026-01-26）里程碑 effects 遍历改为复用 `MilestoneEffectQueries`；晚餐结算 orchestrator 过大；可进一步把“选择/计价/结算写入/报告生成”分层；超长脚本（维护成本高）；建议按职责拆分；preload 依赖较多（耦合偏高）
- `core/rules/phase/marketing/settlement_helpers.gd`：偏长脚本；建议关注职责边界/可读性；存在较多 assert；注意与 Result/fail-fast 策略一致性
- `core/rules/phase/marketing_settlement.gd`：偏长脚本；建议关注职责边界/可读性
- `core/rules/phase/payday_settlement.gd`：（已部分整改 2026-01-26）移除自带 `_parse_int_value`，改用 `IntValueParseHelpers`；（已部分整改 2026-01-26）里程碑 effects 遍历改为复用 `MilestoneEffectQueries`；结算逻辑较大；包含 token 支付/折扣/报告写入等多职责，可分层；偏长脚本；建议关注职责边界/可读性；存在一定数量的 preload 依赖
- `core/rules/placement_conflict_registry.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/rules/pricing_pipeline.gd`：（已部分整改 2026-01-26）移除自带 `_parse_*`，改用 `IntValueParseHelpers`；（已部分整改 2026-01-26）里程碑 effects 遍历改为复用 `MilestoneEffectQueries`；中等体量；后续可按重构优先级处理
- `core/rules/settlement_registry.gd`：依赖 GameLog 全局单例（耦合）；含调试/发布差异分支（DebugFlags/OS.has_feature）
- `core/rules/working/mandatory_actions_rules.gd`：未发现明显结构问题（小文件/职责相对单一）

### state/

- `core/state/game_state.gd`：中等体量；后续可按重构优先级处理
- `core/state/game_state_factory.gd`：含 UI/setup 语义的 logo 分配落盘逻辑；若目标是更纯的 core，可考虑外移到上层；中等体量；后续可按重构优先级处理；存在一定数量的 preload 依赖
- `core/state/game_state_serialization.gd`：中等体量；后续可按重构优先级处理；存在一定数量的 preload 依赖；自带 _parse_* 解析函数（重复实现可收敛）
- `core/state/serialization/json_safe.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/serialization/parse_helpers.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/serialization/round_state_parser.gd`：中等体量；后续可按重构优先级处理
- `core/state/serialization/value_decoder.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/state_schema_registry.gd`：中等体量；后续可按重构优先级处理
- `core/state/state_updater.gd`：存在一定数量的 preload 依赖
- `core/state/state_updater/batch.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/state_updater/cash.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/state_updater/collections.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/state_updater/employees_and_milestones.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/state/state_updater/inventory.gd`：未发现明显结构问题（小文件/职责相对单一）

### types/

- `core/types/command.gd`：（已部分整改 2026-01-26）移除自带 `_parse_int_value`，改用 `JsonValueParseHelpers`；仍含较多“字段存在性 + 类型校验”样板（后续可继续收敛）
- `core/types/result.gd`：未发现明显结构问题（小文件/职责相对单一）

### utils/

- `core/utils/catalog_registry_helpers.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/utils/int_value_parse_helpers.gd`：（已新增 2026-01-26）用于收敛 rules/milestone effects 的整值解析样板
- `core/utils/json_value_parse_helpers.gd`：（已新增 2026-01-26）用于收敛存档/回放/命令解析中的 JSON 数值校验样板
- `core/utils/range_utils.gd`：偏长脚本；建议关注职责边界/可读性
- `core/utils/round_state_counters.gd`：未发现明显结构问题（小文件/职责相对单一）
- `core/utils/type_helpers.gd`：未发现明显结构问题（小文件/职责相对单一）
