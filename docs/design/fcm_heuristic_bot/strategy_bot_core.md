# 启发式人机对手：StrategyBot 核心策略

本文聚焦 StrategyBot 的阶段策略、profile、planner 组件与当前已落地能力。

### 11.4 StrategyBot

StrategyBot 是下一阶段真正的人机对手入口。它不做单步 fork 贪心，而是：

1. 读取 `ObservationState`。
2. 复用 `CandidateGenerator` 产生合法 `MacroAction`。
3. 用 `StrategyProfile` 定义长期偏好（收入路线、员工路线、商品优先级、风险阈值）。
4. 用阶段策略评分候选，例如：
   - Restructuring：优先激活当前计划需要的生产/营销/采购/培训员工。
   - Recruit/Train：按当前能力缺口和路线目标选人。
   - Marketing：只考虑能影响房屋的营销，并按受影响房屋、商品供应能力、已有库存评分。
   - GetFood/GetDrinks：按下一轮需求、库存缺口和供应能力评分。
   - Payday/Cleanup：优先现金安全与保留可服务需求的库存。
5. 生成 `DecisionTrace`，输出 profile id、top candidates、features 与 discarded reasons。

当前已落地最小骨架：

- `core/ai/bot/strategy_bot.gd`
- `core/ai/strategy/strategy_profile.gd`
- `core/ai/strategy/strategy_candidate_filter.gd`
- `core/ai/strategy/strategy_board_analyzer.gd`
- `core/ai/strategy/strategy_cash_planner.gd`
- `core/ai/strategy/strategy_dinner_planner.gd`
- `core/ai/strategy/strategy_employee_planner.gd`
- `core/ai/strategy/strategy_income_analyzer.gd`
- `core/ai/strategy/strategy_scorer.gd`
- `core/ai/strategy/strategy_phase_planner.gd`
- `core/ai/strategy/strategy_route_planner.gd`
- `core/ai/strategy/strategy_recruit_planner.gd`
- `core/ai/strategy/strategy_setup_planner.gd`
- `core/ai/strategy/strategy_supply_planner.gd`
- `core/ai/strategy/strategy_train_planner.gd`
- `core/ai/strategy/strategy_marketing_planner.gd`
- `core/ai/strategy/strategy_structure_planner.gd`
- `core/ai/strategy/strategy_support_planner.gd`
- `core/tests/ai/strategy_bot_test.gd`
- `data/bots/base_revenue_v1.json`
- `data/bots/base_revenue_growth_v1.json`

当前 StrategyBot 已在评分前增加策略层候选过滤：

