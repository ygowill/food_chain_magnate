# milestone/first_campaign_manager_used - 首个使用营销经理（first_campaign_manager_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_campaign_manager_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证 campaign_manager 发起营销会触发里程碑，并在同回合允许放置第二张同类型板件。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 campaign_manager。
2. 执行「发起营销」放置 mailbox #7（参数见推荐）。
3. 同回合应出现动作 place_campaign_manager_second_tile：选择 board_number=8 并放置第二张同类型板件。

## 预期结果

- 玩家 0 获得里程碑 first_campaign_manager_used（player.milestones）。
- 第二张板件放置成功；campaign_manager 应保持 busy，直到两张板件都到期后才返回。

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

- `core/tests/new_milestones_campaign_manager_v2_test.gd`
