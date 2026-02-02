# 超长 GDScript（>800 行）可维护性审计报告（2026-02-02）

## 背景与目标

项目中存在多份超过 800 行的 `.gd` 脚本。超长脚本通常会带来：

- 阅读成本高：定位功能/状态变更路径困难，容易引入回归。
- 合并冲突多：多人协作时频繁触发同文件冲突。
- 责任边界模糊：UI、流程编排、业务规则、模块扩展点混在一起，导致“改 A 影响 B”。
- 测试与复用困难：难以抽出纯逻辑做 `core/tests/` 级别单元测试。

本报告最初用于“发现与改进建议”的记录；在你确认后，已开始按本文档逐步实施拆分，实施记录见下方。

## 扫描方法

- 统计范围：仓库内所有 `.gd` 文件，**排除** `./.history/*`（这些通常是编辑器历史备份，不作为源代码维护对象）。
- 阈值：行数 `> 800`。
- 统计口径：`wc -l` 统计物理行数。

## 清单总览（>800 行）

> 下表的 `funcs/preloads/signals` 是粗略统计，用于判断复杂度维度（并非质量判定）。

| 行数 | funcs | preloads | signals | 文件 |
|---:|---:|---:|---:|---|
| 2457 | 129 | 21 | 0 | `ui/scenes/game/game.gd` |
| 1631 | 117 | 2 | 13 | `ui/components/game_log/game_log_panel.gd` |
| 1622 | 41 | 13 | 2 | `ui/scenes/game/game_map_interaction_controller.gd` |
| 1600 | 41 | 1 | 0 | `ui/scenes/game/map_canvas_drawer.gd` |
| 1085 | 66 | 8 | 2 | `ui/components/action_panel/action_panel.gd` |
| 1019 | 54 | 4 | 0 | `ui/scenes/online/online_lobby.gd` |
| 1006 | 50 | 5 | 8 | `autoload/net_client.gd` |
| 994 | 59 | 3 | 1 | `ui/components/left_panel/left_panel.gd` |
| 911 | 52 | 5 | 2 | `ui/components/reserve_area/reserve_area_full_screen_view.gd` |
| 864 | 48 | 7 | 2 | `ui/components/marketing_panel/marketing_panel.gd` |
| 852 | 38 | 2 | 5 | `ui/components/company_structure/company_structure.gd` |

## 跨文件共性问题（模式级发现）

### 1) “协调器脚本”过载：多条主线混在一个文件里

典型表现：一个脚本同时负责 UI 节点绑定、业务流程编排、状态机、网络/回放、弹窗生命周期、日志/时间线等。

- 代表文件：`ui/scenes/game/game.gd`、`ui/scenes/game/game_panel_controller.gd`、`autoload/net_client.gd`、`ui/scenes/online/online_lobby.gd`。
- 主要风险：
  - 修改局部功能（例如回放、联机、面板 dock）时容易破坏其他流程。
  - 流程状态散落在大量 `var _xxx` 字段里，缺乏明确的“子系统边界”。
  - 逻辑可测试性差：很难对某个子系统做 headless/纯逻辑回归测试。

建议（方向）：

- 将“协调器”拆为多个单一职责控制器/服务对象（`RefCounted` 或 `Node`，取决于是否需要树/信号/生命周期）。
- `Game` 主脚本保留：
  - 节点引用绑定（onready）
  - 控制器实例化与依赖注入
  - 顶层生命周期（ready/exit_tree）
  - 小规模 glue（避免业务规则进入 UI 主脚本）

### 2) 模组（modules）逻辑渗透到基础渲染/通用 UI

目前存在“基础组件直接感知某个模块”的情况，会让模块扩展不可控、耦合变硬：

- `ui/scenes/game/map_canvas_drawer.gd` 直接引用 lobbyists 模组，并包含 lobbyists 专属的绘制分支。

主要风险：

- 新模块要扩展绘制逻辑时只能继续往 `MapCanvasDrawer` 里塞分支，文件会持续膨胀。
- 无法做到“禁用模块即无相关代码路径/资源引用”，增加加载与维护成本。
- 基础层改动会影响模块渲染；模块升级也会反向影响基础层稳定性。

