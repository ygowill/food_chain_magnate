# 人机对手 Phase 0/1 任务拆解

本文是 [fcm_heuristic_bot_implementation_plan.md](fcm_heuristic_bot_implementation_plan.md) 的执行拆解，目标是把“能开始实现”的第一批任务切到可开发、可测试、可验收的粒度。

范围只覆盖：

- Phase -1：规则对齐，确认 Errand Boy 里程碑修复和回归覆盖。
- Phase 0：接口、观察层、最小 Bot 骨架。
- Phase 1：引擎 fork、forward simulation、DinnerPreview 正确性基线。

不覆盖 Greedy 评价函数、完整候选生成和产品 UI 接入；这些应在 Phase 2/3 拆解。

## 0. 交付目标

完成本拆解后，应达到：

- Errand Boy + `first_errand_boy` 与规则书一致。
- `core/ai/` 基础目录存在，核心类型可编译。
- Bot 决策层不能直接读取完整 `GameState`，必须经 `ObservationAdapter`。
- `RandomLegalBot` 至少能完成 Setup、首轮自动进入 Working，并在后续阶段有合法 fallback。
- `AiEngineFork` 能从当前 engine 复制出可执行模拟环境。
- `ForwardSimulator` 能执行候选命令并让 auto-advance/settlement 正常生效。
- `DinnerPreview` 首版以真实 engine settlement 为基线，能产出与 `round_state.dinnertime` 对齐的结果。

## 1. 现有代码复用总表

本计划的实现原则是：AI 只负责观察脱敏、候选生成、评分和调度；规则事实源仍是现有 `Command`、action validator、engine auto-advance、settlement 和 registry。除非先抽到 `core/`，生产 AI 不应直接依赖 `tools/manual_test_saves/` 里的辅助 builder；这些文件只能作为候选生成写法参考。

| AI 部分 | 直接复用 | 需要薄封装或新增 | 不应重复实现 |
| --- | --- | --- | --- |
| 测试框架 | `tools/run_headless_test.sh`、`ui/scenes/tests/all_tests.gd`、`all_tests_plan.gd`、`all_tests_refs.gd`、现有 suite 结构 | 新增 `all_tests_ai_suite.gd`，把 AI smoke/golden 接入 AllTests | 另起一套测试 runner |
| 规则回归 oracle | `core/tests/procure_drinks_route_rules_test.gd`、`procure_drinks_test.gd`、`dinnertime_settlement_test.gd`、`marketing_dinnertime_golden_replay_test.gd`、cleanup/payday/company structure/state access 测试 | AI 测试只补“Bot 边界是否调用同一规则”的薄层断言 | 为 AI 复制一份规则期望 |
| 隐藏信息 | `core/utils/command_privacy.gd`、reserve card/privacy UI 测试、`ui/scenes/tests/restructuring_privacy_test.gd` | `ObservationAdapter` 和 `ObservationState`，覆盖完整 state/round_state 脱敏 | 让 Bot 直接读完整 `GameState` |
| 合法行动 | `ActionRegistry`、`ActionRegistryQueries.get_player_initiatable_actions()`、`ActionAvailabilityRegistry`、各 action 的 `can_initiate` / `validate` | `LegalActionService`，只白名单必须给 Bot 用的 internal action | 在 AI 里手写每个阶段可行动作 |
| 执行与模拟 | `GameEngine.execute_command()`、command runner、auto-advance、`GameState.duplicate_state()`、`compute_hash()`、`GameEngine.create_archive()` / `load_from_archive()` | `AiEngineFork` 与 `ForwardSimulator`，封装 fork、执行候选和 horizon | 手写 phase advance 或 settlement 触发 |
| 地图/距离/放置 | `MapContextBuilder`、`map_runtime/coords.gd`、`structures.gd`、`RoadGraphCache`、`RangeUtils`、`placement_validator/*`、`MarketingPlacementQuery` | `BoardAnalyzer` 作为缓存/read model；可把手动存档 builder 中的候选扫描思路抽到 core | AI 自己判断 road graph、入口点、重叠规则 |
| Dinner/Pricing | `DinnertimeSettlement`、`dinnertime_house_sales.gd`、`dinnertime_selection.gd`、`dinnertime_distance.gd`、`PricingPipeline`、demand/route purchase registry | `DinnerPreview` 首版通过 fork 真实结算读取 `round_state.dinnertime` | Phase 1 手写快速晚餐模拟 |
| Marketing | `InitiateMarketingAction`、`modules/base_marketing/rules/entry.gd`、`MarketingTypeRegistry`、`marketing_settlement.gd`、`MarketingPlacementQuery` | `CampaignReachAnalyzer` / marketing candidate helper，生成后必须 validate | 复制 billboard/mailbox/airplane/radio 覆盖规则 |
| Drinks | `ProcureDrinksAction`、`DrinksProcurement.resolve_procurement_plan()`、route validator、picked source finder、milestone bonus helper | `DrinkRouteAnalyzer` 只生成有限候选，再用现有 action/rules 校验 | 手写 Errand Boy、source bonus、route 合法性 |
| 公司结构/薪资 | `CompanyStructureRules`、`CompanyStructureValidator`、restructure/set/submit actions、`EmployeeRules`、`PaydaySettlement` | 结构候选生成器和 salary/fire 策略；执行仍走 internal command | 直接改 `company_structure` 或重复薪资算法 |
| Cleanup/fridge | `CleanupSettlement`、`ChooseFridgeKeepAction`、cleanup/fridge state access 测试 | fridge keep 候选生成器，输出 `keep` dict 后 validate | 手写 cleanup pending 状态迁移 |
| Milestone | `MilestoneSystem`、`MilestoneEffectQueries`、`MilestoneEffectRegistry`、`MilestoneRegistry`、base milestone JSON | `MilestoneRaceAnalyzer` 只做读模型和评分 | 复制 milestone 触发和 effect 应用 |
| 候选生成参考 | `tools/manual_test_saves/builders/manual_test_save_placement_support.gd`、`manual_test_save_marketing_builders.gd` | 如需生产复用，先抽公共 helper 到 `core/ai/candidates/` 或 `core/map/` | 从生产 AI 直接 import `tools/manual_test_saves` |

