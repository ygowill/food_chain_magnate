# 《快餐连锁大亨》启发式人机对手实施方案

本文档以当前 Godot 4.5 / GDScript 代码实现为准，用于在现有 `GameEngine`、`ActionRegistry`、`PhaseManager` 与 `RulesetV2` 基础上实现可落地的人机对手。

## 0. 当前结论

### 0.1 首版范围

首版 Bot 只要求完整支持默认 base 模块：

- `base_rules`
- `base_products`
- `base_pieces`
- `base_tiles`
- `base_maps`
- `base_employees`
- `base_milestones`
- `base_marketing`

这些模块由 `core/engine/game_defaults.gd` 的 `GameDefaults.build_default_enabled_modules_v2()` 默认启用。其他模块（咖啡、拉面、寿司、lobbyists、new_milestones 等）不进入首版强度验收，但架构必须为后续模块扩展留出边界。

### 0.2 规则差异与已对齐项

当前实现与规则书/早期文档有一个仍需保留的规则差异，以及一个已经在本地 `main` 对齐的规则项：

1. **初始餐厅 pass**

   规则设计中保留“第一轮可 pass，第二轮必须放”的初始餐厅逻辑；当前实现尚未实现该流程。现有代码在 `Setup/ReserveCards` 结束后，由 `place_restaurant` 放置起始餐厅，`skip` 要求玩家已经放过餐厅。

   Bot 文档与代码应保留 pass 规划接口，但在当前引擎未支持前，候选生成器不得产出 pass 命令。

2. **First Errand Boy Played 里程碑**

   规则书要求：

   > If a player has the “First Errand Boy Played” milestone, each source will provide an extra drink. Errand boys will also bring in two drinks of the same type, including the errand boy just played.

   本地 `main` 已在 `1670651b fix(core): apply errand boy milestone drink bonus` 中对齐：Errand Boy 分支会在 `apply_use_employee_event()` 后读取更新后 state 上的 `procure_plus_one` bonus；首次打出并获得 `first_errand_boy` 的 Errand Boy 本次也拿 2 瓶同类饮料。Bot 只需按该现有规则建模，并保留回归测试。

### 0.3 实施原则

- Bot 只能输出 `Command`，不能直接改 `GameState`。
- Bot 必须通过严格 `ObservationAdapter` 读取信息，不能直接把完整 `GameState` 传给决策逻辑。
- 所有候选命令最终必须通过当前 `ActionRegistry` / executor validator 校验。
- 晚餐模拟不得另写一套会长期漂移的规则。首版以 fork 引擎真实推进为正确性基线，再逐步抽取快速 preview。
- 所有 AI 逻辑应保持纯逻辑、可 headless 测试，不依赖 UI Node。

## 1. 当前代码基线

### 1.1 核心入口

当前游戏引擎入口：

- `core/engine/game_engine.gd`
- `core/engine/game_engine/command_runner.gd`
- `core/actions/action_registry.gd`
- `core/engine/phase_manager.gd`
- `core/engine/phase_manager/definitions.gd`
- `gameplay/action_setup.gd`

执行命令的唯一正确入口是：

```gdscript
var command := Command.create("action_id", player_id, params)
var result := engine.execute_command(command)
```

`Command` 定义在 `core/types/command.gd`，实际字段包括：

- `index`
- `action_id`
- `actor`
- `params`
- `phase`
- `sub_phase`
- `timestamp`
- `metadata`

不要在 AI 层引入平行的 `ChooseReserveCardCommand`、`TrainCommand` 等类层级。AI 可用 `MacroAction` 表示意图，但最终必须落到当前 `Command.create(action_id, actor, params)`。

### 1.2 阶段与子阶段

当前阶段常量位于 `core/engine/phase_manager/definitions.gd`。

主阶段：

| 阶段 | 当前字符串 | 说明 |
| --- | --- | --- |
| 设置 | `Setup` | 储备卡选择与初始餐厅放置 |
| 公司重组 | `Restructuring` | 提交本回合公司结构 |
| 行动顺序 | `OrderOfBusiness` | 按空位数量选择 turn order |
| 工作阶段 | `Working` | 招聘、培训、市场、生产、扩张 |
| 晚餐 | `Dinnertime` | 进入阶段时结算销售 |
| 发薪 | `Payday` | 离开阶段时结算薪资 |
| 市场 | `Marketing` | 进入阶段时投放需求 |
| 清理 | `Cleanup` | 冰箱保留、opening soon 开业、里程碑清理 |
| 游戏结束 | `GameOver` | 终局 |

Working 子阶段默认顺序：

1. `Recruit`
2. `Train`
3. `Marketing`
4. `GetFood`
5. `GetDrinks`
6. `PlaceHouses`
7. `PlaceRestaurants`

实际顺序可被模块扩展；AI 不应硬编码为唯一事实，应优先从 `PhaseManager.get_working_sub_phase_order_names()` 读取。

### 1.3 结算机制

结算不是独立 `PhaseResolver`，而是由 `PhaseManager` hooks 与 `SettlementRegistry` 触发。

base 规则注册位置：

- `modules/base_rules/rules/phase_and_map.gd`
- `modules/base_rules/rules/phase/dinnertime_settlement.gd`
- `modules/base_rules/rules/phase/payday_settlement.gd`
- `modules/base_rules/rules/phase/marketing_settlement.gd`
- `modules/base_rules/rules/phase/cleanup_settlement.gd`

默认关键触发点：

