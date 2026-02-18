# milestone/first_lobbyist_used_multi_player_same_round - 同回合多玩家扩边（first_lobbyist_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_lobbyist_used_multi_player_same_round.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Lobbyists (round=1 current_player=0)

## 目的

- 验证同一回合内多名玩家先后使用说客后，都能获得 first_lobbyist_used 并当场二选一（使用扩边/放弃）；同时扩边产生的 void 区域不应显示红叉 blocked 覆盖。

## 复核步骤

1. 载入后应处于 Working/Lobbyists，且玩家 0/1 在岗包含 lobbyist；此时两名玩家都不应已获得 first_lobbyist_used。
2. 玩家 0：放置 1 个「说客道路/公园」（place_lobbyists_road / place_lobbyists_park）以触发里程碑；随后应当场弹出「使用/放弃」二选一；选择“使用”，并在地图上放置 1 个额外 tile（注意扩边后空余区域不应显示红色叉）。
3. 玩家 0：快速跳过后续子阶段直到轮到玩家 1（同一回合内）。
4. 玩家 1：同样放置 1 个「说客道路/公园」触发里程碑；应弹出二选一；选择“使用”，并放置 1 个额外 tile（可复核多名玩家同回合均可扩边）。

## 预期结果

- 玩家 0/1 均在各自首次使用说客后获得 first_lobbyist_used，并在 Lobbyists 子阶段弹出二选一并成功执行扩边放置。
- 扩边造成的空余（void）区域不应显示红叉 blocked 覆盖（仍可能用于后续放置/扩边）。

## 推荐参数（可选）

- action_id: `place_lobbyists_road`
- actor: `0`
- params:
	- `piece_id`: `lobbyists_road_straight`
	- `anchor_pos`: `[10, 1]`
	- `rotation`: `0`

## 关联单元测试

- `core/tests/lobbyists_v2_test.gd`
- `ui/scenes/tests/map_blocked_overlay_skips_void_cells_test.gd`
