# 模块：core/engine（GameEngine：命令执行与可回放引擎）

`GameEngine` 是系统的“唯一写入口”。它保证：

- 所有状态变化都来自 `Command`（`execute_command`）
- 命令历史可重放（`full_replay`）与可回退（`rewind_to_command`）
- 存档可恢复（`create_archive`/`load_from_archive`）
- 可通过 `GameState.compute_hash()` 验证确定性

代码入口：`core/engine/game_engine.gd`

## 代码拆分（按文件职责）

引擎实现被拆分到 `core/engine/game_engine/*`：

- 初始化：`core/engine/game_engine/initializer.gd`
- 执行：`core/engine/game_engine/command_runner.gd`
- 回退/重放：`core/engine/game_engine/rewind_ops.gd`
- 校验点：`core/engine/game_engine/checkpoints.gd`
- 存档：`core/engine/game_engine/archive.gd` + `core/engine/game_engine/loader.gd`
- 不变量：`core/engine/game_engine/invariants.gd`
- 动作装配：`core/engine/game_engine/action_setup.gd` + `core/engine/game_engine/action_wiring.gd`
- 模块系统 V2：`core/engine/game_engine/modules_v2.gd`

相关补充文档：

- 自动推进（AutoAdvance）：`docs/architecture/30a-core-engine-auto-advance.md`
- 存档格式（archive）：`docs/architecture/30b-core-engine-archive.md`

## 时间线语义（线性历史）

引擎维护：

- `command_history`：事实来源（顺序命令列表）
- `current_command_index`：当前“时间线指针”
- `checkpoints`：加速回放/回退的快照点

当你曾 `rewind_to_command(i)` 回到历史位置，再执行新命令时，引擎会：

- 截断 `i` 之后的未来命令与未来 checkpoint（`truncate_future_history`）
- 从而保持“单分支线性时间线”

## 事件输出（可注入 sink）

`GameEngine` 提供：

- `set_event_sink(sink)`
- `emit_event(type, data)`

默认情况下会转发到 autoload 的 `EventBus`（`autoload/event_bus.gd`）。测试/工具场景可注入替代 sink，以避免 Node 依赖或实现“只记录历史不触发订阅者”的行为。

## 与模块系统 V2 的关系

初始化新局时（`initializer.gd`）会：

1. `apply_modules_v2(enabled_modules_v2, modules_v2_base_dir)`
2. 使用装配出的 `ContentCatalog` 构建 `GameData.from_catalog(...)`
3. 配置各类 registry（员工/里程碑/产品/营销、地图 tiles/pieces、结算/效果等）
4. 把 `RulesetV2` 的 settlement/effect registry 注入到 `PhaseManager`

详见：`docs/architecture/60-modules-v2.md`

