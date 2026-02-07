# 模块：core/engine/PhaseManager（阶段/子阶段推进 + 结算触发 + Hooks）

`PhaseManager` 负责“主流程时间轴”的编排（阶段与子阶段推进），并在阶段边界触发结算与 hooks。

代码入口：`core/engine/phase_manager.gd`

相关实现文件：

- 定义与时间戳：`core/engine/phase_manager/definitions.gd`
- 推进实现：`core/engine/phase_manager/advancement.gd`、`advance_phase.gd`、`advance_sub_phase.gd`、`working_flow.gd`
- hooks：`core/engine/phase_manager/hooks.gd`
- 顺序覆盖：`core/engine/phase_manager/order_config.gd`
- 结算触发点：`core/engine/phase_manager/settlement_triggers.gd`

## 与模块系统 V2 的耦合方式（当前已落地）

PhaseManager 本身不 preload 具体结算脚本；它通过“可注入 registry”工作：

- `set_settlement_registry(registry)`：由 `RulesetV2` 提供（见 `core/rules/settlement_registry.gd`）
- `set_effect_registry(registry)`：由 `RulesetV2` 提供（见 `core/rules/effect_registry.gd`）
- `set_*_order(...)` / `set_*_triggers(...)`：模块可覆盖阶段/子阶段顺序与结算触发点

装配发生在：`core/engine/game_engine/modules_v2.gd`

## 阶段与子阶段

阶段与 Working 子阶段常量见：`core/engine/phase_manager/definitions.gd`

- 阶段：`Setup`、`Restructuring`、`OrderOfBusiness`、`Working`、`Dinnertime`、`Payday`、`Marketing`、`Cleanup`、`GameOver`
- Setup 子阶段：`ReserveCards`
- Working 子阶段：`Recruit/Train/Marketing/GetFood/GetDrinks/PlaceHouses/PlaceRestaurants`

> 模块也可以插入自定义子阶段（按名称），并通过 `register_sub_phase_hook_by_name(...)` 注入 hooks。

## 结算触发（Settlement Triggers）

PhaseManager 在阶段 enter/exit 的固定点位调用 settlement registry：

- 默认触发点由 `core/engine/phase_manager/settlement_triggers.gd` 给出
- 模块可通过 RulesetV2 注册 override（见 `RulesetV2.register_settlement_triggers_override`）
- strict：缺失必需的 primary settlements 会在初始化阶段 fail-fast（`validate_required_primary_settlements`）

## Hooks

支持：

- phase hooks：`register_phase_hook(phase_enum, hook_type, callback, ...)`
- subphase hooks：`register_sub_phase_hook(subphase_enum, ...)`
- named subphase hooks：`register_sub_phase_hook_by_name(sub_phase_name, ...)`

hook_type：`BEFORE_ENTER/AFTER_ENTER/BEFORE_EXIT/AFTER_EXIT`

模块注入 hooks 的入口：`RulesetV2.register_phase_hook(...)` / `register_sub_phase_hook(...)`（最终由 `ruleset.apply_hooks_to_phase_manager` 应用）。