建议（方向）：

- 引入“绘制扩展点/渲染 pass 注册机制”：
  - 基础 `MapCanvasDrawer` 只提供通用 draw pipeline。
  - 模块在自己的目录中提供 `draw_pass`（例如 `modules/<mod>/ui/map_draw_pass.gd`），由 `MapSkin`/模块注册表按启用模块加载并参与绘制。
- 扩展点的数据交换尽量走 `state.map` 的规范字段或显式接口，避免硬编码 key 分散在多个 UI 文件中。

### 3) 规则/展示常量重复与双向耦合

可观察到的重复/耦合类型：

- 同一概念在多个文件中以常量存在（例如某类 action 显示名、产品名、阶段显示名、自动补完规则），后续维护容易出现“不一致”。
- UI 组件的常量被其他上层脚本当作“全局定义”引用（例如 `Game` 直接读取 `GameLogPanel` 的 `PHASE_DISPLAY_NAMES`），造成跨层依赖。

建议（方向）：

- 对“展示名/描述/图标”等：优先从 registry（产品/员工/营销类型）或统一的 UI 文案表派生，避免多个组件各自维护。
- 对“规则策略”（例如 mandatory actions 的隐藏/补完/skip 逻辑）：收敛为单一策略源（更适合放在 `gameplay/` 或 `core/rules/`），UI 只消费结果/状态，不参与规则判断。

### 4) “清单型代码（数据）写在脚本里”导致维护困难

典型文件：

- `ui/scenes/tests/all_tests.gd`：手工维护的测试列表（preload 已下沉到 `ui/scenes/tests/all_tests_refs.gd`）。
- `tools/generate_manual_test_saves_manifest.gd`（聚合） + `tools/manual_test_saves/manifest_*.gd`：大量 case 字典堆叠。

主要问题：

- 增删条目需要改动同一个大文件，冲突频繁。
- 很难按模块/领域拆分与复用（比如 lobbyists/v2 各自的用例/测试清单）。

建议（方向）：

- 将清单迁移为“manifest 数据”：
  - 轻量做法：拆成多个 `.gd`（每个领域/模块一个），再在入口处聚合。
  - 更彻底做法：JSON/CSV/自定义数据格式 + 加载器（适合 tests/tools）。
- AllTests 建议引入“自动发现/注册表”机制（按目录、命名约定、或显式注册），降低手工维护 preload 列表的成本。

### 5) 事件/时间线/回放：状态与渲染边界不清晰

观察点（以 `ui/scenes/game/game.gd`、`ui/components/game_log/game_log_panel.gd` 为代表）：

- 既有“时间线数据结构”（step timeline）又有“UI 渲染与交互”，且存在多处指针维护（head/cursor、回放/复盘/时间旅行）。

主要风险：

- 容易出现 UI 状态残留（例如回退后仍保留旧面板缓存/选点上下文）。
- 业务侧（engine/replay）与 UI 侧（log panel）彼此牵引，导致拆分更难。

建议（方向）：

- 将 timeline 的**构建、合并、裁剪、seek 规则**抽为纯数据层（建议在 `gameplay/replay/` 或 `core/` 的纯逻辑层），UI 只渲染其输出。
- `GameLogPanel` 内尽量避免“既计算又展示”，以便后续单元测试覆盖 timeline 行为而非 UI 行为。

## 文件级建议（逐个记录）

### 1) `ui/scenes/game/game.gd`

当前职责（从脚本结构与字段可见）：

- 游戏主场景顶层协调：UI 节点绑定、布局/响应式、左右面板 dock、菜单/存档、回放/复盘时间线、联机 resync、与多个 controller 的组装。

主要问题：

- 单文件承载过多子系统：UI 布局、面板 dock、回放/时间线、联机 resync、提示/音效、存档对话框等。
- 状态字段非常多（大量 `_replay_*`、`_history_*`、`_online_*`、布局/显示状态字段），可读性与回归风险高。

建议拆分方向（示例）：

