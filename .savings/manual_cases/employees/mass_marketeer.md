# employee/mass_marketeer - 大众营销员（mass_marketeer）

## 存档

- JSON: `res://.savings/manual_cases/employees/mass_marketeer.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证进入 Marketing 结算时，marketing_rounds=1+在岗 mass_marketeer 数量。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 mass_marketeer 与 marketing_trainee。
2. 使用 marketing_trainee 放置 1 个 billboard（按推荐坐标）。
3. 结束本回合/推进到 Marketing 结算后，观察产生的需求数量应为 2 轮的叠加效果。

## 预期结果

- state.round_state.marketing_rounds 应为 2（1 + 1 个 mass_marketeer）。

## 推荐参数（可选）

- action_id: `initiate_marketing`
- actor: `0`
- params:
	- `employee_type`: `marketing_trainee`
	- `board_number`: `14`
	- `product`: `burger`
	- `duration`: `1`
	- `position`: `[6, 1]`
	- `rotation`: `0`

## 关联单元测试

- `core/tests/mass_marketeers_v2_test.gd`
