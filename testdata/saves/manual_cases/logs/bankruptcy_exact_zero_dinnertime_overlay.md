# logs/bankruptcy_exact_zero_dinnertime_overlay - 工作结束前触发晚餐首个售卖首次破产（银行恰好归零）

## 存档

- JSON: `res://testdata/saves/manual_cases/logs/bankruptcy_exact_zero_dinnertime_overlay.json`
- 玩家数: 2
- Seed: 20260228
- 当前位置: Working/PlaceRestaurants（点击一次「确认结束」进入晚餐）

## 目的

- 复核：银行在晚餐结算中被支付“恰好耗尽到 0”时，应立即触发首次破产。
- 复核：首次破产事件插入在第一个房屋售卖之后，而不是等到负数。
- 复核：破产面板中应显示所有玩家的储备卡揭示详情。

## 情景设计

- 起点在 `Working/PlaceRestaurants`，尚未结束工作时间。
- 晚餐阶段会发生 2 个房屋销售（house #1 与 house #2，均为 1 份 burger）。
- 银行初始余额为 `$10`。
- 第 1 个房屋销售收入为 `$10`，支付后银行恰好到 `0`，立即触发首次破产。
- 两位玩家储备卡均已预选（P1: `$20`/4 槽，P2: `$30`/5 槽），用于验证面板逐玩家展示。

## 复核步骤

1. 载入存档，确认当前为 `Working/PlaceRestaurants`，银行余额 `$10`。
2. 点击一次「确认结束」，进入晚餐结算。
3. 观察第 1 个房屋销售结算完成后：
   - 首次破产面板立即出现；
   - 触发时点为银行恰好归零（不是负数）。
4. 检查面板内容包含两位玩家储备卡详情。
5. 关闭面板后流程继续，第 2 个房屋销售继续结算。

## 关联单元测试

- `core/tests/bankruptcy_test.gd`
