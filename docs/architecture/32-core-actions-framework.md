# 模块：core/actions（动作框架：ActionRegistry / ActionExecutor / 可用性门禁）

动作框架提供“命令执行的统一接口”与“动作可用性/校验的统一入口”。

核心类型：

- `core/actions/action_executor.gd`：`ActionExecutor`
- `core/actions/action_registry.gd`：`ActionRegistry`
- `core/actions/action_availability_registry.gd`：`ActionAvailabilityRegistry`（phase/sub_phase 门禁）
- `core/actions/action_ids.gd`：内建 action_id 常量

## ActionExecutor：动作接口

`ActionExecutor`（RefCounted）提供三段式接口：

- `validate(state, command) -> Result`：纯校验（禁止写 state）
- `compute_new_state(state, command) -> Result`：默认 copy-on-write（`duplicate_state` + `_apply_changes`）
- `generate_events(old_state, new_state, command) -> Array[Dictionary]`

补充能力（当前代码已用到）：

- `apply_changes_in_place(state, command)`：用于 AutoAdvance/in-place 语义（谨慎使用）
- `is_internal`：内部动作（不应出现在“可用动作列表”，但可直接执行）

## ActionRegistry：分发与校验链

`ActionRegistry` 负责：

- 按 `action_id` 查找执行器
- 运行校验链：`run_validators(state, command)`
  - 0) 可用性门禁（若设置了 availability registry）
  - 1) 全局 validators
  - 2) 动作级 validators

并提供查询：

- `get_available_actions(state)`
- `get_player_available_actions(state, player_id)`
- `get_player_initiatable_actions(state, player_id)`：允许“只缺参数”的动作先进入 UI 流程
- `get_mandatory_actions(state)`

## 动作注册（provider 机制）

GameEngine 不直接硬编码 gameplay/actions 列表，而是通过 provider 装配：

- `core/engine/game_engine/action_setup.gd` 读取 `ProjectSettings["fcm/action_setup_provider_path"]`
- 默认 provider：`res://gameplay/action_setup.gd`

这允许在测试/工具场景替换整套动作集合。

## 模块系统 V2 的扩展点

RulesetV2 支持模块注册：

- 额外 `ActionExecutor`
- action/global validators
- action 可用性覆盖（phase/sub_phase points）

参见：`core/modules/v2/ruleset/action_registration.gd`

