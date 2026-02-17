# milestone/first_drink_marketed - 首个营销饮料（first_drink_marketed）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_drink_marketed.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证发起营销动作 `InitiateMarketing(product=drink)` 会触发里程碑 first_drink_marketed。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 marketing_trainee。
2. 行动面板选择「发起营销」，执行一次营销：`board_number=14 product=drink duration=1 position=[6,1] rotation=0`。

## 预期结果

- 玩家 0 获得里程碑 first_drink_marketed（player.milestones）。
- `state.map.marketing_placements['14'].product == 'drink'`。
- 本场景使用 billboard #14，可能同时触发 first_billboard（属正常联动）。

## 关联单元测试

- `core/tests/milestone_system/milestone_system_triggers_test.gd`
- `core/tests/marketing_campaigns_test.gd`