- Dinnertime：进入阶段时结算。
- Payday：离开阶段时结算。
- Marketing：进入阶段时结算。
- Cleanup：进入阶段时执行清理逻辑。

Bot 的 forward simulation 必须复用这些触发点，不能跳过 auto-advance 与 settlement hooks。

## 2. 推荐目录结构

新增 AI 代码建议放在：

```text
core/
  ai/
    bot/
      fcm_bot.gd
      bot_config.gd
      bot_decision.gd
      ai_decision_context.gd

    observation/
      observation_adapter.gd
      observation_state.gd
      reserve_belief_model.gd
      opponent_public_state.gd

    analysis/
      analysis_context.gd
      board_analyzer.gd
      campaign_reach_analyzer.gd
      drink_route_analyzer.gd
      dinner_preview.gd
      market_opportunity_analyzer.gd
      milestone_race_analyzer.gd

    candidates/
      macro_action.gd
      candidate_generator.gd
      reserve_choice_candidates.gd
      initial_restaurant_candidates.gd
      restructuring_candidates.gd
      turn_order_candidates.gd
      working_candidates.gd
      salary_fire_candidates.gd
      cleanup_candidates.gd

    evaluation/
      evaluator.gd
      feature_extractor.gd
      feature_weights.gd
      risk_model.gd

    search/
      search_controller.gd
      greedy_search.gd
      osla_search.gd
      beam_search.gd
      time_budget.gd

    simulation/
      ai_engine_fork.gd
      forward_simulator.gd

    logging/
      decision_trace.gd
      explanation_formatter.gd

core/tests/
  ai/
    observation_adapter_test.gd
    board_analyzer_test.gd
    dinner_preview_golden_test.gd
    candidate_generator_test.gd
    greedy_bot_smoke_test.gd

data/
  bots/
    easy.json
    normal.json
    hard.json
    expert.json

tools/
  run_bot_selfplay.gd
  run_bot_selfplay.sh
```

理由：

- `core/ai/` 保持纯逻辑，不依赖 UI Node。
- `data/bots/*.json` 与现有模块内容格式一致，避免额外 YAML 解析依赖。
- UI、在线房间、调试面板只做 Bot 接入胶水，不放核心策略。

## 3. AI 与引擎接口契约

### 3.1 Bot 主接口

建议接口：

```gdscript
class_name FcmBot
extends RefCounted

func choose_command(
		observation: ObservationState,
		context: AiDecisionContext,
		budget: TimeBudget
	) -> BotDecision:
	return BotDecision.pass_decision()
```

`BotDecision` 至少包含：

- `command: Command`
- `macro_action: MacroAction`
- `score: float`
- `explanation: Dictionary`
- `trace: Dictionary`

首版每个决策点只返回一个命令。后续可允许返回命令序列，但执行层仍应逐条校验与执行。

### 3.2 决策点识别

不要新增和引擎脱节的 `DecisionPointType` 枚举作为事实源。正确做法是用当前状态与 action registry 推导：

```gdscript
var phase := state.phase
var sub_phase := state.sub_phase
var player_id := state.get_current_player_id()
var initiatable := engine.action_registry.get_player_initiatable_actions(state, player_id)
var mandatory := engine.action_registry.get_mandatory_actions(state)
```

AI 可在内部归类为以下决策点：

| AI 决策点 | 当前判断方式 | 主要 action |
| --- | --- | --- |
| 储备卡选择 | `Setup/ReserveCards` | `select_reserve_card` |
| 初始餐厅 | `Setup` 且 sub_phase 为空 | `place_restaurant`；未来可支持 pass |
| 公司重组 | `Restructuring` | `submit_restructuring` |
| 行动顺序 | `OrderOfBusiness` | `choose_turn_order` |
| 招聘 | `Working/Recruit` | `recruit` / `skip_sub_phase` |
| 培训 | `Working/Train` | `train` / `skip_sub_phase` |
| 市场 | `Working/Marketing` | `initiate_marketing` / `skip_sub_phase` |
| 食物生产 | `Working/GetFood` | `produce_food` / `skip_sub_phase` |
| 饮料采购 | `Working/GetDrinks` | `procure_drinks` / `skip_sub_phase` |
| 房屋/花园 | `Working/PlaceHouses` | `place_house` / `add_garden` / `skip_sub_phase` |
| 餐厅扩张 | `Working/PlaceRestaurants` | `place_restaurant` / `move_restaurant` / `skip` |
| 发薪裁员 | `Payday` | `fire` / `skip` |
| 冰箱保留 | `Cleanup` pending action | `choose_fridge_keep` |
| 结算确认 | pending action | `confirm_dinnertime` / `confirm_marketing` |

注意：`select_reserve_card`、`restructure_employee`、`set_company_structure_direct`、`set_company_structure_report` 等是 internal action，不会出现在普通 ActionPanel 的 `get_player_initiatable_actions()` 结果里。AI controller 可以对白名单 internal action 直接构造命令，但仍必须通过当前 executor validate 与 `engine.execute_command()`。

### 3.3 当前 action 参数表

