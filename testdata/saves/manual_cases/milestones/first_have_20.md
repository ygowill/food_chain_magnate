# milestone/first_have_20 - 首个拥有$20（first_have_20）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_have_20.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证获得 first_have_20 后可查看全部玩家储备卡，且存档保留真实基础地图。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants，并使用真实基础地图板块。
2. 打开「储备卡」总览。

## 预期结果

- 玩家 0 已获得里程碑 first_have_20（player.milestones），现金应 >= 20。
- 玩家 0 可查看全部玩家已选择的储备卡。

## 关联单元测试

- `core/tests/milestone_system_test.gd`
