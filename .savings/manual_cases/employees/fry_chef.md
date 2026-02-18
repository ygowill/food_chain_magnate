# employee/fry_chef - 薯条厨师（fry_chef）

## 存档

- JSON: `res://.savings/manual_cases/employees/fry_chef.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Payday/ (round=1 current_player=0)

## 目的

- 构造双方各卖 1 个房屋的局面，验证 fry_chef 每房屋额外 +$10。

## 复核步骤

1. 载入后应处于 Payday（该存档已推进过晚餐结算）。
2. 观察玩家 0 现金应比玩家 1 多 $10（仅玩家 0 拥有 fry_chef）。

## 预期结果

- players[0].cash == players[1].cash + 10。

## 关联单元测试

- `core/tests/fry_chefs_v2_test.gd`
