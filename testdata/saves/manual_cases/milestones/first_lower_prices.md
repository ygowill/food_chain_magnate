# milestone/first_lower_prices - 首个降价（first_lower_prices）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_lower_prices.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Recruit (round=1 current_player=0)

## 目的

- 验证 set_price 会触发 first_lower_prices，并写入 round_state.price_modifiers。

## 复核步骤

1. 载入后应处于 Working 阶段，且玩家 0 在岗包含 pricing_manager（定价经理）。
2. 行动面板选择强制动作「设定价格（-$1）」并执行。

## 预期结果

- 玩家 0 获得里程碑 first_lower_prices（player.milestones）。
- state.round_state.price_modifiers[0][pricing_manager] == -1。

## 推荐参数（可选）

- action_id: `set_price`
- actor: `0`
- params:

## 关联单元测试

- `core/tests/milestone_system_test.gd`
- `core/tests/milestone_effect_values_test.gd`
- `core/tests/mandatory_actions_test.gd`
