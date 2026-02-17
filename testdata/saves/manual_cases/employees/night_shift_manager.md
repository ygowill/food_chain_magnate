# employee/night_shift_manager - 夜班经理（night_shift_manager）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/night_shift_manager.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/GetFood (round=1 current_player=0)

## 目的

- 验证夜班经理让免薪员工在 Working 子阶段可工作两次（最简单：produce_food 两次）。

## 复核步骤

1. 载入后应处于 Working/GetFood，且玩家 0 在岗包含 night_shift_manager 与 kitchen_trainee。
2. 用 kitchen_trainee 执行 produce_food 第一次。
3. 同一子阶段再次用 kitchen_trainee 执行 produce_food，应仍允许（次数为 2）。

## 预期结果

- 第二次 produce_food 不应被拒绝为“次数耗尽”。

## 推荐参数（可选）

- action_id: `produce_food`
- actor: `0`
- params:
	- `employee_type`: `kitchen_trainee`

## 关联单元测试

- `core/tests/night_shift_managers_v2_test.gd`
