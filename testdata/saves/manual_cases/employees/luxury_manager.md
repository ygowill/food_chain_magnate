# employee/luxury_manager - 强制定价员工（luxury_manager）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/luxury_manager.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Recruit (round=1 current_player=0)

## 目的

- 验证强制动作 set_luxury_price 的可执行性与 round_state 写入。

## 复核步骤

1. 载入后应处于 Working 阶段，且玩家 0 在岗包含 luxury_manager。
2. 行动面板选择强制动作并执行。

## 预期结果

- round_state 中应写入对应价格修正（price_modifiers/discount_modifiers/luxury_price_modifiers 等）。

## 推荐参数（可选）

- action_id: `set_luxury_price`
- actor: `0`
- params:

## 关联单元测试

- `core/tests/mandatory_actions_test.gd`
