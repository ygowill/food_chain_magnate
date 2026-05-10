# 启发式人机对手：StrategyBot 开发流程与场景基准

本文聚焦 StrategyBot 的结构性开发流程和 deterministic scenario benchmark 清单。

## 开发流程切换

当前 StrategyBot 不再按“跑一条固定 selfplay trace，看到局部错误就补一个权重”的方式推进。后续策略开发以场景基准为主入口，自对弈只作为流程 smoke、回归监控和宏观指标来源。

新的实施顺序：

1. 先把策略断点写成 deterministic scenario benchmark，描述路线级不变量，而不是只描述某个 seed 的某一步。
2. 若 benchmark 已经通过，需要在测试名和失败信息中明确它保护的行为；若未通过，再进入实现。
3. 实现阶段优先改 candidate/filter/scorer/profile 中最小的对应层，避免把长程规划问题继续摊成全局权重补丁。
4. 每次策略改动至少跑 scenario benchmark、compile check 和 AllTests；selfplay matrix 只用于观察行动分布、资源趋势和是否出现 softlock。
5. 任何新的 heuristic 权重如果影响路线选择，必须在 trace feature 中可解释，并有一个命名场景保护它。

第一版场景基准放在 `core/tests/ai/strategy_bot_scenario_benchmark_test.gd`，并通过现有 `ui/scenes/tests/all_tests.tscn` 聚合入口运行。它先覆盖已经暴露过的策略断点：

