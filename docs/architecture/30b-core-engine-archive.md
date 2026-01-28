# GameEngine：存档格式（archive）与加载语义

本项目的“存档”本质是一份可重放的归档（archive）：

- `initial_state` + `rng` + `commands` 是事实来源；
- `current_index` 表示当前时间线指针（支持“回退到历史位置”后保存）；
- `final_hash` 可用于快速验证存档一致性。

实现入口：

- 生成/读写：`core/engine/game_engine/archive.gd`
- 加载：`core/engine/game_engine/loader.gd`

## archive 顶层字段（以当前实现为准）

`Archive.create_archive(...)`（实现位于 `core/engine/game_engine/archive.gd`）生成的字典包含：

- `schema_version`：等于 `GameState.SCHEMA_VERSION`
- `game_version`：`ProjectSettings["application/config/version"]`（展示用途）
- `created_at`：`Time.get_datetime_string_from_system()`（展示用途，非确定性）
- `modules_v2_base_dir`：模块目录 spec（可用 `;` 分隔多个目录）
- `rng`：`RandomManager.to_dict()`（当前为 `{initial_seed, call_count}`）
- `initial_state`：来自 `checkpoints[0].state_dict`（初始状态快照）
- `commands`：`Command.to_dict()` 序列（每条命令必须带 `timestamp`）
- `checkpoints`：checkpoint 元数据（不含 state_dict；见下文）
- `current_index`：当前命令指针（-1 表示尚未执行任何命令）
- `final_hash`：`state.compute_hash()`（存档写入时的最终 hash）

## checkpoints：为什么只存元数据

archive 中的 `checkpoints` 只保存：

- `index`：checkpoint 对应的“已执行命令数”
- `hash`：checkpoint 状态 hash
- `rng_calls`：RNG call_count

原因：存档恢复依赖 `initial_state + commands`，而 checkpoint 主要用于运行期的回退加速与调试；在当前实现里，存档并不携带每个 checkpoint 的完整 state_dict。

## 数字归一化（Godot JSON 的 float 问题）

`JSON.parse_string` 会把数字解析为 float。为了避免加载后出现 `int/float` 类型不匹配（现金/计数等语义应为 int），`Archive.load_archive_from_file` 会将“整值 float”归一化为 int（递归处理 Dictionary/Array）。

相关实现：`Archive._normalize_json_numbers`（`core/engine/game_engine/archive.gd`）

## 加载顺序：必须先装配模块再解析 GameState

`Loader.load_from_archive(...)`（实现位于 `core/engine/game_engine/loader.gd`）的关键约束：

1. 先从 `initial_state.modules` 取出本局的完整模块计划；
2. 先调用 `engine.apply_modules_v2(...)` 装配 ruleset 与 state schema（尤其是 int-key dict 的归一化路径）；
3. 再执行 `GameState.from_dict(initial_state)`；
4. 之后按 `commands` 逐条 `execute_command(cmd, is_replay=true)`；
5. 最后若 `current_index` 不是 head，则 `rewind_to_command(current_index)`。

这保证了：读档后的状态结构、模块扩展字段归一化、以及回放 determinism 都遵循 Strict Mode 的 fail-fast 语义。
