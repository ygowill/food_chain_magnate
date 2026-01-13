# Issue Tracker（自动化修复流水线）

> 项目：FCM_new（Godot 4.5）  
> 目标：按 1→7 逐项修复；每次修复后运行：  
>
> - `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`  
> - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`  
> 并在本文件记录“根因/方案/验证结果/状态”。

---

## 0. 总览

| # | 现象摘要 | 类型 | 初步根因假设 | 状态 |
|---|---|---|---|---|
| 1 | 地图缩放（滚轮/右下角 +/-）无效 | UI/交互 | 现有实现虽已显式启用 process/input，但用户仍可复现：疑似滚轮事件未进入 `MapView`（应改走 `_gui_input` 冒泡链路），且按钮触发依赖 `_process` 未保证立即 apply | Implemented（待手动验收） |
| 2 | 招聘面板首次打开横向溢出 | UI/布局 | 嵌入 RightPanel 时 `custom_minimum_size` + `ScrollContainer(horizontal_scroll_mode=DISABLED)` 会推高最小宽度；首帧 `HFlowContainer` 不换行进一步放大溢出 | Implemented（待手动验收） |
| 2b | 培训面板横向溢出（确认不可点） | UI/布局 | 同类：面板最小宽度/滚动策略在小屏下导致溢出 | Implemented（待手动验收） |
| 2c | 采购/生产面板横向溢出（右侧超屏） | UI/布局 | `ProductionPanel.custom_minimum_size` + OptionButton 最小宽度 + `ScrollContainer(horizontal_scroll_mode=DISABLED)` 在嵌入 RightPanel 时会把最小宽度推高 | Implemented（待手动验收） |
| 3 | 日志面板应为独立视图；筛选“全部”失效 | UI/信息 | OptionButton 负数 id 冲突 + Logs 作为 Tab 导致层级混乱 | Implemented（待手动验收） |
| 4 | 跑腿伙计应“直接拿指定饮料”；其它采购需玩家手动选点生成路线再确认 | 规则+UI 流程 | `ProcureDrinksAction` 未区分 `errand_boy`；UI 直接执行 `procure_drinks` 且依赖 `DrinksProcurement` 默认路线 | Implemented（待手动验收） |
| 5 | 重组阶段：经理下属区不可用；槽位统计错误 | UI+交互 | 槽位统计双算 CEO/漏算 CEO；下属分配依赖 `company_structure.structure` 已初始化，UI 预览结构与 state 不一致时会导致拖拽“无效” | Implemented（待手动验收） |
| 6 | 培训：首次后次数看似未消耗；第二次才消耗但无效果 | UI/流程 | `train` 后可能触发 auto-advance 离开 Train 子阶段并重置 `action_counts`，但 UI 仍强制重开 TrainPanel；或 TrainPanel 刷新条件缺失 | Implemented（待手动验收） |
| 7 | 里程碑面板显示不正确（空/全量） | UI/数据绑定 | 首次构建时机 + `get_all_ids()` 导致“空面板/展示全部里程碑”两类问题 | Implemented（待手动验收） |
| 8 | 查看玩家错位：点“玩家1”像在看“玩家2” | UI/交互 | LeftPanel 在 `set_game_state()` 刷新员工列表时使用旧 `view_player_id`，且 `set_view_player()` 未刷新员工列表，导致显示滞后/错位 | Implemented（待手动验收） |
| 9 | 见习厨师无作用：应可选择生产食物 | 规则+UI 流程 | `EmployeeDef.can_produce()` 仅识别 `produces` 字段；`kitchen_trainee` 仅有 `usage_tags(use:produce:*)` 多选能力，且 `produce_food` 缺少 food_type 参数 | Implemented（待手动验收） |
| 10 | 放置餐厅提示遮挡地图导致无法点击 | UI/交互 | `MapModeBar` 的透明占位节点（TopSpacer 等）默认 mouse_filter 会拦截鼠标，导致地图上方区域无法点击选点 | Implemented（待手动验收） |
| 11 | 发薪日面板首次打开超出右侧屏幕 | UI/布局 | `PaydayPanel.custom_minimum_size` + 列表项最小宽度 + `ScrollContainer(horizontal_scroll_mode=DISABLED)` 在嵌入 RightPanel 时会把最小宽度推高 | Implemented（待手动验收） |
| 12 | 欠薪导致无法结束发薪日但无提示 | UI/流程 | `PaydaySettlement.apply` fail-fast 后只返回 Result.failure；UI 层仅写日志不弹提示 | Implemented（待手动验收） |
| 13 | 点击玩家信息项后仍显示其它玩家内容 | UI/交互 | `PlayerInfoItem` 子控件默认会拦截鼠标，导致点击不稳定、view_player 未切换 | Implemented（待手动验收） |
| 14 | 重组阶段手牌区/在岗员工显示“混合两名玩家” | UI/渲染 | `HandArea` 用 `employee_id -> EmployeeCard` 字典追踪卡牌，遇到重复员工类型会漏释放旧卡牌，切换查看玩家后残留显示 | Implemented（待手动验收） |
| 15 | 重组阶段“同时”但存在隐式顺序/不清楚当前查看玩家 | UI/流程 | `submit_restructuring` 推进 `current_player_index` + 重组遮罩缺少玩家切换入口，默认视图可能落在“已提交玩家”导致无法拖拽 | Implemented（待手动验收） |
| 16 | 当前玩家标识不清晰（顺序轨 vs 左侧玩家 tab 易混淆） | UI/信息架构 | “当前回合玩家”与“查看玩家”缺少统一视觉区分；顶部顺序轨提示语不明确 | Implemented（待手动验收） |
| 17 | 开局左侧玩家信息面板宽度与日志面板不一致 | UI/布局 | LeftArea/LeftPanel 的最小宽度策略与 `GameLogPanel` 不一致 | Implemented（待手动验收） |
| 18 | 左侧玩家 tab 点击偶尔不切换 | UI/交互 | PlayerTabs 用 pressed 信号 + 代码直接写 `button_pressed`，在部分情况下会造成状态/信号不一致 | Implemented（待手动验收） |
| 19 | 存档加载提示“无效的 initial_state” | 存档/回放 | JSON.parse_string 将所有数字读成 float，导致玩家字段（cash 等）类型不匹配；同时整值 float/int 的表现差异会导致 hash 不稳定 | Implemented（待手动验收） |
| 20 | 重组阶段公司结构需展示为树（管理岗像 CEO，有槽位） | UI/重构 | 现 UI 仅 CEO 使用卡槽、管理岗用列表，无法表达树；大量槽位时缺少折叠/滚动策略导致易溢出 | Implemented（待手动验收） |
| 21 | 加载存档后日志面板为空/消失 | UI/存档 | 存档回放发生在进入 GameScene 之前，UI 未订阅导致日志未捕获；且 setup 清空日志但未从 EventBus.history 恢复 | Implemented（待手动验收） |

---

## 0b. 自动化回归覆盖

> 说明：这里记录“已经写进 AllTests 的自动化断言”，用于替代低效的手动回归。

- `HandAreaViewSwitchTest`：覆盖 #14（切换玩家时不残留旧卡牌）
- `UiRegressionPropertyTest`：覆盖 #10（MapModeBar 不拦截鼠标）、#13（PlayerInfoItem 全区域可点击）
- `MapZoomPropertyTest`：覆盖 #1（MapCanvas 缩放影响 cell_size / custom_minimum_size / 拾取换算）
- `ArchiveFileRoundtripTest`：覆盖 #19（save_to_file/load_from_file roundtrip 不再因为 JSON float 导致 initial_state 无效，且 hash 稳定）
- `LogRestoreAfterLoadTest`：覆盖 #21（存档加载后从 EventBus.history 恢复日志）

## 1. 地图缩放无效

**现象**

- 点击地图区域右下角 “+/-” 或滚轮缩放会改变“滚动区域”，但地图本身不缩放：看起来地图大小不变，只是地图外空白变大。

**涉及代码**

- `ui/scenes/game/map_view.gd`
- `ui/scenes/game/game_overlay_zoom.gd`
- `ui/components/zoom_control/zoom_control.gd`
- `ui/scenes/game/map_canvas.gd`
- `ui/scenes/game/map_canvas_drawer.gd`

**初步根因（待复现确认）**

- 第一阶段：滚轮事件在 `ScrollContainer` GUI 输入链路中被消费，`_input()` 收不到；按钮触发依赖 `_process`，不保证当帧生效。
- 第二阶段：缩放主要通过调整 `ScrollContainer` 子节点的 `custom_minimum_size` 生效，但 `MapCanvas` 绘制/拾取仍用固定 `CELL_SIZE`，导致“区域变大但绘制不变”。

**修复方案**

- 将滚轮缩放处理从 `_input()` 改为 `_gui_input()`（依赖 `MapCanvas.mouse_filter=PASS` 冒泡到 `MapView`），保证滚轮事件必达。
- 将 `zoom_in/zoom_out/滚轮` 的缩放改为“立即 apply”（必要时先 `animate=false` 确保可用），避免依赖 `_process` 才能生效。
- 将缩放从“缩放节点/仅调最小尺寸”改为由 `MapCanvas` 按 zoom 动态计算 `cell_size`：绘制与拾取统一使用 `get_cell_size()`，并同步更新 `custom_minimum_size`。

**实施记录（现有尝试修复，用户仍可复现）**

- 已存在改动：`ui/scenes/game/map_view.gd` 在 `_ready()` 中显式 `set_process(true)`/`set_process_input(true)`。
- 已修改：`ui/scenes/game/map_view.gd`：滚轮/拖拽改走 `_gui_input()`；`zoom_in/zoom_out/滚轮/fit` 改为当帧 apply（`animate=false`），避免依赖 `_process`。
- 已修改：`ui/scenes/game/map_canvas.gd`：新增 `set_zoom()`/`_zoom`，`get_cell_size()` 随 zoom 变化；拾取 `_local_to_world_cell()` 与 `custom_minimum_size` 统一走 `get_cell_size()`。
- 已修改：`ui/scenes/game/map_view.gd`：缩放时调用 `MapCanvas.set_zoom()`（不再只扩大滚动区域）；并修正 `center_on_position()` 使用 `world_origin` 且不重复乘 zoom。
- 追加修复：`ui/scenes/game/map_view.gd`：缩放后对 `scroll_horizontal/scroll_vertical` 做有效范围 clamp，避免滚动位置越界导致“地图外空白变大”。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（75/75，`.godot/AllTests.log`）

**验收**

- 点击 `+/-` 能改变缩放百分比与地图显示。
- 滚轮缩放可用。

---

## 2. 招聘面板首次打开横向溢出

**现象**

- 招聘面板第一次打开时出现横向溢出/闪一下；再次打开正常。

**涉及代码**

- `ui/scenes/game/game_panel_controller.gd`：`_center_popup()` / `_dock_popup_right()`
- `ui/scenes/game/game.gd`：`dock_popup_into_right_panel()`
- `ui/components/recruit_panel/recruit_panel.tscn`

**初步根因（待复现确认）**

- 现有实现已改为 dock_right 同帧嵌入，但“首次打开溢出”仍可复现：更可能同时包含两类问题：  
 	- `RecruitPanel.custom_minimum_size.x` 在嵌入 RightPanel 时仍生效，若小屏/分栏宽度不足，会把面板撑到右侧溢出；  
 	- `ScrollContainer.horizontal_scroll_mode=DISABLED` 时，为了不出现横向滚动条，会尝试“撑开以容纳内容最小宽度”，叠加 `HFlowContainer` 首帧不换行，导致溢出更明显。

**修复方案**

- `RecruitPanel`：  
 	- 嵌入 RightPanel 时将 `custom_minimum_size` 置零，避免“面板最小宽度”把 RightPanel 撑爆；  
 	- `ScrollContainer.horizontal_scroll_mode` 改为 AUTO，确保内容宽度过大时不会强制扩宽（最坏情况出现横向滚动条）；  
 	- 保留 1-2 帧后 `queue_sort()`，确保 `HFlowContainer` 在尺寸稳定后换行。

**实施记录（现有尝试修复，用户仍可复现）**

- 已存在改动：`ui/scenes/game/game_panel_controller.gd` 对 `dock_right` 分支取消前置 `await process_frame`。
- 已修改：`ui/components/recruit_panel/recruit_panel.tscn`：在 `ScrollContainer` 下新增 `ContentVBox` 包裹 `ItemsContainer`，使 `HFlowContainer` 首帧即可拿到稳定宽度并换行。
- 已修改：`ui/components/recruit_panel/recruit_panel.gd`：更新 `items_container` 节点路径以匹配场景结构调整。
- 追加修复：`ui/components/recruit_panel/recruit_panel.gd`：嵌入 RightPanel 时将 `custom_minimum_size=Vector2.ZERO`，避免最小宽度撑爆。
- 追加修复：`ui/components/recruit_panel/recruit_panel.tscn`：`ScrollContainer.horizontal_scroll_mode=1(AUTO)`，并设置 `size_flags_horizontal=EXPAND_FILL`。
- 追加修复：`ui/scenes/game/game_panel_working_panels.gd`：首次创建 `RecruitPanel` 时先 `visible=false` 再 dock 到 RightPanel，避免 `_ready` 首帧仍以“非嵌入布局/最小宽度”参与尺寸计算导致溢出/闪烁。

**验证**

- 已跑：`GameSmokeTest` / `AllTests`（均通过）。

**验收**

- 首次打开招聘面板不再出现横向溢出/错位闪烁。

---

## 2b. 培训面板横向溢出（确认按钮不可点）

**现象**

- 培训面板右半部分超出屏幕范围，导致无法点击确认培训（尤其在嵌入 RightPanel 时）。

**涉及代码**

- `ui/components/train_panel/train_panel.tscn`
- `ui/components/train_panel/train_panel.gd`
- `ui/scenes/game/game.gd`：`dock_popup_into_right_panel()`（嵌入）

**初步根因（待复现确认）**

- 与招聘面板同类：面板自身 `custom_minimum_size.x` + 内部 `HFlowContainer`/`ScrollContainer(horizontal_scroll_mode=DISABLED)` 在首帧/小屏时共同把最小宽度推高，产生横向溢出。

**修复方案**

- 嵌入 RightPanel 时将 `custom_minimum_size` 置零；同时将关键 `ScrollContainer.horizontal_scroll_mode` 改为 AUTO；并在尺寸稳定后对 `HFlowContainer` 做一次 `queue_sort()`。

**实施记录**

- 已修改：`ui/components/train_panel/train_panel.gd`：嵌入 RightPanel 时 `custom_minimum_size=Vector2.ZERO`；并增加延迟重排（2 帧后 `trainable_container.queue_sort()`）。
- 已修改：`ui/components/train_panel/train_panel.tscn`：`TrainableContainer.size_flags_horizontal=EXPAND_FILL`；`PathSection/ScrollContainer.horizontal_scroll_mode=1(AUTO)` 且 `size_flags_horizontal=EXPAND_FILL`。
- 追加修复：`ui/scenes/game/game_panel_working_panels.gd`：首次创建 `TrainPanel` 时先 `visible=false` 再 dock 到 RightPanel，避免首帧仍以“弹窗布局”参与尺寸计算导致溢出。

**验证**

- 已跑：`GameSmokeTest` / `AllTests`（均通过）。

**验收**

- 培训面板在右侧抽屉中不再横向溢出，右侧确认按钮（RightPanel Footer）可点击。

---

## 2c. 采购/生产面板横向溢出（右侧超屏）

**现象**

- 生产/采购面板（`ProductionPanel`）在右侧抽屉中右半部分超出屏幕范围（尤其在“采购饮料”模式下）。

**涉及代码**

- `ui/components/production_panel/production_panel.tscn`
- `ui/components/production_panel/production_panel.gd`

**初步根因**

- `ProductionPanel` 本体 `custom_minimum_size` + 动态创建的 `OptionButton.custom_minimum_size=380` 会在 RightPanel 宽度不足时把布局最小宽度推高，导致整体溢出。
- `ScrollContainer.horizontal_scroll_mode=DISABLED` 时，为避免横向滚动条会倾向于扩宽内容区域，进一步放大溢出。

**修复方案**

- 嵌入 RightPanel 时将 `custom_minimum_size` 清零（恢复为可收缩）；并将 `ScrollContainer.horizontal_scroll_mode` 改为 AUTO（必要时出现横向滚动条而不是撑爆宽度）。
- 嵌入 RightPanel 时移除 `OptionButton` 的硬编码最小宽度（改为 `EXPAND_FILL` 自适应）。

**实施记录**

- 已修改：`ui/components/production_panel/production_panel.gd`：嵌入 RightPanel 时 `custom_minimum_size=Vector2.ZERO`；并按嵌入状态切换 `ScrollContainer.horizontal_scroll_mode`。
- 已修改：`ui/components/production_panel/production_panel.gd`：`OptionButton` 在嵌入 RightPanel 时不再设置 `custom_minimum_size(380,0)`，改为 `EXPAND_FILL` 自适应宽度。
- 追加修复：`ui/scenes/game/game_panel_working_panels.gd`：首次创建 `ProductionPanel` 时先 `visible=false` 再 dock 到 RightPanel，避免首帧仍以“弹窗布局”参与尺寸计算导致溢出。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（75/75，`.godot/AllTests.log`）

**验收**

- 生产/采购面板在右侧抽屉中不再横向溢出，右侧确认按钮（RightPanel Footer）可点击。

---

## 3. 日志面板嵌入/筛选问题

**现象**

- 期望：LeftArea 的日志面板是**独立视图**（不与“手牌/在职/里程碑”同属一个 TabContainer）。
- 筛选：点“玩家X”能切换，但点“全部”无效。

**涉及代码**

- `ui/components/game_log/game_log_panel.gd`
- `ui/components/left_panel/left_panel.gd`
- `ui/components/left_panel/left_panel.tscn`
- `ui/scenes/game/game.gd`（LogButton 行为）

**初步根因**

- `OptionButton.add_item("全部", -1)`：在 Godot `PopupMenu/OptionButton` 里 `id == -1` 代表“自动分配 id”，实际 id 变成 0，与玩家 0 冲突；导致“全部”选择后仍过滤到玩家 0。
- 日志被作为 `LeftPanel/TabContainer` 的一个 tab：即使切换到“日志”，顶部仍会显示“手牌/在职/里程碑”等 tab bar，导致信息层级混乱。

**修复方案**

- 为“全部”使用一个明确且不冲突的**正数** item id（例如 `9999`），并用 `OptionButton.get_selected_id()` 读取，避免 `get_item_id(index)` 与负数 id 的潜在兼容问题。
- UI layout v2：移除 `LeftPanel` 内的 Logs Tab；`GameLogPanel` 保持为 `LeftArea` 的独立子节点；LogButton 只在两个视图间切换（`LeftPanel` ↔ `GameLogPanel`）。

**实施记录（现有尝试修复，用户仍可复现）**

- 已修改：`ui/components/game_log/game_log_panel.gd`：将“全部”的 item id 改为 `9999`，并改用 `OptionButton.get_selected_id()` 读取，映射回 `_filter_player_id=-1`。
- 已修改：`ui/components/left_panel/left_panel.tscn`：移除 `Logs` Tab（避免与手牌/在职混在同一 TabContainer）。
- 已修改：`ui/components/left_panel/left_panel.gd`：新增 `logs_requested` 信号与 `bind_game_log_panel()`（用于 TurnLogSection 读取日志）；不再 reparent `GameLogPanel`。
- 已修改：`ui/scenes/game/game.gd`：layout v2 下不再把 `GameLogPanel` 挂到 `LeftPanel`；`toggle_game_log()` 改为切换 `LeftPanel.visible` 与 `GameLogPanel.visible`。

**验证**

- 已跑：`GameSmokeTest` / `AllTests`（均通过）。

**验收**

- 点击“全部”可回到不过滤状态，显示所有日志。
- LogButton 在 layout v2 下切换为“独立日志视图”，不会再出现“日志视图仍显示手牌/在职 tab bar”。

---

## 4. 饮料采购：跑腿伙计选择饮料；其它采购手动选点生成路线

**现象**

- `errand_boy` 不应走采购路线，而应让玩家选择“拿哪种饮料”，直接获得 1 瓶。
- 其它采购员工：不应系统自动选路；应玩家逐点选择饮料点 → 系统生成路线 → 玩家确认后执行采购。

**涉及代码**

- `gameplay/actions/procure_drinks_action.gd`
- `core/rules/drinks_procurement.gd`
- `ui/components/production_panel/production_panel.gd`
- `ui/scenes/game/game_panel_working_panels.gd`
- `ui/scenes/game/game_map_interaction_controller.gd`（需要新增采购选点模式）
- `ui/scenes/game/game_overlay_procurement_route.gd`

**初步根因**

- `ProcureDrinksAction` 目前统一按“路线拾取饮料源×2/源”结算，未对 `errand_boy` 特判。
- UI 在 `ProductionPanel` 中直接执行 `procure_drinks(employee_type)`，`DrinksProcurement.resolve_procurement_plan()` 在无 route 参数时会自动生成默认路线。

**修复方案（按最小可用版本落地）**

1) `errand_boy`：`procure_drinks` 增加参数 `drink_type`（由 UI 选择），执行时直接 `add_inventory(player_id, drink_type, 1)`；不再依赖路线/饮料源拾取。  
2) 其它采购员工：改 UI 流程  
 - 进入“采购选点模式”：地图点击饮料源逐个加入列表（按点击顺序）。  
 - 系统使用道路图最短路（或飞艇 Manhattan 路径）拼接生成 route，并用现有 `procurement_route_overlay` 预览。  
 - 玩家点“确认采购”后执行 `procure_drinks`，携带 `route`（必要时携带 `restaurant_id` 以消歧）。  

**需要用户澄清（如与预期不一致再调整）**

- 选点顺序是否允许调整/撤销（本轮先实现“撤销最后一个/清空”即可）。
- 是否要求路线必须回到餐厅（当前规则不要求；本轮先不回程）。

**实施记录**

- 已修改：`gameplay/actions/procure_drinks_action.gd`：`errand_boy` 采购改为校验 `drink_type` 并直接获得 1 瓶；其它采购员工强制要求 `route/selected_sources`，并使用 `DrinksProcurement.resolve_procurement_plan()` 做 fail-fast 校验。
- 已修改：`core/rules/drinks_procurement.gd`：强制 `route/selected_sources` 非空；校验所选来源存在、路线覆盖全部所选来源；只结算所选来源（不再“路过顺便买”）。
- 已修改：`ui/components/production_panel/production_panel.gd`：为 `errand_boy` 提供饮料类型选择；为其它采购提供“撤销最后一个/清空”选择点操作入口。
- 已修改：`ui/scenes/game/game_panel_working_panels.gd`：新增采购选点状态（`_procure_selected_sources`），基于选点顺序生成 air/road 路线并预览 overlay；确认采购时发送 `route + selected_sources`；并修复一次缩进导致的脚本 parse error。
- 已修改：`core/tests/procure_drinks_test.gd`、`core/tests/procure_drinks_route_rules_test.gd`：补齐 `selected_sources` 与显式 `route` 构造，适配“手动选点/路线必填”的新规则。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（72/72，`.godot/AllTests.log`）

**验收**

- 跑腿伙计采购时能选择饮料并直接获得 1 瓶。
- 其它采购需手动选点后才能确认执行；不再自动选路。

---

## 5. 重组阶段：拖拽与槽位统计

**现象**

- 管理培训生等“经理员工”下属区无法拖入空闲员工。
- 无法将员工拖回手牌区（尤其当待命区为空时）。
- 槽位统计错误：例（CEO + 管理培训生）期望 remaining=4，总槽位=6（员工2 + 空槽4）。

**涉及代码**

- `ui/components/company_structure/company_structure.gd`
- `ui/scenes/game/game_panel_controller.gd`（拖拽落点 → 生成内部命令）
- `gameplay/actions/set_company_structure_direct_action.gd`
- `gameplay/actions/set_company_structure_report_action.gd`
- `core/rules/company_structure_rules.gd`

**初步根因**

- UI 槽位统计：`_count_total_slots()` 将 CEO slots 与 CEO 自身 `manager_slots` 双算；`_count_used_slots()` 又排除了 CEO，导致 used/total 体系与 `CompanyStructureRules` 不一致。
- 下属拖拽：`set_company_structure_report` 要求 `company_structure.structure` 已按 `ceo_slots` 初始化且目标槽已有“经理”；但 UI 会基于 employees 生成“预览结构”，导致看起来有经理但 state 里未写入，从而拖拽“无效”（命令失败但 UI 缺少显式提示）。
- 回拖失败：`HandArea` 会在 `reserve_employees` 为空时隐藏待命区 section，导致没有任何 drop target 命中（拖拽释放后不触发命令）。
- 重复经理类型：UI 展示结构读取 `company_structure.structure[*].reports` 时若按 `manager_employee_id` 作为 key，会在存在多个同类型经理（如两张 `management_trainee`）时互相覆盖，导致“拖到下属区但看起来不生效/显示丢失”。
- 同名员工多实例：`set_company_structure_direct/report` 在 apply_changes 中仅在 `reserve.has(employee_id) and not employees.has(employee_id)` 时才把员工从待命区移动到在岗；当同名员工一张已在岗、另一张在待命时，放入第二张会导致 `assigned_count > active_count` 并触发“移除多余占用”，表现为卡牌被“挤下来”。
- 待命同步残留：`restructure_employee` 仅移动 `employees/reserve_employees`，未同步移出 `company_structure.structure`，会留下“待命员工仍占用结构”的隐式残留；当再次放置同名员工到结构时会触发计数纠正，表现为“放第三张时有一张被挤下来”。

**修复方案**

- UI 统计：对齐 `CompanyStructureRules`（内部 used/total 不含 CEO）并在 UI 展示时统一 +1（含 CEO），保证：  
 	- remaining = total - used  
 	- 示例可得到 used=2 total=6 remaining=4  
- 拖拽下属：在向 `set_company_structure_report` 提交前，若对应 `manager_slot_index` 在 state 中未初始化/未放置经理，则先补写一次 `set_company_structure_direct`（以 UI 当前显示的经理为准），再写入 report。

**验收**

- 经理下属区可拖入非经理员工并生效。
- 槽位显示符合示例与 `CompanyStructureRules.get_empty_slots()`。

**实施记录**

- 已修改：`ui/components/company_structure/company_structure.gd`：卡槽统计对齐 `CompanyStructureRules`（不再把 CEO 的 `manager_slots` 再算一次），并在展示层统一 `+1`（含 CEO），示例应显示 `2/6`。
- 已修改：`ui/components/company_structure/company_structure.gd`：在经理下属 drop 区写入 `manager_employee_id` meta，供拖拽命令补全结构使用。
- 已修改：`ui/scenes/game/game_panel_controller.gd`：拖拽到经理下属区时，若 `company_structure.structure` 未初始化，先自动执行一次 `set_company_structure_direct` 初始化对应经理槽位，再执行 `set_company_structure_report`。
- 追加修复：`ui/components/company_structure/company_structure.gd`：优先下属分配从按员工 id 改为按 `manager_slot_index` 存储/读取，避免重复经理类型覆盖导致的下属显示/分配异常。
- 追加修复：`ui/scenes/game/game_panel_controller.gd`：当 UI 显示的经理与 state 中该槽位的 `employee_id` 不一致时，先同步 `set_company_structure_direct`（避免“看起来是经理但实际不是/槽位不匹配”导致 report 命令失败）；并在失败时写入 `GameLog.warn`。
- 追加修复：`ui/components/hand_area/hand_area.gd`：拖拽启用时强制显示“在岗/待命”两个 section（即使为空），保证有可命中的 drop target。
- 追加修复：`ui/components/hand_area/hand_area.tscn`：为 `ActiveContainer/ReserveContainer` 增加最小高度并 `EXPAND_FILL`，提升空容器可投放性。
- 追加修复：`gameplay/actions/set_company_structure_direct_action.gd`、`gameplay/actions/set_company_structure_report_action.gd`：当 `assigned_count > active_count` 时按差值从 `reserve_employees` 补齐到 `employees`（而不是只在“在岗不存在该员工”时补齐），避免同名员工多实例从待命放入结构时互相“挤掉”。
- 追加修复：`gameplay/actions/restructure_employee_action.gd`：当员工被拖到待命区时，同步从 `company_structure.structure` 移除一个实例（直属槽优先，其次 reports），避免“待命员工仍占用结构”导致后续放置同名员工时被挤掉。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（75/75，`.godot/AllTests.log`）

---

## 15. 重组阶段：隐式顺序与查看玩家不清晰

**现象**

- 理论上两名玩家可同时进行重组，但 UI 存在“隐含顺序”，不清楚当前正在操作/查看哪位玩家。
- 有时会出现“无法拖拽”的观感（实际是默认视图落在已提交玩家，拖拽被禁用）。

**涉及代码**

- `ui/components/modal_panel/restructuring_modal.tscn`
- `ui/components/modal_panel/restructuring_modal.gd`
- `ui/scenes/game/game_panel_controller.gd`
- `gameplay/actions/submit_restructuring_action.gd`
- `core/tests/test_phase_utils.gd`（测试辅助：完成重组阶段）

**根因**

- 重组遮罩（RestructuringModal）缺少“玩家切换”的直达入口，依赖侧边面板切换导致不直观。
- `submit_restructuring` 在内部推进 `current_player_index`，强化了“顺序阶段”观感（与“同时阶段”预期冲突）。
- 默认 `view_player` 选择逻辑在部分情况下会落在“已提交玩家”，拖拽被禁用但缺少强提示。

**修复方案**

- 在重组遮罩内新增“玩家切换”按钮组，显示每位玩家的提交状态（已提交/未提交）。
- 统一通过 `view_player_id` 决定“正在编辑哪位玩家”的手牌/公司结构数据与拖拽可用性。
- `submit_restructuring` 不再推进 `current_player_index`（保留 Restructuring 作为“同时阶段”的语义）。
- 更新测试辅助与相关用例：完成重组阶段时不依赖 `current_player_index` 自动推进，而是对未提交玩家逐个提交。

**实施记录**

- 已修改：`ui/components/modal_panel/restructuring_modal.tscn`：新增 `PlayerRow/PlayerButtons`。
- 已修改：`ui/components/modal_panel/restructuring_modal.gd`：新增 `player_selected` 信号与 `set_player_switcher()`，展示并切换查看玩家。
- 已修改：`ui/scenes/game/game_panel_controller.gd`：连接重组遮罩的 `player_selected`；同步 `set_player_switcher()`；当默认视图玩家已提交时自动切到未提交玩家。
- 已修改：`gameplay/actions/submit_restructuring_action.gd`：不再推进 `current_player_index`（避免隐式顺序）。
- 已修改：`core/tests/test_phase_utils.gd`、`core/tests/order_of_business_test.gd`、`core/tests/restructuring_overflow_penalty_test.gd`：重组提交不再依赖 `get_current_player_id()`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（75/75，`.godot/AllTests.log`）

**验收**

- 重组遮罩内可清晰看到并切换“当前查看玩家”，且可分别提交。
- 不再出现“隐含顺序导致不知道是谁/看起来拖不动”的情况（已提交会明确展示，未提交可拖拽）。

## 16. 当前玩家标识不清晰（顺序轨 vs 左侧玩家 tab 易混淆）

**现象**

- 根本不知道目前是哪个玩家的阶段（尤其在“查看玩家 != 当前行动玩家”时）。
- 顶部回合顺位显示不够直观，容易与左侧玩家 tab（查看玩家）混淆。
- 选择顺位（OrderOfBusiness）时缺少“当前正在选择的玩家”提示。
- 在 Restructuring 这种“同时阶段”中仍展示“当前行动玩家”，会强化“隐含顺序”的误解。

**涉及代码**

- `ui/scenes/game/game.gd`（TopBar 的 CurrentPlayerLabel 文案）
- `ui/components/action_panel/action_panel.gd`（右侧动作面板标题）
- `ui/components/turn_order/turn_order_display.gd` / `ui/components/turn_order/turn_order_display.tscn`（顶部顺位展示）
- `ui/components/turn_order/turn_order_track.gd`（顺序轨标题提示）
- `ui/components/modal_panel/turn_order_selection_modal.gd`（顺位选择遮罩提示）
- `ui/components/left_panel/left_panel.gd`（左侧玩家 tab 的 current/view 高亮）
- `ui/scenes/game/game_panel_controller.gd`（重组遮罩提示文案）

**根因**

- 顶部顺位显示缺少明确的语义提示（仅一排数字徽章），与左侧玩家 tab（也是数字按钮）容易混淆。
- 右侧动作面板未标识“动作所属玩家”，当左侧切换查看玩家时容易误认为右侧动作也已切换。
- 左侧玩家 tab 的“当前行动玩家”样式仅写在 pressed 样式中：当查看其它玩家时（按钮未 pressed）当前玩家高亮消失。
- OrderOfBusiness 的顺位选择遮罩/顺序轨没有展示 “selecting_player”，导致玩家不知道当前是谁在选。
- Restructuring 为“同时阶段”，但 TopBar 仍显示“行动玩家”，造成误导。

**修复方案**

- 顶部顺位展示增加“顺位”标题，并将徽章文字改为“顺位编号”（用颜色表示该顺位对应玩家，白色边框表示当前行动玩家所在顺位）。
- 右侧动作面板标题展示“行动: 玩家X”，与 TopBar 的“行动”一致，避免与“查看玩家”混淆。
- 顺位选择遮罩/顺序轨标题显示“当前选择玩家”，与 TopBar 的“行动”一致。
- TopBar 文案在 Restructuring 阶段改为“重组（同时）｜查看｜提交进度”，避免强化隐含顺序；其它阶段保持“行动｜查看”双标识。
- 左侧玩家 tab：当 `is_current && not is_view` 时也应用 current 高亮到 normal 样式，保证“当前行动玩家”始终可见。

**实施记录**

- 已修改：`ui/components/action_panel/action_panel.gd`：标题显示“可用动作（行动: 玩家X）”，明确动作面板对应的当前行动玩家。
- 已修改：`ui/components/turn_order/turn_order_display.tscn`：增加“顺位”标题；Root 改为 `HBoxContainer` 以便自动布局。
- 已修改：`ui/components/turn_order/turn_order_display.gd`：徽章文字改为 `slot_position+1`（顺位编号），tooltip 文案同步为“顺位 …”。
- 已修改：`ui/components/turn_order/turn_order_track.gd`：当可选择顺位时，标题显示“选择顺位：玩家X”。
- 已修改：`ui/components/modal_panel/turn_order_selection_modal.gd`：遮罩标题/提示行显示“当前: 玩家X”；并将选择提示从“位置”改为“顺位”。
- 已修改：`ui/scenes/game/game.gd`：Restructuring 阶段 TopBar 显示“重组（同时）｜查看｜提交进度”；其它阶段显示“行动｜查看”。
- 已修改：`ui/components/left_panel/left_panel.gd`：当前行动玩家在 `not is_view` 时也会在 normal 样式中高亮边框。
- 已修改：`ui/scenes/game/game_panel_controller.gd`：重组遮罩提示文案由“左侧切换玩家”改为“上方切换玩家”。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（75/75，`.godot/AllTests.log`）

## 17. 开局左侧玩家信息面板宽度与日志面板不一致

**现象**

- Layout V2 下左侧区域在“玩家信息面板”和“日志面板”之间切换时宽度不一致，开局视觉跳变明显。

**涉及代码**

- `ui/scenes/game/game.gd`：`_apply_responsive_layout()`（LeftArea 宽度策略）
- `ui/components/game_log/game_log_panel.tscn`：`custom_minimum_size`

**根因**

- `GameLogPanel.custom_minimum_size.x=340` 会抬高 LeftArea 的组合最小宽度；当切换为日志面板时 LeftArea 会被动变宽，而玩家信息面板未强制同宽，造成不一致。

**修复方案**

- 将 `GameLogPanel.custom_minimum_size.x` 置为 0，使 LeftArea 的宽度统一由 `_apply_responsive_layout()`/用户拖拽决定；日志与玩家信息视图仅切换可见性，不再影响 SplitContainer 的布局宽度。

**实施记录**

- 已修改：`ui/components/game_log/game_log_panel.tscn`：`custom_minimum_size = Vector2(0, 240)`（移除固定最小宽度）。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（75/75，`.godot/AllTests.log`）

## 18. 左侧玩家 tab 点击偶尔不切换

**现象**

- 左侧玩家 tab 偶尔点击后“查看玩家”不切换，导致玩家信息看起来不更新。

**涉及代码**

- `ui/components/left_panel/left_panel.gd`

**根因（推测）**

- `pressed` 仅在按钮按下/松开满足条件时触发；同时 UI 同步阶段会直接写 `button_pressed`，容易造成按钮组状态与用户点击的信号触发不稳定（表现为“有时点了没反应”）。

**修复方案**

- PlayerTabs 改用 `toggled`（仅在 `pressed=true` 时触发切换），并在 UI 同步时用 `set_pressed_no_signal()` 设定选中状态，避免同步过程中触发信号/互相打架。

**实施记录**

- 已修改：`ui/components/left_panel/left_panel.gd`：玩家 tab 从 `pressed` 改为 `toggled`；同步选中状态改为 `set_pressed_no_signal()`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（75/75，`.godot/AllTests.log`）

## 6. 培训次数显示/消耗异常

**现象**

- 第一次培训后次数看似未消耗，仍可继续点；第二次才显示消耗，但第二次培训无效果。

**涉及代码**

- `ui/scenes/game/game_panel_working_panels.gd`：`_on_train_requested()`
- `core/engine/game_engine/auto_advance.gd` / `core/engine/phase_manager/advance_sub_phase.gd`（可能触发子阶段自动推进与 action_counts 重置）

**初步根因（优先验证）**

- `train` 执行后，若当前玩家在 Train 子阶段已无可做动作，`auto_advance` 可能自动推进到下一子阶段并清空 `round_state.action_counts`；但 UI 仍无条件 `show_train_panel()`，导致：
 	- 面板重开时次数看似“没消耗”（action_counts 已被重置）
 	- 再次点击培训时因为不在 Train 子阶段而失败（看起来“无效果”）

**修复方案**

- 在 `_on_train_requested()` 中：仅当执行后 state 仍处于 `Working/Train` 才重开 TrainPanel；否则不重开（让流程自然进入下一子阶段）。

**验收**

- Train 子阶段结束后不再弹回 TrainPanel；次数显示与实际一致。

**实施记录**

- 已修改：`ui/scenes/game/game_panel_working_panels.gd`：`train` 成功后只在仍处于 `Working/Train` 时才重开 TrainPanel，避免离开子阶段后错误地继续展示/可点培训。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（72/72，`.godot/AllTests.log`）

---

## 7. 里程碑面板无内容

**现象**

- 玩家里程碑面板打开为空。
- 修复后又出现：里程碑面板显示了全部里程碑，而不是玩家已获得的里程碑。

**涉及代码**

- `ui/components/milestone_panel/milestone_panel.gd`
- `ui/scenes/game/game_panel_working_panels.gd`（show_milestone_panel 时 set_*）
- `ui/components/left_panel/left_panel.tscn`（也嵌入了 MilestonePanel）

**初步根因**

- `MilestonePanel` 只在 `_ready()` 时构建列表；后续 set 数据只更新状态，不触发列表重建；首次构建发生在数据注入之前时会导致永远空。
- 当 `MilestoneRegistry` 已加载时，面板用 `get_all_ids()` 构建列表，导致把全部里程碑都展示出来。

**修复方案**

- `set_milestone_pool()` / `set_player_milestones()` 改为触发 `_rebuild_milestones()`（或在 ids 发生变化时重建）。
- 列表 ids 改为仅基于 `player.milestones`（去重+排序）；当玩家尚未获得任何里程碑时显示占位文案。

**验收**

- 里程碑面板仅显示玩家已获得的里程碑（为空时显示“暂无已获得的里程碑”）。

**实施记录**

- 已修改：`ui/components/milestone_panel/milestone_panel.gd`：`set_milestone_pool/set_player_milestones` 在里程碑 ids 变化时重建列表（否则仅刷新状态），修复“首次构建为空后永远空”的问题。
- 追加修复：`ui/components/milestone_panel/milestone_panel.gd`：将展示 ids 改为仅来自 `player_milestones`（去重+排序），避免展示全部里程碑；空列表时增加占位文案。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（72/72，`.godot/AllTests.log`）

---

## 8. 查看玩家错位（玩家面板/右侧 PlayerPanel / 左侧 Tab）

**现象**

- 点击“玩家1”后，信息看起来像是“玩家2”的内容（查看玩家切换不生效/或视觉上误判）。

**初步根因**

- `GamePanelController` 在 `Restructuring` 阶段强制将 `view_player_id` 重置为 `current_player_id`，导致点击切换“查看玩家”不会生效。
- 右侧 `PlayerPanel` 只高亮“当前行动玩家”，未高亮“查看玩家”，容易造成“点了但没切换”的误判。
- 左侧 `LeftPanel` 的员工列表（手牌/在职）仅在 `set_game_state()` 里刷新；而 `GamePanelController` 同步 UI 时先调用 `set_game_state()` 再调用 `set_view_player()`，且 `LeftPanel.set_view_player()` 本身不刷新员工列表，导致“高亮/摘要已切换，但员工列表仍显示上一位玩家”的错位（看起来像把玩家数据混了/换错了）。

**修复方案**

- 取消 `Restructuring` 阶段对 `view_player_id` 的强制覆盖；仍保持“view!=current 时禁用拖拽”来保证重组交互安全。
- `PlayerPanel` 新增 `set_view_player()`，并在 item 上同时显示：
 	- `current_player`：白色边框
 	- `view_player`：玩家色边框/背景
- `LeftPanel.set_view_player()` 需要刷新员工列表（至少调用一次 `_refresh_employee_icons()`），保证切换查看玩家后列表立即同步。

**实施记录**

- 已修改：`ui/scenes/game/game_panel_controller.gd`：移除重组阶段强制 `view_player=current_player`；同步时将 `view_player_id` 传给 `PlayerPanel`。
- 已修改：`ui/components/player_panel/player_panel.gd`：新增 `set_view_player()`；高亮逻辑同时区分 current/view。
- 已修改：`ui/components/player_panel/player_info_item.gd`：新增 `set_selection(is_current,is_view)` 并按 current/view 组合渲染样式。
- 追加修复：`ui/components/left_panel/left_panel.gd`：`set_view_player()` 时刷新员工列表（调用 `_refresh_employee_icons()`），避免切换查看玩家后列表仍显示上一位玩家。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（75/75，`.godot/AllTests.log`）

**验收**

- 点击 PlayerPanel/左侧玩家 Tab 能稳定切换到对应玩家内容。
- 在 `Restructuring` 阶段可查看其它玩家；当 `view_player != current_player` 时拖拽保持禁用（不应误改他人结构）。

---

## 9. 见习厨师（kitchen_trainee）：可选择生产食物

**现象**

- 见习厨师（`kitchen_trainee`）在右侧“生产食物”流程中不出现/无法生产，导致该员工看起来“没有作用”。
- 期望：类似跑腿伙计采购饮料一样，允许玩家选择生产哪种食物（汉堡/披萨），确认后执行生产。

**涉及代码**

- `modules/base_employees/content/employees/kitchen_trainee.json`
- `core/data/employee_def.gd`
- `core/engine/game_engine/modules_v2.gd`（内容校验）
- `gameplay/actions/produce_food_action.gd`
- `ui/components/production_panel/production_panel.gd`
- `ui/scenes/game/game_panel_working_panels.gd`
- `core/tests/produce_food_test.gd`

**初步根因**

- `EmployeeDef.can_produce()` 只基于 `produces.food_type/amount` 判断；但 `kitchen_trainee` 未配置 `produces`，仅通过 `usage_tags(use:produce:burger|pizza)` 表达“多选生产”能力，导致被判定为不可生产。
- `produce_food` 动作参数仅有 `employee_type`，无法表达“生产 burger 还是 pizza”。
- 模块系统内容校验假设 `can_produce() => produces.food_type 非空`，在引入“多选生产”后需同步更新校验逻辑。

**修复方案**

- `EmployeeDef`：支持“多选生产”（从 `usage_tags` 解析 `use:produce:*`），并提供 `get_production_food_options()` 给 UI/规则使用。
- `produce_food`：对固定生产员工保持兼容；对多选生产员工要求 `food_type` 参数并校验在可选范围内（默认产量 1）。
- `ProductionPanel`（food 模式）：当员工存在 `food_options` 时显示食物选择下拉框，并把选择结果随确认一起提交。

**实施记录**

- 已修改：`core/data/employee_def.gd`：`can_produce()` 支持从 `usage_tags(use:produce:*)` 推导；新增 `get_production_food_options()`；`get_production_info()` 在多选场景返回 `food_options`。
- 已修改：`core/engine/game_engine/modules_v2.gd`：内容校验改为校验 `production_food_options[*]`（不再假设 `produces.food_type` 必填）。
- 已修改：`gameplay/actions/produce_food_action.gd`：支持可选参数 `food_type`；对 `kitchen_trainee` 等多选生产员工强制要求并校验。
- 已修改：`ui/components/production_panel/production_panel.gd`：food 模式新增“见习厨师：选择食物”下拉框；提供 `get_selected_food_type()`；确认按钮按选择状态启用。
- 已修改：`ui/scenes/game/game_panel_working_panels.gd`：执行 `produce_food` 时透传 `food_type`（若存在）。
- 已修改：`core/tests/produce_food_test.gd`：新增 `kitchen_trainee` 选择生产 burger/pizza 的覆盖测试。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（72/72，`.godot/AllTests.log`）

**验收**

- `kitchen_trainee` 会出现在“生产食物”面板可选员工中。
- 可选择生产汉堡/披萨并成功增加库存（每次 1 个）。

---

## 10. 放置餐厅提示遮挡地图导致无法点击

**现象**

- 放置餐厅/移动餐厅时，地图上方出现提示条，覆盖区域内的格子无法点击，导致部分位置无法放置。

**涉及代码**

- `ui/components/map_mode_bar/map_mode_bar.tscn`

**初步根因**

- `MapModeBar` 的透明占位节点（如 `TopSpacer`）默认 `mouse_filter` 会拦截鼠标事件；即使提示条本体设为 IGNORE，子节点仍可能成为 hovered control，导致地图区域点击事件无法落到 `MapView`。

**修复方案**

- 将提示条内部所有占位/容器节点统一设为 `mouse_filter=IGNORE`，确保不会阻断地图选点。

**实施记录**

- 已修改：`ui/components/map_mode_bar/map_mode_bar.tscn`：为 `TopSpacer/MarginContainer/VBoxContainer` 补齐 `mouse_filter=2(IGNORE)`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（72/72，`.godot/AllTests.log`）

**验收**

- 放置餐厅时，提示条覆盖区域内也可以正常点击地图选点/放置。

---

## 11. 发薪日面板首次打开超出右侧屏幕

**现象**

- 发薪日面板第一次打开时右侧部分超出屏幕范围（嵌入 RightPanel 抽屉时更明显）。

**涉及代码**

- `ui/components/payday_panel/payday_panel.gd`
- `ui/components/payday_panel/payday_panel.tscn`

**初步根因**

- `PaydayPanel.custom_minimum_size` 在嵌入 RightPanel 时仍生效，导致面板最小宽度过大。
- 薪资列表项 `SalaryItem.custom_minimum_size.x` 固定为 300，进一步推高内容最小宽度。
- `ScrollContainer.horizontal_scroll_mode=DISABLED` 会倾向于扩宽而不是出现横向滚动条，导致溢出。

**修复方案**

- 嵌入 RightPanel 时将 `custom_minimum_size` 置零，并将 `ScrollContainer.horizontal_scroll_mode` 改为 AUTO。
- 薪资列表项移除固定最小宽度（只保留高度），让布局可收缩。

**实施记录**

- 已修改：`ui/components/payday_panel/payday_panel.gd`：`set_embedded_in_right_panel()` 清零 `custom_minimum_size`；新增 `_apply_embedding_layout()` 切换横向滚动策略。
- 已修改：`ui/components/payday_panel/payday_panel.gd`：`SalaryItem.custom_minimum_size` 改为 `Vector2(0, 40)`，避免固定宽度撑爆抽屉。
- 追加修复：`ui/scenes/game/game_panel_end_panels.gd`：首次创建 `PaydayPanel` 时先 `visible=false` 再 dock 到 RightPanel，避免首帧仍以“弹窗布局”参与尺寸计算导致溢出。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（75/75，`.godot/AllTests.log`）

**验收**

- 发薪日面板首次打开在右侧抽屉中不再横向溢出，按钮可正常点击。

---

## 12. 欠薪导致无法结束发薪日但无提示

**现象**

- 发薪日（Payday）阶段点击“确认结束/下一阶段”后看似没有任何反应（仅日志出现“命令执行失败”），导致玩家以为卡死。

**涉及代码**

- `core/rules/phase/payday_settlement.gd`
- `gameplay/actions/skip_action.gd`（全员确认结束会自动推进阶段）
- `ui/scenes/game/game.gd`（`_execute_command` 失败仅写日志）
- `ui/scenes/game/game_panel_end_panels.gd`（`PaydayPanel` 打开入口）

**初步根因**

- 离开 Payday 时，`PaydaySettlement.apply()` 会在“任一玩家薪水不足且不允许欠薪”时 `Result.failure("玩家 %d 薪水不足：仍欠 $%d...")`。
- 该失败会沿 `skip/advance_phase` 返回到 UI，但 UI 目前只写 `GameLog.warn`，没有任何可见提示，也不会引导打开 `PaydayPanel` 处理欠薪。

**修复方案**

- UI 层在命令失败且满足以下条件时给出**可见提示**并引导处理：
 	- 当前仍处于 `Payday` 阶段；
 	- `result.error` 包含“薪水不足”（或其它 Payday 结算失败关键字）。
- 交互：自动打开 `PaydayPanel`，并弹出提示对话框展示失败原因（headless 测试环境不弹窗）。

**实施记录**

- 已修改：`ui/scenes/game/game.gd`：命令失败且处于 `Payday` 且错误包含“薪水不足”时，自动打开 `PaydayPanel` 并弹出确认对话框展示原因（headless 环境不弹窗）。
- 已修改：`ui/scenes/game/game.gd`：`_show_confirm()` 支持自定义按钮文案（用于“打开发薪日/知道了”）。
- 已修改：`ui/scenes/game/game_panel_controller.gd`：新增 `show_payday_panel()` 作为 `Game` 的安全入口（内部转调 `_end_panels.show_payday_panel()`）。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（72/72，`.godot/AllTests.log`）

**验收**

- 当欠薪阻塞推进时，界面会出现明确提示，并自动打开 `PaydayPanel` 供玩家解雇员工/处理薪资。

---

## 13. 点击玩家信息项后仍显示其它玩家内容

**现象**

- 在右侧 `PlayerPanel` 中点击“玩家1”后，显示内容看起来仍是“玩家2”（更像是点击不生效/只在某些区域可点）。

**涉及代码**

- `ui/components/player_panel/player_info_item.gd`
- `ui/components/player_panel/player_panel.gd`
- `ui/scenes/game/game_panel_controller.gd`（view_player 切换）

**初步根因**

- `PlayerInfoItem` 用 `PanelContainer.gui_input` 监听点击，但其内部 `HBoxContainer/Label/ColorRect` 等子控件默认 `mouse_filter` 会拦截鼠标事件，导致点击落在文本区域时不会触发父节点的 `gui_input`，从而“点击不生效”，看起来像“玩家对不上”。
- 经全局搜索，`state.players` 在运行时没有被排序/重排的写入点；更可能是 UI 点击链路问题而非玩家数组顺序改变。

**修复方案**

- 将 `PlayerInfoItem` 内部子控件统一设置为 `mouse_filter=IGNORE`，确保整个条目区域都由 `PlayerInfoItem` 接收点击并发出 `item_clicked(player_id)`。

**实施记录**

- 已修改：`ui/components/player_panel/player_info_item.gd`：将条目内部 `HBoxContainer/Label/ColorRect` 的 `mouse_filter` 设为 `IGNORE`，确保点击任意区域都能触发父节点 `gui_input` 并发出 `item_clicked(player_id)`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（72/72，`.godot/AllTests.log`）

**验收**

- 点击玩家信息项任意区域都能稳定切换 view_player，显示内容与所选玩家一致。

---

## 14. 重组阶段手牌区/在岗员工显示“混合两名玩家”

**现象**

- 重组阶段（Restructuring）打开公司结构重组界面时，手牌区的“在岗员工”显示不正常：看起来像混合了两名玩家的员工（切换查看玩家后残留上一位玩家的卡牌）。

**涉及代码**

- `ui/components/hand_area/hand_area.gd`
- `ui/components/employee_card/employee_card.gd`

**根因**

- `HandArea` 之前用 `_cards: Dictionary` 以 `employee_id -> EmployeeCard` 追踪卡牌并在重建时仅释放 `_cards.values()`。
- 但本项目员工是“类型字符串数组”，允许同一类型出现多次（例如 `["recruiter", "recruiter"]`）。字典 key 冲突会覆盖引用，导致部分旧卡牌**不在字典里**，从而在 `_rebuild_cards()` 时漏释放，切换玩家后就会残留在容器里，表现为“混合显示”。

**修复方案**

- 将 `_cards` 改为“保存所有卡牌实例”的数组，并在 `_rebuild_cards()` 中直接清空三个容器子节点，避免重复类型导致的漏释放。
- 同时拖拽信号改为 `bind(card)`，确保拖拽来源卡牌与视觉一致（避免重复类型时拖拽选中错误卡牌）。

**实施记录**

- 已修改：`ui/components/hand_area/hand_area.gd`：`_cards` 改为 `Array[EmployeeCard]`；新增 `_clear_container_children()`；重建时清空容器；拖拽信号 `bind(card)` 并透传 source card。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（74/74，`.godot/AllTests.log`）
- 新增回归测试：`HandAreaViewSwitchTest`（覆盖“重复 employee_id 切换玩家会残留卡牌”）

**验收**

- 重组阶段切换查看玩家后，手牌区/在岗员工不再残留上一位玩家的卡牌，不会出现“混合两名玩家员工”的错觉。

---

## 19. 存档加载提示“无效的 initial_state”

**现象**

- 已有存档加载时提示：`无效的 initial_state`（例如 `GameState.players[0].cash 类型错误（期望 int）`）。
- 同一局面 `save_to_file -> load_from_file` 后，`GameState.compute_hash()` 可能不一致（整值 float vs int 的 JSON 表现差异）。

**涉及代码**

- `core/engine/game_engine/archive.gd`
- `core/engine/game_engine/loader.gd`
- `core/state/game_state.gd`
- `core/state/game_state_serialization.gd`
- `ui/components/replay_player/replay_player.gd`
- `core/tests/archive_file_roundtrip_test.gd`
- `ui/scenes/tests/all_tests.gd`

**根因**

- Godot `JSON.parse_string()` 会把 JSON 数字全部解析成 `float`。
- `GameStateSerialization.apply_from_dict()` 对 `players` 只做了“数组/字典”层级校验，没有对 `cash/inventory/...` 等字段进行严格解析/类型归一化，导致从存档加载后玩家字段仍是 `float`，被引擎不变量校验拒绝。
- 同时，部分运行时数据（以及从 JSON 数据源进入 state 的字段）可能携带“整值 float”，在 `JSON.stringify` 时会输出 `3.0` 而不是 `3`，造成哈希在 roundtrip 前后不稳定。
- 另外，部分 `Vector2i` 字段在 `JSON.stringify` 时会退化为字符串（例如 `marketing_instances[*].world_pos` 变成 `"(x, y)"`），加载后若不反序列化会在 UI/规则层触发类型错误。

**修复方案**

- 存档读入时对解析结果做一次“整值 float -> int”的深度归一化（不改变真正的小数）。
- 计算 `GameState.compute_hash()` 时同样做“整值 float -> int”的归一化，保证回放/校验点/文件 roundtrip 的哈希稳定。
- 增加回归测试覆盖 `save_to_file/load_from_file` roundtrip，避免后续改动回归。
- 回放加载失败时在 UI 中显示可见错误文案（避免仅 tooltip 难发现）。

**实施记录**

- 已修改：`core/engine/game_engine/archive.gd`：`load_archive_from_file()` 返回前对解析结果做 `_normalize_json_numbers()`（整值 float -> int）。
- 已修改：`core/state/game_state.gd`：`compute_hash()` 计算前对 `to_dict()` 结果做 `_normalize_json_numbers()`（整值 float -> int）。
- 已修改：`core/state/serialization/value_decoder.gd`：补齐 `map_origin` 的 Vector2i 反序列化（避免存档加载后 `ui/scenes/game/map_canvas.gd` 读取时报 “Array -> Vector2i” 类型错误）。
- 已修改：`core/state/serialization/value_decoder.gd`：支持将 `"(x, y)"` / `Vector2i(x, y)` 字符串解析回 `Vector2i`（用于兼容旧存档/非 map 字段的 Vector2i 表示）。
- 已修改：`core/state/game_state_serialization.gd`：对 `marketing_instances` 做 ValueDecoder 解码，确保 `world_pos` 等字段回读为 `Vector2i`。
- 新增：`core/tests/archive_file_roundtrip_test.gd`：覆盖文件 roundtrip + hash 稳定性。
- 已更新：`core/tests/archive_file_roundtrip_test.gd`：增加 `map_origin/grid_size/tile_grid_size/tile_placements[0].board_pos/marketing_instances[0].world_pos` 的 Vector2i 类型断言。
- 已修改：`ui/scenes/tests/all_tests.gd`：加入 `ArchiveFileRoundtripTest`。
- 已修改：`ui/components/replay_player/replay_player.gd`：加载失败时显示 `_error_label`，并在开始加载前清理旧错误。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（76/76，`.godot/AllTests.log`）

**验收**

- 使用现有测试存档加载不再出现“无效的 initial_state”。
- `save_to_file -> load_from_file` 的 roundtrip 不再引入 hash 差异（至少对整值 float/int 的表现差异保持稳定）。

---

## 20. 重组阶段公司结构需展示为树（管理岗像 CEO，有槽位）

**现象**

- 重组阶段中，CEO 下属槽位可拖拽，但管理岗（如管理培训生）下属区仅显示“列表”，无法用“卡槽”表达公司树结构，也不利于拖拽放置。
- 当 CEO 槽位较多时，结构横向可能超出容器（尤其在重组 Modal 中）。

**涉及代码**

- `ui/components/company_structure/company_structure.tscn`
- `ui/components/company_structure/company_structure.gd`
- `ui/scenes/game/game_panel_controller.gd`（拖拽落点分派：`company_structure_reports_drop_target` / `company_structure_direct_slot`）

**修复方案**

- 将“经理下属列表”替换为“下属卡槽”（每个管理岗按 `manager_slots` 显示对应数量的 `CardSlot`），形成 CEO -> 直属 -> 下属 的树形展示。
- 为 CEO 直属槽位区域增加横向滚动（ScrollContainer），避免槽位多时溢出容器。
- 复用现有拖拽分派：下属卡槽继续加入 `company_structure_reports_drop_target` group 并设置 `manager_slot_index/manager_employee_id` meta，保持 `GamePanelController._on_hand_card_dropped()` 逻辑不变。

**实施记录**

- 已修改：`ui/components/company_structure/company_structure.tscn`：为 `ManagerContainer` 增加 `ManagerScroll(ScrollContainer)`，支持横向滚动。
- 已修改：`ui/components/company_structure/company_structure.gd`：
	- 移除 `ReportsDropTarget(列表)`，改为为每个管理岗动态生成 `cap=manager_slots` 个下属 `CardSlot`。
	- 每个下属 `CardSlot` 加入 `employee_card_drop_target` 与 `company_structure_reports_drop_target` group，并写入 meta：`manager_slot_index/manager_employee_id/report_slot_index`。
	- 下属槽位使用 `EmployeeCard` 展示已分配员工，并接入同一套拖拽视觉逻辑（可拖回手牌区/拖到其它槽位）。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（76/76，`.godot/AllTests.log`）

**验收**

- 重组阶段公司结构展示为树：管理岗下方显示可交互的下属卡槽（非列表）。
- CEO 槽位较多时可横向滚动查看，不再超出容器。

---

## 21. 加载存档后日志面板为空/消失

**现象**

- 从主菜单加载存档进入游戏后，LeftArea 的事件日志面板内容为空（看起来像“日志消失”）。

**涉及代码**

- `core/engine/game_engine/loader.gd`（存档回放：`execute_command(cmd, true)`）
- `core/events/event_bus.gd`（事件历史）
- `ui/scenes/menus/main_menu.gd`（主菜单加载存档入口）
- `ui/scenes/game/game.gd`（GameScene 初始化顺序）
- `ui/scenes/game/game_event_log_controller.gd`
- `ui/components/game_log/game_log_panel.gd`
- `ui/scenes/tests/log_restore_after_load_test.gd`

**根因**

- `GameLogPanel` 只在内存中维护 `_entries`，本身不会持久化到存档。
- 存档加载时 `GameEngine.load_from_file()` 会先回放命令恢复到存档状态（发生在进入 `GameScene` 之前），此时 UI 还未订阅 `EventBus`，导致回放阶段发射的事件没有被写入日志面板。
- 进入 `GameScene` 后，`GameEventLogController.setup()` 会先 `clear_logs()`，并仅订阅“未来发生的事件”，未从 `EventBus.get_history()` 做恢复，因此表现为“日志为空”。
- 另外如果不清理 `EventBus.history`，从上一次对局残留的历史会污染下一局的“恢复结果”。

**修复方案**

- 将日志恢复的“数据源”定义为 `EventBus.history`（由存档回放自动生成），在 `GameEventLogController.setup()` 时按白名单事件类型恢复，并在完成后再订阅新事件。
- 在开始新游戏/加载存档前清空 `EventBus.history`，避免跨对局污染。
- 增加 headless 回归测试，模拟“先发射事件，再 setup 日志控制器”的加载顺序，断言日志会被恢复，且不会把 `command_executed` 这种噪声事件恢复进面板。

**实施记录**

- 已修改：`ui/scenes/menus/main_menu.gd`：加载存档前 `EventBus.clear_history()`，避免旧对局历史污染。
- 已修改：`ui/scenes/game/game.gd`：进入 GameScene 时，若不是“复用已载入引擎”则清理 `EventBus.history`；并将 `GameEventLogController.setup(game_log_panel, should_restore_history)` 与存档载入场景关联。
- 已修改：`ui/scenes/game/game_event_log_controller.gd`：
	- 增加 `EVENT_TYPES_TO_LOG` 白名单；
	- `setup(..., restore_history=true)` 时从 `EventBus.get_history()` 恢复对应事件并写入 `GameLogPanel`。
- 已修改：`ui/components/game_log/game_log_panel.gd`：自动滚动改为 `call_deferred`（避免批量恢复时每条 `await process_frame` 导致卡顿/潜在时序问题）。
- 新增：`ui/scenes/tests/log_restore_after_load_test.gd`：覆盖“存档加载后日志恢复”回归。
- 已修改：`ui/scenes/tests/all_tests.gd`：加入 `LogRestoreAfterLoadTest`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（77/77，`.godot/AllTests.log`）

**验收**

- 从主菜单加载存档进入游戏后，日志面板能看到回放恢复出的历史事件（至少包含阶段变化/招聘/训练等），不再为空。
