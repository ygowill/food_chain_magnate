# milestone/first_cart_operator_used - 首个使用手推车操作员（first_cart_operator_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_cart_operator_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/GetDrinks (round=1 current_player=0)

## 目的

- 验证 procure_drinks 会触发 UseEmployee(cart_operator) 并获得里程碑（不同采购员每源+饮料数量增量）。

## 复核步骤

1. 载入后应处于 `Working/GetDrinks`，且玩家 0 在岗包含 `cart_operator`。
2. 执行 `procure_drinks`，只选择 1 个饮料源完成一次采购。
3. 记录本次新增库存数量（同一饮料源下，`cart_operator` 应体现每源 +2 的里程碑增量）。

## 预期结果

- 玩家 0 获得里程碑 `first_cart_operator_used`（`player.milestones`）。
- 对单一饮料源采购时，`cart_operator` 的新增饮料数量应高于基础值（体现 `drinks_per_source_delta`）。

## 关联单元测试

- `core/tests/procure_drinks_test.gd`
