# milestone/first_have_100 - 首个拥有$100（first_have_100）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_have_100.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证 first_have_100 在 Dinnertime 结算末尾（CashReached/100）触发，并应用 `ceo_get_cfo + ban_card(cfo)`。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants，且本回合已准备好一笔晚餐收入（cash 约为 95）。
2. 点击「推进子阶段」离开 Working：进入晚餐结算后会自动跳到 Payday。

## 预期结果

- 玩家 0 获得里程碑 first_have_100（player.milestones）。
- 玩家 0 现金应 >= 100。
- `player.banned_employee_ids` 包含 `cfo`，且玩家手牌/待命/忙碌区均不应再持有 `cfo`。
- `player.ceo_cfo_ability_start_round == state.round_number + 1`（本存档在 round=1 触发后应为 2）。

## 关联单元测试

- `core/tests/milestone_system/milestone_system_triggers_test.gd`
- `modules/base_rules/rules/phase/dinnertime/dinnertime_settlement_impl.gd`
