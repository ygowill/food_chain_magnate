# milestone/first_trainer_used - 首个使用培训讲师（first_trainer_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_trainer_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Train (round=1 current_player=0)

## 目的

- 验证 train 会推导 UseEmployee(trainer) 并触发里程碑；效果包含 gain_card(trainer) 与允许欠薪离开 Payday。

## 复核步骤

1. 载入后应处于 `Working/Train`，且玩家 0 在岗包含 `trainer`；`reserve_employees` 包含 `management_trainee`。
2. 执行 `train(management_trainee -> new_business_developer)`。
3. 打开调试状态（如 `player 0`），检查 `salary_allow_unpaid` 标记。

## 预期结果

- 玩家 0 获得里程碑 `first_trainer_used`（`player.milestones`）。
- 玩家 0 `reserve_employees` 新增 1 张 `trainer`（`gain_card`）。
- 玩家 0 `salary_allow_unpaid == true`（后续 Payday 可验证欠薪仍可离开）。

## 推荐参数（可选）

- action_id: `train`
- actor: `0`
- params:
	- `from_employee`: `management_trainee`
	- `to_employee`: `new_business_developer`

## 关联单元测试

- `core/tests/new_milestones_beer_trainer_payday_v2_test.gd`
