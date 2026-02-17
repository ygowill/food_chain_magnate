# milestone/first_brand_manager_used_dual_ui - 品牌经理双半边飞机广告显示验证（first_brand_manager_used）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_brand_manager_used_dual_ui.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证品牌经理里程碑触发后，飞机广告会切换为双半边样式。
- 验证编号显示为 `4A/4B`（`5A/5B`、`6A/6B` 同理），而不是右上角单徽标。
- 验证 A/B 半边分别承载商品信息。

## 复核步骤

1. 执行 `initiate_marketing` 放置 `airplane #4`（建议 `product=beer`）。
2. 执行 `set_brand_manager_airplane_second_good`，设置 `product_b=burger`。
3. 查看地图上的 #4 飞机广告绘制与商品显示。
4. （可选）推进到 Marketing 结算后，查看受影响房屋需求顺序是否为 A 再 B。

## 预期结果

- #4 飞机广告显示分割线，且显示 `4A`、`4B` 两个编号。
- 不应显示旧样式的右上角单编号徽标。
- A 半边显示 `beer`，B 半边显示 `burger`。
- 结算顺序为 A→B。

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

- `core/tests/new_milestones_brand_manager_v2_test.gd`
- `ui/scenes/tests/new_milestones_dual_airplane_badge_test.gd`