| 意图 | action_id | 关键 params |
| --- | --- | --- |
| 选择储备卡 | `select_reserve_card` | `selected_index` |
| 放初始餐厅/新餐厅 | `place_restaurant` | `position: Vector2i`, `rotation: int`, Working 时可带 `employee_type`, `staff_id` |
| 移动餐厅 | `move_restaurant` | `restaurant_id`, `position`, `rotation`, 可带 `employee_type`, `staff_id` |
| 移员工到待命 | `restructure_employee` | `employee_id`, `to_reserve` |
| 设置 CEO 直属槽 | `set_company_structure_direct` | `slot_index`, `employee_id` |
| 设置经理下属 | `set_company_structure_report` | `manager_slot_index`, `employee_id` |
| 提交公司结构 | `submit_restructuring` | 无；读取 `player.company_structure.structure` |
| 选择行动顺序 | `choose_turn_order` | `position` |
| 招聘 | `recruit` | `employee_type`, 可带 `staff_id` |
| 培训 | `train` | `from_employee`, `to_employee`, 可带 `source_staff_id`/`staff_id`, `trainer_staff_id` |
| 发起营销 | `initiate_marketing` | `employee_type`, `board_number`, `product`, `position`, 可带 `rotation`, `duration`, `axis`, `staff_id` |
| 生产食物 | `produce_food` | `employee_type`, 可带 `food_type`, `staff_id` |
| 采购饮料 | `procure_drinks` | Errand Boy: `employee_type`, `drink_type`; 路线型: `employee_type`, `route`, `selected_sources`, 可带 `staff_id` |
| 放房屋 | `place_house` | `position`, `rotation`, `house_number`, 可带 `employee_type`, `staff_id` |
| 加花园 | `add_garden` | `house_id`, `direction`, 可带 `employee_type`, `staff_id` |
| 价格经理 | `set_price` | 无 |
| 折扣经理 | `set_discount` | 无 |
| 奢侈经理 | `set_luxury_price` | 无 |
| 裁员 | `fire` | `employee_id`, 可带 `location`, `staff_id` |
| 冰箱保留 | `choose_fridge_keep` | `keep: Dictionary` |
| 跳过子阶段 | `skip_sub_phase` | 无 |
| 确认结束 | `skip` | 无 |

AI 候选生成器可以构造参数，但最终必须调用 executor validate。凡是 validate 失败的候选直接丢弃，并记录 trace。

## 4. 严格隐藏信息

### 4.1 强制 ObservationAdapter

首版按严格版实现：Bot 决策层不得接收完整 `GameState`。只有 `ObservationAdapter.observe_for_player(engine, player_id)` 可以读取真实状态并生成 `ObservationState`。

`ObservationState` 应是只读快照，至少包含：

- 自己的完整玩家状态。
- 对手公开现金、餐厅、库存、公开员工区域、已公开里程碑。
- 当前地图公开状态。
- 当前阶段、子阶段、turn order、round number、bank 状态。
- 自己可见的 reserve card 信息。
- 对手隐藏信息的 belief model 输入，而不是原值。

### 4.2 储备卡隐藏

现有 `core/utils/command_privacy.gd` 只对命令参数做联机脱敏，不足以作为 Bot 观察层。

ObservationAdapter 必须遵守：

- 本人能看到自己的 `reserve_cards`、`reserve_card_selected`。
- 对手的 `reserve_card_selected` 在 `reserve_card_revealed == false` 时不可见。
- 若观察者有 `can_peek_all_reserve_cards`，可见所有玩家的储备卡选择。
- 若储备卡已揭示，可见。

### 4.3 公司结构隐藏

`submit_restructuring` 是 hotseat 同时提交模型。严格 Bot 应按规则处理未公开结构：

- Restructuring 中，自己提交前可见自己的编辑中结构。
- 对手未提交或阶段未 finalized 时，不得读取对手本回合计划结构。
- 所有人提交并进入后续阶段后，公司结构公开。
- 对手结构未知时使用 `BeliefState` 采样，而不是读取真实 `player.company_structure.structure`。

### 4.4 BeliefState

首版 belief 不需要复杂，但必须接口正确：

- `ReserveBeliefModel`：对未知储备卡按可行范围采样。
- `StructureBeliefModel`：对未公开公司结构生成若干合理结构样本。
- `OpponentPolicy`：用 `RandomLegalBot` / `ScriptBot` / 简化 HeuristicBot 预测对手后续行动。

任何搜索或模拟如果使用隐藏信息样本，必须在 trace 中标明样本来源，避免调试时误以为是确定信息。

## 5. 当前状态模型摘要

### 5.1 GameState

`GameState` 定义在 `core/state/game_state.gd`，重要字段：

- `round_number`
- `phase`
- `sub_phase`
- `turn_order`
- `current_player_index`
- `selection_order`
- `bank`
- `rules`
- `modules`
- `players`
- `map`
- `employee_pool`
- `milestone_pool`
- `marketing_instances`
- `round_state`
- `seed`

已有 `duplicate_state()` 与 `compute_hash()`。AI 不应自行实现深拷贝格式，优先复用当前方法。

### 5.2 Player

玩家字典由 `core/state/game_state_factory.gd` 初始化，常用字段：

- `id`
- `cash`
- `employees`
- `employees_staff_ids`
- `reserve_employees`
- `reserve_staff_ids`
- `busy_marketers`
- `busy_staff_ids`
- `staff_registry`
- `inventory`
- `restaurants`
- `milestones`
- `company_structure`
- `reserve_cards`
- `reserve_card_selected`
- `reserve_card_revealed`
- `banned_employee_ids`
- `can_peek_all_reserve_cards`
- `multi_trainer_on_one`
- `ceo_cfo_ability_start_round`

AI 读取这些字段时应优先使用现有 access helpers，例如：

- `core/state/player_state_access.gd`
- `core/state/map_state_access.gd`
- `core/state/staff_state.gd`

