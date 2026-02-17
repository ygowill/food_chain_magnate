# employee/hr_director - 招聘能力员工（hr_director）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/hr_director.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Recruit (round=1 current_player=0)

## 目的

- 验证 Recruit 子阶段招聘次数上限（CEO 1 + recruit_capacity 加成）。

## 复核步骤

1. 载入后应处于 Working/Recruit，且玩家 0 在岗包含 hr_director。
2. 重复执行 recruit，直到达到上限（上限随员工不同）。

## 预期结果

- 超过上限后应被拒绝（"本子阶段招聘次数已用完"）。

## 推荐参数（可选）

- action_id: `recruit`
- actor: `0`
- params:
	- `employee_type`: `waitress`

## 关联单元测试

- `core/tests/employee_action_test.gd`
