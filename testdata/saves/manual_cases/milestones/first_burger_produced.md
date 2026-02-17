# milestone/first_burger_produced - 首个生产汉堡（first_burger_produced）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_burger_produced.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/GetFood (round=1 current_player=0)

## 目的

- 验证 Produce(product=burger) 会触发里程碑 first_burger_produced，并发放奖励员工卡。

## 复核步骤

1. 载入后应处于 Working/GetFood，且玩家 0 在岗包含 burger_cook。
2. 行动面板选择「生产食物」并执行（employee_type=burger_cook）。

## 预期结果

- 玩家 0 获得里程碑 first_burger_produced（player.milestones）。
- 玩家 0 库存 burger 增加。
- 玩家 0 `reserve_employees` 新增 1 张 `burger_cook`（gain_card）。

## 推荐参数（可选）

- action_id: `produce_food`
- actor: `0`
- params:
	- `employee_type`: `burger_cook`

## 关联单元测试

- `core/tests/milestone_system/milestone_system_triggers_test.gd`
- `core/tests/produce_food_test.gd`