不要在 AI 里散落大量裸字典读取。

### 5.3 round_state

`round_state` 是很多规则的事实来源。Bot 必须理解以下常见键：

- `mandatory_actions_completed`
- `actions_this_round`
- `action_counts`
- `sub_phase_passed`
- `staff_usage`
- `staff_train_event_counts`
- `restructuring`
- `order_of_business`
- `price_modifiers`
- `production_counts`
- `procurement_counts`
- `house_placement_counts`
- `opening_soon_restaurants`
- `pending_phase_actions`
- `dinnertime`
- `payday`
- `milestones_claimed`
- `milestones_auto_awarded`

AI 评分价格、薪资、里程碑、opening soon 时不能只看静态员工列表，必须结合 `round_state`。

## 6. Forward Simulation

### 6.1 首版正确性路线

首版模拟器应优先正确：

1. 从当前 `GameEngine` fork 一个 simulation engine。
2. 复制 `state`、`module_plan_v2`、registry bundles、ruleset、action registry、phase manager 必要依赖。
3. 对候选命令逐条执行 `simulation_engine.execute_command(command)`。
4. 让 auto-advance 和 settlement hooks 正常运行。
5. 从模拟后的 `state` / `round_state` 提取评分特征。

建议新增 `core/ai/simulation/ai_engine_fork.gd`，封装这些细节。不要让各个搜索器自己复制引擎。

### 6.2 全局 registry 注意事项

`GameEngine.activate_registry_bundles()` 会切换当前 bundle：

- `ProductRegistry`
- `EmployeeRegistry`
- `MarketingRegistry`
- `MilestoneRegistry`
- `TileRegistry`
- `PieceRegistry`
- `MarketingTypeRegistry`
- `DinnertimeDemandRegistry`
- `DinnertimeRoutePurchaseRegistry`
- `MilestoneEffectRegistry`

AI 并行模拟前必须先解决 registry 切换问题。首版建议单线程搜索，避免多个 fork 同时切换全局 bundle。

### 6.3 快速模拟路线

只有在黄金测试稳定后，才实现快速 preview：

- `DinnerPreview` 复用或抽取 `DinnertimeHouseSales`、`DinnertimeSelection`、`PricingPipeline`。
- `BoardAnalyzer` 复用 `RoadGraphCache`、`Structures.get_restaurant_entrance_points()`、`RangeUtils`。
- `DrinkRouteAnalyzer` 复用 `DrinksProcurement.resolve_procurement_plan()` 做合法性确认。

快速版本必须与真实 engine settlement 做 golden 对照。

## 7. BoardAnalyzer

### 7.1 目标

`BoardAnalyzer` 把当前地图转成 AI 可快速查询的数据：

- 房屋、餐厅、道路、饮料源。
- 餐厅到房屋距离。
- 营销覆盖范围。
- 饮料路线候选。
- 可放餐厅、房屋、花园位置。
- 竞争热点与价格距离差。

### 7.2 应复用的现有代码

优先复用：

- `core/map/map_runtime/coords.gd`
- `core/map/map_runtime/structures.gd`
- `core/map/map_runtime/road_graph_cache.gd`
- `modules/base_rules/rules/phase/dinnertime/dinnertime_distance.gd`
- `core/utils/range_utils_road/*`
- `core/utils/range_utils_air.gd`
- `core/rules/marketing_type_registry.gd`
- `modules/base_marketing/rules/entry.gd`
- `core/rules/drinks_procurement.gd`

### 7.3 餐厅入口与 drive-through

当前 drive-through 不是单独路径模式，而是入口点查询规则：

`Structures.get_restaurant_entrance_points(state, restaurant_id, rest)`

若餐厅 owner 有在岗 `drivethrough` 标签员工，则该餐厅四角都视为入口点；否则只使用 `entrance_pos`。Local Manager / Regional Manager 的具体行为通过员工 tag 和餐厅放置逻辑体现。

因此 AI 距离查询不应自己判断四角入口，应调用同一个 helper。

### 7.4 营销 reach

营销类型由 `MarketingTypeRegistry` 和 base marketing 模块注册。首版支持 base 类型：

- billboard
- mailbox
- airplane
- radio

候选生成时按 `initiate_marketing` validate 为准：

- `board_number`
- `product`
- `position`
- `rotation`
- `duration`
- `axis`（airplane）
- `employee_type`
- `staff_id`

营销在 Working 阶段发起，但需求在 `Marketing` 阶段结算产生；同回合 Dinnertime 不会吃到本回合新广告。

### 7.5 饮料路线

饮料路线生成不要只写抽象 DFS 后直接执行。正确流程：

1. `DrinkRouteAnalyzer` 生成有限数量候选 route 和 selected_sources。
2. 用 `Command.create("procure_drinks", actor, params)` 构造命令。
3. 通过 `ProcureDrinksAction` / `DrinksProcurement.resolve_procurement_plan()` 校验。
4. 丢弃 validate 失败候选。

Errand Boy 当前规则：

- 无需地图饮料源。
- 每种注册饮料各生成一个候选。
- 没有 `first_errand_boy` 时拿 1 瓶。
- 有 `first_errand_boy`，包括本次刚触发时，应拿 2 瓶同类饮料。

路线型采购员工：

- 使用当前员工定义的 range / route 类型。
- `first_cart_operator` 等距离里程碑通过现有规则查询，不在 AI 中硬编码。
- 每名采购员工保留 topK 路线，先按能满足的当前/未来需求打分。

