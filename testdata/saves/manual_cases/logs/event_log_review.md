# logs/event_log_review - 日志回放验证（营销结算 + 采购路线）

## 存档

- JSON: `res://testdata/saves/manual_cases/logs/event_log_review.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Restructuring/ (round=2 current_player=0)

## 目的

- 用于手工复核日志：营销结算产生需求（DEMAND_GENERATED）与采购路线（DRINKS_PROCURED）的摘要/详情展示。

## 复核步骤

1. 载入后打开日志视图（左侧「日志」按钮）。
2. 确认存在「采购饮料」日志（摘要含起点餐厅与选定进货点）。
3. 确认存在「产生需求/打上广告」日志（摘要含 board_number/新增需求数/房屋编号）。
4. 双击上述日志条目打开详情窗口，核对 details 中的 picked_sources / affected_house_numbers 等字段。

## 预期结果

- 日志可筛选玩家；「全部」可显示全体日志。
- 双击条目可打开详情窗口。

## 关联单元测试

- `core/tests/marketing_demand_generated_event_test.gd`
- `core/tests/procure_drinks_route_rules_test.gd`
- `ui/scenes/tests/log_restore_after_load_test.gd`
