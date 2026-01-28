# 模块：autoload（全局单例）

autoload 目录提供跨场景可用的单例节点（见 `project.godot` 的 `[autoload]`）。它们是“粘合层”：UI 方便，但也会提高耦合度，因此 core 侧尽量只通过可注入接口使用（例如 `GameEngine.event_sink`）。

本项目实际包含：

- `autoload/globals.gd`：`Globals`（配置、玩家资料、运行时引擎引用）
- `autoload/scene_manager.gd`：`SceneManager`（场景切换 + loading overlay）
- `autoload/event_bus.gd`：`EventBus`（事件发布/订阅 + 历史）
- `autoload/debug_flags.gd`：`DebugFlags`（调试开关）

## Globals：跨场景配置与“当前对局上下文”

代码：`autoload/globals.gd`

关键字段（以当前代码为准）：

- 新局配置：`player_count`、`random_seed`
- 模块系统 V2：`enabled_modules_v2`、`modules_v2_base_dir`
- UI/玩家资料：`player_names`、`player_color_indices`、`player_restaurant_logo_choices`、`ui_scale`、`font_scale` 等
- 运行时：`current_game_engine`、`is_game_active`
- 回放入口：`pending_replay_file_path`（主菜单选择回放文件后，进入 Game 场景自动打开回放播放器）

## SceneManager：场景切换与加载遮罩

代码：`autoload/scene_manager.gd`

职责：

- 统一场景跳转：`goto_scene(...)`/`goto_main_menu()`/`goto_game_setup()`/`goto_game()`
- 维护 scene 栈：`go_back()`（用于“返回上一页”）
- 加载遮罩：`show_loading(...)`/`hide_loading()`（避免初始化/读档卡顿的观感）

## EventBus：事件总线与“事件历史”

代码：`autoload/event_bus.gd`

特性：

- 订阅：`subscribe(event_type, callback, priority=100, source="")`
- 发射：`emit_event(event_type, data={})`
- **确定性序号**：事件自带 `sequence/timestamp`，用于回放/日志对齐（timestamp=sequence）
- 历史：`get_history(...)`/`clear_history()`/`clear_history_and_reset_sequence()`
- 回退/重放支持：`record_event(...)`（只写历史，不触发订阅者副作用）
- 事件类型常量：`EventBus.EventType.*`（字符串）

> 约定：core 侧不直接依赖 `EventBus`，而是调用 `GameEngine.emit_event(...)`；引擎默认会把事件转发到 autoload 的 `EventBus`，但也允许通过 `GameEngine.set_event_sink(...)` 注入替代实现（用于 headless/测试/日志重建）。

## DebugFlags：调试与校验开关

代码：`autoload/debug_flags.gd`

常用字段：

- `verbose_logging`：更详细的日志
- `validate_invariants`：每条命令后校验不变量（现金/员工守恒等）
- `force_execute_commands`：跳过大部分校验（仅 DebugPanel 用，风险很高）
- `show_console`：UI 控制台/调试面板显隐