## 2. 任务依赖图

```text
HB-001 -> HB-002 -> HB-003

AI-001 -> AI-002 -> AI-003 -> AI-004
AI-001 -> AI-005 -> AI-006 -> AI-007 -> AI-008

SIM-001 -> SIM-002 -> SIM-003
SIM-002 -> SIM-004 -> SIM-005

Phase 1 依赖 Phase -1/0 的基础类型和测试习惯，但 AiEngineFork 可以在 ObservationAdapter 之后并行开发。
```

## 3. Phase -1：规则对齐

### HB-001：确认 Errand Boy 规则回归测试

状态：本地 `main` 的 `1670651b fix(core): apply errand boy milestone drink bonus` 已补入核心回归覆盖，主要位于 `core/tests/procure_drinks_route_rules_test.gd`。本任务后续只负责确认覆盖仍在，并在行为扩展时补充专用测试。

建议文件：

- `core/tests/procure_drinks_route_rules_test.gd`
- 可选新增：`core/tests/procure_drinks_errand_boy_milestone_test.gd`
- `ui/scenes/tests/all_tests_refs.gd`
- `ui/scenes/tests/suites/all_tests_core_rules_suite.gd`

测试场景：

1. 玩家没有 `first_errand_boy`，执行 `procure_drinks` + `employee_type="errand_boy"`，获得 1 瓶指定饮料。
2. 玩家已经有 `first_errand_boy`，执行 Errand Boy，获得 2 瓶同类饮料。
3. 玩家本次使用 Errand Boy 触发 `first_errand_boy`，本次也获得 2 瓶同类饮料。
4. 路线型采购员工已有 `first_errand_boy` 时，每个 source 仍按 `DRINKS_PER_SOURCE + procure_plus_one` 计算。

实现要点：

- 用 `GameEngine.initialize(2, seed)` 初始化默认 base 模块。
- 将玩家推进到 `Working/GetDrinks`，并把 `turn_order/current_player_index` 调整到测试玩家。
- 给测试玩家一个在岗 `errand_boy`，必要时从 `employee_pool` 扣除。
- 执行：

```gdscript
Command.create("procure_drinks", player_id, {
	"employee_type": "errand_boy",
	"drink_type": "soda",
})
```

验收：

- 当前回归测试必须覆盖“首次跑腿伙计本次获得 2 瓶”。
- 失败信息明确说明期望数量。
- 测试已纳入 AllTests。

