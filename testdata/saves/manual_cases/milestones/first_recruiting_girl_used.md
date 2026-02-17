# milestone/first_recruiting_girl_used - 首个使用人力资源专员（first_recruiting_girl_used）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_recruiting_girl_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Recruit (round=1 current_player=0)

## 目的

- 验证 recruiting_girl 的 recruit 容量在第 2 次招聘时必然被推导使用，从而触发里程碑并获得 executive_vice_president（永久免薪）。

## 复核步骤

1. 载入后应处于 Working/Recruit，且玩家 0 在岗包含 recruiting_girl。
2. 连续执行 2 次 recruit（任意入门级员工均可）。

## 预期结果

- 第 2 次 recruit 后：玩家 0 获得里程碑 first_recruiting_girl_used（player.milestones）。
- 玩家 0 reserve_employees 新增 executive_vice_president，且其永久免薪。

## 推荐参数（可选）

- action_id: `recruit`
- actor: `0`
- params:
	- `employee_type`: `waitress`

## 关联单元测试

- `core/tests/new_milestones_recruiter_waitress_v2_test.gd`
