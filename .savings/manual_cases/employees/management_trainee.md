# employee/management_trainee - 经理链员工（management_trainee）

## 存档

- JSON: `res://.savings/manual_cases/employees/management_trainee.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Train (round=1 current_player=0)

## 目的

- 验证 management_trainee 可作为 from_employee 被培训为 junior_vice_president。

## 复核步骤

1. 载入后应处于 Working/Train，且玩家 0 在岗包含 trainer；reserve_employees 包含 management_trainee。
2. 将 management_trainee 培训为 junior_vice_president 并执行。

## 预期结果

- management_trainee 从 reserve_employees 移除；junior_vice_president 加入 reserve_employees。

## 推荐参数（可选）

- action_id: `train`
- actor: `0`
- params:
	- `from_employee`: `management_trainee`
	- `to_employee`: `junior_vice_president`

## 关联单元测试

- `core/tests/company_structure_test.gd`