### HB-002：确认 `ProcureDrinksAction` Errand Boy 数量实现

状态：本地 `main` 的 `1670651b` 已完成。后续如回归，按本任务检查实现。

目标：保证 Errand Boy 分支也吃到本次 `UseEmployee` 触发的 `first_errand_boy` 效果。

目标文件：

- `gameplay/actions/procure_drinks_action.gd`

历史问题与当前检查点：

- 历史问题是 Errand Boy 分支硬编码 `StateUpdater.add_inventory(..., 1)`，且事件中的 `drinks_procured` 也硬编码为 1。
- 当前实现已通过 `_get_errand_boy_drink_amount(state, player_id)` 统一读取数量。

建议实现：

- 在 Errand Boy 分支内，完成 `apply_use_employee_event()` 后，对更新后的 `state` 读取：

```gdscript
DrinksProcurementClass.get_drinks_per_source_bonus_from_milestones(state, player_id)
```

- Errand Boy 数量为：

```gdscript
var amount := 1 + int(bonus_read.value)
```

- `StateUpdater.add_inventory()`、返回 payload、`_generate_specific_events()` 都使用同一数量。
- 如果未来模块加入负向 delta，Errand Boy 数量下限应保守 clamp 到 1，除非规则明确允许 0。

验收：

- HB-001 四个测试通过。
- 现有 `ProcureDrinksTest`、`ProcureDrinksRouteRulesTest` 仍通过。

### HB-003：确认规则测试纳入 AllTests

目标：相关测试进入 headless 聚合，避免后续回归。

目标文件：

- `ui/scenes/tests/all_tests_refs.gd`
- `ui/scenes/tests/suites/all_tests_core_rules_suite.gd`

验收：

- `all_tests_refs.gd` preload 新测试类。
- `all_tests_core_rules_suite.gd` 添加测试项，放在 `ProcureDrinksTest` 附近。
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 会运行该测试。

## 4. Phase 0：AI 接口与观察层

### AI-001：建立 `core/ai/` 基础目录与核心类型

目标：先建立稳定的 AI 类型边界。

新增文件：

- `core/ai/bot/bot_decision.gd`
- `core/ai/bot/ai_decision_context.gd`
- `core/ai/candidates/macro_action.gd`
- `core/ai/search/time_budget.gd`
- `core/ai/logging/decision_trace.gd`

建议最小职责：

`BotDecision`：

- `command: Command`
- `macro_action_id: String`
- `score: float`
- `explanation: Dictionary`
- `trace: Dictionary`
- `static func failure(reason: String) -> BotDecision`

`AiDecisionContext`：

- `player_id: int`
- `phase: String`
- `sub_phase: String`
- `round_number: int`
- `decision_seed: int`
- `allowed_internal_actions: Array[String]`

`MacroAction`：

- `id: String`
- `commands: Array[Command]`
- `prior_score: float`
- `tags: Array[String]`
- `debug: Dictionary`

`TimeBudget`：

- `started_ms: int`
- `budget_ms: int`
- `func expired() -> bool`
- `func remaining_ms() -> int`

验收：

- 所有新增 `.gd` 可编译。
- 不引用 UI Node。
- 不直接依赖具体 Bot 实现。

### AI-002：定义 `ObservationState` schema

目标：把“严格隐藏信息”变成明确字段，不靠口头约束。

新增文件：

- `core/ai/observation/observation_state.gd`

建议字段：

- `viewer_player_id: int`
- `round_number: int`
- `phase: String`
- `sub_phase: String`
- `current_player_id: int`
- `turn_order: Array[int]`
- `selection_order: Array[int]`
- `bank_public: Dictionary`
- `rules_public: Dictionary`
- `modules: Array[String]`
- `own_player: Dictionary`
- `public_players: Array[Dictionary]`
- `map_public: Dictionary`
- `marketing_instances_public: Array`
- `employee_pool_public: Dictionary`
- `milestone_pool_public: Array`
- `round_state_public: Dictionary`
- `hidden_summary: Dictionary`

隐藏规则：

- `own_player` 可包含自己的 `reserve_cards`、`reserve_card_selected`、`company_structure`。
- `public_players[i]` 不包含对手隐藏 reserve 信息。
- Restructuring 未 finalized 时，对手 `company_structure.structure` 必须隐藏或替换为公开的上一稳定结构摘要。
- `round_state_public` 不应暴露对手未公开提交内容。

