# employee/regional_manager - 移动餐厅员工（regional_manager）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/regional_manager.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证 move_restaurant 可用与移动合法性。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants，且玩家 0 在岗包含 regional_manager。
2. 行动面板选择「移动餐厅」，并按推荐参数移动。

## 预期结果

- 移动成功后：餐厅 anchor_pos/entrance_pos 更新；drive_thru_active=true（本回合）。

## 推荐参数（可选）

- action_id: `move_restaurant`
- actor: `0`
- params:
	- `restaurant_id`: `rest_1`
	- `position`: `[13, 0]`
	- `rotation`: `0`

## 关联单元测试

- `core/tests/move_restaurant_rules_test.gd`