- 有营销链路但无食品供给时，Restructuring 应优先激活可兑现营销需求的食品生产员工，而不是提交结构或激活无关员工。
- 有 Trainer 且员工可继续培训时，若当前收入链需要该员工供给，候选生成不能把它从结构上岗候选里隐藏。
- 营销候选如果只会给对手餐厅价格/距离占优的房屋制造需求，应在候选生成阶段被过滤；同时必须保留至少一个己方可服务、可竞争的营销候选。
- 己方 pending marketing 还没转成房屋需求时，供给评分应遵守真实时序：无冰箱则延后到下一轮生产/采购，有冰箱且商品可储存时才允许提前备货，特别是路线饮料来源。
- Cleanup 冰箱保留应走真实 pending action：有 `gain_fridge`、库存超容量且己方 pending marketing 需要某商品时，StrategyBot 应选择 `choose_fridge_keep`，保留至少对应未来需求量，并通过真实 action 清掉 pending。
- Payday 现金危机应走真实裁员动作：现金只够支付部分工资时，StrategyBot 应优先解雇收入链价值较低的可付薪员工，保留能产生收入的员工，并让随后真实 Payday settlement 不再欠薪。
- 营销评分应区分“已经通过招聘/培训拿到下轮产能”和“完全没有可兑现产能”：前者可以作为下一轮收入路线，后者即使影响房屋也会被严重降权。
- 无冰箱的常规营销收入链应按真实回合闭环：本回合营销只在 Marketing 结算后产生房屋需求；下轮先在 Restructuring 补齐或激活产能，再在 GetFood/GetDrinks 生产或采购，Dinnertime 才能销售并清掉需求。
- 早期收入路线应能按真实子阶段顺序串联：已有 Trainer、Campaign Manager、餐厅和预备区 `kitchen_trainee` 时，即使当前还没有房屋需求，Train 也应先补成 `burger_cook`，同回合 Marketing 发起 burger 需求，下轮 Restructuring 激活产能，GetFood 生产，Dinnertime 卖出并清掉需求。
- Train 子阶段应能沿收入路线补产能：已有 Trainer、营销能力和可服务食品需求时，预备区的 `kitchen_trainee` 应优先训练成 `burger_cook`，并触发真实 `first_train` 里程碑，而不是跳过或继续补无关营销能力。
- Train 子阶段还应能沿收入路线升级产能：已有基础汉堡供给、Trainer 和超过普通厨师产量的可服务汉堡需求时，预备区的 `burger_cook` 应优先训练成 `burger_chef`，并在 trace 中暴露正的 `train_capacity_upgrade_value`，避免只按“能生产汉堡”而忽视每次生产数量。
- Train 子阶段也应覆盖饮料路线升级：已有 Trainer、基础 Errand Boy 供给、可服务 soda 需求和可达 soda source 时，预备区的 `errand_boy` 应训练成 `cart_operator`，并在 trace 中暴露正的 `train_drink_route_upgrade_value`，避免饮料路线只靠泛化的 `procure_drink` 员工价值解释。
- 首次 Errand Boy 饮料路线必须和规则层一致：公开 `first_errand_boy` 仍可争取时，StrategyScorer 应估算本次会拿 2 瓶，并让 StrategyBot 对准当前可服务饮料需求。
- 路线型饮料需求应能真实闭环：有 `truck_driver`、可服务 soda 需求和可达 soda source 时，StrategyBot 应通过 `DrinkRouteAnalyzer` 生成路线采购，按 `drink_route_expected_units_by_product` 识别 2 瓶 soda，并在 Dinnertime 卖掉库存、清掉需求。
- 首次 Cart Operator 的距离奖励必须和规则层一致：公开 `first_cart_operator` 仍可争取、soda source 只在基础 range 外但在同回合 `UseEmployee` 后 range 内时，StrategyBot 应通过 `DrinkRouteAnalyzer` 生成路线采购，执行后立即获得里程碑，并在 Dinnertime 卖掉库存、清掉需求。
- 早期 Recruit 应按收入路线补齐能力：先拿食品生产；已有食品供给后补营销；公开饮料需求出现且无饮料供给时补采购员工。
- 稳定收入路线已经具备餐厅、生产、营销、现金缓冲、可服务需求和可卖库存后，Recruit 应把无薪价格支持纳入下一层收入路线；即使使用完整 base 员工池和默认候选预算，也必须先保留并优先拿 `pricing_manager`，并把 `first_lower_prices` 可用性暴露为 trace feature。
- 已经招到价格支持后，Restructuring 应在稳定收入路线中激活 `pricing_manager`，让下一次 Working 能执行真实 `set_price` mandatory action，而不是把空位让给泛用 Trainer 或直接提交。
- `pricing_manager` 已经上岗时，StrategyBot 应把 mandatory `set_price` 排在生产/跳过等候选之前，并在 trace 中暴露 `price_action_delta` 与预计销售单位，确认价格路线闭环到真实行动。
- 稳定收入路线已经具备价格支持和可卖库存后，Recruit 应把 waitress 作为下一层无薪现金支持；即使使用完整 base 员工池和默认候选预算，也必须保留并优先拿 waitress，计入当前小费、`first_waitress` 公开可争取性和里程碑弱估值；已经招到 waitress 后，Restructuring 应优先激活 waitress 以便下次 Dinnertime 产生小费和触发 `first_waitress`。
- 当前玩家本回合已经招聘 2 次时，第三次 `recruit` 应显式计入 `first_hire_3` 的 `gain_cards` 价值；第一/第二次招聘不应提前拿到这项即时里程碑 race value。真实路线场景还应通过两次合法招聘搭出 `recruit_used=2`，再由 StrategyBot 执行第三次 `recruit`，确认真实 action 领取里程碑并发放 2 张 `management_trainee`。
- `first_lower_prices` 必须按真实 action trigger 识别：`set_price` / `set_discount` 可以计入，`set_luxury_price` 不能因为同属价格动作而获得降价 race value。
- `DinnerPreview` 如果显示生产后的 Dinnertime 结算会让己方获得新的公开里程碑，例如现金里程碑 `first_have_20` / `first_have_100`，或销售员工触发的 `first_waitress`，`StrategyDinnerPlanner` 应把这些 preview milestone value 计入，同时过滤当前生产动作本身已经由 immediate milestone race 处理的首产里程碑。
- `first_*_marketed` 这类销售奖金里程碑不能只按基础首发标记计分，必须把公开规则数据里的 `sell_bonus` 计入 `milestone_race_value`。
- `first_airplane` 必须由飞机营销触发，不能由 `zeppelin_pilot` 饮料采购误触发；公开规则数据里的 `turnorder_empty_slots` 需要进入弱估值。
- base 支持型里程碑不能退化成默认弱值：`first_waitress`、`first_throw_away`、`first_pay_20_salaries`、`first_billboard`、`first_radio`、`first_cart_operator` 应把公开规则 effect 里的小费、冰箱、多 trainer、营销免薪/永久、额外营销和距离收益计入 `milestone_value()`。

这组 benchmark 是 StrategyBot MVP 进入下一阶段的行为闸门；后续新增路线时，应先追加场景，再做 scorer 或 profile 调整。
