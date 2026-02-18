# employee/new_business_developer - 建房/花园员工（new_business_developer）

## 存档

- JSON: `res://.savings/manual_cases/employees/new_business_developer.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceHouses (round=1 current_player=0)

## 目的

- 验证 place_house/add_garden 两类动作可用（通过 2 张同类员工提供足够次数）。

## 复核步骤

1. 载入后应处于 Working/PlaceHouses，且玩家 0 在岗包含 new_business_developer x2。
2. 行动面板选择「放置房屋」，按推荐参数放置并确认。
3. 同一子阶段再执行一次「添加花园」（选择任意无花园房屋与方向）应允许。

## 预期结果

- place_house 成功后：state.map.houses 新增房屋；house_number_supply_remaining 消耗。
- add_garden 成功后：目标 house.has_garden=true 且占地更新为 house_with_garden。

## 推荐参数（可选）

- action_id: `place_house`
- actor: `0`
- params:
	- `position`: `[10, 2]`
	- `rotation`: `0`
	- `house_number`: `1`

## 关联单元测试

- `core/tests/place_house_rules_test.gd`
- `core/tests/add_garden_rules_test.gd`
