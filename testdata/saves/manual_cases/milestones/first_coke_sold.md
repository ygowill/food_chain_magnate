# milestone/first_coke_sold - 首个卖出可乐（first_coke_sold）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_coke_sold.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证晚餐卖出 soda 会触发里程碑，并获得 freezer（gain_fridge=10）：Cleanup 后库存应保留到 10。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants（已预置 soda 需求与库存 soda=12）。
2. 点击「推进子阶段」离开 Working，完成晚餐与 Cleanup 后进入 Payday。

## 预期结果

- 玩家 0 获得里程碑 first_coke_sold（player.milestones）。
- 进入 Payday 时 soda 库存应为 10（Cleanup 后按 freezer 容量限幅）。

## 关联单元测试

- `core/tests/new_milestones_coke_sold_v2_test.gd`
