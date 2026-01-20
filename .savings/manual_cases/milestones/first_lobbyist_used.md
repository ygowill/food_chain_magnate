# milestone/first_lobbyist_used - 首个使用说客（first_lobbyist_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_lobbyist_used.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Lobbyists (round=1 current_player=0)

## 目的

- 验证 Lobbyists 子阶段放置道路会触发 first_lobbyist_used，并为该玩家生成 extra tile 放置权限。

## 复核步骤

1. 载入后应处于 Working/Lobbyists，且玩家 0 在岗包含 lobbyist。
2. 按说明文件的推荐参数执行「放置道路（说客）」动作（place_lobbyists_road）。

## 预期结果

- 玩家 0 获得里程碑 first_lobbyist_used（player.milestones）。
- round_state.lobbyists_extra_tile_pending[0] == true（随后可执行 place_lobbyists_extra_map_tile）。

## 推荐参数（可选）

- action_id: `place_lobbyists_road`
- actor: `0`
- params:
	- `piece_id`: `lobbyists_road_straight`
	- `anchor_pos`: `[10, 1]`
	- `rotation`: `0`

## 关联单元测试

- `core/tests/lobbyists_v2_test.gd`
