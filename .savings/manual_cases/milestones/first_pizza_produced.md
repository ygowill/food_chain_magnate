# milestone/first_pizza_produced - 首个生产披萨（first_pizza_produced）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_pizza_produced.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/GetFood (round=1 current_player=0)

## 目的

- 验证 Produce(product=pizza) 会触发里程碑 first_pizza_produced。

## 复核步骤

1. 载入后应处于 Working/GetFood，且玩家 0 在岗包含 pizza_cook。
2. 行动面板选择「生产食物」并执行（employee_type=pizza_cook）。

## 预期结果

- 玩家 0 获得里程碑 first_pizza_produced（player.milestones）。
- 玩家 0 库存 pizza 增加。

## 推荐参数（可选）

- action_id: `produce_food`
- actor: `0`
- params:
	- `employee_type`: `pizza_cook`

## 关联单元测试

- `core/tests/produce_food_test.gd`
