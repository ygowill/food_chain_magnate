# milestone/first_billboard - 首个放置广告牌（first_billboard）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_billboard.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证 `InitiateMarketing(type=billboard)` 会触发里程碑 first_billboard，并对当次板件生效永久化。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 marketing_trainee。
2. 行动面板选择「发起营销」，按推荐参数放置 billboard #14。
3. 继续推进阶段到 Payday，查看薪资结算。

## 预期结果

- 玩家 0 获得里程碑 first_billboard（player.milestones）。
- `state.map.marketing_placements['14'].type == 'billboard'`。
- `state.map.marketing_placements['14'].remaining_duration == -1`（当次放置应被永久化）。
- Payday 结算中，营销员应免薪（本场景可检查 `state.round_state.payday.details[0].due == 0`）。

## 推荐参数（可选）

- action_id: `initiate_marketing`
- actor: `0`
- params:
	- `employee_type`: `marketing_trainee`
	- `board_number`: `14`
	- `product`: `burger`
	- `duration`: `1`
	- `position`: `[6, 1]`
	- `rotation`: `0`

## 关联单元测试

- `core/tests/marketing_campaigns_test.gd`
- `core/tests/milestone_system/milestone_system_triggers_test.gd`
