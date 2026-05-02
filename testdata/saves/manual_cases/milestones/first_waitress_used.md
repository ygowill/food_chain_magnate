# milestone/first_waitress_used - 首个使用服务员（first_waitress_used）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_waitress_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/PlaceRestaurants (round=1 current_player=0)

## 目的

- 验证晚餐结算触发 UseEmployee(waitress) -> first_waitress_used，并将该玩家薪水改为每人 $3。

## 复核步骤

1. 载入后应处于 Working/PlaceRestaurants，且玩家 0 在岗包含 waitress（并已准备至少 1 名需薪员工）。
2. 点击「推进子阶段」离开 Working：晚餐会自动结算并跳到 Payday。

## 预期结果

- 玩家 0 获得里程碑 first_waitress_used（player.milestones）。
- player.salary_cost_override == 3（Payday 计算薪水时可观察）。

## 关联单元测试

- `core/tests/new_milestones_recruiter_waitress_v2_test.gd`
