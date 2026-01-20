# milestone/first_brand_director_used - 首个使用品牌总监（first_brand_director_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_brand_director_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证 brand_director 发起营销会触发里程碑：radio 永久（duration=-1），且 brand_director 忙碌到游戏结束。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 brand_director。
2. 执行「发起营销」放置 radio #1（参数见推荐）。

## 预期结果

- 玩家 0 获得里程碑 first_brand_director_used（player.milestones）。
- 该 radio 的 remaining_duration 应为 -1，且 brand_director 应保持 busy（不会因到期返回）。

## 推荐参数（可选）

- action_id: `initiate_marketing`
- actor: `0`
- params:
	- `employee_type`: `brand_director`
	- `board_number`: `1`
	- `product`: `soda`
	- `duration`: `1`
	- `position`: `[11, 0]`
	- `rotation`: `0`

## 关联单元测试

- `core/tests/new_milestones_brand_director_v2_test.gd`
