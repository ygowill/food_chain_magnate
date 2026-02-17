# milestone/first_burger_sold - 首个卖出汉堡（first_burger_sold）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_burger_sold.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证晚餐卖出 burger 会触发里程碑，并将 CEO 卡槽至少提升到 4。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants（已预置 burger 需求与库存）。
2. 点击「推进子阶段」离开 Working，完成晚餐结算并跳到 Payday。

## 预期结果

- 玩家 0 获得里程碑 first_burger_sold（player.milestones）。
- player.company_structure.ceo_slots 应为 4。

## 关联单元测试

- `core/tests/new_milestones_burger_sold_v2_test.gd`
