# core/ 目录结构

本目录放**纯逻辑/可复用**的引擎核心代码（尽量不依赖 UI 节点与场景），按职责分层：

- `core/types/`：基础类型（`Result`、`Command` 等）
- `core/state/`：状态结构与更新工具（`GameState`、`StateUpdater`）
- `core/engine/`：引擎与流程编排（`GameEngine`、`PhaseManager`）
- `core/actions/`：动作执行框架（`ActionExecutor`、`ActionRegistry`）
- `core/random/`：受控随机（`RandomManager`）
- `core/data/`：数据加载与解析（`GameData`）
- `core/rules/`：跨动作共享的规则/计算（例如 `EmployeeRules`）
- `core/modules/`：模块系统（v2 content/ruleset/加载与校验）
- `core/tests/`：纯逻辑 headless 测试入口（`*_test.gd`）
- `core/map/`：地图系统（烘焙、道路图、放置校验等）
- `core/utils/`：通用工具（解析 helper、范围/距离、类型 helper 等）
- `core/debug/`：调试相关（少量 shim/工具封装；避免引入 core→ui 依赖）

> 说明：`EventBus` 是 autoload（见 `res://autoload/event_bus.gd`）。core 侧默认通过 `GameEngine.emit_event(...)` 输出事件（可注入 sink），必要时再通过 `core/utils/autoload_access.gd` 访问 autoload 单例以降低硬依赖。
