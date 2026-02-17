# employee/truck_driver - 采购员工（truck_driver）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/truck_driver.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/GetDrinks (round=1 current_player=0)

## 目的

- 验证 procure_drinks 的路线/范围校验与库存增加（route/selected_sources 由 UI 生成）。

## 复核步骤

1. 载入后应处于 Working/GetDrinks，且玩家 0 在岗包含 truck_driver。
2. 行动面板选择「采购饮料」。
3. 选择 employee_type=truck_driver，并在地图上点选 1~N 个饮料来源生成路线后确认执行。

## 预期结果

- 库存获得饮料（数量受里程碑与员工影响）。
- 超范围/不连通/未经过选定来源等场景应被拒绝并给出原因。

## 关联单元测试

- `core/tests/procure_drinks_test.gd`
- `core/tests/procure_drinks_route_rules_test.gd`
