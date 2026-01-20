# milestone/first_brand_manager_used - 首个使用品牌经理（first_brand_manager_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_brand_manager_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证 brand_manager 放置 airplane 会触发里程碑，并允许同回合追加第二种商品。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 brand_manager。
2. 执行「发起营销」放置 airplane #4（参数见推荐）。
3. 同回合执行动作 set_brand_manager_airplane_second_good，设置 product_b=burger。

## 预期结果

- 玩家 0 获得里程碑 first_brand_manager_used（player.milestones）。
- 追加第二种商品成功（同回合仅一次）。

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
