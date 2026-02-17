# milestone/first_beer_sold - 首个卖出啤酒（first_beer_sold）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_beer_sold.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证晚餐卖出 beer 会触发里程碑，并允许在 Payday 用 token 支付薪水（并消耗库存）。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants（已预置 beer 需求与库存，且现金=0）。
2. 点击「推进子阶段」离开 Working，完成晚餐/清理后进入 Payday。
3. 在 Payday 点击「推进阶段」离开：应允许用 token 支付薪水并消耗库存。

## 预期结果

- 玩家 0 获得里程碑 first_beer_sold（player.milestones）。
- 离开 Payday 时应消耗一定数量的 food/drink token 用于支付薪水。

## 关联单元测试

- `core/tests/new_milestones_beer_trainer_payday_v2_test.gd`