- `GameLayoutController`：布局/响应式/面板可见性与动画。
- `GameDockController`：右侧 dock host + footer source 绑定与同步。
- `GameTimelineController`：history/replay 模式切换、head/cursor、seek、只读/编辑模式策略。
- `GameOnlineResyncController`：resync 票据、pending cmds、rewind 请求等。
- `GameSaveLoadController`：存档 UI + 流程（选择/确认/回调）。

优先级建议：

- 先拆“最少依赖其他系统”的：Layout/Dock/SaveLoad（更容易独立）。
- 再拆 Timeline/Online（需要更多依赖注入与验证）。

### 2) `ui/scenes/game/game_panel_controller.gd`

当前职责：

- ActionPanel 的 action 路由（决定弹什么面板、创建什么命令）。
- 管理 Working/Marketing/Placement/End 等多个面板集合对象。
- 处理重组阶段拖拽（隐私规则/提交限制/同步直属槽等）。

主要问题：

- action 分发与重组阶段的复杂规则混在同一个控制器里，增长趋势明显。
- “面板生命周期管理（创建/显示/隐藏/对齐/居中）”代码模式重复，后续继续加面板会进一步膨胀。

建议拆分方向：

- `ActionRouting`：只负责把 action_id 映射为“面板动作”或“命令动作”。
- `RestructuringController`：重组阶段拖拽、隐私约束、提交状态检查、与 CompanyStructure 交互。
- 各阶段面板控制器：Working/Marketing/Placement/End 分离后，`GamePanelController` 只做聚合与对外接口。

实施结果（阶段性）：

- 已完成：提取重组阶段控制器 `ui/scenes/game/game_panel_restructuring_controller.gd`。
- 已完成：提取通用模态弹窗控制器 `ui/scenes/game/game_panel_modals_controller.gd`（并新增 `sync_for_state()` 统一同步入口）。
- 已完成：提取全屏/覆盖视图控制器 `ui/scenes/game/game_panel_views_controller.gd`（EmployeeTree/Milestone/ReserveArea 的创建/显示/隐藏/释放）。
- 当前：`ui/scenes/game/game_panel_controller.gd` 行数已降至 790（低于 800），主要保留 action 路由 + 子控制器聚合与少量 glue。

### 3) `ui/scenes/game/game_panel_working_panels.gd`

当前职责：

- Working 阶段的多个面板：Recruit/Train/Price/Production/Milestone 的创建、显示、同步、回调处理。

主要问题：

- 多面板集合导致文件自然膨胀；且每个 panel 的 “show + sync + set_xxx + connect” 模式高度重复。
- 部分面板相关的规则/数据准备（如计数、来源列表构建）写在 controller 内，难以复用与测试。

建议拆分方向：

- 每个面板独立 controller（或把更多逻辑下沉到 panel 脚本）：
  - `working/recruit_panel_controller.gd`
  - `working/train_panel_controller.gd`
  - `working/price_panel_controller.gd`
  - `working/production_panel_controller.gd`
  - `working/milestone_panel_controller.gd`
- WorkingPanels 仅保留 `sync(state)` 与“打开某面板”的薄封装。

实施结果：

- 已完成：按面板拆 controller（Recruit/Train/Price/Milestone/Production/ProcureDrinks），`ui/scenes/game/game_panel_working_panels.gd` 行数降至 108，仅保留面板聚合与薄封装。

### 4) `ui/scenes/game/game_map_interaction_controller.gd`

当前职责：

- 管理地图交互模式（marketing/procure/placement/distance tool 等），处理 hover/点击并联动 overlay/panel。

主要问题：

- 多 mode 的 `match` 分支会持续增长；每个 mode 的状态字段散落在同一个类中。
- mode 之间的共享逻辑（例如清理高亮、恢复 outside margin、预览 overlay）容易交叉污染。

建议拆分方向：

- 使用“模式对象/策略对象”：
  - `MapModeBase`（接口：begin/clear/on_hover/on_select）
  - `ProcureDrinksMode`、`MarketingPlacementMode`、`StructurePlacementMode`、`DistanceToolMode` 等
- Controller 只维护当前 mode 实例 + 输入分发 + 与 MapCanvas 的信号连接。

### 5) `ui/scenes/game/map_canvas_drawer.gd`

当前职责：

