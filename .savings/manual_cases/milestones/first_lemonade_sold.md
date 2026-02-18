# milestone/first_lemonade_sold - 首个卖出柠檬水（first_lemonade_sold）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_lemonade_sold.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证晚餐卖出 lemonade 会触发里程碑，并启用“在岗同色培训”等规则变化。

## 复核步骤

1. 载入后应处于 `Working/PlaceRestaurants`（已预置 `lemonade` 需求与库存）。
2. 点击「推进子阶段」离开 `Working`，完成晚餐结算并进入 `Payday`（里程碑应在此过程中获得）。
3. 打开调试状态（如 `player 0`），检查玩家字段 `train_from_active_same_color`。

## 预期结果

- 玩家 0 获得里程碑 `first_lemonade_sold`（`player.milestones`）。
- 玩家 0 的 `train_from_active_same_color == true`。

## 关联单元测试

- `core/tests/new_milestones_lemonade_sold_v2_test.gd`
