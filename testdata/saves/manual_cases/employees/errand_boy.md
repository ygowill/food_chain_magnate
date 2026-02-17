# employee/errand_boy - 跑腿伙计（errand_boy）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/errand_boy.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/GetDrinks (round=1 current_player=0)

## 目的

- 验证 errand_boy 的特殊采购（直接获得指定饮料 1 瓶）。

## 复核步骤

1. 载入后应处于 Working/GetDrinks，且玩家 0 在岗包含 errand_boy。
2. 行动面板选择「采购饮料」。
3. 选择 employee_type=errand_boy，并指定 drink_type=soda，确认执行。

## 预期结果

- 玩家 0 库存 soda +1。

## 推荐参数（可选）

- action_id: `procure_drinks`
- actor: `0`
- params:
	- `employee_type`: `errand_boy`
	- `drink_type`: `soda`

## 关联单元测试

- `core/tests/procure_drinks_route_rules_test.gd`
