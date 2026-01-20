# employee/cfo - CFO（cfo）

## 存档

- JSON: `res://.savings/manual_cases/employees/cfo.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Payday/ (round=1 current_player=0)

## 目的

- 用 tips 触发 CFO +50%（向上取整）加成，便于手工对照差额。

## 复核步骤

1. 载入后应处于 Payday（该存档已推进过晚餐结算）。
2. 观察玩家 0 现金应比玩家 1 多 $3（双方都有 waitress tips=$5，但仅玩家 0 有 CFO，CFO 加成为 ceil(5*50%)=$3）。

## 预期结果

- players[0].cash == players[1].cash + 3。

## 关联单元测试

- `core/tests/dinnertime_settlement_test.gd`
- `core/tests/milestone_system_test.gd`
