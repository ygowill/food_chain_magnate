# ADR 0003：core 边界冻结与守卫测试

- 状态：已采纳
- 日期：2026-03-06

## 背景

`docs/core_architecture_audit_and_refactor_roadmap_2026-03-06.md` 明确指出，当前 `core/` 已经具备较好的确定性、回放和模块化主干，但仍存在三类需要尽快收口的边界泄漏：

- UI 元数据仍通过 `RulesetV2`、`ActionExecutor` 等 core 协议承载。
- 运行时环境读取仍通过 `AutoloadAccess`、`ProjectSettings` provider path 等方式进入 core。
- 架构约束目前主要依赖人工 code review，缺少可回归的自动守卫。

阶段 0 的目标不是立刻完成大迁移，而是先冻结边界，避免债务继续扩散。

## 决策

### D3.1 `core/` 不新增 `res://ui/` 依赖

- `core/` 非测试脚本不得新增对 `res://ui/` 的直接引用。
- 如确需新增展示层资源接入，必须先在 `gameplay/` 或 `ui/` 层落地，再评估是否需要新的适配接口。

### D3.2 UI 元数据职责只允许停留在当前桥接点

在阶段 1 完成前，以下 UI 元数据仍允许存在，但仅限当前桥接文件中维护，不得继续向其他 `core/` 文件扩散：

- `phase_action_ui_modals`
- `piece_ui_hints`
- `effect_ui_texts`
- `milestone_effect_ui_texts`
- `map_overlay_providers`
- `ui_hide_if_not_initiatable`
- `ui_piece_ids`

这是一条“冻结现状、禁止继续蔓延”的规则，而不是长期目标。

### D3.3 core 不新增新的平台环境读取入口

- `core/` 非测试脚本不得直接访问 `EventBus`、`Globals`、`GameLog`、`DebugFlags` 等 autoload 全局对象。
- 现阶段允许继续通过 `core/utils/autoload_access.gd` 这一过渡封装访问 autoload。
- `ProjectSettings` 读取只允许保留在现有 provider/version 桥接点中；新增读取前必须先有新的 ADR 或完成显式依赖注入改造。

当前允许保留的 `ProjectSettings` 读取点：

- `core/engine/game_engine/action_setup.gd`
- `core/engine/game_engine/command_runner.gd`
- `core/engine/game_engine/archive.gd`
- `core/state/game_state_factory.gd`

## 实施

- 新增 `core/tests/core_architecture_boundary_contract_test.gd`，将以上边界规则转成自动化守卫。
- 将该守卫接入 `ui/scenes/tests/all_tests.tscn` 聚合测试。
- 后续每次推进阶段 1/2 重构时，同步收缩守卫测试中的允许列表，而不是删除守卫。

## 影响

- 优点：把“不要继续恶化”的架构约束变成可回归、可审查的测试信号。
- 代价：在完成后续重构前，需要维护一份显式允许列表。

## 参考

- `docs/core_architecture_audit_and_refactor_roadmap_2026-03-06.md`
- `core/tests/module_boundary_contract_test.gd`
