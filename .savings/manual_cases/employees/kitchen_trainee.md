# employee/kitchen_trainee - 见习厨师（kitchen_trainee）

## 存档

- JSON: `res://.savings/manual_cases/employees/kitchen_trainee.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/GetFood (round=1 current_player=0)

## 目的

- 验证 produce_food 对“多选生产”员工的参数校验与库存变化。

## 复核步骤

1. 载入后应处于 Working/GetFood，且玩家 0 在岗包含 kitchen_trainee。
2. 行动面板选择「生产食物」。
3. 选择 employee_type=kitchen_trainee，并选择 food_type=burger（或 pizza），确认执行。

## 预期结果

- 玩家 0 库存 burger +1（或 pizza +1）。
- 同一子阶段再次对同一 kitchen_trainee 执行 produce_food 应提示次数耗尽。

## 关联单元测试

- `core/tests/produce_food_test.gd`
