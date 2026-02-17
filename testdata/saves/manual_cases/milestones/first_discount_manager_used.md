# milestone/first_discount_manager_used - 首个使用折扣经理（first_discount_manager_used）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_discount_manager_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Recruit (round=1 current_player=0)

## 目的

- 验证 set_discount 会触发里程碑，并在下一回合 Restructuring 结束扣除银行 $100。

## 复核步骤

1. 载入后应处于 `Working` 阶段，且玩家 0 在岗包含 `discount_manager`。
2. 执行强制动作 `set_discount`（`-$3`）。
3. 立即检查玩家 0：应已获得里程碑，且 `bank_burn_pending=true`。
4. 进入下一回合 `Restructuring` 并推进离开，观察银行与玩家标记变化。

## 预期结果

- 玩家 0 获得里程碑 `first_discount_manager_used`（`player.milestones`），且 `bank_burn_pending=true`。
- 下一回合离开 `Restructuring` 后：`bank.total` 扣减 `100`，且 `bank_burn_pending` 被清除。

## 推荐参数（可选）

- action_id: `set_discount`
- actor: `0`
- params:

## 关联单元测试

- `core/tests/new_milestones_discount_manager_bank_burn_v2_test.gd`
