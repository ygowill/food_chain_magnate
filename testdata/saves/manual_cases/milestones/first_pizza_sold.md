# milestone/first_pizza_sold - 首个卖出披萨（first_pizza_sold）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_pizza_sold.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证晚餐卖出 pizza 会触发里程碑：生成 3 个待放置 radio（#1-#3），放完前阻断推进阶段。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants（已预置 3 个 pizza 需求与库存）。
2. 点击「推进子阶段」离开 Working：应进入 Dinnertime，且出现 3 个 pizza radio pending。
3. 依次执行 place_pizza_radio（position 选取任意合法空位）放置 3 个 radio；放完后才可推进阶段。

## 预期结果

- 玩家 0 获得里程碑 first_pizza_sold（player.milestones）。
- 应放置 3 个 radio marketing_instances：board_number=1..3、product=pizza、remaining_duration=2、employee_type=__milestone__。

## 关联单元测试

- `core/tests/new_milestones_pizza_sold_v2_test.gd`
