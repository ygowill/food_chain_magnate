# milestone/first_radio - 首个进行电波营销（first_radio）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_radio.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证 InitiateMarketing(type=radio) 会触发里程碑 first_radio，并使 radio 的需求量额外 +1。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 brand_director。
2. 行动面板选择「发起营销」，按推荐参数放置 radio #1。
3. 推进到 Marketing 结算，观察该 radio 对应产品的需求增加量。

## 预期结果

- 玩家 0 获得里程碑 first_radio（player.milestones）。
- `state.map.marketing_placements['1'].type == 'radio'`。
- 在后续 Marketing 结算中，该 radio 需求增加应为“基础 1 + 里程碑额外 1”。

## 推荐参数（可选）

- action_id: `initiate_marketing`
- actor: `0`
- params:
	- `employee_type`: `brand_director`
	- `board_number`: `1`
	- `product`: `burger`
	- `duration`: `1`
	- `position`: `[11, 0]`
	- `rotation`: `0`

## 关联单元测试

- `core/tests/marketing_campaigns_test.gd`
- `modules/base_rules/rules/phase/marketing/settlement_demand_effects.gd`