- MapCanvas `_draw` 的分层绘制实现，包含纹理缩放、裁剪绘制、各种 piece/overlay 绘制逻辑。

主要问题：

- 绘制逻辑跨度大（地面/道路/结构/营销/高亮/预览/选择等），天然容易超长。
- 存在模块专属绘制分支（例如 lobbyists），基础 drawer 与模块耦合。

建议拆分方向：

- 按 draw pass 拆文件：`draw_ground.gd`、`draw_roads.gd`、`draw_structures.gd`、`draw_marketing.gd`、`draw_overlays.gd` 等，通过一个统一入口组装调用顺序。
- 模块绘制通过可插拔 pass 注册，避免在基础 drawer 内写模块分支。

### 6) `ui/components/game_log/game_log_panel.gd`

当前职责：

- 承载“时间线模式（step timeline）”的数据 + 条目合并/裁剪 + UI 渲染 + 交互（seek/详情/折叠）。

主要问题：

- “数据处理”和“UI 渲染”强耦合，后续时间线策略调整容易引发 UI 回归。
- 作为组件却对外暴露较多策略性常量/行为，可能被上层依赖，增加拆分难度。

建议拆分方向：

- 抽纯数据层：`LogTimelineModel`（构建 entries、分组、折叠策略、max_entries 裁剪等），可在 `core/` 或 `gameplay/` 测试。
- Panel 只做：渲染 model 输出 + 转发 UI 事件（close/seek/click）。

### 7) `ui/components/action_panel/action_panel.gd`

当前职责：

- 展示可用动作列表、处理点击、处理上下文选择（餐厅/员工/旋转/方向等）。
- 内含较多硬编码映射（动作显示名/描述/隐藏动作/特殊规则）。

主要问题：

- 动作文案与规则散落在 UI 组件中，容易与 action executor/规则侧产生不一致。
- 与 `Game` 存在策略耦合（例如 mandatory actions 的隐藏+自动补完+skip 放行逻辑需要双边维护）。

建议拆分方向：

- 文案/描述优先来源于 executor 元数据（已有趋势），UI 常量仅保底。
- 将“mandatory actions 策略”收敛为单一来源（规则层或 gameplay 层），ActionPanel 只显示“当前为何可/不可点”。
- 将 context UI（餐厅/员工/旋转等）拆成子组件，以减少主文件长度与状态字段。

### 8) `ui/scenes/online/online_lobby.gd`

当前职责：

- 页面导航（Connect/Rooms/Create/Room）。
- 网络信号绑定、配置同步状态机、列表渲染、弹窗。

主要问题：

- UI 与“同步状态机”交织：既处理页面显示，又处理 debounce、patch、syncing/error 状态。
- Room/Players/Spectators 的渲染代码容易增长（每增加字段/状态就改这里）。

建议拆分方向：

- `LobbyNavController`：页面切换与标题状态。
- `RoomListController`：列表刷新、渲染、点击行为。
- `RoomConfigSyncController`：debounce、dirty/syncing/error 状态机与补丁合并。
- `LobbyViewModel`：将 `NetContext.room_state` 映射为 UI 可消费的数据结构（减少 UI 层字典操作）。

### 9) `autoload/net_client.gd`

当前职责：

- Client/Server 共用的 RPC 节点（WebSocket peer、房间管理、请求 id、resync archive 等）。

主要问题：

- 一个文件同时承担 transport、protocol、server room manager glue、client requests 等，天然会持续膨胀。
- RPC 接口稳定性要求高（注释中也强调 checksum mismatch 风险），但实现集中在一个脚本里，改动风险高。

建议拆分方向：

- `NetTransport`：peer 建立/关闭、连接状态。
- `NetProtocol`：请求 id、payload schema、版本协商。
- `RoomServer`：server-only 的 room 管理与广播。
- `RoomClient`：client-only 的请求封装与回调分发。
- `NetClient` 作为 façade：对外保持 RPC/信号接口稳定，内部组合上述子模块。

### 10) `ui/components/left_panel/left_panel.gd`

当前职责：

- player tabs、摘要区、员工/里程碑 tab、turn log 小节、与 HandArea/CompanyStructure/LogPanel 的 attach/detach glue。

主要问题：

