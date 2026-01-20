# milestone/first_cart_operator_used - 首个使用手推车操作员（first_cart_operator_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_cart_operator_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/GetDrinks (round=1 current_player=0)

## 目的

- 验证 procure_drinks 会触发 UseEmployee(cart_operator) 并获得里程碑（不同采购员每源+饮料数量增量）。

## 复核步骤

1. 载入后应处于 Working/GetDrinks，且玩家 0 在岗包含 cart_operator。
2. 执行「采购饮料」并在地图上选择饮料来源生成路线后确认执行。

## 预期结果

- 玩家 0 获得里程碑 first_cart_operator_used（player.milestones）。

## 关联单元测试

- `core/tests/procure_drinks_test.gd`
