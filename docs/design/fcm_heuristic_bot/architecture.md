# 启发式人机对手：架构与接口契约

本文由原 `fcm_heuristic_bot_implementation_plan.md` 拆分而来，聚焦 AI 代码基线、目录结构、接口、隐藏信息和状态模型。

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

    strategy/
      strategy_profile.gd
      strategy_candidate_filter.gd
      strategy_board_analyzer.gd
      strategy_income_analyzer.gd
      strategy_scorer.gd
      phase_policy_*.gd

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
    strategy_bot_test.gd

data/
  bots/
    easy.json
    normal.json
    hard.json
    expert.json

tools/
  run_bot_selfplay.gd
  run_bot_selfplay.sh
  run_bot_selfplay_matrix.gd
  run_bot_selfplay_matrix.sh
  run_bot_tuning_matrix.gd
  run_bot_tuning_matrix.sh
  generate_bot_profile_variants.gd
  generate_bot_profile_variants.sh
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
