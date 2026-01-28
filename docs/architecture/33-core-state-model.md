# 模块：core/state（GameState：状态模型、序列化与哈希）

`GameState` 是对局的唯一事实来源。它承载：

- 回合/阶段/子阶段
- 玩家/银行/供应池/营销实例
- 地图运行时结构（烘焙结果 + 放置结果 + 缓存）
- 模块计划与规则常量（用于存档/回放一致性）

代码入口：`core/state/game_state.gd`

## 关键字段（以当前 schema 为准）

- 流程：`round_number`、`phase`、`sub_phase`
- 顺序：`turn_order`、`current_player_index`、`selection_order`
- 银行：`bank`（含 broke_count、reserve_added_total 等用于不变量）
- 规则常量：`rules`（来自 `GameConfig`，写入存档）
- 模块计划：`modules`（本局启用模块 plan，写入存档）
- 玩家：`players: Array[Dictionary]`
- 地图：`map: Dictionary`（结构由 `core/map/map_runtime/*` 维护）
- 供应池：`employee_pool`、`milestone_pool`
- 营销实例：`marketing_instances`
- 回合态：`round_state`（强制动作、计数、顺序覆盖、pending_phase_actions 等）
- 随机：`seed`（与 `RandomManager` 配合）

schema 版本：`GameState.SCHEMA_VERSION`（不兼容直接拒绝加载）

## 序列化/哈希

- `to_dict()` / `from_dict(...)`：实现见 `core/state/game_state_serialization.gd`
- `compute_hash()`：
  - `JSON.stringify(..., sort_keys=true)` 保证 Dictionary 顺序不影响结果
  - 将“整值 float”归一化为 int，避免 JSON parse 导致的浮点漂移

## 运行时缓存（RoadGraph）

`GameState` 内含 RoadGraph 缓存（不序列化）。地图结构变化时必须 invalidate，否则距离/路径计算可能读取过期缓存。

地图 apply/失效逻辑见：

- `core/map/map_runtime/baked_map.gd`（写入 baked map 结构并 invalidate）
- `core/map/map_runtime/road_graph_cache.gd`

## 模块扩展与 schema 契约

模块可以扩展 `state.map` 与 `state.round_state` 的结构，但必须遵守：

- core-owned key 不得覆盖
- module-owned key 必须 namespaced（建议用 module_id 前缀）
- JSON 存档会把 int-key Dictionary 的 key 变为字符串，需要统一归一化

详见：`docs/architecture/33a-core-state-schema-contract.md`

序列化/反序列化与 StateSchemaRegistry 的细节见：`docs/architecture/33b-core-state-serialization.md`

