# logs/event_log_dinnertime_sale - 日志回放验证（晚餐售出）

## 存档

- JSON: `res://.savings/manual_cases/logs/event_log_dinnertime_sale.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Payday/ (round=1 current_player=1)

## 目的

- 用于手工复核晚餐日志：DINNERTIME_REPORT + FOOD_SOLD。

## 复核步骤

1. 载入后打开日志视图。
2. 确认存在「晚餐结算」日志。
3. 确认存在至少 1 条「售出」日志。

## 预期结果

- 售出日志 details.required 与 details.revenue 正确填充。

## 关联单元测试

- `core/tests/dinnertime_settlement_test.gd`
