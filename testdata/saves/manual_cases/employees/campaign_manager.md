# employee/campaign_manager - 营销员工（campaign_manager）

## 存档

- JSON: `res://testdata/saves/manual_cases/employees/campaign_manager.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证 initiate_marketing(board=10) 可用与放置合法性。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 campaign_manager。
2. 行动面板选择「发起营销」，并按说明文件中的推荐坐标放置。

## 预期结果

- 营销板件成功放置，并写入 state.map.marketing_placements；员工进入 busy_marketers。

## 推荐参数（可选）

- action_id: `initiate_marketing`
- actor: `0`
- params:
	- `employee_type`: `campaign_manager`
	- `board_number`: `10`
	- `product`: `burger`
	- `duration`: `1`
	- `position`: `[6, 1]`
	- `rotation`: `0`

## 关联单元测试

- `core/tests/marketing_campaigns_test.gd`
