# milestone/first_have_100 - 首个拥有$100（first_have_100）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_have_100.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证 pay_bank_to_player 后 cash>=100 会触发 first_have_100（可能同时触发 first_have_20）。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants，且本回合已准备好一笔晚餐收入（cash 约为 95）。
2. 点击「推进子阶段」离开 Working：进入晚餐结算后会自动跳到 Payday。

## 预期结果

- 玩家 0 获得里程碑 first_have_100（player.milestones）。
- 玩家 0 现金应 >= 100。

## 关联单元测试

- `core/tests/milestone_system_test.gd`
