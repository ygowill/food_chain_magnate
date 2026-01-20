# milestone/first_marketeer_used - 首个使用营销员（first_marketeer_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_marketeer_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证首次使用任意营销员发起营销会触发 first_marketeer_used（Marketing 每放 1 个需求 +$5；Dinnertime distance -2 可为负）。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 campaign_manager。
2. 执行「发起营销」放置 mailbox #7（参数见推荐）。
3. （可选）推进到 Marketing/Dinnertime 结算，观察 cash +5/需求与负距离逻辑。

## 预期结果

- 玩家 0 获得里程碑 first_marketeer_used（player.milestones）。

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
