# milestone/first_lobbyist_used_multi_player_same_round - 同回合多玩家扩边（first_lobbyist_used）

## 存档

- JSON: `res://.savings/manual_cases/milestones/first_lobbyist_used_multi_player_same_round.json`
- 玩家数: 2
- Seed: 12345
- 当前位置: Working/Lobbyists (round=1 current_player=0)

## 目的

- 验证同一回合内多名玩家都拥有「额外地图板块」放置机会时，UI 会在各自回合弹出二选一并允许依次扩边；同时扩边产生的 void 区域不应显示红叉 blocked 覆盖。

## 复核步骤

1. 载入后应处于 Working/Lobbyists，且玩家 0/1 都已获得 first_lobbyist_used（或等价的 extra tile pending）。
2. 玩家 0：应立刻看到「使用/放弃」二选一；选择“使用”，并在地图上放置 1 个额外 tile（注意扩边后空余区域不应显示红色叉）。
3. 玩家 0：点击 Pass 结束本子阶段行动，轮到玩家 1。
4. 玩家 1：同样应看到二选一；选择“使用”，并放置 1 个额外 tile（可复核多名玩家同回合均可扩边）。

## 预期结果

- 玩家 0/1 均能在 Lobbyists 子阶段弹出二选一并成功执行扩边放置。
- 扩边造成的空余（void）区域不应显示红叉 blocked 覆盖（仍可能用于后续放置/扩边）。

## 关联单元测试

- `core/tests/lobbyists_v2_test.gd`
- `ui/scenes/tests/map_blocked_overlay_skips_void_cells_test.gd`