## 8. Dinner Preview

### 8.1 当前真实晚餐流程

真实晚餐结算入口：

- `modules/base_rules/rules/phase/dinnertime_settlement.gd`
- `modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd`
- `modules/base_rules/rules/phase/dinnertime/dinnertime_house_sales.gd`
- `modules/base_rules/rules/phase/dinnertime/dinnertime_selection.gd`
- `modules/base_rules/rules/phase/dinnertime/dinnertime_distance.gd`

关键规则：

- 房屋按 `Structures.get_sorted_house_ids(state)` 的 house number 顺序处理。
- 每个房屋必须完整满足需求，否则该餐厅不能服务该房屋。
- 需求变体由 `DinnertimeDemandRegistry` 提供；base 之外模块可加入 noodles/sushi 等替代需求。
- 候选餐厅用 `decision_unit_price + distance` 比较。
- 平局先比 tiebreak effect（base 中 waitress），再比 turn order，再比同玩家更短距离/步数/餐厅 id。
- 花园影响收入，不改变顾客选择时的 `decision_unit_price`。
- 销售后立即扣库存，因此前面房屋会影响后面房屋。
- waitress tips、CFO bonus、route purchases、sale house bonus、bankruptcy events 都在结算内处理。

### 8.2 价格计算

不要按“在岗价格经理数量”直接算价格。当前实现通过 `PricingPipeline` 与 `round_state.price_modifiers` 计算：

- 基础单价来自 `state.rules["base_unit_price"]`，通常为 10。
- `first_lower_prices` 等里程碑通过 `base_price_delta` 修正。
- `set_price`、`set_discount`、`set_luxury_price` 写入本回合 `round_state.price_modifiers`。
- mandatory price actions 可被 `auto_advance_working_mandatory.gd` 自动补完。

因此 AI 在模拟 Dinnertime 前必须保证相关 mandatory actions 已执行或让 fork engine auto-advance 补完。

### 8.3 DinnerPreview 输出

`DinnerPreview` 可返回轻量结构，但字段应能映射真实 `round_state.dinnertime`：

- `sales`
- `skipped`
- `income_sales`
- `income_sale_house_bonus`
- `income_tips`
- `income_cfo_bonus`
- `total_income`
- `sold_marketed_demand_events`
- `bankruptcy_events`

首版可以直接 fork 到 Dinnertime 后读取真实 `round_state.dinnertime`，性能优化以后再做。

### 8.4 Golden 测试

必须覆盖：

- 房屋顺序消耗库存。
- 低价距离选择不乘需求数量。
- 花园只影响收入，不影响选择价格。
- waitress 平局。
- `first_burger_marketed` / `first_pizza_marketed` / `first_drink_marketed` bonus。
- CFO bonus 向上取整。
- 破产后强制 `GameOver`。
- drive-through 四角入口。
- 模块关闭时 base 行为稳定。

## 9. 候选生成

### 9.1 通用规则

候选生成器输出 `MacroAction`：

```gdscript
{
	"id": "human_readable_id",
	"commands": [Command],
	"prior_score": 0.0,
	"tags": [],
	"debug": {},
}
```

首版每个 `MacroAction` 通常只含一个命令。公司结构是例外：一个结构候选应展开为多条 internal 编辑命令，再以 `submit_restructuring` 结束，不能绕过命令系统直接写真实状态。

所有候选必须：

- 数量有限。
- 有 deterministic 排序。
- validate 后再进入搜索。
- 记录丢弃原因，便于调试。

### 9.2 储备卡选择

当前 action：

```gdscript
Command.create("select_reserve_card", player_id, {"selected_index": i})
```

启发式：

- 优先选择能延长 bank clock 且不破坏早期现金节奏的卡。
- 严格隐藏信息下，只能看自己的 reserve cards。
- 若有 `can_peek_all_reserve_cards`，ObservationAdapter 可提供对手选择信息。

### 9.3 初始餐厅放置

当前 action：

```gdscript
Command.create("place_restaurant", player_id, {
	"position": Vector2i(x, y),
	"rotation": rotation,
})
```

候选评分：

- 附近早号房价值。
- 未来 billboard/mailbox/radio 位置。
- 饮料路线起点价值。
- 距离对手优势。
- 后续扩张空间。
- 入口 tile 冲突风险。

保留未来 pass 接口：

```gdscript
{
	"type": "initial_restaurant_pass",
	"enabled": false,
}
```

在当前引擎未支持初始餐厅 pass 前，该候选必须禁用。

### 9.4 公司结构

当前 `submit_restructuring` 不从 command params 接收结构，而是读取：

`player.company_structure.structure`

因此 AI 真实执行时应生成如下命令序列：

1. 用 `restructure_employee` 把不需要上班的员工移到待命。
2. 用 `set_company_structure_direct` 设置 CEO 直属槽。
3. 用 `set_company_structure_report` 设置经理下属。
4. 用 `submit_restructuring` 提交。

这些编辑 action 是 internal action，但仍是正式命令。AI 只允许在自己的 Restructuring 决策中使用它们。

结构格式：

```gdscript
{
	"ceo_slots": 3,
	"structure": [
		{"employee_id": "trainer", "reports": ["management_trainee"]},
		{"employee_id": "", "reports": []},
		{"employee_id": "pricing_manager", "reports": []},
	]
}
```

提交时当前实现会 normalize/prune：

