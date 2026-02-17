# employee/guru - 培训员工（guru）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/guru.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Train (round=1 current_player=0)

## 目的

- 验证 Train 子阶段可执行一次培训，并遵循 train_to 链与供应池约束。

## 复核步骤

1. 载入后应处于 Working/Train，且玩家 0 在岗包含 guru；reserve_employees 包含 management_trainee。
2. 行动面板选择「培训」，将 management_trainee 培训为 new_business_developer 并执行。

## 预期结果

- management_trainee 从 reserve_employees 移除；new_business_developer 加入 reserve_employees。

## 推荐参数（可选）

- action_id: `train`
- actor: `0`
- params:
	- `from_employee`: `management_trainee`
	- `to_employee`: `new_business_developer`

## 关联单元测试

- `core/tests/milestone_system_test.gd`
