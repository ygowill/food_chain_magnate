# milestone/ketchup_sold_your_demand - 有人卖了你的需求（ketchup_sold_your_demand）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/ketchup_sold_your_demand.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证“他人卖出你营销产生的需求”后，你会在晚餐结算结束时获得番茄酱里程碑。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants（已预置：玩家 1 会卖出玩家 0 的 burger 需求）。
2. 点击「推进子阶段」离开 Working（晚餐会自动结算并跳到 Payday）。

## 预期结果

- 玩家 0 获得里程碑 ketchup_sold_your_demand（player.milestones）。
- 该里程碑提供番茄酱效果：晚餐距离 -1（clamp 到 0）。

## 关联单元测试

- `core/tests/ketchup_mechanism_v2_test.gd`
