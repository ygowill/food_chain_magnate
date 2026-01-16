# GameState 扩展字段契约（state.map / state.round_state）

目的：把“模块如何扩展状态结构”的隐式约定显式化，降低跨模块耦合与存档/读档后的类型漂移风险。

## 设计原则

- **core-owned vs module-owned**：core 定义的 key 属于稳定 ABI；模块不应覆盖/重解释。
- **模块不得窥探其他模块私有结构**：模块 A 不能通过 `state.map[...] / state.round_state[...]` 直接读取模块 B 的字段来做规则推断；应改为 core-owned 的 registry/helper 查询（见下方）。
- **命名规则**：
	- module-owned：必须以 `module_id` 为前缀（例如 `rural_marketeers_offramps`、`lobbyists_extra_tile_pending`）
	- core-owned/shared：使用无前缀的稳定 key（例如 `cells`、`pending_phase_actions`）
- **存档一致性**：运行时如果使用 “int key Dictionary”（如 `{player_id(int) -> ...}`），则 JSON 存档会变成数字字符串 key（`"0"`），读档阶段必须做归一化。

## key 分类与约束

### core-owned（禁止模块覆盖）

`state.map`（基础地图结构，示例）：
- `cells`、`grid_size`、`tile_grid_size`
- `houses`、`restaurants`
- `marketing_placements`、`tile_placements`
- `external_cells`、`external_tile_placements`（模块扩展点：棋盘外结构/板块）
- `tile_supply_remaining`

`state.round_state`（基础回合结构，示例）：
- `mandatory_actions_completed`、`actions_this_round`、`action_counts`、`sub_phase_passed`
- `pending_phase_actions`（shared，总线：需明确写入/清理职责）

### shared（允许多模块读写，但必须遵守写入规则）

#### `global_effect_ids`

用途：在晚餐等阶段作为“全局 effect 总线”供 EffectRegistry 调用。

存储分层（推荐约定）：
- `state.map.global_effect_ids`：**永久性/全局**效果（跨回合持续）
- `state.round_state.global_effect_ids`：**回合性**效果（仅本回合有效；由写入方负责清理/重置）

读写规范：
- 禁止模块直接写裸数组；统一使用 `core/rules/global_effect_list.gd`（`GlobalEffectList.add_to_map/add_to_round_state/get_all_effect_ids`）。
- `effect_id` 必须为非空字符串；默认不允许重复（helper 会去重添加；读取阶段若发现重复会 warning）。

### module-owned（仅模块自己负责结构与版本）

模块自有 key 由模块维护 schema/version；其他模块禁止直接读取其内部结构。

跨模块需要“查询/互斥/占用”时：
- 模块注册 provider 到 core-owned registry
- 其他模块只调用 core API 查询，不依赖字段结构

目前已落地的例子：
- `PlacementConflictRegistry`（`core/rules/placement_conflict_registry.gd`）：提供“某 world_pos 是否存在外部冲突”的查询面；例如 rural_marketeers 提供 offramp connection cell 冲突。

