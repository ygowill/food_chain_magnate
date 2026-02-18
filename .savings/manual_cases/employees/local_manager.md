# employee/local_manager - 放置餐厅员工（local_manager）

## 存档

- JSON: `res://.savings/manual_cases/employees/local_manager.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证 place_restaurant 可用与放置合法性。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants，且玩家 0 在岗包含 local_manager。
2. 行动面板选择「放置餐厅」，并按推荐坐标放置。

## 预期结果

- 放置成功后：state.map.restaurants 增加新餐厅；玩家 drive_thru_active=true（本回合）。

## 推荐参数（可选）

- action_id: `place_restaurant`
- actor: `0`
- params:
	- `position`: `[13, 0]`
	- `rotation`: `0`

## 关联单元测试

- `core/tests/place_restaurant_rules_test.gd`