验收：

- schema 文档写在类注释或本文件顶部。
- 提供 `to_debug_dict()`，方便测试断言。

### AI-003：实现 `ObservationAdapter`

目标：唯一允许从真实 engine/state 读取并生成 Bot 观察的入口。

新增文件：

- `core/ai/observation/observation_adapter.gd`

核心接口：

```gdscript
static func observe_for_player(engine: GameEngine, viewer_player_id: int) -> Result
```

实现规则：

- 输入必须是 `GameEngine`，不要只传裸 `GameState`，因为后续可能需要 registry/ruleset 信息。
- 对当前玩家复制完整自有状态，但可以去掉无关 UI/debug 字段。
- 对对手使用 `_sanitize_public_player(...)`。
- 对 map 使用 public copy；base 模块下地图公开。
- 对 `round_state` 使用 `_sanitize_round_state(...)`，明确过滤 Restructuring 隐藏字段。
- 对 reserve card 使用与 `command_privacy.gd` 一致但更完整的状态脱敏逻辑。

可复用参考：

- `core/utils/command_privacy.gd` 已有 command 参数隐私处理，可复用其 reserve card 隐私判断思路，但它不能替代完整状态脱敏。
- `ui/scenes/tests/reserve_card_selection_modal_privacy_test.gd`、`entity_tab_reserve_card_privacy_test.gd`、`reserve_cards_full_screen_view_privacy_test.gd`、`restructuring_privacy_test.gd` 可作为隐藏信息测试 oracle。
- 读取玩家和地图字段时优先用 `PlayerStateAccess`、`MapStateAccess`、`StaffState` 等现有 access helper，避免在 adapter 里散落裸字典读取。

需要单独 helper：

- `_viewer_can_peek_all_reserve_cards(state, viewer_player_id)`
- `_is_reserve_card_revealed(state, player_id)`
- `_is_restructuring_finalized(state)`
- `_sanitize_player_for_viewer(state, viewer, target)`
- `_sanitize_round_state_for_viewer(state, viewer)`

验收：

- Bot 代码审查时，除 ObservationAdapter 外不得直接读取真实 `engine.state`。
- Adapter 返回 `Result.success(observation)`，错误信息含路径。

### AI-004：观察层测试

目标：防止 AI 隐藏信息作弊。

新增文件：

- `core/tests/ai/observation_adapter_test.gd`

测试接入：

- `ui/scenes/tests/all_tests_refs.gd`
- 可新增 `ui/scenes/tests/suites/all_tests_ai_suite.gd`，并在 `all_tests_plan.gd` 中挂载；或先放入 `CoreArchitectureSuite`/`CoreRulesSuite` 附近。推荐新增 AI suite，避免测试列表继续膨胀。

测试用例：

1. 观察自己时可见自己的 `reserve_cards` 和 `reserve_card_selected`。
2. 观察对手时，若 `reserve_card_revealed == false` 且自己没有 peek 能力，不能看到 `selected_index`。
3. 自己有 `can_peek_all_reserve_cards` 时可见对手 reserve 选择。
4. Restructuring 未 finalized 时，对手结构不可见。
5. Restructuring finalized 后，对手结构可见。
6. `ObservationState.to_debug_dict()` 不包含被标记为 hidden 的真实值。

验收：

- 这些测试必须在没有 Bot 实现时也能运行。
- 如果有人把真实隐藏字段塞回 observation，测试失败。

### AI-005：定义决策点与 legal action 服务

目标：为 Bot 提供统一行动入口，包括必要 internal action 白名单。

新增文件：

- `core/ai/bot/ai_decision_point.gd`
- `core/ai/bot/legal_action_service.gd`

`AiDecisionPoint` 不作为规则事实源，只是分类结果：

- `RESERVE_CARD`
- `INITIAL_RESTAURANT`
- `RESTRUCTURING`
- `ORDER_OF_BUSINESS`
- `WORKING_SUB_PHASE`
- `PAYDAY`
- `CLEANUP_PENDING`
- `CONFIRM_SETTLEMENT`
- `NO_DECISION`

`LegalActionService` 职责：

