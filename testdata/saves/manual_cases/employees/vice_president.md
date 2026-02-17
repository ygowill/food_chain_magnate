# employee/vice_president - 经理链员工（vice_president）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/vice_president.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Train (round=1 current_player=0)

## 目的

- 验证 vice_president 可作为 from_employee 被培训为 senior_vice_president。

## 复核步骤

1. 载入后应处于 Working/Train，且玩家 0 在岗包含 trainer；reserve_employees 包含 vice_president。
2. 将 vice_president 培训为 senior_vice_president 并执行。

## 预期结果

- vice_president 从 reserve_employees 移除；senior_vice_president 加入 reserve_employees。

## 推荐参数（可选）

- action_id: `train`
- actor: `0`
- params:
	- `from_employee`: `vice_president`
	- `to_employee`: `senior_vice_president`

## 关联单元测试

- `core/tests/company_structure_test.gd`
