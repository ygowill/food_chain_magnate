# milestone/first_cart_operator - 首个打出手推车操作员（first_cart_operator）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_cart_operator.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/GetDrinks (round=1 current_player=0)

## 目的

- 验证 procure_drinks 会触发 UseEmployee(cart_operator) -> first_cart_operator，并在当次采购应用 `distance_plus_one`。

## 复核步骤

1. 载入后应处于 Working/GetDrinks，且玩家 0 在岗包含 cart_operator。
2. 行动面板选择「采购饮料」，优先尝试选择一个“刚好超过默认距离 1 格”的饮料点并生成路线后执行。

## 预期结果

- 玩家 0 获得里程碑 first_cart_operator（player.milestones）。
- 该次采购应可成功执行，并体现“首个手推车操作员”带来的当次距离放宽（`distance_plus_one`）。

## 关联单元测试

- `core/tests/procure_drinks_test.gd`
- `core/tests/procure_drinks_route_rules_test.gd`