- 同时包含：展示数据映射（产品名/分类 icon）、节点 reparent 逻辑、UI 渲染、选择逻辑等。
- 与其他面板可能存在展示映射重复（例如产品名映射）。

建议拆分方向：

- `LeftPanelTabs`（玩家 tabs）
- `LeftPanelSummary`
- `LeftPanelEmployeesView`（手牌/公司结构宿主）
- `LeftPanelMilestonesView`
- `LeftPanelTurnLog`
- 展示名/图标尽量从 registry/统一文案派生。

### 11) `ui/components/company_structure/company_structure.gd`

当前职责：

- 公司结构 UI（槽位布局、卡片拖拽、校验、drop target groups）。

主要问题：

- UI 控件内包含较多结构计算/校验/重建逻辑；拖拽相关状态字段较多，容易引入边界 bug。
- 存在空实现 `_build_initial_slots()`，可能是历史遗留接口/未完成的初始化路径。

建议拆分方向：

- 抽“结构模型/容量计算/合法性校验”为纯逻辑模块（更适合 `core/`），UI 只负责呈现与交互。
- 将拖拽视觉层/preview 与结构重建逻辑拆成子对象，降低主脚本复杂度。

### 12) `ui/components/marketing_panel/marketing_panel.gd`

当前职责：

- 发起营销 UI：类型/员工/板件/产品/持续时间/旋转/地图选点联动。

主要问题：

- `MARKETING_TYPES`（含 range）属于规则/数据，硬编码在 UI 中会造成扩展困难（特别是模块引入新营销类型时）。
- 选择状态字段较多，且 rebuild_* 方法组合复杂。

建议拆分方向：

- 营销类型/范围/显示信息尽量从 `MarketingRegistry/MarketingTypeRegistry` 派生，UI 仅做渲染。
- 拆子组件：TypeButtons、BoardPicker、ProductPicker、DurationPicker、RotationPicker、TargetSection。

### 13) `ui/components/reserve_area/reserve_area_full_screen_view.gd`

当前职责：

- 供应堆全屏展示：按类别构建 section、支持缩放、后台分帧构建。

主要问题：

- 单文件囊括 section 构建、皮肤选择、缩放、后台调度等多职责。

建议拆分方向：

- 将各 section builder 拆为独立文件（house numbers / gardens / marketing boards / module supplies / player token supplies）。
- 保留一个 orchestrator 负责 build key、后台构建节奏、zoom 应用。

### 14) `ui/scenes/tests/all_tests.gd`

当前职责：

- headless 测试聚合入口：按固定顺序执行全部测试（preload 列表已下沉到 `ui/scenes/tests/all_tests_refs.gd`）。

主要问题：

- 维护成本高：新增/删除测试要改同一个大文件。
- 测试清单仍集中在一个文件里，仍可能引发 merge 冲突（已缓解：preload 列表已拆出）。

建议拆分方向：

- 按领域拆清单：`core_tests_manifest.gd`、`ui_tests_manifest.gd`、`modules_tests_manifest.gd` 等，由 AllTests 组合。
- 或引入“自动发现”：按 `*_test.gd` 命名与目录规则收集（需要定义排序规则与排除规则）。

### 15) `core/tests/milestone_system_test.gd`

当前职责：

- 里程碑系统测试聚合入口（对外保留 `MilestoneSystemTest.run()`），具体用例已拆分到 `core/tests/milestone_system/*.gd`。

主要问题：

- 新增用例若继续堆回聚合文件，会再次膨胀；建议按领域继续落在分组脚本中。

建议拆分方向：

- 已完成：按触发点/规则拆分到 `core/tests/milestone_system/milestone_system_triggers_test.gd` 与 `core/tests/milestone_system/milestone_system_train_rules_test.gd`，共享 helper 放在 `core/tests/milestone_system/milestone_system_test_support.gd`。

### 16) `tools/generate_manual_test_saves_manifest.gd`（已拆分）

当前职责：

- `tools/generate_manual_test_saves_manifest.gd`：清单聚合入口，保持对外 `get_cases()` 不变。
- `tools/manual_test_saves/manifest_*.gd`：按主题拆分的 case 清单。

