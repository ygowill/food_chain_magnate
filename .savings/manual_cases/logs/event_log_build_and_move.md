# logs/event_log_build_and_move - 日志回放验证（建房 + 花园 + 开店 + 搬店）

## 存档

- JSON: `res://.savings/manual_cases/logs/event_log_build_and_move.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 用于手工复核地图建造日志：HOUSE_PLACED/GARDEN_ADDED/RESTAURANT_PLACED/RESTAURANT_MOVED。

## 复核步骤

1. 载入后打开日志视图。
2. 确认存在放置房屋/添加花园/放置餐厅/移动餐厅相关日志。

## 预期结果

- 放置/移动日志摘要包含坐标；details 中包含 restaurant_id/house_id 等字段。

## 关联单元测试

- `core/tests/place_house_rules_test.gd`
- `core/tests/add_garden_rules_test.gd`
