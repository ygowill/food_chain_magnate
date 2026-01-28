# Game 场景：controller 拆分与职责边界（ui/scenes/game/*）

`ui/scenes/game/game.gd` 是“协调器”：负责节点绑定、引擎初始化/复用、以及把 UI 逻辑拆分到多个 controller。

本文件描述当前 `ui/scenes/game/*` 的主要脚本分工，便于定位“某类 UI 问题应该改哪一层”。

## 顶层协调器：game.gd

代码：`ui/scenes/game/game.gd`

职责（节选）：

- 创建/复用 `GameEngine`（新局/读档/回放入口）
- 提供统一命令入口 `_execute_command(command: Command) -> Result`
  - 回放模式禁止执行
  - 处于历史指针位置时默认禁止执行（防止未显式进入时间线编辑就分叉）
- 统一 `_update_ui()`：从 `game_engine.get_state()` 拉取并刷新 UI
- 初始化并编排各 controller（map/panels/overlays/menu/debug）
- 处理加载遮罩（`SceneManager.show_loading/hide_loading`）与首帧性能打点（`PerfTrace`）

## 面板：GamePanelController + 子面板

代码：

- `ui/scenes/game/game_panel_controller.gd`：面板编排与信号连接
- `ui/scenes/game/game_panel_working_panels.gd`：Working 子阶段相关面板
- `ui/scenes/game/game_panel_marketing_panels.gd`：营销相关面板
- `ui/scenes/game/game_panel_end_panels.gd`：回合/结算/游戏结束相关面板
- `ui/scenes/game/game_panel_placement_overlays.gd`：放置/移动时的 UI 叠层（与 map 交互协作）

交互边界：

- panels 负责“把 UI 选择转成 Command/参数”
- 真正执行通过 `game.gd` 注入的 `Callable(_execute_command)` 完成

## 地图与交互：MapView/Canvas + InteractionController

代码：

- `ui/scenes/game/map_view.gd`：地图视图容器/滚动缩放层
- `ui/scenes/game/map_canvas.gd`：地图绘制主节点
- `ui/scenes/game/map_canvas_drawer.gd`：绘制实现（ground/roads/structures/标记等）
- `ui/scenes/game/map_canvas_indexer.gd`：坐标/命中检测与索引（world/grid/tile 映射）
- `ui/scenes/game/game_map_interaction_controller.gd`：鼠标/手势交互（点击/拖拽/选择/模式切换）
- `ui/scenes/game/map_canvas_tooltip.gd`：悬浮提示

交互边界：

- InteractionController 负责把输入转换成“选点/预览/确认”流程
- 确认后仍通过面板/`_execute_command` 提交命令，避免 UI 直接写状态

## Overlays：统一管理与具体叠层

代码：

- `ui/scenes/game/game_overlay_controller.gd`：统一开关/刷新/协作入口
- 具体 overlays：
  - `ui/scenes/game/game_overlay_distance.gd`
  - `ui/scenes/game/game_overlay_marketing_range.gd`
  - `ui/scenes/game/game_overlay_procurement_route.gd`
  - `ui/scenes/game/game_overlay_demand_indicator.gd`
  - `ui/scenes/game/game_overlay_dinnertime.gd`
  - `ui/scenes/game/game_overlay_zoom.gd`
  - `ui/scenes/game/game_overlay_utils.gd`

Overlay 的约束：

- 尽量只读 `GameState`（渲染/提示）
- 需要规则计算时调用 core/rules/core/map 提供的公共函数（避免复制规则）

## 日志：EventBus 订阅日志 vs StepTimeline

目前主流程使用 **StepTimeline**（从引擎状态/命令历史重建），而不是“订阅 EventBus 实时追加日志”：

- StepTimeline 构建：`gameplay/replay/step_timeline_build.gd`
- 派生时间线总览（含 EventTimeline）：`docs/architecture/42-gameplay-replay-timelines.md`

仓库中仍保留了基于 EventBus 的日志控制器（可用于调试或旧路径兼容）：

- `ui/scenes/game/game_event_log_controller.gd`
- `ui/scenes/game/game_event_log_formatter.gd`

## 调试菜单与调试面板

代码：

- `ui/scenes/game/game_menu_debug_controller.gd`：游戏内菜单/调试入口编排
- Debug commands registry：`ui/debug/debug_command_registry.gd`（详见 `docs/architecture/25-debug-and-profiling.md`）
