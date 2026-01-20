# employee/rural_marketeer - 乡村营销员（rural_marketeer）

## 存档

- JSON: `res://.savings/manual_cases/employees/rural_marketeer.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Marketing (round=1 current_player=0)

## 目的

- 验证 place_giant_billboard（巨型广告牌）与员工永久忙碌。

## 复核步骤

1. 载入后应处于 Working/Marketing，且玩家 0 在岗包含 rural_marketeer。
2. 行动面板选择「放置巨型广告牌」，选择 side=N product=burger 并确认。

## 预期结果

- rural_area.giant_billboards[N] 被写入；rural_marketeer 从 employees 移到 busy_marketers。

## 推荐参数（可选）

- action_id: `place_giant_billboard`
- actor: `0`
- params:
	- `side`: `N`
	- `product`: `burger`

## 关联单元测试

- `core/tests/rural_marketeers_v2_test.gd`