主要问题：

- 拆分后仍需防止个别主题文件重新膨胀；新增用例应优先落在对应主题/模块文件中（避免回到“单文件堆叠”）。

建议拆分方向：

- 按领域/模块拆清单文件（employee/milestone/logs/每个模块各自一份）。（已完成：按主题拆分；里程碑已进一步按模块拆分）
- 或迁移为 JSON 数据（便于工具脚本读取与 diff）。

### 17) `tools/generate_manual_test_saves.gd`（已拆分）

当前职责：

- `tools/generate_manual_test_saves.gd`：入口 runner（解析参数/读取 manifest/写出 JSON+MD）。
- `tools/manual_test_saves/builders/*.gd`：按领域拆分的 builder 实现 + registry（name -> Callable）。
- `tools/manual_test_saves/builders/*_support.gd`：共用 helper（phase 推进、map/placement helper 等）。

主要问题：

- （已解决）builder 分发与 builder 实现混在同一文件，导致文件极度膨胀。
- （保留）builder 参数读取/校验代码在多个 builder 中仍有重复空间（可在后续按领域再抽 helper）。

实施结果：

- 已完成：builder 拆分到 `tools/manual_test_saves/builders/`（employees/placement/logs/milestones + support）。
- 已完成：runner 使用 builder registry（`Dictionary` 映射 name -> Callable），替代巨大 `match`。
- `tools/generate_manual_test_saves.gd` 行数从 3255 降至 361，不再属于超长脚本。

## 建议的实施优先级（你点头后可执行）

> 目标：先拆“低耦合、回归风险低”的子系统；再拆“高耦合、影响面大”的子系统。

### P0（最快降低痛点）

- `ui/scenes/tests/all_tests.gd`：清单拆分/自动发现（降低日常冲突与维护）。（已完成：preload 列表下沉到 `ui/scenes/tests/all_tests_refs.gd`）
- `tools/generate_manual_test_saves_manifest.gd`：按领域拆分清单（减少冲突）。（已完成：拆分到 `tools/manual_test_saves/manifest_*.gd`）
- `tools/generate_manual_test_saves.gd`：按 builder 拆文件 + registry 分发（降低 3k 行单点风险）。（已完成：builder 拆分到 `tools/manual_test_saves/builders/`，runner 使用 registry 分发）

### P1（主线可维护性）

- `ui/scenes/game/game.gd`：按子系统拆 controller（layout/dock/save-load）。
- `ui/scenes/game/game_panel_controller.gd` / `ui/scenes/game/game_panel_working_panels.gd`：按阶段/面板拆 controller。
- `ui/scenes/game/game_map_interaction_controller.gd`：按 mode 拆策略对象。

### P2（架构层面优化）

- `ui/scenes/game/map_canvas_drawer.gd`：抽 draw pass + 模块绘制扩展点（避免模块逻辑进入基础渲染）。
- `autoload/net_client.gd`：拆 transport/protocol/server/client 子模块（降低联机改动风险）。

## 实施注意事项（避免引入回归）

