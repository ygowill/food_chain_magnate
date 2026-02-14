# milestone/first_coffee_sold - 首个卖出咖啡（first_coffee_sold）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_coffee_sold.json`
- 玩家数: 3
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=0 current_player=0)

## 目的

- 验证 Dinnertime 路线购买中的咖啡销售会触发 `ProductSold(product=coffee)`，并授予里程碑 first_coffee_sold。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants。
2. 点击「推进子阶段」离开 Working：将自动进入 Dinnertime 结算后到 Payday。
3. （可选）继续推进到 Cleanup，观察咖啡里程碑奖励待处理动作注入。

## 预期结果

- 玩家 1 与玩家 2 获得里程碑 first_coffee_sold（player.milestones）。
- `state.round_state.dinnertime.sales[*].route_purchases` 中可看到 `kind=coffee` 的购买记录。
- （可选）到 Cleanup 后，`pending_phase_actions['Cleanup']` 中出现 `coffee_first_coffee_sold_bonus_coffee_shop` 待处理任务（按 turn_order 排序）。

## 关联单元测试

- `core/tests/coffee_v2_test.gd`
