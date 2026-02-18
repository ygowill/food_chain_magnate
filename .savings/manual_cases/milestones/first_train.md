# milestone/first_train - 首个培训员工（first_train）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_train.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Train (round=1 current_player=0)

## 目的

- 验证 train 会触发 first_train，并在后续 Payday 永久降低薪资总额（salary_total_delta=-15）。

## 复核步骤

1. 载入后应处于 Working/Train，且玩家 0 在岗包含 trainer；待命区 reserve_employees 包含 management_trainee。
2. 行动面板选择「培训」，将 management_trainee 培训为 new_business_developer 并执行。

## 预期结果

- 玩家 0 获得里程碑 first_train（player.milestones）。
- 培训后：management_trainee 从 reserve_employees 移除；new_business_developer 加入 reserve_employees。
- （后续回合验证）进入 Payday 时，薪资总额应永久 -15（最低到 0）。

## 推荐参数（可选）

- action_id: `train`
- actor: `0`
- params:
	- `from_employee`: `management_trainee`
	- `to_employee`: `new_business_developer`

## 关联单元测试

- `core/tests/milestone_system_test.gd`
- `core/tests/payday_salary_test.gd`
