# core/ 目录结构

本目录放**纯逻辑/可复用**的引擎核心代码（尽量不依赖 UI 节点与场景），按职责分层：

- `core/types/`：基础类型（`Result`、`Command` 等）
- `core/state/`：状态结构与更新工具（`GameState`、`StateUpdater`）
- `core/engine/`：引擎与流程编排（`GameEngine`、`PhaseManager`）
- `core/actions/`：动作执行框架（`ActionExecutor`、`ActionRegistry`）
- `core/events/`：事件总线（`EventBus`）
- `core/random/`：受控随机（`RandomManager`）
- `core/data/`：数据加载与解析（`GameData`）
- `core/rules/`：跨动作共享的规则/计算（例如 `EmployeeRules`）
- `core/tests/`：纯逻辑 headless 测试入口（`*_test.gd`）
- `core/map/`：地图系统（烘焙、道路图、放置校验等）
