# milestone/first_cart_operator - 首个打出手推车操作员（first_cart_operator）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_cart_operator.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/GetDrinks (round=1 current_player=0)

## 目的

- 验证 procure_drinks 会触发 UseEmployee(cart_operator) -> first_cart_operator。

## 复核步骤

1. 载入后应处于 Working/GetDrinks，且玩家 0 在岗包含 cart_operator。
2. 行动面板选择「采购饮料」，在地图上点选饮料源生成路线并执行。

## 预期结果

- 玩家 0 获得里程碑 first_cart_operator（player.milestones）。

## 关联单元测试

- `core/tests/procure_drinks_test.gd`
- `core/tests/procure_drinks_route_rules_test.gd`
