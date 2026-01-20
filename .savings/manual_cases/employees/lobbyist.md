# employee/lobbyist - 说客（lobbyist）

## 存档

- JSON: `res://.savings/manual_cases/employees/lobbyist.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Lobbyists (round=1 current_player=0)

## 目的

- 验证 Lobbyists 子阶段与放置建设中道路/公园的合法性。

## 复核步骤

1. 载入后应处于 Working/Lobbyists，且玩家 0 在岗包含 lobbyist。
2. 行动面板选择「说客：放置道路（建设中）」并按推荐参数放置。

## 预期结果

- state.map.lobbyists_pending_roads 增加 1 条；并消耗道路供应计数。

## 推荐参数（可选）

- action_id: `place_lobbyists_road`
- actor: `0`
- params:
	- `piece_id`: `lobbyists_road_straight`
	- `anchor_pos`: `[10, 1]`
	- `rotation`: `0`

## 关联单元测试

- `core/tests/lobbyists_v2_test.gd`
