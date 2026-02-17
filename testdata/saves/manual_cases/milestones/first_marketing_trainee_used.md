# milestone/first_marketing_trainee_used - 首个使用营销实习生（first_marketing_trainee_used）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_marketing_trainee_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证 marketing_trainee 发起营销会触发里程碑，并获得 kitchen_trainee + errand_boy 各 1 张。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 marketing_trainee。
2. 执行「发起营销」并放置 billboard #11（参数见推荐）。

## 预期结果

- 玩家 0 获得里程碑 first_marketing_trainee_used（player.milestones）。
- 玩家 0 reserve_employees 新增 kitchen_trainee 与 errand_boy。
- （可能同时获得 first_marketeer_used，这是正常的）。

## 推荐参数（可选）

- action_id: `initiate_marketing`
- actor: `0`
- params:
	- `employee_type`: `marketing_trainee`
	- `board_number`: `11`
	- `product`: `burger`
	- `duration`: `1`
	- `position`: `[6, 1]`
	- `rotation`: `90`

## 关联单元测试

- `core/tests/new_milestones_marketing_trainee_v2_test.gd`
