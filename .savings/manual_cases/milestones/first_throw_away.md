# milestone/first_throw_away - 首个丢弃食物/饮品（first_throw_away）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_throw_away.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Payday/ (round=1 current_player=0)

## 目的

- 验证进入 Cleanup 时若有库存被清空，会触发 CleanupDiscard -> first_throw_away。

## 复核步骤

1. 载入后应处于 Payday 阶段，且玩家 0 库存包含 burger/soda。
2. 点击「推进阶段」离开 Payday（Marketing/Cleanup 会自动结算并跳过）。

## 预期结果

- 玩家 0 获得里程碑 first_throw_away（player.milestones）。
- 进入 Cleanup 后库存被清空（无冰箱）。

## 关联单元测试

- `core/rules/phase/cleanup_settlement.gd`
- `core/tests/cleanup_inventory_test.gd`