- 从 observation/context 判断阶段。
- 从 `engine.action_registry.get_player_initiatable_actions()` 获取普通 action。
- 对白名单 internal action 做显式允许：
  - `select_reserve_card`
  - `restructure_employee`
  - `set_company_structure_direct`
  - `set_company_structure_report`
  - `submit_restructuring`
  - `choose_fridge_keep`
  - confirmation actions 如适用
- 提供 `validate_command(engine, command) -> Result`。

可复用接口：

- `core/actions/action_registry.gd`
- `core/actions/action_registry_queries.gd`
- `core/actions/action_availability_registry.gd`
- 各 `gameplay/actions/*_action.gd` 的 `can_initiate()` 与 `validate()`

`get_player_initiatable_actions()` 会过滤 internal action，因此 internal 白名单必须显式、窄口径，并写明对应决策点。

验收：

- 不把所有 internal action 全开放。
- 每个白名单 action 都有注释说明哪个决策点使用。

### AI-006：实现 `RandomLegalBot`

目标：先有一个不会 softlock 的最小 Bot。

新增文件：

- `core/ai/bot/fcm_bot.gd`
- `core/ai/bot/random_legal_bot.gd`
- `core/ai/candidates/basic_candidate_helpers.gd`

首版策略：

- `Setup/ReserveCards`：选择第一个或 seed 随机合法 `selected_index`。
- `Setup` 初始餐厅：按固定顺序扫描地图坐标和 rotation，选择第一个 validate 通过的 `place_restaurant`。
- `Restructuring`：生成 CEO-only 或当前合法最小结构，执行 internal 编辑命令后 `submit_restructuring`。
- `OrderOfBusiness`：选择第一个空 slot。
- `Working` 非最后子阶段：优先 `skip_sub_phase`。
- `Working/PlaceRestaurants`：使用 `skip`。
- `Payday`：若能 `skip` 则 skip；若薪资不足，先不在 RandomLegalBot 里做复杂裁员，留到 AI-008 暴露问题后补最小 `fire` fallback。
- `Cleanup` pending fridge：保留价值最高的食物/饮料，数量不超过容量。
- Dinnertime/Marketing confirm pending：执行对应 confirm action。

注意：

- RandomLegalBot 仍通过 `ObservationState` 做决策。
- 需要参数的候选必须用真实 `Command` validate。
- 初始餐厅、房屋、花园、营销候选可以参考 `tools/manual_test_saves/builders/manual_test_save_placement_support.gd` 和 `manual_test_save_marketing_builders.gd` 的扫描方式；若要生产复用，先抽公共 helper，不直接依赖 `tools/`。
- 如果所有候选都失败，返回 `BotDecision.failure()`，由 controller 记录错误；不要静默乱发命令。

验收：

- 至少能从新局 Setup 跑完首轮放餐厅并进入 Working。
- 决策 deterministic：同 seed、同 observation，输出同一命令。

### AI-007：BotController 测试驱动

目标：在测试里能让 Bot 接管指定玩家并推进若干步。

新增文件：

- `core/ai/bot/bot_controller.gd`
- `core/tests/ai/bot_controller_smoke_test.gd`

接口建议：

```gdscript
func step(engine: GameEngine, player_id: int, bot: FcmBot, budget: TimeBudget) -> Result
func run_until(engine: GameEngine, stop_condition: Callable, max_steps: int) -> Result
```

职责：

- 调用 `ObservationAdapter`。
- 构造 `AiDecisionContext`。
- 调用 `bot.choose_command(...)`。
- 执行返回命令或命令序列。
- 收集 `DecisionTrace`。

验收：

- 每步只通过 `engine.execute_command()` 改状态。
- max_steps 触发时返回 failure，避免测试死循环。

### AI-008：RandomLegalBot smoke 测试

目标：Phase 0 的终点验收。

新增文件：

- `core/tests/ai/random_legal_bot_smoke_test.gd`

测试：

1. 2p 默认 base 模块，固定 seed。
2. 两个 RandomLegalBot 从新局开始轮流决策。
3. 跑到 `Working` 或最多 80 步。
4. 不出现 invalid command。
5. 不出现 max_steps softlock。
6. 记录每步 action_id，失败时输出最后 10 步。

验收：

- 测试纳入 AI suite。
- Phase 0 完成标准是该测试通过。

