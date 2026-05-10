# 启发式人机对手：模拟、地图与晚餐预览

本文聚焦 fork/forward simulation、BoardAnalyzer 与 DinnerPreview 的实现边界。

## 6. Forward Simulation

### 6.1 首版正确性路线

首版模拟器应优先正确：

1. 从当前 `GameEngine` fork 一个 simulation engine。
2. 复制 `state`、`module_plan_v2`、registry bundles、ruleset、action registry、phase manager 必要依赖。
3. 对候选命令逐条执行 `simulation_engine.execute_command(command)`。
4. 让 auto-advance 和 settlement hooks 正常运行。
5. 从模拟后的 `state` / `round_state` 提取评分特征。

建议新增 `core/ai/simulation/ai_engine_fork.gd`，封装这些细节。不要让各个搜索器自己复制引擎。

用于验证搜索/fork 的测试场景也必须可回放：优先通过真实 `engine.execute_command()` 历史构造状态，或使用能完整恢复当前状态的存档。不要在这类测试里直接修改 `GameState` 后再调用 `ForwardSimulator`，因为当前 fork 路径基于 archive/command history，直接状态修改不会进入模拟分支。

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
- `DrinkRouteAnalyzer` 的有效 range 必须和 `ProcureDrinksAction` 的预览状态一致：已拥有的 `distance_plus_one` effect 要生效；如果当前员工本次 `UseEmployee` 会从公开 milestone pool 触发新的 `distance_plus_one`，也要在同一条候选路线中生效。
- `first_cart_operator` 等距离里程碑通过公开里程碑定义的 trigger/effects 查询，不在 AI 中硬编码具体里程碑 id。
- 每名采购员工先从 `DrinkRouteAnalyzer` 多取一批路线，再按路线经过的饮料类型、当前公开需求和己方库存缺口排序，最后只保留 topK。不要让单纯的路线距离/source_count 截断掉真正能满足需求的饮料源。


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
