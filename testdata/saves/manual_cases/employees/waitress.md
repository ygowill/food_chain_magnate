# employee/waitress - 女服务员（waitress）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/waitress.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Payday/ (round=1 current_player=0)

## 目的

- 验证 waitress tips（默认 +$3）在晚餐结算中生效。

## 复核步骤

1. 载入后应处于 Payday（该存档已推进过晚餐结算）。
2. 观察玩家 0 现金应比玩家 1 多 $5（仅玩家 0 拥有 waitress；且会触发 first_waitress 将 tips 提升为 $5）。

## 预期结果

- players[0].cash == players[1].cash + 5。

## 关联单元测试

- `core/tests/dinnertime_settlement_test.gd`
