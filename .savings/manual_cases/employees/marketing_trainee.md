# employee/marketing_trainee - 营销实习生（marketing_trainee）

## 存档

- JSON: `res://.savings/manual_cases/employees/marketing_trainee.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证 initiate_marketing(billboard) 的可用性、距离限制与放置合法性。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 marketing_trainee，并已拥有至少 1 家餐厅。
2. 行动面板选择「发起营销」。
3. 选择 employee_type=marketing_trainee，board_number=14（billboard），product=burger，duration=1，并按说明文件中的推荐坐标放置。

## 预期结果

- 营销板件成功放置，marketing_trainee 进入 busy_marketers；并在 state.map.marketing_placements 占用 board_number。
- 若放在错误位置（非贴边/超距/占地冲突），应给出明确拒绝原因。

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

- `core/tests/marketing_campaigns_test.gd`
- `core/tests/new_milestones_marketing_trainee_v2_test.gd`