## 5. Phase 1：Simulation 与 DinnerPreview

### SIM-001：实现 `AiEngineFork`

目标：复制当前 engine 到可安全模拟的 fork。

新增文件：

- `core/ai/simulation/ai_engine_fork.gd`

接口建议：

```gdscript
static func fork_from_engine(source: GameEngine) -> Result
```

必须复制或重建：

- `state.duplicate_state()`
- `phase_manager`
- `action_registry`
- `module_plan_v2`
- `module_manifests_v2`
- `content_catalog_v2`
- `ruleset_v2`
- `module_ui_extensions_v2`
- `modules_v2_base_dir`
- `catalog_registry_bundle`
- `rules_registry_bundle`
- `dependencies` 中会影响 command runner / event builder / action setup 的配置

建议路线：

1. 先评估 `GameEngine.create_archive()` / `load_from_archive()` 是否能完整复原当前 engine；若可行，优先走 archive 路线。
2. 若 archive 不足，再实现保守版本：新建 `GameEngine`，复制必要字段，再调用 `activate_registry_bundles()`。
3. 不复制 UI/event sink；模拟默认禁用外部事件副作用。
4. command history 可不复制，除非模拟需要 rewind；首版只需要当前状态 forward。
5. 全局 registry bundle 切换是风险点，首版禁止并行 fork 模拟。

验收测试：

- fork 后 `fork.state.compute_hash() == source.state.compute_hash()`。
- fork 执行一个合法命令不改变 source state hash。
- source 执行同一个命令后，source/fork 结果 hash 一致。

### SIM-002：实现 `ForwardSimulator`

目标：统一执行候选命令并处理模拟 horizon。

新增文件：

- `core/ai/simulation/forward_simulator.gd`

接口建议：

```gdscript
func simulate_command(engine: GameEngine, command: Command, options: Dictionary = {}) -> Result
func simulate_commands(engine: GameEngine, commands: Array[Command], options: Dictionary = {}) -> Result
```

返回结构：

- `engine: GameEngine`
- `state: GameState`
- `commands_executed: Array`
- `warnings: Array[String]`
- `failed_command_index: int`
- `error: String`

horizon 选项：

- `mode="after_command"`：只执行候选命令和命令自身触发的 auto-advance。
- `mode="until_phase"`：继续执行合法 auto/skip fallback 到指定 phase。
- `mode="max_steps"`：最多推进 N 个 Bot/controller 步。

首版只必须支持 `after_command`，`until_phase` 可用于 DinnerPreview。

必须复用：

- `engine.execute_command()`。
- `core/engine/game_engine/command_runner.gd`。
- `core/engine/game_engine/auto_advance_try_step.gd`。
- `core/engine/game_engine/auto_advance_working_mandatory.gd`。

`ForwardSimulator` 只能决定 horizon 和 fallback 边界，不能复制 command runner 的推进规则。

验收：

- validate 失败时返回 failure，不改原 engine。
- 模拟成功时原 engine 不变。
- warnings 不丢失。

### SIM-003：auto-advance 与 mandatory action 验证

目标：确认模拟没有绕过当前 command runner 的自动推进。

新增测试：

- `core/tests/ai/forward_simulator_test.gd`

测试场景：

1. Working 中无可做动作时，执行 skip/候选后 auto-advance 行为与真实 engine 一致。
2. mandatory price action 可由 `auto_advance_working_mandatory.gd` 补完。
3. Restructuring 全员 submit 后自动进入下一阶段。
4. OrderOfBusiness 选完后自动进入 Working。

验收：

- 不允许 ForwardSimulator 自己手写 phase advance 规则。
- 所有推进都来自 `engine.execute_command()` 和 command runner drain。

### SIM-004：实现 `DinnerPreview` 基线版

目标：为后续 evaluator 提供正确的晚餐结果。

新增文件：

- `core/ai/analysis/dinner_preview.gd`

接口建议：

```gdscript
static func preview_after_commands(
		engine: GameEngine,
		commands: Array[Command],
		options: Dictionary = {}
	) -> Result
```

首版算法：

1. 用 `AiEngineFork` fork 当前 engine。
2. 执行候选 commands。
3. 如果目标状态还没进入 Dinnertime，则使用受控 fallback 推进：
   - Working 当前玩家可跳过时执行 `skip_sub_phase` / `skip`。
   - 结算阶段让 auto-advance 自然推进。
   - 遇到需要真实玩家选择的阶段则停止并返回“无法预览到晚餐”。
