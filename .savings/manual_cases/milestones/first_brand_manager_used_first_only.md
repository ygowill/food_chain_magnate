# milestone/first_brand_manager_used_first_only - 品牌经理里程碑仅首个飞机广告生效（first_brand_manager_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_brand_manager_used_first_only.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)
- 说明: 本档在玩家 0 起始携带 2 张在岗 `brand_manager`，用于验证“同回合仅首个飞机广告生效”。

## 目的

- 验证 `first_brand_manager_used` 仅对本回合**第一个**由 `brand_manager` 放置的 `airplane` 生效。
- 验证同回合后续由同玩家 `brand_manager` 放置的 `airplane` 不再触发该能力。

## 复核步骤

1. 执行 `initiate_marketing`：`brand_manager` 放置 `airplane #4`（建议 `product=beer`）。
2. 不执行第二商品动作，继续执行第二次 `initiate_marketing`：另一张 `brand_manager` 放置 `airplane #5`（建议 `product=pizza`）。
3. 检查可执行动作与地图状态：`set_brand_manager_airplane_second_good` 仍应只对应 #4。
4. 执行 `set_brand_manager_airplane_second_good`，设置 `product_b=burger`。

## 预期结果

- `first_brand_manager_used` 只在第 1 次飞机广告时触发。
- `pending.board_number` 始终是 `4`，不会切换为 `5`。
- #4 切换为 dual piece（可追加 B 半边）；#5 不切换为 dual piece。
- `set_brand_manager_airplane_second_good` 同回合仅可成功一次。

## 推荐参数（可选）

- 第一次 action_id: `initiate_marketing`
- actor: `0`
- params:
	- `employee_type`: `brand_manager`
	- `board_number`: `4`
	- `product`: `beer`
	- `duration`: `1`
	- `position`: `[0, 10]`

- 第二次 action_id: `initiate_marketing`
- actor: `0`
- params:
	- `employee_type`: `brand_manager`
	- `board_number`: `5`
	- `product`: `pizza`
	- `duration`: `1`
	- `position`: `[0, 12]`

## 关联单元测试

- `core/tests/new_milestones_brand_manager_v2_test.gd`
