# milestone/first_brand_manager_used - 首个使用品牌经理（first_brand_manager_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_brand_manager_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证 `brand_manager` 放置 `airplane` 会触发里程碑，并允许同回合为该飞机广告追加第二种商品（A→B）。
- 验证触发后使用的仍是原始飞机编号（#4/#5/#6），并切换为双半边展示样式（如 `4A/4B`）。

## 复核步骤

1. 载入后应处于 `Working/Marketing`，且玩家 0 在岗包含 `brand_manager`。
2. 执行 `initiate_marketing` 放置 `airplane #4`（参数见推荐）。
3. 观察是否出现动作 `set_brand_manager_airplane_second_good`，并执行该动作，设置 `product_b=burger`。
4. 查看地图上 #4 飞机广告：应显示双半边与双编号（`4A/4B`），而不是右上角单一编号。

## 预期结果

- 玩家 0 获得里程碑 `first_brand_manager_used`（`player.milestones`）。
- #4 飞机广告成功追加第二商品，按 `A=beer -> B=burger` 顺序结算。
- 该广告仍使用基础编号 `4`（不是 `5100+` 编号），并以 `4A/4B` 形式绘制。

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
