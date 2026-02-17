# milestone/first_new_restaurant - 首个新餐厅（first_new_restaurant）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_new_restaurant.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证首次在 Working 阶段放置新餐厅会触发里程碑，并允许放置一个永久 mailbox（#5-#10，同街区）。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants，且玩家 0 在岗包含 local_manager。
2. 执行 place_restaurant 放置一间新餐厅（参数见推荐）。
3. 随后执行动作 place_new_restaurant_mailbox（board_number=5 product=burger position=[0,2] rotation=0）。

## 预期结果

- 放置新餐厅后：玩家 0 获得里程碑 first_new_restaurant（player.milestones）。
- place_new_restaurant_mailbox 成功后：marketing_placements 占用 #5，且 remaining_duration=-1。

## 推荐参数（可选）

- action_id: `place_restaurant`
- actor: `0`
- params:
	- `position`: `[4, 0]`
	- `rotation`: `0`

## 关联单元测试

- `core/tests/new_milestones_new_restaurant_v2_test.gd`
