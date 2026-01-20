# milestone/first_burger_marketed - 首个营销汉堡（first_burger_marketed）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_burger_marketed.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Payday/ (round=1 current_player=0)

## 目的

- 验证 Marketing 结算产生需求时，会触发 DemandMarked(product=burger)。

## 复核步骤

1. 载入后应处于 Payday 阶段。
2. 点击「推进阶段」进入 Marketing（会自动结算并跳过到下一可停留阶段）。

## 预期结果

- 玩家 0 获得里程碑 first_burger_marketed（player.milestones）。
- state.map.houses['house_1'].demands 应新增 product=burger 的需求。

## 关联单元测试

- `core/tests/milestone_system_test.gd`
