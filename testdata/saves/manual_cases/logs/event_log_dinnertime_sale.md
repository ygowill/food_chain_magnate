# logs/event_log_dinnertime_sale - 日志回放验证（晚餐结算：售出 + 现金变化）

## 存档

- JSON: `res://testdata/saves/manual_cases/logs/event_log_dinnertime_sale.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Payday/ (round=1 current_player=1)

## 目的

- 用于手工复核晚餐结算日志：DINNERTIME_REPORT + FOOD_SOLD + PLAYER_CASH_CHANGED（覆盖花园翻倍、营销加成、沿路购买、服务员小费、CFO 加成、薯条主厨房屋奖）。

## 情景设计

- 地图：水平道路 y=3；rest_0/rest_1 位于道路下方；h0(花园)/h1/h2 位于道路上方。
- h0：花园房屋，需求 burger+beer（覆盖：花园翻倍 + 营销加成 + 薯条主厨房屋奖）。
- h1：需求 pizza（覆盖：按品类营销加成）。
- h2：需求 soda（由玩家2售出）。
- 沿路购买：玩家2在 rest_1 持有 coffee 库存；玩家1从 rest_0 前往 h0/h1 的路径会路过 rest_1，触发咖啡沿路购买收入。
- 玩家1：waitress x2（tips + 平局）、cfo x1（+50%）、fry_chef x2（每房屋+$10）；里程碑 first_*_marketed 提供 sell_bonus。

## 复核步骤

1. 载入后打开日志视图。
2. 确认存在「晚餐结算」日志。
3. 确认存在多条「售出」日志（至少覆盖：花园翻倍、营销加成、房屋奖拆分）。
4. 子项顺序调整：售出在前、现金变化在后。
5. 确认存在「玩家 X 现金变化」日志，且摘要包含「晚餐收入来源」分解（至少覆盖：花园加成/营销加成/沿路购买收入/服务员收入/CFO 加成/薯条主厨加成）。

## 预期结果

- 售出日志 details.required/details.revenue/details.house_bonus_breakdown 正确填充。
- 现金变化日志 details.income_breakdown.context == dinnertime_income，且 items 覆盖上述加成来源。

## 关联单元测试

- `core/tests/dinnertime_settlement_test.gd`
