# milestone/first_have_20 - 首个拥有$20（first_have_20）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_have_20.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证 pay_bank_to_player 后 cash>=20 会触发 first_have_20。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants，且本回合已准备好一笔晚餐收入（cash 约为 15）。
2. 点击「推进子阶段」离开 Working：进入晚餐结算后会自动跳到 Payday。

## 预期结果

- 玩家 0 获得里程碑 first_have_20（player.milestones）。
- 玩家 0 现金应 >= 20。

## 关联单元测试

- `core/tests/milestone_system_test.gd`
