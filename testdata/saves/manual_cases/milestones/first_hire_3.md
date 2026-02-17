# milestone/first_hire_3 - 首个一回合雇佣三人（first_hire_3）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_hire_3.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Recruit (round=1 current_player=0)

## 目的

- 验证 Recruit 子阶段第 3 次 recruit 会触发 first_hire_3，并获得 2 张 management_trainee。

## 复核步骤

1. 载入后应处于 Working/Recruit，且玩家 0 在岗包含 hr_director。
2. 依次执行 3 次「招聘」（任意 entry_level 员工均可）。

## 预期结果

- 第 3 次 recruit 后：玩家 0 获得里程碑 first_hire_3（player.milestones）。
- 玩家 0 reserve_employees 新增 2 张 management_trainee。

## 推荐参数（可选）

- action_id: `recruit`
- actor: `0`
- params:
	- `employee_type`: `waitress`

## 关联单元测试

- `core/tests/milestone_system_test.gd`
