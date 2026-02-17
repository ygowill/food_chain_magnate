# milestone/first_house_built - 首个建造房屋（first_house_built）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_house_built.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceHouses (round=1 current_player=0)

## 目的

- 验证 place_house 触发 HouseBuilt -> first_house_built，并启用 multi_trainer_on_one。

## 复核步骤

1. 载入后应处于 Working/PlaceHouses，且玩家 0 在岗包含 new_business_developer。
2. 执行 place_house 放置任意房屋（参数见推荐）。

## 预期结果

- 玩家 0 获得里程碑 first_house_built（player.milestones）。
- player.multi_trainer_on_one == true。

## 推荐参数（可选）

- action_id: `place_house`
- actor: `0`
- params:
	- `position`: `[10, 2]`
	- `rotation`: `0`
	- `house_number`: `1`

## 关联单元测试

- `core/tests/place_house_rules_test.gd`