- Godot/GDScript 缩进：全程使用 tabs，避免混用空格导致运行期错误（尤其是 `match`/多层 if/信号回调）。
- 重构应“先移动/拆分，再改行为”，每次 PR 保持范围小、可回滚。
- 拆分后优先补齐 headless 测试覆盖：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`。
- 对模块扩展点：先定义接口/数据格式，再迁移现有模块（例如 lobbyists）作为样板。

## 实施记录

- 2026-02-02：拆分手工复核存档 manifest：`tools/generate_manual_test_saves_manifest.gd` 改为聚合入口；新增 `tools/manual_test_saves/manifest_examples.gd`、`tools/manual_test_saves/manifest_employees.gd`、`tools/manual_test_saves/manifest_logs.gd`，并引入 `tools/manual_test_saves/manifest_milestones.gd` 作为里程碑聚合入口；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：进一步拆分里程碑清单：新增 `tools/manual_test_saves/manifest_milestones_base.gd`、`tools/manual_test_saves/manifest_milestones_ketchup.gd`、`tools/manual_test_saves/manifest_milestones_lobbyists.gd`、`tools/manual_test_saves/manifest_milestones_rural_marketeers.gd`、`tools/manual_test_saves/manifest_milestones_new_milestones.gd`；`tools/manual_test_saves/manifest_milestones.gd` 改为聚合入口；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：AllTests preload 列表拆分：新增 `ui/scenes/tests/all_tests_refs.gd`；`ui/scenes/tests/all_tests.gd` 仅保留 runner 与测试顺序；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：拆分里程碑系统单测：`core/tests/milestone_system_test.gd` 改为聚合入口；新增 `core/tests/milestone_system/milestone_system_triggers_test.gd`、`core/tests/milestone_system/milestone_system_train_rules_test.gd`、`core/tests/milestone_system/milestone_system_test_support.gd`；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：拆分手工复核存档生成器 builder：新增 `tools/manual_test_saves/builders/`（support + employees/placement/logs/milestones）；`tools/generate_manual_test_saves.gd` 改为 runner + runtime registry 分发；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：提取存档/回放选择控制器：新增 `ui/scenes/game/game_save_load_controller.gd`；`ui/scenes/game/game.gd` 下沉 SaveLoadDialog 生命周期与回调分发；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：提取右侧 Dock 控制器：新增 `ui/scenes/game/game_right_panel_dock_controller.gd`；`ui/scenes/game/game.gd` 下沉 dock/title/footer 分发逻辑；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：提取布局/响应式控制器：新增 `ui/scenes/game/game_layout_controller.gd`；`ui/scenes/game/game.gd` 下沉左侧信息区/右侧操作区/底部面板的可见性与响应式布局逻辑；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：提取重组阶段控制器：新增 `ui/scenes/game/game_panel_restructuring_controller.gd`；`ui/scenes/game/game_panel_controller.gd` 下沉重组弹窗/视角隐私/拖拽重组命令等逻辑；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：提取 Working/Recruit 面板控制器：新增 `ui/scenes/game/game_panel_working_recruit_controller.gd`；`ui/scenes/game/game_panel_working_panels.gd` 下沉 RecruitPanel 的生命周期/同步/命令分发；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：提取 Working/Price 面板控制器：新增 `ui/scenes/game/game_panel_working_price_controller.gd`；`ui/scenes/game/game_panel_working_panels.gd` 下沉 PriceSettingPanel 的生命周期/同步/命令分发；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：提取 Working/Milestone 面板控制器：新增 `ui/scenes/game/game_panel_working_milestone_controller.gd`；`ui/scenes/game/game_panel_working_panels.gd` 下沉 MilestonePanel 的生命周期/同步；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：提取 Working/Train 面板控制器：新增 `ui/scenes/game/game_panel_working_train_controller.gd`；`ui/scenes/game/game_panel_working_panels.gd` 下沉 TrainPanel 的生命周期/同步/命令分发；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：提取 Working/Production（生产/采购）面板控制器：新增 `ui/scenes/game/game_panel_working_production_controller.gd` 与 `ui/scenes/game/game_panel_working_drinks_procurement_controller.gd`；`ui/scenes/game/game_panel_working_panels.gd` 仅保留面板聚合与薄封装（行数降至 108）；并更新 `ui/scenes/tests/air_procure_start_tile_choice_test.gd` 适配新结构；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：提取通用模态弹窗控制器：新增 `ui/scenes/game/game_panel_modals_controller.gd`；`ui/scenes/game/game_panel_controller.gd` 下沉 TurnOrder/ReserveCard/FridgeKeep modal 的创建/显示/回调与延迟打开逻辑（行数降至 980）；并通过 `ui/scenes/tests/all_tests.tscn`。
- 2026-02-02：提取全屏/覆盖视图控制器：新增 `ui/scenes/game/game_panel_views_controller.gd`；`ui/scenes/game/game_panel_controller.gd` 下沉 EmployeeTree/MilestoneFullScreen/ReserveAreaFullScreen 的创建/显示/隐藏/释放逻辑（行数降至 790，低于 800）；并为 `ui/scenes/game/game_panel_modals_controller.gd` 增加 `sync_for_state()` 统一同步入口；并通过 `ui/scenes/tests/all_tests.tscn`。
