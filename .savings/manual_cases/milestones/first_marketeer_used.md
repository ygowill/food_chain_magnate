# milestone/first_marketeer_used - 首个使用营销员（first_marketeer_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_marketeer_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证首次使用任意营销员发起营销会触发 first_marketeer_used（Marketing 每放 1 个需求 +$5；Dinnertime distance -2 可为负）。

## 复核步骤

1. 载入后应处于 `Working/Marketing`，且玩家 0 在岗包含 `campaign_manager`。
2. 执行 `initiate_marketing` 放置 `mailbox #7`（参数见推荐）。
3. 推进到 `Marketing` 结算，记录玩家 0 现金变化（每新增 1 个需求应给 `$5`）。
4. 再推进到 `Dinnertime`，确认距离 `-2` 修正不会导致结算失败（允许负距离）。

## 预期结果

- 玩家 0 获得里程碑 `first_marketeer_used`（`player.milestones`）。
- `Marketing` 结算时，玩家 0 现金按“每需求 +$5”增加（通常至少增加 `$5`）。
- `Dinnertime` 在存在 `-2` 距离修正时仍能正常结算（包括负距离场景）。

## 推荐参数（可选）

- action_id: `initiate_marketing`
- actor: `0`
- params:
	- `employee_type`: `campaign_manager`
	- `board_number`: `7`
	- `product`: `burger`
	- `duration`: `1`
	- `position`: `[6, 1]`
	- `rotation`: `0`

## 关联单元测试

- `core/tests/new_milestones_v2_test.gd`
