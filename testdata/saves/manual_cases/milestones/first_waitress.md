# milestone/first_waitress - 首个使用服务员（first_waitress）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_waitress.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证晚餐结算时 UseEmployee(waitress) 会触发 first_waitress，并将 tips 提升到 5。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants，且玩家 0 在岗包含 waitress。
2. 点击「推进子阶段」离开 Working：进入晚餐结算后会自动跳到 Payday。

## 预期结果

- 玩家 0 获得里程碑 first_waitress（player.milestones）。
- 本次晚餐 tips 应按 5 计算（可在 dinnertime 报告或 cash 变化中观察）。

## 关联单元测试

- `core/tests/dinnertime_settlement_test.gd`