- CEO 自动纠正回在岗。
- 未知员工移除。
- 数量不足的重复员工移除。
- 经理不能作为下属。
- 超过 manager capacity 的下属移除。
- 未放入结构的员工进入 reserve。

Bot 不能依赖“非法结构会原样失败”。候选生成必须先用当前公司结构规则预校验，避免被 prune 后行为和评分不一致。

### 9.5 Order of Business

当前选择顺序由 `WorkingFlow.start_order_of_business()` 计算：

- 空位多的玩家先选。
- 空位相同按上一轮 turn order 打破平局。
- `first_airplane` 的 `turnorder_empty_slots` 会增加空位计数。

选择命令：

```gdscript
Command.create("choose_turn_order", player_id, {"position": slot})
```

评分：

- 本轮关键稀缺动作是否要抢先。
- Dinnertime 平局是否需要更早 turn order。
- 是否需要靠后观察对手。
- 是否要避免先服务高需求导致库存被过早消耗。

### 9.6 Working 子阶段

Recruit：

- `recruit` 候选来自员工池、现金、当前结构需求、里程碑竞速。
- 第三次 recruit 触发 `first_hire_3` 的逻辑应通过真实事件系统判断。

Train：

- `train` 只能沿员工定义 `train_to` 路径。
- coach/guru 多步、培训锁、`multi_trainer_on_one`、`train_from_active_same_color` 都由当前 executor 管。
- 候选生成只生成少量目标路径，并依赖 validate 筛选。

Marketing：

- `initiate_marketing` 必须满足 board spec、range、位置合法性。
- 首版只支持 base marketing。
- 广告评分要考虑未来数轮收益和是否帮对手。

GetFood：

- `produce_food` 根据员工定义生产。
- kitchen trainee 等需要 `food_type` 的员工要生成多个候选。

GetDrinks：

- Errand Boy 按当前已对齐的规则处理。
- route-based 员工由 `DrinkRouteAnalyzer` 生成 topK 合法路线。

PlaceHouses：

- `place_house` 使用当前房屋供应号。
- 当前新房 action 放的是 `house_with_garden`，即新房自带花园。
- `add_garden` 与 `place_house` 共享房屋/花园放置计数，需要通过 action count 校验。

PlaceRestaurants：

- `local_manager` 放置 `opening_soon` 餐厅，Cleanup 才正式开业。
- `regional_manager` 可立即放/移餐厅。
- `place_restaurant` 与 `move_restaurant` 共享使用次数。

### 9.7 Payday 与裁员

薪资结算入口是 `modules/base_rules/rules/phase/payday_settlement.gd`。Bot 不应使用简化公式。

当前薪资因素：

- `state.rules["salary_cost"]`
- `salary_cost_override`
- `EmployeeRules.count_paid_employees(player)`
- 招聘经理/HR 未使用招聘折扣。
- `salary_total_delta` 里程碑。
- 可选 `salary_pay_with_tokens`
- 可选 `salary_allow_unpaid`

裁员 action：

```gdscript
Command.create("fire", player_id, {
	"employee_id": employee_id,
	"location": "active",
	"staff_id": staff_id,
})
```

Bot 裁员策略：

- 优先保留能产生本轮或下轮现金的员工。
- 忙碌市场人员通常不能裁，除非满足当前 executor 的特殊条件。
- 现金危机时用 fork engine 验证裁员序列能通过 Payday。

### 9.8 Cleanup

Cleanup 相关真实逻辑：

- `choose_fridge_keep`
- `CleanupSettlement.apply_opening_soon_restaurants`
- `CleanupSettlement.apply_cleanup_milestones`

Bot 需要处理：

- 冰箱容量来自 `gain_fridge` 里程碑。
- `keep` 字典总数不得超过容量。
- 同回合获得的里程碑在 Cleanup 从 `milestone_pool` 移除。
- `expires_at` 里程碑会在 Cleanup 清理。
- `opening_soon_restaurants` 在 Cleanup 正式写入 `state.map.restaurants`。

## 10. 评价函数

首版 `Evaluator` 采用线性特征即可：

```text
score =
  cash_value
  + expected_dinner_income
  + inventory_value
  + employee_value
  + milestone_value
  + map_position_value
  + marketing_pipeline_value
  + turn_order_value
  - salary_risk
  - bank_clock_risk
  - hidden_info_risk
```

特征必须从 `ObservationState` 与 simulation result 提取，不得越过隐藏信息边界读取真实对手结构/储备卡。

关键 feature：

- 当前现金与预计发薪后现金。
- 下一次 Dinnertime 可服务房屋数。
- 能否抢到关键里程碑。
- 是否有足够厨师/采购/市场/培训链条。
- 广告是否主要给自己创造需求。
- 对手在 belief 样本下可反抢的概率。
- bank 离破产还有多少现金。

## 11. 搜索策略

### 11.1 实现顺序

1. `RandomLegalBot`
2. `ScriptBot`
3. `GreedyBot`
4. `OSLABot`
5. `BeamSearchBot`

首版不要直接上 MCTS。当前游戏分支因子高、结算复杂、隐藏信息多，先把候选和 forward simulation 做准更重要。

### 11.2 RandomLegalBot

用途：

- 验证 action registry 接入。
- 自对弈压力测试。
- 避免 Bot controller 软锁。

要求：

- 只从 `get_player_initiatable_actions()` 与候选参数生成器中选择。
- 对需要参数的 action 必须有最小合法参数生成器。
- 若无真实动作，选择 `skip_sub_phase` 或 `skip`。

