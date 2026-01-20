# employee/gourmet_food_critic - 营销员工（gourmet_food_critic）

## 存档

- JSON: `res://.savings/manual_cases/employees/gourmet_food_critic.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证 initiate_marketing(board=17) 可用与放置合法性。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 gourmet_food_critic。
2. 行动面板选择「发起营销」，并按说明文件中的推荐坐标放置。

## 预期结果

- 营销板件成功放置，并写入 state.map.marketing_placements；员工进入 busy_marketers。

## 推荐参数（可选）

- action_id: `initiate_marketing`
- actor: `0`
- params:
	- `employee_type`: `gourmet_food_critic`
	- `board_number`: `17`
	- `product`: `burger`
	- `duration`: `1`
	- `position`: `[2, 0]`
	- `rotation`: `90`

## 关联单元测试

- `core/tests/gourmet_food_critics_v2_test.gd`
