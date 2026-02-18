# milestone/first_errand_boy - 首个打出跑腿伙计（first_errand_boy）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_errand_boy.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/GetDrinks (round=1 current_player=0)

## 目的

- 验证 errand_boy 的 procure_drinks 会触发 UseEmployee(errand_boy) -> first_errand_boy，且里程碑效果在当次生效。

## 复核步骤

1. 载入后应处于 Working/GetDrinks，且玩家 0 在岗包含 errand_boy。
2. 行动面板选择「采购饮料」，选择 `employee_type=errand_boy drink_type=soda` 并执行。

## 预期结果

- 玩家 0 获得里程碑 first_errand_boy（player.milestones）。
- 玩家 0 库存 `soda` 当次应增加 2（基础 1 + 里程碑 `procure_plus_one` 1）。

## 推荐参数（可选）

- action_id: `procure_drinks`
- actor: `0`
- params:
	- `employee_type`: `errand_boy`
	- `drink_type`: `soda`

## 关联单元测试

- `core/tests/procure_drinks_route_rules_test.gd`
