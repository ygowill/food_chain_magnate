# milestone/first_airplane - 首个进行飞机营销（first_airplane）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_airplane.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证 InitiateMarketing(type=airplane) 会触发里程碑 first_airplane。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 brand_manager。
2. 行动面板选择「发起营销」，按推荐参数放置 airplane #4。

## 预期结果

- 玩家 0 获得里程碑 first_airplane（player.milestones）。
- state.map.marketing_placements['4'].type == 'airplane'。

## 推荐参数（可选）

- action_id: `initiate_marketing`
- actor: `0`
- params:
	- `employee_type`: `brand_manager`
	- `board_number`: `4`
	- `product`: `beer`
	- `duration`: `1`
	- `position`: `[2, 0]`
	- `rotation`: `90`

## 关联单元测试

- `core/tests/marketing_campaigns_test.gd`
