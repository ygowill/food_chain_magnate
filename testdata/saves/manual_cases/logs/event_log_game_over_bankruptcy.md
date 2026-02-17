# logs/event_log_game_over_bankruptcy - 游戏结束复核（银行二次破产 -> GameOver）

## 存档

- JSON: `res://testdata/saves/manual_cases/logs/event_log_game_over_bankruptcy.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceHouses (round=1 current_player=0)

## 目的

- 用于手工复核终局：第二次破产触发 Working -> Dinnertime -> GameOver，并弹出 GameOver 面板且按钮可用（返回主菜单/再来一局）。

## 情景设计

- 预置：银行余额被清空为 $0；两名玩家储备卡均为 cash=$10（第一次破产注资总额=$20）。
- 地图：单餐厅 rest_0 + 单房屋 h0（3 个 burger 需求）。
- 玩家 1（P1）库存 burger=3，可在晚餐结算获得 $30；触发第二次破产并在晚餐结束后进入 GameOver。
- 起始位置：Working/PlaceHouses；先点「跳过放置房屋」，再点「确认结束」触发终局。

## 复核步骤

1. 载入后确认当前位置为 Working/PlaceHouses。
2. 点击「跳过放置房屋」（skip_sub_phase），进入 PlaceRestaurants。
3. 点击「确认结束」（skip），触发晚餐结算与二次破产，阶段自动推进到 GameOver。
4. 确认弹出「游戏结束」面板，且「返回主菜单」「再来一局」按钮可点击并生效。

## 预期结果

- 触发终局时游戏不应卡死；GameOver 面板可正常展示排名与统计。
- 可正常返回主菜单或重新开始游戏。

## 关联单元测试

- `core/tests/bankruptcy_test.gd`
