# Game 场景：controller 拆分与职责边界（ui/scenes/game/*）

`ui/scenes/game/game.gd` 是“编排器”：负责节点绑定、引擎生命周期管理，以及初始化/连接各个 controller。

本文件按“改 UI/交互/联机/回放时应该找哪层”来索引当前实现。

## 顶层编排：game.gd

代码：`ui/scenes/game/game.gd`

职责（以当前实现为准）：

- 入口分流：新局 / 读档复用 `Globals.current_game_engine` / 主菜单回放（`Globals.pending_replay_file_path`）/ 联机 InGame
- 创建/切换 `GameEngine`，并把引擎提供给各 controller
- 统一 UI 刷新：从 `game_engine.get_state()` 拉取并触发同步
- 初始化并编排 controller（layout/command/timeline/panels/map/overlays/menu/online/debug）
- 处理加载遮罩（`SceneManager.show_loading/hide_loading`）与首帧性能打点（`PerfTrace`）

## Controllers 一览（按职责）

> 这些 controller 都由 `game.gd` 创建并注入回调；大部分 UI 行为应优先落在对应 controller，而不是继续膨胀 `game.gd`。

- 命令执行：`ui/scenes/game/game_command_controller.gd`（本地/联机命令、回退到回合开始、SKIP 前强制动作自动补完、发薪日提示拦截）
- 时间线/回放：`ui/scenes/game/game_timeline_controller.gd`（StepTimeline 构建、ReplayBar、回放引擎切换）
- 联机 Resync/Rewind：`ui/scenes/game/game_online_resync_controller.gd`（CommandApplied 回放、ResyncArchive 应用、回退回合开始的回灌与超时兜底）
- UI 同步：`ui/scenes/game/game_ui_sync_controller.gd`（顶栏信息、地图/面板/覆盖层同步、联机轮到你/阶段切换 toast、调试命令后的 UI 重建触发）
- 输入/快捷键：`ui/scenes/game/game_input_controller.gd`（ESC/Enter/R/D 等快捷键分发，优先关闭顶层 UI）
- 布局/响应式：`ui/scenes/game/game_layout_controller.gd`（左/右/底部面板显隐与响应式参数）
- 右侧 Dock/抽屉：`ui/scenes/game/game_right_panel_dock_controller.gd`（DockHost 的标题/按钮/抽屉内容切换）
- 日志 Dock：`ui/scenes/game/game_log_dock_controller.gd`（打开/关闭日志，并嵌入右侧 DockHost）
- 菜单/确认弹窗：`ui/scenes/game/game_menu_controller.gd`（菜单按钮、保存/回放入口、返回主菜单确认）
- 存档/回放选择：`ui/scenes/game/game_save_load_controller.gd`（SaveLoadDialog 生命周期与回调分发）
- DebugPanel：`ui/scenes/game/game_debug_panel_controller.gd`（调试面板创建/显示/命令执行信号绑定）
- 后台预热：`ui/scenes/game/game_background_warmup_controller.gd`（后台构建重面板，减少首帧卡顿）

## 面板：GamePanelController（以及 views/modals 子控制器）

面板编排入口：`ui/scenes/game/game_panel_controller.gd`

常见子文件（节选）：

- Working 子阶段：`ui/scenes/game/game_panel_working_panels.gd` + `ui/scenes/game/game_panel_working_*_controller.gd`
- 营销/结算：`ui/scenes/game/game_panel_marketing_panels.gd`、`ui/scenes/game/game_panel_end_panels.gd`
- 放置叠层与地图协作：`ui/scenes/game/game_panel_placement_overlays.gd`
- 顶层浏览视图：`ui/scenes/game/game_panel_views_controller.gd`（EmployeeTree/Milestone/ReserveArea 全屏）
- 顶层模态：`ui/scenes/game/game_panel_modals_controller.gd`（ReserveCards/TurnOrder/FridgeKeep 等）

交互边界：

- panels 负责“把 UI 选择转成 Command/参数”
- 真正执行应通过注入的 `Callable(_execute_command)`（或 `GameCommandController`）完成，避免 UI 直接写 state

## 地图与交互：MapView/Canvas + InteractionController

地图绘制与索引：

- `ui/scenes/game/map_view.gd`：地图视图容器/滚动缩放层
- `ui/scenes/game/map_canvas.gd`：地图绘制主节点
- `ui/scenes/game/map_canvas_indexer.gd`：坐标/命中检测与索引（world/grid/tile 映射）
- `ui/scenes/game/map_canvas_tooltip.gd`：悬浮提示

绘制实现：

- `ui/scenes/game/map_canvas_drawer.gd`：绘制编排（将绘制拆成多个 pass）
- 主要 pass（节选）：`map_canvas_drawer_ground_pass.gd`、`map_canvas_drawer_tiles_pass.gd`、`map_canvas_drawer_roads_pass.gd`、`map_canvas_drawer_structures_pass.gd`、`map_canvas_drawer_marketing_pass.gd`

交互控制：

- `ui/scenes/game/game_map_interaction_controller.gd`：鼠标/手势交互（点击/拖拽/模式切换/预览与确认流程）
- 模式实现（节选）：`game_map_interaction_placement_mode.gd`、`game_map_interaction_marketing_mode.gd`
- 顶部模式条：`ui/scenes/game/game_map_mode_bar_controller.gd`

交互边界：

- InteractionController 管理“选点/预览/确认”的 UI 流程与 overlay
- 确认后仍通过面板/命令控制器提交命令，保持“唯一写入口”的约束

## Overlays：统一管理与具体叠层

入口：`ui/scenes/game/game_overlay_controller.gd`

常见 overlays（节选）：

- `ui/scenes/game/game_overlay_distance.gd`
- `ui/scenes/game/game_overlay_marketing_range.gd`
- `ui/scenes/game/game_overlay_procurement_route.gd`
- `ui/scenes/game/game_overlay_demand_indicator.gd`
- `ui/scenes/game/game_overlay_dinnertime.gd`

Overlay 的约束：

- 尽量只读 `GameState`（渲染/提示）
- 需要规则计算时调用 core/rules/core/map 提供的公共函数（避免复制规则）

## 日志：StepTimeline（派生时间线）为主

当前主流程使用 **StepTimeline**（从引擎状态/命令历史重建），而不是“订阅 EventBus 实时追加日志”：

- 构建：`gameplay/replay/step_timeline_build.gd`
- 总览：`docs/architecture/42-gameplay-replay-timelines.md`

仓库中仍保留基于 EventBus 的日志控制器（用于调试或旧路径兼容）：

- `ui/scenes/game/game_event_log_controller.gd`
- `ui/scenes/game/game_event_log_formatter.gd`

