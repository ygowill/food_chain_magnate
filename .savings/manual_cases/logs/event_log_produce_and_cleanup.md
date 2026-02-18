# logs/event_log_produce_and_cleanup - 日志回放验证（生产食物 + Cleanup 丢弃）

## 存档

- JSON: `res://.savings/manual_cases/logs/event_log_produce_and_cleanup.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Restructuring/ (round=2 current_player=0)

## 目的

- 用于手工复核生产与清理日志：FOOD_PRODUCED/FOOD_DISCARDED。

## 复核步骤

1. 载入后打开日志视图。
2. 确认存在「生产食物」日志。
3. 确认存在「清理库存：丢弃 ...」日志。

## 预期结果

- 丢弃日志 details.discarded 为 product_id -> count 字典。

## 关联单元测试

- `core/tests/produce_food_test.gd`