4. 一旦进入并结算 Dinnertime，读取 `state.round_state["dinnertime"]`。
5. 输出轻量 result：
   - `sales`
   - `skipped`
   - `income_sales`
   - `income_tips`
   - `income_cfo_bonus`
   - `total_income`
   - `bankruptcy_events`

重要限制：

- 不在 Phase 1 做快速手写晚餐模拟。
- 不绕过 `DinnertimeSettlement`。
- 若无法合法推进到 Dinnertime，返回 failure 或 partial result，不猜。

验收：

- 对已接近 Dinnertime 的测试状态，能稳定返回真实 `round_state.dinnertime`。
- 结果结构字段名与真实 report 对齐。

### SIM-005：DinnerPreview golden 测试

目标：证明 preview 与真实 settlement 一致。

新增文件：

- `core/tests/ai/dinner_preview_golden_test.gd`

复用现有测试作为 oracle：

- `core/tests/dinnertime_settlement_test.gd`
- `core/tests/dinnertime_distance_entry_boundary_test.gd`
- `core/tests/dinnertime_demand_registry_v2_test.gd`
- `core/tests/marketing_dinnertime_golden_replay_test.gd`
- `core/tests/confirm_dinnertime_availability_test.gd`
- `core/tests/online_dinnertime_confirm_enforced_test.gd`

测试用例：

1. 使用现有 `DinnertimeSettlementTest` 风格构造两个玩家、两个餐厅、一个有需求房屋。
2. 直接推进真实 engine 到 Dinnertime，保存 `round_state.dinnertime`。
3. 从同一前置状态调用 `DinnerPreview.preview_after_commands(...)`。
4. 比较：
   - sales 数量
   - winner owner
   - required
   - unit_price
   - distance
   - total_income
   - inventory 消耗
5. 加 drive-through case：玩家在岗 `local_manager`/`regional_manager` 或含 `drivethrough` tag 员工时，preview 与真实 settlement 一致。

验收：

- 所有 golden tests 通过。
- 测试失败时输出真实 report 与 preview report 的关键差异。

## 6. 建议执行顺序

1. HB-001：确认 Errand Boy 回归测试覆盖。
2. HB-002：确认 Errand Boy 实现仍通过回归测试。
3. HB-003：确认测试纳入 AllTests。
4. AI-001：建立 AI 基础类型。
5. AI-002/AI-003：实现 ObservationState/Adapter。
6. AI-004：隐藏信息测试。
7. AI-005：LegalActionService。
8. AI-006/AI-007：RandomLegalBot + BotController。
9. AI-008：Random smoke。
10. SIM-001：AiEngineFork。
11. SIM-002/SIM-003：ForwardSimulator。
12. SIM-004/SIM-005：DinnerPreview golden。

## 7. Phase 0/1 完成标准

必须全部满足：

- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests` 通过。
- 新增 AI suite 中的 Observation、Random smoke、ForwardSimulator、DinnerPreview golden 全通过。
- `RandomLegalBot` 固定 seed 下 deterministic。
- Bot 决策层没有直接读取真实 `GameState` 的入口。
- `AiEngineFork` 模拟不会污染 source engine。
- Errand Boy 规则与规则书一致。

可暂缓：

- GreedyEvaluator。
- 高质量营销/生产/扩张候选。
- 自对弈调参。
- UI 中选择 Bot 玩家。
- 在线房间 Bot 接入。

## 8. 风险与处理

- **全局 registry bundle 串局**：Phase 1 禁止并行模拟；后续若要并行，必须隔离进程或重构 registry。
- **ObservationAdapter 漏隐藏字段**：先写隐藏信息测试，再接 Bot。
- **RandomLegalBot 参数生成不足**：Phase 0 只要求从 Setup 到 Working；完整工作阶段策略在 Phase 2/3 做。
- **DinnerPreview 推不到 Dinnertime**：首版允许返回 failure，不猜测结算。
- **公司结构 internal action 复杂**：RandomLegalBot 首版用 CEO-only submit，Greedy 结构候选后续再展开。
- **AllTests 过慢**：AI golden 初期保持小场景，不做大规模随机测试。