- `StrategyProfile.configure_base_revenue()` 优先读取 `data/bots/base_revenue_v1.json`，解析失败时回落到内置默认值；`StrategyProfile.configure(id_or_path)` 可按 `data/bots/<id>.json` 或显式路径加载 profile，当前已有默认 `base_revenue_v1` 与偏扩张/供给的 `base_revenue_growth_v1`。
- `StrategyBot`、`OSLABot`、`BeamBot` 都支持 `configure_profile()`。`tools/run_bot_selfplay.gd` / matrix runner 可用 `--profile=base_revenue_growth_v1` 将同一 profile 应用到 strategy/osla/beam bot，并把 profile 写入 `bot_config` / row metadata，避免调参结果混在同一个 summary bucket。
- `StrategyPhasePlanner` 已作为阶段策略拆分的第一层入口：它把当前 `phase/sub_phase` 分类为稳定的 `phase_strategy` 与 `phase_strategy_goal`，并由 `StrategyBot` 写入 explanation / trace。当前这一层不改变候选或评分行为，只提供后续把 Recruit、Train、Marketing、Supply、Payday/Cleanup 等阶段策略逐步拆出 `StrategyScorer` 的测试挂点。
- `StrategyRoutePlanner` 已作为路线级 readiness 分析入口：它把稳定收入路线、价格支持机会、房屋/花园扩张门槛、waitress 支持前置条件等判断集中成可测试 payload，并由 `StrategyScorer` 复用。价格支持已从完整 `stable_income_ready` 中拆出独立 `price_route_ready`：只要己方已有餐厅、已有可供应产品且存在至少一个可服务需求，就允许 `pricing_manager` 进入招聘/上岗路线，以便争取 `first_lower_prices` 和真实价格竞争；waitress 仍必须等待稳定收入和价格支持后再进入下一层无薪支持。
- `StrategyEmployeePlanner` 已作为通用员工估值与员工路线 readiness 入口：它集中处理 `recruit` / `train` / `set_company_structure_*` 共享的员工基础价值、首个收入链角色加成、房屋/花园扩张路线价值和 `*_route_readiness_adjustment`。新房路线仍保持低优先级：只有 `StrategyRoutePlanner` 判定经济和需求规模达到 house growth ready 时，`management_trainee`、`new_business_developer` 等 placement 员工才会获得正的 `*_placement_route_value`；早期 NBD 培训/上岗仍携带严格 readiness penalty。
- `StrategyRecruitPlanner` 已作为招聘动作估值入口：它基于 `StrategyEmployeePlanner`、`StrategySupportPlanner`、`StrategyIncomeAnalyzer` 与 `StrategyRoutePlanner` 组合员工基础价值、placement route、价格/waitress 支持路线、`desired_count`、当前拥有数量和 roster saturation，并直接返回 `value/features` payload；`StrategyScorer` 只负责合并 payload。当前行为与原 scorer helper 等价，但招聘需求上限和 action payload 已有独立 targeted tests，可继续下钻到 Recruit 阶段候选约束。
- `StrategySupplyPlanner` 已作为供给动作估值入口：它集中计算食品生产、普通饮料采购、路线饮料采购的预计产量、商品推断、库存缺口覆盖、future storage/pending marketing 处理和过量库存惩罚，并组合 `StrategyCashPlanner` 的无需求现金安全惩罚与 `StrategyDinnerPlanner` 的真实销售预览。`StrategyScorer` 只消费其 `value/features` payload，不再内联供给动作组合逻辑。
- `StrategyTrainPlanner` 已作为训练动作估值入口：它复用 `StrategyEmployeePlanner`、`StrategySupplyPlanner`、`StrategyIncomeAnalyzer` 与 `DrinkRouteAnalyzer`，集中计算目标员工基础收入价值、placement route readiness、食品产能增量和路线饮料产能增量，并直接返回 `value/features` payload；`StrategyScorer` 只负责合并 payload。当前行为与原 scorer helper 等价，并已有 direct planner tests 与场景 benchmark 双层覆盖。
- `StrategyMarketingPlanner` 已作为营销评分入口：它集中处理营销商品 pipeline、受影响房屋、可服务性、当前/下轮供给 readiness、road graph 距离来源和 `MarketingPreview` 真实结算惩罚。`StrategyScorer` 只合并 planner 返回的 value/features；影响不到房屋的候选仍由 `CandidateGenerator` / `StrategyCandidateFilter` 先过滤，影响房屋但没有库存、当前供给或下轮可上岗供给的候选会被 planner 强惩罚。
- `StrategyStructurePlanner` 已作为结构动作估值入口：它复用 `StrategyEmployeePlanner` 与 `StrategySupportPlanner` 组合员工基础价值、placement route readiness、价格/waitress 支持路线，并集中计算食品员工上岗对当前/规划库存缺口的价值，以及“已有营销能力和餐厅、但当前没有活跃食品供给”时对下轮营销链兑现能力的价值。`StrategyScorer` 只负责合并其 `value/features` payload。
- `StrategySupportPlanner` 已作为价格与无薪支持路线入口：它集中计算价格员工的招聘/上岗价值、waitress 的支持路线价值，以及 `set_price` / `set_discount` / `set_luxury_price` 的当前价格读取与收益/竞争估算。招聘路径由 `StrategyRecruitPlanner` 组合其 `recruit_price_route_*` / `recruit_waitress_*` payload；结构路径由 `StrategyStructurePlanner` 组合其 `structure_price_route_*` / `structure_waitress_*` payload；价格动作路径由 `StrategySupportPlanner.evaluate_price_action()` 直接产出 `value/features`。价格员工路线使用 `price_route_ready`，不再要求完整现金缓冲和多需求稳定收入；waitress 路线仍使用更严格的 `stable_income_ready` 与 price/waitress support gate。
- `StrategyCashPlanner` 已作为现金安全与 Payday 裁员入口：它集中计算无需求生产时的薪资安全惩罚、Payday shortfall 下裁员价值、有效薪资缓解和 `PaydayPreview` 真实结算惩罚。生产/采购路径由 `StrategySupplyPlanner` 组合其无需求现金安全 payload；裁员路径由 `StrategyScorer` 复用其 payload 写入 `fire_*` trace features。无需求生产现金安全惩罚已按 `base_revenue_v1` 与 `base_revenue_growth_v1` 两个 profile 校验，避免成长 profile 的更高 `produce_food` 权重把首产里程碑短期收益推到薪资安全之上。`PaydayPreview` 欠薪失败只在当前行动玩家自己的 shortfall 仍未解决时惩罚候选；如果当前 fire 已解决行动玩家欠薪、但 preview 因其他玩家尚未处理 Payday 而失败，则只记录 `fire_payday_preview_actor_shortfall_resolved` / `fire_payday_preview_other_player_shortfall_pending`，不把当前候选视为无效。`StrategyBotScenarioBenchmark` 已覆盖 Payday shortfall 中通过真实 `fire` action 解雇低收入价值员工，并在随后真实 Payday settlement 中清掉欠薪。
- `StrategyDinnerPlanner` 已作为生产后真实销售预览入口：它集中调用 `DinnerPreview` 读取候选生产后的真实 `total_income` / `income_sales`、过滤已由即时 action 处理的首产里程碑、估值 Dinnertime 新增公开里程碑，并在有公开需求但预览无收入且现金不安全时给出 `product_dinner_preview_no_income_penalty`。生产/采购路径由 `StrategySupplyPlanner` 组合其 `product_dinner_preview_*` payload。
- `StrategySetupPlanner` 已作为 Setup/ReserveCards 与 OrderOfBusiness 的动作估值入口：它集中处理 `select_reserve_card` 与 `choose_turn_order` 评分并直接返回 `value/features` payload，不再依赖候选顺序选择储备卡；储备卡评分按当前规则实现里的 `ceo_slots` 与 `cash` 建模，优先获得后续公司结构容量，其次考虑银行续局资源；行动顺序评分保留早位优先的基础权重。`StrategyScorer` 只合并其 `reserve_card_*` 与 `turn_order_*` trace features。
- `CandidateGenerator` 在有 `source_state` 时复用 `MarketingRangeCalculator` 过滤影响不到房屋的营销候选，并复用 `StrategyMarketingPlanner.service_features()` 过滤没有己方可服务房屋、或全部受影响房屋都会被对手餐厅价格/距离占优抢走的营销候选；营销商品候选按已有库存、公开需求和当前活跃员工可供应性排序，避免 `max_valid_per_action` 被字母序靠前但短期无法兑现的商品占满。营销板件候选在公开 `first_airplane` / `first_radio` / `first_billboard` 可争取时会优先对应类型，避免默认预算先被 billboard/mailbox 填满而让关键类型里程碑在评分前丢失。
- `CandidateGenerator` 的 Recruit 候选先按招聘规则过滤非入门级员工，再按当前策略路线 prior 排序后应用 `max_valid_per_action`，而不是把预算浪费在 validator 必然拒绝的高级员工上：早期保留生产/营销/饮料供给，稳定收入已成型时保留 `pricing_manager` 等价格支持；新房/花园扩张相关的 `management_trainee` 只有在严格 house growth ready 时才回到高优先级，避免少见的新房路线挤占核心收入链候选。executor validator 仍是最后防线，但候选生成阶段不应产生“只能招聘入门级员工”这类可预判 discard。
- `CandidateGenerator` 的培训 prior 已覆盖更多 base 进阶路线：厨师长、饮料路线、管理路线、招聘/薪资折扣、价格、新店和部分特殊员工不会再因默认低 prior 在生成阶段被直接过滤；`campaign_manager -> brand_manager` 这类会牺牲当前收入能力的可选培训仍保持低 prior，避免阻塞营销员上岗。
- `StrategyCandidateFilter` 作为后置防线，在 `macro.debug.affected_house_ids` 明确为空时丢弃营销候选，并把原因写入 trace。
- `StrategyIncomeAnalyzer` 从 `ObservationState` 提取产品需求、可服务需求、库存缺口、供给能力、己方尚未结算的公开营销实例和员工对收入链的贡献。己方 pending marketing 会转成 `pending_marketing_demand`、`planning_demand` 与 `planning_inventory_gap`，只用于规划下一轮供应；对手营销和已结束营销不会计入己方 planning demand。无冰箱时，pending marketing 不会把当前库存视为可保留的未来供给；有 `gain_fridge` 且商品可储存时，才会产生 `pending_marketing_inventory_credit`，并让冰箱保留优先照顾这类未来需求。
- `StrategyBoardAnalyzer` 对餐厅放置/移动做基础动作价值与位置评分，优先贴近公开房屋、公开需求和当前尚未服务的需求，并通过 `evaluate_restaurant_action()` 直接返回 `restaurant_base_value`、`restaurant_placement_value`、合并后的 `restaurant_value` 等 `value/features` payload。有 `source_state` 时会先在 state 副本上复用现有 `RestaurantPlacement.validate_restaurant_placement()` 构造候选餐厅，再用 `BoardAnalyzer` / road graph 计算真实餐厅到房屋距离；无 source state 或临时放置失败时回退到 observation anchor 近似。`StrategyScorer` 只合并其 payload。
- `StrategyRecruitPlanner` 的早期生产员工招聘需求上限按食品需求/缺口计算，而不是用所有商品总需求；当已经有食品生产角色且食品缺口不大时，不再继续把 `kitchen_trainee` 排在营销/饮料供给前面。这样 StrategyBot 的收入路线招聘顺序会先补食品供给，再补营销，遇到饮料需求时补饮料采购。首个路线关键员工仍可高分；当同名员工数量已经达到当前需求上限，或训练源的目标路线已经完成时会降权，避免基础 action weight 推动重复招聘 trainer、management trainee 或入门员工。
- `StrategyStructurePlanner` 对结构上岗候选记录 `structure_employee_value`、`structure_placement_route_value`、`structure_route_readiness_adjustment`、`structure_activation_value`、`structure_activation_products` 与 `structure_marketing_supply_products`。当前/规划库存缺口会提高对应生产员工的上岗价值；当已有营销能力和餐厅、但没有活跃食品供给时，食品生产员工会获得额外结构价值，避免营销链路因为厨师留在 reserve 而无法兑现。`CandidateGenerator._should_preserve_for_training()` 也会让当前需求或营销收入链需要的可生产员工优先保持可上岗，不再单纯因为能继续培训成更高级厨师就从结构候选中隐藏。
- `StrategyTrainPlanner` 对 `train` 候选产出 `train_value`、`train_target_income_value`、`train_placement_route_value`、`train_route_readiness_adjustment`，食品侧的 `train_capacity_upgrade_value` / `train_capacity_upgrade_products`，以及饮料路线侧的 `train_drink_route_upgrade_value` / `train_drink_route_upgrade_products`、来源/目标产量与对应供应价值差。训练评分复用 `StrategyEmployeePlanner` 的员工/placement route readiness，复用 `StrategySupplyPlanner.product_supply_action_value()`、`DrinkRouteAnalyzer` 与路线饮料商品推断，只对目标员工相对来源员工的有效产能增量加分；因此在已有基础供给、可服务食品需求明显超过普通厨师产能时，`burger_cook -> burger_chef` 会压过继续补普通 `burger_cook`，在有可服务饮料需求和可达饮料源时，`errand_boy -> cart_operator` 会暴露路线升级价值；但无需求或过量库存时不会无条件追高级员工。
- `StrategyEmployeePlanner` 与 `StrategyRecruitPlanner` 已给房屋/花园扩张链路增加显式路线价值与招聘上限，但该路线是低优先级的后期选择：只有当己方已有餐厅、生产和营销能力，现金至少达到更高的后期缓冲线，并且公开需求/可服务需求已经形成规模时，`management_trainee`、`management_trainee -> new_business_developer` 培训，以及把 reserve 中的 NBD 上岗才会获得 `*_placement_route_value`。在早期经济未成型时，`management_trainee` 的招聘需求上限为 0，NBD 培训/上岗会携带显式 route readiness 惩罚，避免 Bot 为少见的新房路线压过生产、营销、采购、价格和现金安全。`pricing_manager` 与 `recruiting_girl` 这类高级支持员工也需要先满足稳定收入路线门槛，避免在无法扩大可服务收入时提前消耗招聘节奏。
- `CandidateGenerator` 放房屋候选不再直接使用左上到右下的 grid order 截断 topK，而是先尝试己方餐厅附近、再尝试已有房屋附近、最后才全图兜底；`StrategyBoardAnalyzer.evaluate_house_action()` 对 `place_house` 记录 `house_nearest_restaurant_distance`、`house_nearest_existing_house_distance` 与 `house_placement_value`，优先把新房放到后续可营销、可服务的位置。该路径只保留既有位置估值，新房路线整体仍由 `StrategyEmployeePlanner` / `StrategyRecruitPlanner` 的严格 readiness 作为低优先级后期选择。
- `StrategyMarketingPlanner` 对营销候选记录 `affected_houses`、`marketing_serviceable_houses`、`marketing_inventory_units`、`marketing_can_supply_product`、`marketing_can_future_supply_product`、`marketing_supply_readiness_penalty`、`marketing_distance_source` 等特征。`marketing_can_supply_product` 表示当前活跃员工可在本回合后续供应该商品，预备区/忙碌员工不会被当作即时供给；`marketing_can_future_supply_product` 表示已经拥有下轮可通过 Restructuring 上岗的产能。已有库存单独通过 `marketing_inventory_units` 计分。`StrategyBot.choose_command_with_engine()` 会把 source state 传入 scorer，使营销可服务性优先复用 `BoardAnalyzer` / road graph / drive-through 入口点；无 source state 时才回退到 observation anchor 近似。营销即使影响房屋，也会因没有己方餐厅、没有库存/生产能力而降权；如果既没有库存，也没有当前或下轮可用的供给产能，会携带严重 readiness penalty，避免先做无法兑现的营销。有 source engine 时，营销候选还会通过 `MarketingPreview` 读取真实 `demands_added`；若房屋已满等原因导致实际新增需求为 0，会记录 `marketing_preview_no_demand_penalty` 并降权。
- `StrategySupplyPlanner` 对生产/采购候选记录 `product_public_demand`、`product_serviceable_demand`、`product_inventory_gap`、`product_pending_marketing_demand`、`product_planning_inventory_gap`、`product_effective_pending_marketing_demand`、`product_future_supply_storage_available`、`product_pending_marketing_supply_deferred`、`product_can_supply`、`product_supply_expected_units`、`product_supply_current_covered_units`、`product_supply_future_covered_units` 等特征，并用这些特征优先补当前可销售产品缺口。无冰箱时，己方已经发起、但还未在 Marketing 结算成房屋需求的商品只保留为规划信号，不会让当前 `GetFood` / `GetDrinks` 获得 future covered units；有冰箱且商品可储存时，才允许提前生产/采购并把 pending marketing 计入有效未来缺口。生产/采购使用独立的 `product_supply_action_value`：Burger Cook、Burger Chef、Errand Boy 与路线饮料这类不同产量动作会按预计供给数量覆盖 effective planning gap，当前缺口权重高于可储存的未来缺口，超过 effective planning gap 的部分会降权；首次 Errand Boy 若公开 `first_errand_boy` 仍在 milestone pool 中，会按本次触发后立即生效的规则估算为 2 瓶；路线饮料没有 `drink_type` 参数时，会从公开 `drink_sources` 与 `selected_sources` 反推 `drink_route_expected_units_by_product`，把每种饮料分别按 effective planning gap 评分；当库存已经覆盖公开需求和一单位缓冲时会施加包含本次预计产量的 `product_overstock_penalty`，避免多个员工在同一子阶段继续无效囤货。若食物生产没有公开需求、没有可服务需求、没有库存缺口且现金不足以支付基础薪资，`StrategyCashPlanner` 会额外记录 `product_no_demand_cash_safety_penalty`，避免为了短期生产里程碑拿到带薪厨师后又立刻在 Payday 解雇；该断言已同时覆盖 `base_revenue_v1` 与 `base_revenue_growth_v1`。pending marketing 不会被当作本轮 Dinnertime 已可出售收入，因此不会绕过这条现金安全线。
- `StrategyDinnerPlanner` 在 `StrategyBot.choose_command_with_engine()` 路径下，对公开需求存在的食物生产通过 `DinnerPreview` fork 当前 engine 执行该候选并推进到 Dinnertime，读取真实 `total_income` / `income_sales` 写入 `product_dinner_preview_*` features；如果 fork 后己方新增公开可争取、且不是当前生产动作本身已由 immediate milestone race 处理的里程碑，例如 `first_have_20` / `first_have_100` 或 Dinnertime 中由销售员工触发的 `first_waitress`，会记录 `product_dinner_preview_milestone_ids` 与 `product_dinner_preview_milestone_value` 并加入评分。如果预览显示本次生产不能带来收入且现金不足基础薪资，会记录 `product_dinner_preview_no_income_penalty`，覆盖“有需求但被对手餐厅、距离、库存或价格竞争抢走”的现金安全场景。
- `CandidateGenerator` 对路线型饮料采购会按 `max_valid_per_action` 的数倍先取候选路线，再用路线 source types 的商品 pipeline prior 重新排序，保证紧预算下需求相关饮料源不会在评分前被距离/source_count 排序截断。
- `DrinkRouteAnalyzer` 已把路线有效距离和真实执行规则对齐：通过 `MilestoneEffectQueries` 读取已拥有 `distance_plus_one` effect，并通过公开里程碑定义检查本次 `UseEmployee` 会立即触发的距离 effect，因此首次 `cart_operator` 路线不会因为候选生成仍用基础 range 而被提前丢弃。
- `StrategySupportPlanner.evaluate_price_action()` 对 `set_price`、`set_discount`、`set_luxury_price` 产出 `price_source`、`price_current_unit_price`、`price_action_delta`、`price_projected_unit_price`、`price_round_modifier_total` 等特征。有 `source_state` 时直接复用 `PricingPipeline.calculate_unit_price()` 读取当前单价与 `round_state.price_modifiers`；无 source state 时才用 observation 中的公开规则、己方里程碑和公开 round state 做保守回退。`StrategyScorer` 只合并其 payload。
- `StrategySupportPlanner` 对价格员工的招聘/上岗记录 `recruit_price_route_value` / `structure_price_route_value`、可服务需求、库存、预计销售单位和 `first_lower_prices` 可用性。`pricing_manager` 这类价格支持只在已有餐厅、已有可供应商品且至少有一个可服务需求时进入优先级；这比完整稳定收入门槛更早，但仍要求价格动作能影响可卖收入。早期无餐厅、无供给或无可服务需求时，仍优先补生产、营销和饮料供给。
- `StrategySupportPlanner` 对 waitress 的招聘/上岗记录 `recruit_waitress_route_value` / `structure_waitress_route_value`、当前 `waitress_tips`、`first_waitress` 可用性和对应里程碑估值。waitress 只在稳定收入路线已经具备生产、营销、现金缓冲、可服务需求，并且价格支持已经能形成可卖收入后，才作为下一层无薪现金支持进入 Recruit / Restructuring 优先级；早期不把 waitress 当作生产、营销或饮料供给的替代品。场景基准已覆盖 active waitress 在真实 `GetFood -> Dinnertime` 销售链中触发 `first_waitress` 并获得小费收入。
- `MilestoneRaceAnalyzer` 只基于公开 `milestone_pool_public`、己方已获得里程碑、公开 round counters 和候选动作触发类型做弱评估；当前覆盖 `first_train`、第三次招聘触发的 `first_hire_3`、基础生产、Errand Boy/Cart、飞机营销、基础营销与降价类里程碑，并会把 `gain_card` / `gain_cards`、营销里程碑的 `sell_bonus`、飞机营销的 `turnorder_empty_slots`、冰箱 `gain_fridge`、服务员 `waitress_tips`、`multi_trainer_on_one`、`extra_marketing`、`distance_plus_one` 与 `drinks_per_source_delta` 这类公开规则 effect 计入弱估值，把 `milestone_race_value` / `milestone_race_ids` 写入 scorer features。`first_lower_prices` 只由真实会触发 `LowerPrice` 的 `set_price` / `set_discount` 计入，`set_luxury_price` 不会获得降价里程碑价值。它不会读取隐藏对手状态，也不会假设未公开结构。
- `CandidateGenerator` 在 `choose_fridge_keep` 中复用 `StrategyIncomeAnalyzer.build_fridge_keep()`，按可服务需求、公开需求、己方 pending marketing 和可补给性逐单位选择冰箱保留库存，而不是简单保留最大库存堆。`StrategyBotScenarioBenchmark` 已覆盖 Cleanup pending 中选择并执行 `choose_fridge_keep`，并确认冰箱会优先保留满足己方未结算营销需求的库存。
- `StrategyCashPlanner` 对 `fire` 候选记录发薪现金、估算应付、短缺、解雇后的有效薪资缓解和员工收入价值；发薪短缺时优先解雇收入链价值较低的可付薪员工。有 source engine 时，`fire` 候选还会通过 `PaydayPreview` 执行候选裁员并推进真实 Payday 退出结算，记录 `fire_payday_preview_due` / `paid` / `unpaid` / `cash_after`。如果预览显示当前行动玩家裁员后仍无法完成 Payday 结算，会记录 `fire_payday_preview_failure_penalty` 并降权，避免只靠估算薪资缓解选择无效裁员；如果失败来自其他玩家仍未处理欠薪，而当前行动玩家自己的 shortfall 已被候选 fire 解决，则记录 `fire_payday_preview_actor_shortfall_resolved` / `fire_payday_preview_other_player_shortfall_pending`，不施加 failure penalty。
- `DinnerPreview` 已用 `AiEngineFork` fork 当前 engine，通过真实 `execute_command()` 和 settlement hooks 推进到 Dinnertime，并在返回前恢复 source engine 的 registry bundle。
- `DinnerPreviewGoldenTest` 已覆盖基础销售、花园收入、drive-through 入口点与 source 不变性/registry 恢复，比较 preview 与真实 Dinnertime report 的关键字段和库存消耗。
- `MarketingPreview` 已用 `AiEngineFork` fork 当前 engine，执行候选命令后通过真实阶段推进进入 Marketing，读取 `round_state.marketing.processed` / `expired` / `timeline_events`，并在返回前恢复 source engine 的 registry bundle。它只负责真实结算预览，不替代营销候选的影响房屋过滤和供给 readiness 评分。
- `MarketingPreviewGoldenTest` 已覆盖从同一前置状态分别执行 `initiate_marketing` 并推进真实 engine / preview 到 Marketing，比较 report、最终 state hash、`first_burger_marketed` 触发、source 不变性和 registry 恢复。`StrategyBotTest` 也覆盖了“营销覆盖房屋但需求已满”的评分回归，确保这类候选不会仅凭覆盖范围获得正收益。
- `PaydayPreview` 已用 `AiEngineFork` fork 当前 engine，执行候选命令后通过真实 Payday 退出 settlement 写入 `round_state.payday`。Payday 不是自动跳过阶段，但从 Payday 进入 Marketing 会触发 Marketing enter settlement；因此预览在 Payday 直接调用 `phase_manager.advance_phase(state)`，避免普通 `execute_command(advance_phase)` 继续自动跳过 Marketing/Cleanup 而丢失稳定落点。
- `PaydayPreviewGoldenTest` 已覆盖无额外命令的 Payday 结算，以及 Payday 中先 `fire` 再结算的场景；测试比较真实 engine 与 preview 的 Payday report、最终 state hash、source 不变性和 registry 恢复。`StrategyBotTest` 也覆盖了“裁员一个人仍无法支付薪水”的评分回归。
- `CleanupPreview` 已用 `AiEngineFork` fork 当前 engine，并通过真实 Marketing -> Cleanup 进入结算读取 `round_state.cleanup.inventory_discarded` / `fridge_choice_pending`。无 pending 时预览会停在 Cleanup report 落点；有冰箱超容量 pending 时，预览可返回刚进入 Cleanup 的 pending report。对 `choose_fridge_keep` 这类 Cleanup pending 命令，预览执行真实 action executor 但不触发 Cleanup auto-skip，因为普通 `execute_command()` 会进入下一轮 Restructuring 并由 `start_new_round()` 清空旧 `round_state.cleanup`。
- `CleanupPreviewGoldenTest` 已覆盖从 Marketing 进入 Cleanup 的库存丢弃 report，以及 Cleanup pending 后执行 `choose_fridge_keep` 的 report/inventory 变化；测试比较 preview 与真实 direct settlement/action executor 的关键 report 字段、最终 state hash、source 不变性和 registry 恢复。