### 11.3 GreedyBot

流程：

1. 识别决策点。
2. 生成 topN 候选。
3. 对每个候选 fork engine 执行。
4. 让 auto-advance 跑到稳定点或指定 horizon。
5. 用 Evaluator 打分。
6. 选择最高分合法命令。

### 11.4 OSLA / Beam

OSLA 用一层自己的候选 + 对手简单策略 response。

Beam Search 用 `MacroAction` 而不是裸 action 枚举，并设置：

- 最大宽度。
- 最大深度。
- 每阶段 topK。
- 每个候选最大模拟时间。

所有搜索都必须支持固定 seed 与 deterministic 排序。

## 12. 模块扩展契约

虽然首版只支持 base，AI 架构必须预留扩展点：

- 未识别 action：默认不主动生成，但可由 `RandomLegalBot` fallback 处理。
- 未识别产品：ObservationState 仍记录 inventory/demand，Evaluator 用通用商品价值。
- 未识别营销类型：只通过 registry reach 查询，不手写规则。
- 未识别 Dinnertime demand variant：DinnerPreview 以真实引擎结算为准。
- 模块新增里程碑：MilestoneRaceAnalyzer 用 trigger/effects 数据做弱评估，必要时配置覆盖。

每个扩展模块接入 AI 时，需要补：

- 候选生成器。
- feature extractor。
- golden tests。
- 难度配置权重。

## 13. 日志与调试

每次 Bot 决策记录 `DecisionTrace`：

- `round_number`
- `phase`
- `sub_phase`
- `player_id`
- `observation_hash`
- `candidate_count`
- `valid_candidate_count`
- `chosen_action_id`
- `chosen_params`
- `score`
- `top_candidates`
- `discarded_reasons`
- `belief_samples_summary`
- `time_ms`

解释文本只面向 UI/调试，不参与规则：

```text
选择培训 Burger Cook：下轮可服务 2 个 burger 需求，并竞争 first_burger_produced。
```

## 14. 测试计划

测试原则：

- 规则正确性复用现有 core/golden 测试作为 oracle；AI 测试只验证 Bot、Observation、candidate、simulation 是否调用同一套规则。
- smoke test 复用当前 headless 聚合入口和 deterministic replay 思路，不新建测试 runner。
- golden test 不复制结算规则，期望值来自同一前置状态下的真实 engine settlement/report。

### 14.1 规则回归测试

必须保留测试：

- Errand Boy 首次使用并获得 `first_errand_boy` 时，本次拿 2 瓶。
- 已有 `first_errand_boy` 时，后续 Errand Boy 拿 2 瓶。
- 路线型采购仍按每 source +1。

初始餐厅 pass 保留为未来规则工作；若实现 pass，也要补 Setup 双轮放置测试。

### 14.2 AI 观察测试

`core/tests/ai/observation_adapter_test.gd`：

- 对手未揭示 reserve card 不可见。
- `can_peek_all_reserve_cards` 后可见。
- Restructuring 未 finalized 时对手结构不可见。
- finalized 后结构可见。

可复用现有隐私覆盖作为 oracle：

- `core/tests/command_privacy_test.gd`
- `ui/scenes/tests/reserve_card_selection_modal_privacy_test.gd`
- `ui/scenes/tests/entity_tab_reserve_card_privacy_test.gd`
- `ui/scenes/tests/reserve_cards_full_screen_view_privacy_test.gd`
- `ui/scenes/tests/restructuring_privacy_test.gd`

### 14.3 候选生成测试

- 每个阶段至少能生成一个合法命令或合法 skip。
- 所有候选 validate 通过。
- 隐藏信息测试中候选生成不读取真实隐藏字段。
- 初始餐厅 pass 在当前引擎未支持前不会生成。

候选测试应尽量复用现有 action/state access 测试的 fixture；生产候选 helper 若参考 `tools/manual_test_saves/builders/*`，需要先抽到 `core/`，不能让 AI runtime 依赖 `tools/`。

### 14.4 Dinner golden 测试

复用并扩展现有测试：

- `core/tests/dinnertime_settlement_test.gd`
- `core/tests/dinnertime_distance_entry_boundary_test.gd`
- `core/tests/dinnertime_demand_registry_v2_test.gd`
- `core/tests/marketing_dinnertime_golden_replay_test.gd`
- `core/tests/confirm_dinnertime_availability_test.gd`
- `core/tests/online_dinnertime_confirm_enforced_test.gd`

新增 AI golden：同一状态下，`DinnerPreview` 与真实 Dinnertime settlement 的销售、收入、库存、bankruptcy 结果一致。

### 14.5 自对弈 smoke

复用当前 AllTests/headless 测试入口，新增 AI suite 或挂在现有 suite 附近：

- 2p base 模块。
- 固定 seed。
- 两个 `RandomLegalBot` 能跑到至少第 3 轮或 GameOver。
- 无 softlock。
- replay hash deterministic。

可复用：

- `core/tests/replay_determinism_test.gd` 的 deterministic 校验思路。
- `tools/run_headless_test.sh` 与 `ui/scenes/tests/all_tests.tscn`。
- 现有 action panel “隐藏非 initiatable special actions”测试可作为 internal action 白名单的 UI 侧参考，但 Bot 白名单仍应在 `LegalActionService` 中独立约束。

运行方式仍使用：

```bash
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests
```

当前实现状态：

