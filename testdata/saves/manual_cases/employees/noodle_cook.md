# employee/noodle_cook - 员工（noodle_cook）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/noodle_cook.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/GetFood (round=1 current_player=0)

## 目的

- 验证 produce_food 可用，并按员工定义将产物加入库存。

## 复核步骤

1. 载入后应处于 Working/GetFood，且玩家 0 在岗包含 noodle_cook。
2. 行动面板选择「生产食物」并执行。

## 预期结果

- 玩家 0 对应产物库存增加（数量取决于员工 produces.amount）。

## 推荐参数（可选）

- action_id: `produce_food`
- actor: `0`
- params:
	- `employee_type`: `noodle_cook`

## 关联单元测试

- `core/tests/noodles_sushi_v2_test.gd`
