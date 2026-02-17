# employee/kimchi_master - 泡菜大师（kimchi_master）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/kimchi_master.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Payday/ (round=1 current_player=0)

## 目的

- 验证 Cleanup 丢弃食物后 kimchi_master 自动产出 kimchi。

## 复核步骤

1. 载入后应处于 Payday（该存档已推进过 Cleanup）。
2. 观察玩家 0 库存应包含 kimchi +1（并且 burger 被丢弃为 0）。

## 预期结果

- players[0].inventory.kimchi >= 1。

## 关联单元测试

- `core/tests/kimchi_v2_test.gd`
