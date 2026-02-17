# milestone/first_rural_marketeer_used - 首个使用乡村营销员（first_rural_marketeer_used）

## 存档

- JSON: `res://testdata/saves/manual_cases/milestones/first_rural_marketeer_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证放置巨型广告牌会触发 first_rural_marketeer_used，并生成 offramp pending。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 rural_marketeer。
2. 执行「放置巨型广告牌（place_giant_billboard）」动作（side=N product=burger）。

## 预期结果

- 玩家 0 获得里程碑 first_rural_marketeer_used（player.milestones）。
- round_state.rural_marketeers_offramp_pending[0] == true。

## 推荐参数（可选）

- action_id: `place_giant_billboard`
- actor: `0`
- params:
	- `side`: `N`
	- `product`: `burger`

## 关联单元测试

- `core/tests/rural_marketeers_v2_test.gd`