- `core/tests/ai/random_legal_bot_smoke_test.gd`：两个 `RandomLegalBot` 在 2p base、固定 seed 下跑到至少第 3 轮或 GameOver，并校验同 seed 行动 trace deterministic。
- `core/tests/ai/greedy_bot_smoke_test.gd`：保留 GreedyBot 短程 deterministic 校验，并新增单程跑到至少第 3 轮或 GameOver 的 smoke。完整打完 2p base 局仍未完成。

## 15. 开发路线图

Phase -1 到 Phase 1 的可执行任务拆解与现有代码复用总表见：[fcm_heuristic_bot_phase0_phase1_breakdown.md](fcm_heuristic_bot_phase0_phase1_breakdown.md)。

### Phase -1：规则对齐

- 确认 Errand Boy + `first_errand_boy` 已按规则书对齐。
- 保留对应 core 回归测试。
- 保留初始餐厅 pass 为规则差异记录，不在当前 Bot 候选中启用。

### Phase 0：接口与观察层

- 新建 `core/ai/` 基础结构。
- 实现 `ObservationAdapter` 严格隐藏信息。
- 实现 `BotDecision`、`MacroAction`、`TimeBudget`。
- 实现 `RandomLegalBot` 的最小合法行动。

### Phase 1：Simulation 与 DinnerPreview

- 实现 `AiEngineFork`。
- 实现基于 fork engine 的 forward simulation。
- 实现 DinnerPreview 正确性基线。
- 补 golden tests。

### Phase 2：BoardAnalyzer 与候选生成

- BoardAnalyzer 复用当前地图/距离/range helper。
- 实现 base 模块候选生成：
  - reserve
  - initial restaurant
  - restructuring
  - turn order
  - recruit/train
  - marketing
  - production/drinks
  - expansion
  - salary/fire
  - cleanup

### Phase 3：GreedyBot MVP

- 实现线性 Evaluator。
- GreedyBot 可完整打完 2p base 局。
- 记录 DecisionTrace。
- 加入难度 JSON。

### Phase 4：OSLA 与 Beam

- 实现简单 opponent policy。
- OSLA 加入一层对手响应。
- Beam 只枚举 MacroAction topK。
- 加时间预算与 deterministic seed。

### Phase 5：自对弈调参

- `tools/run_bot_selfplay.gd`
- 输出 JSONL match logs。
- 支持固定 bot config 对战。
- 先做简单网格/随机搜索，再考虑 SPSA。

### Phase 6：产品接入

- UI/本地游戏可选择 Bot 玩家。
- 在线/房间配置中 Bot 不泄露隐藏信息。
- 调试面板显示 DecisionTrace。
- 长时间思考有超时 fallback。

## 16. 最小可用实现顺序

最小切片建议：

1. 确认 Errand Boy 回归测试通过。
2. `ObservationAdapter`。
3. `RandomLegalBot` 能从 Setup 跑到 Working。
4. `AiEngineFork`。
5. Greedy 初始餐厅 + reserve。
6. Greedy restructuring + recruit/train。
7. DinnerPreview golden。
8. Greedy 生产/饮料/营销。
9. Payday fire 策略。
10. 自对弈 smoke。

## 17. 常见失败模式

- Bot 直接读取 `GameState`，导致隐藏信息作弊。
- 价格只看员工，不看 `round_state.price_modifiers`。
- 晚餐模拟漏掉需求变体或 route purchases。
- drive-through 自己算四角入口，和 `Structures.get_restaurant_entrance_points()` 漂移。
- Errand Boy 回归测试未纳入就开始训练权重。
- `submit_restructuring` 候选被 executor prune 后，与评分时结构不一致。
- Local Manager opening soon 被当成本轮可营业餐厅。
- Cleanup 前就把同回合里程碑从 pool 移除。
- 搜索并行切换全局 registry，导致模拟串局。
- 候选生成不 deterministic，replay 难以复现。

## 18. 验收检查表

### 架构

- [ ] AI 核心在 `core/ai/`，不依赖 UI Node。
- [ ] Bot 只输出 `Command`。
- [ ] 所有候选命令经当前 validator 校验。
- [ ] ObservationAdapter 是唯一真实状态入口。
- [ ] Simulation 复用当前 `GameEngine` 和 settlement hooks。

### 规则

- [x] Errand Boy 规则已按规则书修复并测试。
- [ ] 初始餐厅 pass 当前禁用但接口保留。
- [ ] DinnerPreview 与真实 settlement 有 golden test。
- [ ] Pricing 使用 `PricingPipeline` / `round_state.price_modifiers`。
- [ ] Drive-through 使用 `Structures.get_restaurant_entrance_points()`。
- [ ] Cleanup、Payday、Marketing 均通过真实 settlement 模拟。

### 强度

- [x] RandomLegalBot 无 round 3 smoke softlock（完整局仍待自对弈工具覆盖）。
- [ ] GreedyBot 能完整打完 2p base 局。
- [ ] 决策 trace 可解释最高分候选。
- [x] 固定 seed 下 RandomLegalBot selfplay deterministic；GreedyBot 短程 deterministic。
- [ ] 搜索超时有合法 fallback。

## 19. 后续模块支持顺序建议

base MVP 之后，按影响面从小到大支持：

1. `new_milestones`
2. `fry_chefs`
3. `coffee`
4. `noodles` / `sushi`
5. `rural_marketeers`
6. `lobbyists`

每支持一个模块，都要先补 AI golden tests，再纳入难度配置与自对弈验收。
