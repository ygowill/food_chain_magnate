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
| 22 | 多餐厅：飞艇驾驶员采购饮料起点应由玩家选择 | UI/流程+规则 | UI 侧 `_resolve_procure_restaurant_and_entrance()` 固定取排序后的首家餐厅；且 `_auto_select_air_start_tile()` 会强制把“第一格”设为该餐厅板块 | Implemented（待手动验收） |
| 23 | UI 配色：营销板背景/空地背景/可用点提示色 | UI/视觉 | 多处硬编码颜色/贴图：营销板使用深色占位；地图地面使用纹理；可用点高亮使用绿色，需统一替换 | Implemented（待手动验收） |
| 24 | 重组阶段拖拽员工卡：拖拽预览会变形 | UI/交互 | 拖拽预览卡用 `EmployeeCard.new()` 重建，未复制源卡的缩放/变体；且 `setup()` 会重置 `custom_minimum_size`，导致预览尺寸与缩略卡不一致 | Implemented（待手动验收） |
| 25 | 重组界面：全屏覆盖；左侧仅待命卡；三列滚动；右侧公司树满宽；多管理槽下属卡槽改为网格 | UI/重构 | `ModalPanelBase` 设计为“不遮挡左侧信息区”；`HandArea` 默认显示在岗/待命/忙碌；`CompanyStructure` 下属槽位纵向堆叠导致高度溢出 | Implemented（待手动验收） |
| 26 | 招聘/培训等面板统一复用员工缩略卡（EmployeeCard） | UI/一致性 | Recruit/Train 等面板各自实现了 PoolCard/TrainableCard/OptionButton 文本，导致表现不一致、维护分散 | Implemented（待手动验收） |
| 27 | 地图高亮/覆盖机制统一：边框 + 透明层覆盖完整 piece | UI/渲染 | 当前存在多套：cell 选中框、cell_highlights、structure_preview、MarketingRangeOverlay 等；且房屋“被覆盖”只高亮锚点格 | Implemented（待手动验收） |
| 28 | 移动餐厅：餐厅选项改为可阅读；切换时高亮当前餐厅 | UI/交互 | move_restaurant 下拉框仅显示 `rest_0` 等 id；地图餐厅无 id/编号标记；现高亮逻辑只显示“可放置锚点”，未高亮被选餐厅 | Implemented（待手动验收） |
| 29 | 营销面板遮挡；营销放置缺少形状预览；营销图标大小需适配 piece | UI/布局+渲染 | 右侧抽屉嵌入时布局/裁剪导致左侧内容被遮挡；地图交互仅高亮 anchor 未显示 footprint；地图渲染中营销图标缩放策略不匹配多格 board | Implemented（待手动验收） |
| 30 | 飞机营销板件：应贴地图外侧边缘且不在地图内；可用宽度仅 1/3/5 | UI/规则+渲染 | 当前飞机按普通营销板件在地图内绘制/占地，且尺寸来自现有 `footprint_size`（含 2x1/3x2/5x2 等），与目标规则不一致 | Implemented（待手动验收） |
| 31 | 关闭“点击地图格高亮” | UI/一致性 | `MapCanvas` 记录 `_selected_pos` 且 `MapCanvasDrawer._draw_selection()` 绘制蓝色选中框 | Implemented（待手动验收） |
| 32 | 地图渲染：tile 内部细分网格线（细线）与 tile 外边缘粗线一起绘制 | UI/渲染 | `MapCanvasDrawer._draw_tile_borders()` 目前仅绘制 tile 外边缘粗线，未绘制 tile 内部单元格分割线 | Implemented（待手动验收） |
| 33 | 营销板件数据修复：piece 命名/类型/尺寸对齐真实数据 | 数据/规则 | `base_marketing` 的板件定义与真实数据不一致（radio/airplane/mailbox/billboard 的编号与 footprint_size 错配） | Implemented（待手动验收） |
| 34 | 营销面板：选择员工的缩略卡高度不足，导致与下方板件区重叠 | UI/布局 | `EmployeePickerItem` 未提供稳定最小高度，FlowContainer 行高计算偏小导致下方区被覆盖 | Implemented（待手动验收） |
| 35 | 营销板件：禁止覆盖饮料进货点；可选点高亮需剔除 | 规则+UI | 可选点计算未排除覆盖 `drink_source` 的 anchors | Implemented（待手动验收） |
| 36 | 营销板件：点击选点时地图显示半透明预览；放置后不透明；去掉边框 | UI/交互+渲染 | 仅高亮 anchor，未走 structure_preview；营销板件绘制仍带边框/透明度不一致 | Implemented（待手动验收） |
| 37 | 营销板件：地图/按钮预览显示序号徽标（白底圆+黑字） | UI/渲染 | 营销板件未复用房屋编号徽标绘制；MarketingBoardButton 预览未显示编号 | Implemented（待手动验收） |
| 38 | 飞机营销：可选点应显示为地图外一圈（且仅在飞机模式显示） | UI/交互 | highlights 仍使用地图内 anchor；外圈映射与显示模式未区分 | Implemented（待手动验收） |
| 39 | 重组：CEO 下方员工槽不可见 | UI/布局 | CompanyStructure 纵向布局/最小高度不足导致 CEO slots 被裁剪 | Implemented（待手动验收） |
| 40 | 飞机营销：仅允许 1/3/5 长度贴边；外圈仅飞机模式显示且无背景；外圈包含 external_cells | 规则+UI | airplane 规则/外圈渲染与外部格处理不一致；外圈背景被误填充 | Implemented（待手动验收） |
| 41 | 重组：左侧员工面板过宽；仍看不到 CEO 下属槽（需定位根因） | UI/布局 | SplitContainer/HandArea 最小宽度与 split_offset 语义误用导致左侧过宽；CEO slots 与裁剪叠加 | Implemented（待手动验收） |
| 42 | 飞机营销：放置不受道路/距离影响；可用点全边可选；影响范围为跨全图条带（宽=1/3/5） | 规则+UI | airplane 被错误套用“道路连接/距离/range”校验；影响范围未按条带覆盖整图 | Implemented（待手动验收） |
| 43 | 营销放置：点击选点后预览固定，不再跟随鼠标，直到确认/取消 | UI/交互 | 放置流程把“hover anchor”当作最终目标，点击后仍持续更新 preview | Implemented（待手动验收） |
| 44 | 重组结构：CEO 直属槽可见；管理岗员工卡不随下属槽拉宽（保持 compact 且居中） | UI/布局 | 右侧树布局用 `HFlowContainer` 导致卡片被拉伸；CEO slots 未正确参与布局 | Implemented（待手动验收） |
| 45 | 重组结构：左侧员工卡牌区域宽度收敛到“三列 compact 卡”所需宽度 | UI/布局 | `HSplitContainer.split_offset` + HandArea 最小宽度导致左侧偏宽 | Implemented（待手动验收） |
| 46 | 重组结构：拖回待命区 drop 区域过小（仅左上角可成功） | UI/交互 | drop target 仅覆盖 reserve_container 的一部分；ScrollContainer 空白区域不命中 | Implemented（待手动验收） |
| 47 | 飞机营销：图标需随摆放方向旋转（长边为底） | UI/渲染 | `_draw_marketing_placement()` 始终按轴对齐绘制纹理，导致左右边贴时飞机图标横向被压缩 | Implemented（待手动验收） |
| 48 | 游戏日志：房屋被打上广告缺日志；采购日志缺路线；需要可读性方案 | UI/信息架构 | 缺少 MarketingSettlement/路线等结构化事件；现有日志仅平铺文本，难在“不刷屏”和“可追溯细节”间平衡 | Implemented（待手动验收） |
| 49 | 提供“日志验证”测试存档（便于手工审查日志改动） | 测试/工具 | 现有 manual_cases 会冻结命令历史，无法承载“回放产生事件→复核日志”的场景 | Implemented（待手动验收） |
| 50 | 日志验证存档：尽可能覆盖更多日志事件类型（便于集中审查） | 测试/工具 | 现有 `logs/event_log_review` 覆盖面有限，难以一次性审查招聘/培训/解雇/餐厅/花园/生产/里程碑等日志 | 待澄清 |
| 51 | 晚餐结算日志过噪：包含冗余统计/拆分信息 | UI/日志 | `_log_dinnertime_report` 中为诊断添加的“总计/拆分/按产品”日志已不需要；用户已临时注释，需移除冗余代码并清理无用计算 | Implemented（待手动验收） |
| 52 | 培训日志缺少“培训员来源”（trainer/coach/guru） | UI/日志 | `EMPLOYEE_TRAINED` 事件数据未携带 trainer_id/instance/steps，日志只能显示 from->to | Implemented（待手动验收） |
| 53 | 决定顺序阶段缺少最终顺序结果日志 | UI/日志 | OrderOfBusiness 完成后未发射“最终 turn_order”事件；日志仅能看到阶段推进 | Implemented（待手动验收） |
| 54 | 游戏日志默认应隐藏阶段信息 | UI/日志 | `GameLogPanel` 默认 `_filter_types` 包含 `PHASE`，导致 phase/subphase/回合等信息默认刷屏 | Implemented（待手动验收） |
| 55 | Payday 阶段缺少结算日志（仅现金变化） | UI/日志 | `PaydaySettlement` 写入 `round_state.payday`，但未发射类似 `DINNERTIME_REPORT` 的汇总事件；日志只看到 `PLAYER_CASH_CHANGED` | Implemented（待手动验收） |
| 56 | 冰箱容量规则错误（应总量 10）+ Cleanup 冰箱选择流程缺失 | 规则+UI+测试 | `CleanupSettlement` 当前“每种各自限幅”；且 Cleanup 被 auto-skip，无法弹窗让玩家选择保留哪些食物/饮料 | Implemented（待手动验收） |
| 57 | 员工行动用尽后：员工卡应灰显且不可点击（多次行动员工例外） | UI/交互 | UI 未按子阶段用量（`production_counts/procurement_counts/...`）刷新卡片 enabled；且 `EmployeeCard.set_busy()` 仅改样式不阻止输入 | 待实施（已澄清） |
| 58 | 玩家数据面板：里程碑 tab 样式不统一且左右溢出 | UI/布局 | `MilestonePanel` 作为独立面板自带 Background/Margin/custom_minimum_size，嵌入 `LeftPanel.TabContainer` 后出现双层背景/最小宽度推高/溢出 | 待澄清 |
| 59 | 距离工具：提示/结果与顺位重叠；交互需优化（点任意道路格重开；结果放终点上方；起点高亮） | UI/交互 | `DistanceOverlay` 结果用 Label 无背景且定位在中点；`distance_tool` 状态机需点起点才能重置；未对起点做高亮提示 | 待实施（已澄清） |
| 60 | 设置：移除经典 UI 布局选择，只保留新布局并清理旧布局代码 | UI/架构 | `ui_layout_version` 贯穿 Settings/Game/GamePanelController 等大量分支；旧布局入口与节点仍存在 | 待实施（已确认） |
| 61 | 左侧玩家信息面板拖拽调整宽度卡住（无法缩小/到达上限后无法再调） | UI/布局 | `Game` 对 split_offset 做 `[MIN,MAX]` clamp 且把 `LeftArea.custom_minimum_size.x` 设为当前宽度，导致最小宽度被抬高 + MAX=400 限制拉伸 | 待确认 |
| 62 | 折扣经理：无法结束回合（疑似强制动作未自动触发/Skip 在动作面板被禁用） | 规则+UI 流程 | `ActionRegistry.get_player_initiatable_actions()` 以 `SkipAction.validate` 判定可点；强制动作未完成时 skip 校验失败导致按钮灰；而 `set_discount` 又被隐藏且仅 UI 层尝试 auto-run -> 形成死锁 | 待实施（已复现） |
| 63 | 上方工具栏移除“确认结束/调试”按钮 | UI/清理 | `Game.tscn` TopBar 仍保留旧入口；功能与 ActionPanel/DebugPanel 重复 | 待确认 |
| 64 | 地图外圈不可见格导致地图缩小：外圈为空时应放大，只有需要/已有外圈 piece 才完整显示 | UI/交互+渲染 | `MapCanvasIndexer.compute_bounds()` 无条件添加 UI-only margin=2 外圈；`MapView.fit_to_view()` 基于 `_grid_size` 导致整体缩小；需可切换 bounds/margin 并与现有缩放/auto-fit 协同 | 待实施（已澄清） |

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

---

## 22. 多餐厅：飞艇驾驶员采购饮料起点应由玩家选择

**现象**

- 玩家可能拥有多家餐厅；在 Working/GetDrinks 使用飞艇驾驶员采购饮料时，路线的第一个板块（起点餐厅板块）被 UI 强制为“排序后第一家餐厅”，玩家无法选择从哪家餐厅出发。

**涉及代码**

- `ui/scenes/game/game_panel_working_panels.gd`：`_auto_select_air_start_tile()` / `_resolve_procure_restaurant_and_entrance()` / `_recompute_procurement_plan()`
- `core/rules/drinks_procurement/start_restaurant_resolver.gd`：核心侧已支持从 route 起点反推餐厅，或在歧义时要求显式 `restaurant_id`

**初步根因**

- UI 为了确定性，直接对 `restaurant_ids.sort()` 后取第一家作为 `chosen_restaurant_id`，并在飞艇模式下自动把 `_procure_selected_tiles[0]` 设为该餐厅的 `entrance_tile`。
- 这在“多餐厅”场景下等价于把起点写死，违背“玩家应选择从哪家店出发”的交互预期。

**确认（来自你的说明 #22）**

- 交互选择 A：玩家在地图上先点击某一家餐厅所在板块作为第一格（起点），再继续选相邻板块。
- 仅覆盖飞艇驾驶员（不需要覆盖手推车/卡车采购）。

**修复方案**

- 改为“起点由玩家选择”：当处于飞艇采购且 `_procure_selected_tiles` 为空时，允许玩家选择任意属于自己的餐厅板块作为第一格，并据此解析 `restaurant_id/entrance_pos`。
- 仅当玩家只有 1 家餐厅时，才允许保留当前的自动起点行为（减少操作）。
- UI 组装 `procure_drinks` 命令时，优先使用“玩家选中的餐厅”；或直接依赖 core 的 `StartRestaurantResolver` 由 route 起点推导（如无歧义）。

**验收**

- 多餐厅时，飞艇采购的第一格不再被强制固定；玩家可明确选择从哪家餐厅出发，且后续校验/预览/执行一致。

**实施记录**

- 已修改：`ui/scenes/game/game_panel_working_panels.gd`：飞艇采购在“未选第一格”时改为高亮“所有自有餐厅所在 tile”作为合法起点；只有 1 家餐厅时才自动选起点。
- 已新增：`ui/scenes/tests/air_procure_start_tile_choice_test.gd`：覆盖“多餐厅不自动锁定起点，且起点 tiles 列表正确”。
- 已修改：`ui/scenes/tests/all_tests.gd`：加入 `AirProcureStartTileChoiceTest`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（88/88，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 57.（用户反馈 1）员工行动用尽后：员工卡应灰显且不可点击（多次行动员工例外）

**现象**

- 员工执行完本回合/本子阶段的可用行动后，相关 UI 上的“员工卡牌”仍保持可点状态；继续点击会走到校验失败（或产生误导）。
- 例：厨师生产完食物后，卡牌应变灰并不可点击。
- 例：guru 等一回合可多次行动的员工，在行动次数用完前应保持可用状态。

**当前实现观察（可定位的事实）**

- `ui/components/employee_card/employee_card.gd`：`set_busy()` 仅改变 style/modulate；`_on_gui_input()` 不检查 `_busy`，仍会发射 `card_clicked`。
- `ui/components/production_panel/production_panel.gd`：生产/采购面板的员工选择用 `EmployeePicker` 展示，但 `enabled` 始终为 true、角标为“员工数量”，未扣除已用次数。
- gameplay 侧已有“子阶段用量”数据：
	- `state.round_state.production_counts`（`produce_food`）
	- `state.round_state.procurement_counts`（`procure_drinks`）
	- `state.round_state.marketing_used` / `players[*].busy_marketers`（营销发起）
	- `state.round_state.train_slot_usage_instances`（trainer/coach/guru 多步培训 slot 使用）

**初步根因**

- UI 没有把“剩余可用次数”作为一等数据源来驱动 `EmployeePickerItem.enabled` / `EmployeeCard` 灰显；并且上游（如 `show_production_panel()`）传入的 `available_producers` 只是“拥有该员工”的列表，不包含“已用/剩余”的扣减信息。
- `EmployeeCard` 的 busy/disabled 仅做视觉，不做交互禁用。

**建议方案（偏保守，先做可验证的最小闭环）**

- 需求包含“同类型多张卡逐张消耗/灰显”，因此员工选择 UI 不能仅按 `employee_type -> count` 聚合；需要支持“按实例渲染/选择”，并在动作执行成功后把“本次选中并使用的那一张”标记为已用。
- 我倾向优先覆盖动作面板中会“选择员工”的面板：
	- `ProductionPanel`（生产/采购）：执行成功后灰显并禁用本次选中的那一张；若仍有同类型未用卡则仍可继续。
	- `RecruitPanel` / 其它类似“选择员工/来源”的面板：同理（若存在多张同类型候选卡）。
- 交互禁用落地两种选择：
	- A）仅在 `EmployeePickerItem` 层禁用（通过 mouse_filter + modulate），避免动 `EmployeeCard` 的基础行为；
	- B）给 `EmployeeCard` 增加“disabled”语义（busy/disabled 分离），统一处理 hover/cursor/click/drag（改动面更大）。

**澄清（来自用户）**

- 范围：动作面板中使用“招聘/生产食物/采购饮料”等动作时，在对应面板里用于“选择员工”的卡牌。
- 重复员工：若有 2 个厨师，生产一次后应灰显并禁用“本次选中并使用的那一张”。

**验收标准**

- 在动作面板的员工选择卡中：每次执行成功后，只灰显并禁用“本次选中并使用的那一张”；若同类型仍有未用卡则保持可用。
- 多次行动员工：在行动次数用尽前保持可用；用尽后灰显禁用。

---

## 58.（用户反馈 2）玩家数据面板：里程碑 tab 样式不统一且左右溢出

**现象**

- 玩家数据面板中的“里程碑”tab 样式与“员工”tab 不统一。
- 里程碑内容在左右两侧会超出玩家面板边界。

**涉及代码**

- `ui/components/left_panel/left_panel.tscn`：`TabContainer/Milestones/MilestonePanel`（嵌入式展示）
- `ui/components/milestone_panel/milestone_panel.tscn` / `ui/components/milestone_panel/milestone_panel.gd`

**初步根因**

- `MilestonePanel` 作为独立弹窗/右侧面板组件自带：
	- `Background(ColorRect)` + `MarginContainer(16px)` + `TitleLabel` + `custom_minimum_size=Vector2(280,260)`
	- `ScrollContainer.horizontal_scroll_mode=DISABLED`
- 当它被直接嵌入 `LeftPanel.TabContainer` 时，会出现“与 LeftPanel 自身背景/边距叠加”的样式不一致，并可能因 `custom_minimum_size` / horizontal_scroll_mode 策略导致横向溢出。

**建议方案**

- 为 `MilestonePanel` 增加明确的“嵌入 LeftPanel 模式”（类似右侧嵌入的处理）：
	- 关闭/隐藏自身 Background/Title、将 margin 收敛到与 Employees tab 一致；
	- 嵌入时将 `custom_minimum_size` 归零，并确保 `ScrollContainer.horizontal_scroll_mode=AUTO`（至少不要为了禁止横向滚动而强行撑宽）。

**待澄清**

- 里程碑 tab 的目标样式：是否应完全复用 LeftPanel 的背景（里程碑面板自身不再画背景），并去掉 “里程碑”标题行？
- 你更偏好：允许出现横向滚动条（极端小屏）还是强制换行/截断？

**验收标准**

- 里程碑 tab 的背景/边距/标题风格与员工 tab 统一；内容不再左右溢出玩家面板。

---

## 59.（用户反馈 3）距离工具：提示/结果与顺位重叠；交互需优化（点任意道路格重开；结果放终点上方；起点高亮）

**现象**

- 测距结果/提示信息可能与玩家顺位（顶部顺序轨/信息）重叠，叠加后难以看清；需要背景提升可读性。
- 当前需要重新点击起点取消起点，才能开始下一次测距；你希望“测距结束后点击任意道路格即可重新开始”。
- 测距结果目前显示在起点与终点中心，难以寻找；应显示在终点上方，并增加背景与地图区分。
- 起点选中后道路格无视觉变化，玩家难以确认是否已选中；需高亮提示。

**涉及代码**

- `ui/scenes/game/game_map_interaction_controller.gd`：`distance_tool` 状态机（`_distance_tool_from`）
- `ui/overlays/distance_overlay.gd`：结果 label 的生成与定位（目前用中心点 + outline）
- `ui/scenes/game/map_canvas.gd` / `ui/scenes/game/map_canvas_drawer.gd`：cell_highlights 绘制能力（可用于起点高亮）

**初步根因**

- `DistanceOverlay` 仅使用 Label 的 outline，缺少背景容器；且定位逻辑固定为“起点+终点的中点”。
- `distance_tool` 交互状态只支持“再次点击起点清除”，不支持“完成后任意点击重置为新起点”。
- 起点未通过 `MapCanvas.set_cell_highlights()` 或 overlay 表达，因此缺少反馈。

**建议方案**

- 结果 label 改为“带背景的控件”（例如 PanelContainer+Label），并改定位到终点上方（必要时做屏幕边缘避让）。
- `distance_tool` 状态机改为三态：未选起点 -> 已选起点 -> 已测距完成；在“已测距完成”态下点击任意道路格将其设为新起点并清空旧 overlay。
- 起点选中后立刻高亮（例如对起点 cell 设置 highlights 或单独的 piece_overlay id）。
- 起点/终点选择限制为“道路格”：非道路格点击无效（不产生“无法连接”结果）。

**澄清（来自用户）**

- 只允许点道路格。
- 每次只测一段；测完后点击任意道路格就会重新开始测距。

**验收标准**

- 测距结果与提示信息在任何位置都可读（有背景，不被顺位/地图背景吞没）。
- 测距完成后点击任意道路格能立即开始下一次测距（无需先点回起点取消）。
- 起点选中后有明显高亮提示；结果显示在终点上方。

---

## 60.（用户反馈 4）设置：移除经典 UI 布局选择，只保留新布局并清理旧布局代码

**现象**

- 设置中仍可选择“经典 UI 布局”（`ui_layout_version`），你希望去掉该选择，仅保留新布局，并清理旧布局相关代码。

**涉及代码（初步）**

- `ui/dialogs/settings_dialog.gd` / `ui/dialogs/settings_dialog.tscn`：`ui_layout_version` 的读写与选项 UI
- `ui/scenes/game/game.gd`：`Globals.ui_layout_version` 分支（布局装配/面板挂载）
- `ui/scenes/game/game_panel_controller.gd`：多处 `layout_version != 2` 的兼容分支
- 其它按 `rg "ui_layout_version"` 继续收敛

**初步根因**

- 新旧布局并行导致大量 if/else 分支与“旧入口节点”（例如 TopBar 的按钮、旧面板挂载逻辑）长期共存。

**建议方案**

- 先把“新布局=唯一入口”定为硬约束：
	- Settings 中移除 UI 布局选择项；启动时强制 `Globals.ui_layout_version=2`（并忽略/清理旧配置）。
- 再逐步删除旧布局专用节点/分支（以可运行/可测试为前提，小步提交）。

**澄清（来自用户）**

- 不需要兼容：强制切到 2，并清理旧值相关的代码/配置读写逻辑。

**验收标准**

- 设置中不再出现 UI 布局选择；游戏始终使用新布局；旧布局相关代码/入口被清理且不影响现有功能。

---

## 61.（用户反馈 5）左侧玩家信息面板拖拽调整宽度卡住（仅希望设置最小宽度）

**现象**

- 左侧玩家信息面板无法缩小；可以向右拉伸，但拉伸到一定距离后无法继续拉长或缩窄。
- 你只希望设置一个最小宽度。

**涉及代码**

- `ui/scenes/game/game.gd`：`_on_main_content_dragged()` / `LEFT_AREA_MIN_WIDTH/LEFT_AREA_MAX_WIDTH`
- `ui/scenes/game/game.tscn`：`UIRoot/MainContent(HSplitContainer)` 与 `LeftArea.custom_minimum_size`

**初步根因（可从代码直接解释现象）**

- `_on_main_content_dragged()` 将 split_offset clamp 到 `[LEFT_AREA_MIN_WIDTH, LEFT_AREA_MAX_WIDTH]`（当前 MAX=400），导致“拉到一定距离后无法再拉长”。
- 同时它把 `LeftArea.custom_minimum_size.x` 设置为当前 clamped 值，等价于“把最小宽度抬到当前宽度”，因此一旦拉宽就无法再缩回去。

**建议方案**

- 仅保留最小宽度约束：去掉 MAX clamp；并且不要把 `LeftArea.custom_minimum_size.x` 设置为当前宽度，而是保持为固定的 `LEFT_AREA_MIN_WIDTH`（或不强设，交给子控件的 min size）。

**验收标准**

- 左侧面板可自由拖拽变宽/变窄；不会在某个宽度后“卡死”；且最小宽度符合预期。

---

## 62.（用户反馈 6）折扣经理：无法结束回合（疑似强制动作未自动触发/Skip 在动作面板被禁用）

**现象**

- 玩家拥有/使用折扣经理时，无法结束回合（推进 Working 回合/阶段）。
- 你怀疑折扣经理的强制行动未自动触发，导致阶段无法推进。

**涉及代码（初步）**

- `gameplay/actions/skip_action.gd`：Working 最后子阶段会校验强制动作（未完成则拒绝 skip）
- `gameplay/actions/set_discount_action.gd`：折扣经理强制动作（`set_discount`）
- `ui/scenes/game/game.gd`：`_maybe_auto_complete_mandatory_actions_before_skip()`（仅 UI 层在执行 skip 前自动补齐强制动作）
- `core/actions/action_registry.gd`：`get_player_initiatable_actions()`（ActionPanel 是否可点由 validate 决定）
- `ui/components/action_panel/action_panel.gd`：按钮 enabled 依赖 “initiable actions”

**初步根因（高概率）**

- `ActionPanel` 通过 `ActionRegistry.get_player_initiatable_actions()` 计算按钮是否可点；该逻辑会直接 `validate(skip)`。
- `SkipAction.validate()` 在 Working 最后子阶段若存在未完成强制动作会返回 failure（例如缺少 `set_discount`）。
- 同时 `set_discount` 又被 `ActionPanel` 隐藏（不展示给玩家点），且目前“自动执行强制动作”仅发生在 UI 的 `_execute_command(skip)` 前。
- 结果：当玩家依赖 ActionPanel 来点“确认结束”时，skip 被置灰，玩家无法触发 UI 的 auto-run，从而形成软锁。

**建议修复方向（需你确认偏好）**

- A）更稳健：把“自动完成可无参执行的强制动作（`set_price/set_discount/set_luxury_price`）”下沉到引擎/动作层（例如在 GameEngine 执行 skip 前自动补齐），让 `skip` 在 ActionRegistry 判定中也可 initiatable。
- B）仅修 UI：让 ActionRegistry/ActionPanel 对 `skip` 做特判——当缺少的强制动作全部属于“可自动执行集合”时，仍把 `skip` 视为可启动（按钮可点），并由现有 UI auto-run 补齐。

**澄清（来自用户）**

- 右侧动作面板的“确认结束”无法点击（按钮为 disabled）。
- 顶部工具栏的“确认结束”点击无反应（无弹窗/无提示文案）。
- 没有任何提示文案。

**验收标准**

- 拥有折扣经理（mandatory）时，玩家仍可正常结束 Working 回合并推进阶段；强制动作会被自动补齐，不会软锁。

---

## 63.（用户反馈 7）上方工具栏移除“确认结束/调试”按钮

**现象**

- 上方工具栏存在“确认结束”和“调试”按钮。
- 你希望移除它们：确认结束已在动作面板提供；调试面板有更完善版本。

**涉及代码**

- `ui/scenes/game/game.tscn`：`UIRoot/TopBar/ButtonRow/SkipButton`、`DebugButton` 及其信号连接
- `ui/scenes/game/game.gd`：`_on_skip_pressed()`、`_on_debug_pressed()`、DebugDialog 相关逻辑

**注意事项**

- 该清理与 #62 有依赖：若 ActionPanel 的 skip 仍可能被置灰（强制动作问题未完全修复），移除顶部 skip 入口会放大软锁风险。建议先解决 #62，再做本项清理。

**验收标准**

- TopBar 不再显示这两个按钮；主要流程仍可通过 ActionPanel/新 DebugPanel 完成。

---

## 64.（用户反馈 8）地图外圈不可见格导致地图缩小：外圈为空时应放大，只有需要/已有外圈 piece 才完整显示

**现象**

- 为支持飞机广告等需要在地图外围不可见区放置 piece 的特性，地图外围增加了一圈不可见格子，导致地图整体缩小显示。
- 你希望：当外围不可见区没有任何 piece 时，地图“看起来”没有外圈空格（更大、更贴合）；只有在需要放置（例如飞机广告模式）或已经放置了这类 piece 时，地图才缩小并完整显示外圈。
- 额外约束：不希望地图放大后出现滚动条等；并需考虑对现有地图缩放/fit 机制的影响。

**涉及代码（初步）**

- `ui/scenes/game/map_canvas_indexer.gd`：`compute_bounds()` 无条件 `margin := 2`（UI-only outside ring）
- `ui/scenes/game/map_canvas.gd`：`set_map_data()` 用 bounds 计算 `_world_origin/_grid_size/custom_minimum_size`；`get_base_size()` 被 MapView 用于 fit
- `ui/scenes/game/map_view.gd`：auto-fit 基于 `canvas.get_base_size()`（随 `_grid_size` 变化会触发重新 fit）
- `ui/scenes/game/map_canvas_drawer.gd`：airplane 营销板件“视觉贴地图外侧”绘制，需要画布 bounds 留出外圈空间
- `ui/scenes/game/game_map_interaction_controller.gd`：airplane 的可选点/高亮使用 outside cells（依赖外圈 cell 在 bounds 内）

**初步根因**

- UI-only outside ring（`compute_bounds` 的固定 margin）始终参与 `_grid_size`，导致 `MapView.fit_to_view()` 用更大的 base_size 计算缩放，从而把地图整体缩小。
- 由于该 margin 是“为了飞机等外圈交互/绘制”的支持，但在不需要外圈时也始终开启，因此产生不必要的缩小。

**建议方案（方向）**

- 让 UI-only margin 成为“可切换”的 bounds 策略，而不是固定常开：
	- 默认：margin=0（外圈不占版面，地图更大，且 fit 后不出现额外滚动范围）。
	- 需要外圈时（进入飞机广告放置/预览，或地图上已存在外圈展示的 piece）：margin=2（完整显示外圈并允许交互）。
- 需要一个清晰的“何时需要外圈”的判定来源：
	- A）UI 模式驱动：当进入 airplane 营销选点/放置模式时临时开启；退出则关闭；
	- B）地图内容驱动：当 `marketing_placements` 中存在 airplane（或未来其它 outside piece）时保持开启；
	- 实际可能需要 A+B 组合。
- 与缩放的交互：bounds 切换会改变 `get_base_size()`，从而触发 MapView 的 auto-fit；允许覆盖玩家当前手动缩放（见澄清）。

**澄清（来自用户）**

- 未来还有别的外圈 piece（不仅 airplane）。
- 进入/退出外圈模式时允许系统自动重新 fit。

**验收标准**

- 外圈为空且不在外圈放置模式时：地图自动显示为“无外圈空格”的观感（更大、更贴合），且不会引入额外滚动条/滚动范围。
- 进入外圈放置模式或已有外圈 piece 时：地图自动缩小并完整显示外圈，交互/高亮/绘制正常。

## 51. 晚餐结算日志过噪：包含冗余统计/拆分信息

**现象**

- 晚餐结算日志包含额外的“总计/拆分/按产品收入”信息，影响可读性（过噪）。
- 你已在 `_log_dinnertime_report()` 中将这些日志临时注释，但代码仍保留（死代码/冗余计算）。

**涉及代码**

- `ui/scenes/game/game_event_log_controller.gd`

**初步根因**

- `_log_dinnertime_report()` 里为诊断/分析加入的细分统计（总计/拆分/按产品）当前不再需要。
- 注释掉日志后，对应的中间统计仍在计算，后续维护成本变高且容易误导。

**实施记录**

- 已修改：`ui/scenes/game/game_event_log_controller.gd`
	- 移除晚餐“总计/拆分/按产品收入”的冗余日志与相关无用统计计算（保留逐房屋消费 + 晚餐总结 玩家X）。

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS（107/107，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

## 52. 培训日志缺少“培训员来源”（trainer/coach/guru）

**现象**

- 玩家培训日志只显示 “培训 A -> B”，未体现“本次培训消耗了哪名培训员/哪种培训员（trainer/coach/guru）”。

**涉及代码（初步定位）**

- `gameplay/actions/train_action.gd`：分配培训 slots（`allocate_train_slots_for_working`）与记录 `round_state.train_events`
- `core/rules/employee_rules/train_slot_usage.gd`：选择 `trainer_id/instance_idx` 并写入 round_state 计数
- `ui/scenes/game/game_event_log_controller.gd`：渲染 `EMPLOYEE_TRAINED`

**初步根因**

- `EMPLOYEE_TRAINED` 事件 data 当前仅包含 `from_employee/to_employee/from_pending`，没有 trainer 信息，因此 UI 无法展示。

**实施记录**

- 已修改：`gameplay/actions/train_action.gd`
	- 扩展 `round_state.train_events`：记录 `trainer_id/trainer_instance_idx/steps`
	- `TrainAction._generate_specific_events()` 从 `train_events` 读取并发射 `EMPLOYEE_TRAINED`（包含培训员与步数）
- 已修改：`ui/scenes/game/game_event_log_controller.gd`
	- 培训日志追加展示：`N步` + `培训员：X`（并保留 `预支清账` 标记）

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS（107/107，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

## 53. 决定顺序阶段缺少最终顺序结果日志

**现象**

- 在 OrderOfBusiness（决定顺序/挑选顺序）阶段，所有玩家选完位置后，最终 `turn_order` 未体现在日志中。

**涉及代码（初步定位）**

- `gameplay/actions/choose_turn_order_action.gd`：落地 `state.turn_order` 并 auto-advance
- `core/engine/game_engine/auto_advance.gd`：首轮 OrderOfBusiness auto finalize（直接写 turn_order）
- `autoload/event_bus.gd` / `ui/scenes/game/game_event_log_controller.gd`：缺少对应事件类型/渲染

**初步根因**

- 当前没有发射“turn_order 最终确定”的 EventBus 事件，因此日志只能看到阶段推进（`PHASE_CHANGED`），看不到最终顺序结果。

**实施记录**

- 已修改：`autoload/event_bus.gd`：新增 `EventBus.EventType.TURN_ORDER_FINALIZED`
- 已修改：`gameplay/actions/choose_turn_order_action.gd`：当 `finalized` 从 `false -> true` 时发射 `TURN_ORDER_FINALIZED`（只发射一次）
- 已修改：`core/engine/game_engine/command_runner.gd`：首轮 OrderOfBusiness auto finalize（auto_advance）离开阶段时同样发射 `TURN_ORDER_FINALIZED`
- 已修改：`ui/scenes/game/game_event_log_controller.gd`：订阅并渲染“行动顺序（回合 X）：玩家A -> 玩家B ...”
- 已修改：`core/tests/order_of_business_test.gd`：覆盖“常规选择完成/首轮 auto finalize”两条路径的事件发射

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS（107/107，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

## 54. 游戏日志默认应隐藏阶段信息

**现象**

- 游戏日志默认显示阶段信息（阶段/子阶段/回合开始结束/玩家回合开始结束）。
- 需求：默认不显示这些“阶段类”日志（用户需要时再手动开启筛选）。

**涉及代码（初步定位）**

- `ui/components/game_log/game_log_panel.gd`：`_filter_types` 默认值包含 `LogType.PHASE`

**初步根因**

- `GameLogPanel` 默认筛选包含 `PHASE`，Filter 菜单初始化时据此默认勾选。

**修复方案（待你点头后实施）**

- 默认 `_filter_types` 移除 `LogType.PHASE`（仍保留在筛选菜单中可手动开启）。
- 若存在持久化设置（需确认），保证用户自定义偏好不会被重置。

**实施记录**

- 已修改：`ui/components/game_log/game_log_panel.gd`
	- 默认过滤移除 `PHASE`（阶段/子阶段/回合/玩家回合开始结束默认不显示，可在筛选菜单手动开启）

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120`：PASS（107/107，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

## 55. Payday 阶段缺少结算日志（仅现金变化）

**现象**

- Payday 结算时，日志目前只能看到玩家现金减少（`PLAYER_CASH_CHANGED`），缺少“为什么扣钱/扣了什么”的可读汇总。

**涉及代码（初步定位）**

- `core/rules/phase/payday_settlement.gd`：计算薪资并写入 `round_state.payday.details`
- `core/engine/game_engine/command_runner.gd` + `gameplay/actions/*`：离开 Payday 时缺少“结算报告事件”的发射路径
- `ui/scenes/game/game_event_log_controller.gd`：无对应事件渲染

**初步根因**

- 事件体系对 Dinnertime 有 `DINNERTIME_REPORT`，但 Payday 没有同类 report event，导致日志不可从 `EventBus.history` 可靠恢复，也缺少可读摘要。

**实施记录**

- 已修改：`autoload/event_bus.gd`：新增 `EventBus.EventType.PAYDAY_REPORT`
- 已修改：`core/engine/game_engine/command_runner.gd`：离开 Payday 时生成 `PAYDAY_REPORT`（用于潜在 auto-advance 路径）
- 已修改：`gameplay/actions/advance_phase_action.gd` / `gameplay/actions/skip_action.gd`：离开 Payday 时发射 `PAYDAY_REPORT`（覆盖手动推进/确认结束）
- 已修改：`ui/scenes/game/game_event_log_controller.gd`
	- 订阅 `PAYDAY_REPORT`
	- 每玩家 1 条汇总日志：默认短文本，仅在“有值”时追加 `支付(现金/代币)`、`欠薪`、`折扣/里程碑` 信息
- 已新增：`core/tests/payday_report_event_test.gd` 并纳入 `ui/scenes/tests/all_tests.gd`

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 150`：PASS（108/108，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

## 56. 冰箱容量规则错误（应总量 10）+ Cleanup 冰箱选择流程缺失

**现象**

- 冰箱目前的效果是“每种产品各自最多保留 10”（按产品限幅），而不是“食物+饮料总量最多保留 10”。
- Cleanup 阶段目前自动结算并 auto-skip；即使有冰箱也不会弹窗让玩家选择保留哪些食物/饮料。

**涉及代码（初步定位）**

- 规则：
	- `core/rules/phase/cleanup_settlement.gd`：库存清理逻辑（文件注释也标注了“后续可升级为总容量分配”）
- 测试：
	- `core/tests/cleanup_inventory_test.gd`：当前断言为“每种各自限幅”
- UI 文案：
	- `ui/components/left_panel/left_panel.gd`
	- `ui/components/inventory_panel/inventory_panel.gd`
	- `ui/components/milestone_panel/milestone_panel.gd`
- 自动推进：
	- `core/engine/game_engine/auto_advance.gd`：默认 auto-skip `Cleanup`
	- `core/engine/phase_manager/advance_phase.gd`：`pending_phase_actions` 可用于阻断推进

**初步根因**

- `CleanupSettlement.apply()` 采用了简化实现：对每个 product clamp 到 fridge_cap。
- `Cleanup` 被视为“无玩家交互结算阶段”而 auto-skip，缺少 `pending_phase_actions` 门禁与可执行动作，无法实现“弹窗选择保留”。

**澄清（来自用户）**

- 只统计 food+drink。
- 仅在 `total > cap` 时出现弹窗；按玩家顺序（`turn_order`）逐个弹窗；允许主动保留少于 `cap`。

**修复方案（最终）**

- 规则：冰箱容量按 food+drink 总量限制（`sum(food+drink) <= cap`），不再逐产品限幅。
- 交互：进入 Cleanup 时若玩家有冰箱且总量 > cap：
	- 写入 `round_state.pending_phase_actions["Cleanup"]` 阻断 auto-advance（避免 Cleanup 被自动跳过）
	- 将 `current_player_index` 对齐到待处理的第一位玩家（按 `turn_order`）
	- UI 弹出“冰箱保留选择”遮罩面板；确认后执行 `choose_fridge_keep`
- 动作：`choose_fridge_keep` 提交“各产品保留数量”，应用到 inventory，计算 discarded，写入 `round_state.cleanup.inventory_discarded` 并触发 `CleanupDiscard` 里程碑；当全部玩家完成后执行“里程碑池清理”。
- 文案：库存/里程碑效果描述改为“总量≤cap”。

**实施记录**

- 已修改：`core/rules/phase/cleanup_settlement.gd`
	- 冰箱容量改为 food+drink 总量限制；总量 > cap 时进入 pending（不自动丢弃）
	- 写入 `round_state.pending_phase_actions["Cleanup"]` 并按 `turn_order` 排序；对齐 `current_player_index`
	- pending 存在时暂缓 `apply_cleanup_milestones`（避免 CleanupDiscard 触发的里程碑残留在 pool 中）
- 已新增：`gameplay/actions/choose_fridge_keep_action.gd`（并注册到 `core/engine/game_engine/action_setup.gd`）
	- 校验 keep 总量 <= cap、且不超过现有库存；允许保留少于 cap
	- 应用库存变更、更新 `round_state.cleanup.inventory_discarded`、触发 `CleanupDiscard`；全部完成后补跑 `apply_cleanup_milestones`
- 已新增：`ui/components/modal_panel/fridge_keep_modal.tscn` / `ui/components/modal_panel/fridge_keep_modal.gd`
- 已修改：`ui/scenes/game/game_panel_controller.gd`：Cleanup pending 时按玩家顺序弹出冰箱选择弹窗，并发送 `choose_fridge_keep`
- 已修改：`ui/components/left_panel/left_panel.gd` / `ui/components/inventory_panel/inventory_panel.gd` / `ui/components/milestone_panel/milestone_panel.gd`：更新冰箱容量文案为“总量≤cap”
- 已修改：`core/tests/cleanup_inventory_test.gd` / `core/tests/new_milestones_coke_sold_v2_test.gd`：更新断言以覆盖新规则与选择动作

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 240`：PASS（108/108，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 34. 营销面板：选择员工的缩略卡高度不足，导致与下方板件区重叠

**现象/需求**

- 在营销动作面板中，选择员工时显示的员工缩略卡高度不够，视觉上会与下方“营销板件选择区”发生重叠。

**涉及代码（初步定位）**

- `ui/components/marketing_panel/marketing_panel.tscn`：`MarketerOption`（员工选择容器，已切到 `EmployeePicker`）
- `ui/components/employee_picker/employee_picker.gd`：`EmployeePickerItem`（内部把 `EmployeeCard` 设为 FullRect）
- `ui/components/employee_card/employee_card.gd`：compact 卡片最小尺寸（`COMPACT_SIZE=130×90`）

**初步根因假设**

- `EmployeePickerItem`（父容器）未显式设置 `custom_minimum_size`，导致 `HFlowContainer` 计算行高偏小；而 `EmployeeCard` 仍按自身绘制/最小尺寸呈现，造成下方布局未被正确“顶开”从而出现视觉重叠。

**修复方案**

- 保持 compact 卡尺寸不变，仅修复布局：在 `EmployeePickerItem` 内显式设置 `custom_minimum_size = EmployeeCard.COMPACT_SIZE`，让 `FlowContainer` 的行高/换行高度计算稳定，从而为下方板件区留足间距。

**实施记录**

- 已修改：`ui/components/employee_picker/employee_picker.gd`：`EmployeePickerItem` 设置稳定 `custom_minimum_size`，避免卡片绘制溢出覆盖下方内容。
- 已新增：`ui/scenes/tests/employee_picker_min_size_test.gd`：断言 `EmployeePickerItem.custom_minimum_size.y >= EmployeeCard.COMPACT_SIZE.y` 防回归。
- 已修改：`ui/scenes/tests/all_tests.gd`：加入 `EmployeePickerMinSizeTest`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（96/96，`.godot/AllTests.log`）

**验收**

- 营销面板中员工缩略卡不再与下方营销板件区重叠；滚动/点击选择不受影响。

**状态**

- Implemented（待手动验收）

---

## 35. 营销板件：禁止覆盖饮料进货点；可选点高亮需剔除

**现象/需求**

- 营销 piece 不能覆盖地图上的饮料进货点（`drink_source`）。
- 在显示可选点（绿色高亮）时就需要剔除会覆盖进货点的放置位置。

**涉及代码（初步定位）**

- UI 可选点计算：
	- `ui/scenes/game/game_map_interaction_controller.gd`：`_sync_marketing_highlights()`（构建 `_marketing_valid_anchors` 与 `set_cell_highlights`）
- Core 规则校验：
	- `gameplay/actions/initiate_marketing/validation.gd`：遍历 footprint cells 的合法性校验
- 地图数据字段：
	- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_drink_sources()` 读取 `cell["drink_source"]`

**初步根因假设**

- 现有“营销可放置格”校验只排除了：建筑占用、越界、营销重叠（非边缘营销额外排除了 road/blocked）；但未将 `drink_source` 视为不可占用对象，导致 UI 高亮与 core 校验均允许覆盖。

**修复方案**

- 规则对所有营销类型生效（radio/mailbox/billboard/airplane 均不可覆盖 `drink_source`）。
- UI：在 `_sync_marketing_highlights()` 的 footprint 遍历中，若任一占地格为 `drink_source` 则判定该 anchor 不可用（不加入高亮）。
- Core：在 `InitiateMarketingAction.validate`（`gameplay/actions/initiate_marketing/validation.gd`）中加入同样校验，确保回放/脚本绕过也会被拒绝。

**实施记录**

- 已修改：`ui/scenes/game/game_map_interaction_controller.gd`：营销可放置 anchor 扫描时剔除覆盖 `drink_source` 的候选点。
- 已修改：`gameplay/actions/initiate_marketing/validation.gd`：执行前验证中禁止占地覆盖 `drink_source`。
- 已修改：`core/tests/marketing_campaigns_test.gd`：新增用例 `_test_marketing_rejects_drink_source_overlap`。
- 已新增：`ui/scenes/tests/marketing_highlights_no_drink_source_test.gd`：验证“可选点高亮”不包含覆盖饮品进货点的 anchor。
- 已修改：`ui/scenes/tests/all_tests.gd`：加入 `MarketingHighlightsNoDrinkSourceTest`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（97/97，`.godot/AllTests.log`）

**验收**

- 任何营销板件均无法放置到覆盖饮料进货点的位置；绿色可选点中不会出现此类 anchor。

**状态**

- Implemented（待手动验收）

---

## 36. 营销板件：点击选点时地图显示半透明预览；放置后不透明；去掉边框

**现象/需求**

- 营销 piece 在“点击选择放置点”后，地图上应显示半透明预览（直到确认）。
- 放置后（实际落地的营销 piece）背景色不应带透明度。
- 营销 piece 不需要边框。

**涉及代码（初步定位）**

- 营销落地渲染：
	- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_marketing()`（目前 fill 有 alpha，且绘制 outline 边框）
- 营销选点交互：
	- `ui/scenes/game/game_map_interaction_controller.gd`：`_on_map_cell_selected()`（点击选点后目前只更新面板与 range overlay）
	- `ui/scenes/game/game_map_interaction_controller.gd`：`_on_map_cell_hovered()`（目前 hover 仅做 footprint 高亮）
- 预览渲染入口：
	- `ui/scenes/game/map_canvas.gd`：`set_structure_preview()`（已有）
	- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_structure_preview_piece()`（目前仅支持 restaurant/house）

**待澄清**

- 你希望“半透明预览”出现的时机：
	- A. hover 即显示板件半透明预览；
	- B. 仅点击选中 anchor 后显示（当前你描述更像 B）。
- 预览是否需要显示产品图标/类型图标，还是只显示板件背景块？

**修复方案**

- 预览时机：按 A（hover 即显示）。
- 落地渲染：`_draw_marketing()` 背景改为不透明（alpha=1.0），并移除边框绘制。
- hover 预览：对合法 anchor 调用 `MapCanvas.set_structure_preview(cells, true, preview_info)`，并在 `_draw_structure_preview_piece()` 支持 `piece_id="marketing"`，以半透明 alpha 绘制营销板件；同时将默认“格子高亮层”设为透明（避免双重叠加）。

**实施记录**

- 已修改：`ui/scenes/game/map_canvas_drawer.gd`：
	- `marketing` 落地渲染改为不透明背景、无边框；
	- 新增 `_draw_marketing_placement(...)` 统一绘制入口；
	- 结构预览支持 `piece_id="marketing"`（半透明预览）。
- 已修改：`ui/scenes/game/game_map_interaction_controller.gd`：hover 到合法 anchor 时传入 `preview_info(piece_id=marketing)`，并隐藏默认格子高亮层。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（97/97，`.godot/AllTests.log`）

**验收**

- 点击选择营销位置后能看到半透明板件预览；确认放置后板件背景不透明且无边框；交互不回归。

**状态**

- Implemented（待手动验收）

---

## 37. 营销板件：地图上显示序号徽标（右上角白底圆+黑色编号）

**现象/需求**

- 营销 piece 目前没有显示序号（board_number）。
- 需要参考房屋序号的显示方式：在右上角绘制白色底的圆，内部为黑色数字编号。

**涉及代码（初步定位）**

- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_marketing()`（可读取 placement 中的 `board_number`）
- 参考实现：
	- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_house_id()`（文字渲染风格参考）

**待澄清**

- 该序号仅要求显示在地图上的“已放置营销板件”，还是也要显示在 `MarketingPanel` 的板件选择按钮预览里？

**修复方案**

- 地图上的已放置营销板件与 MarketingPanel 的板件选择按钮都显示同样的序号徽标：
	- 右上角白底圆（不透明）
	- 圆内黑色序号（居中）

**实施记录**

- 已修改：`ui/scenes/game/map_canvas_drawer.gd`：
	- 营销板件绘制时追加 `board_number` 徽标（白圆+黑字）。
- 已修改：`ui/components/marketing_panel/marketing_board_button.gd`：
	- 板件选择按钮的占地预览中追加同样的 `board_number` 徽标。
- 已新增：`ui/scenes/tests/marketing_board_number_badge_test.gd`：验证地图营销绘制会触发徽标 draw 调用。
- 已修改：`ui/scenes/tests/all_tests.gd`：加入 `MarketingBoardNumberBadgeTest`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（98/98，`.godot/AllTests.log`）

**验收**

- 地图上所有营销板件右上角显示白底圆形序号；缩放后仍清晰可读。

**状态**

- Implemented（待手动验收）

---

## 38. 飞机营销：可选点应显示为地图外一圈（与外侧摆放一致）

**现象/需求**

- 飞机营销板件视觉上摆放在地图外侧（已在 #30 修复渲染）。
- 当前“可选点”高亮仍在地图内边缘，与你期望的“地图外一圈可选点”不一致。

**涉及代码（初步定位）**

- `ui/scenes/game/game_map_interaction_controller.gd`：`_sync_marketing_highlights()`（生成绿色可选点）
- `ui/scenes/game/game_map_interaction_controller.gd`：`_on_map_cell_selected()`（点击选点）
- `ui/scenes/game/map_canvas.gd`：点击位置来源为 world_pos（包含 external_cells bounds）

**待澄清（关键）**

- 你希望玩家实际点击的位置是：
	- A. 仍点击地图内边缘格（只是高亮显示在外侧作为“视觉提示”）；
	- B. 直接点击地图外侧一圈格子来选点（更直观，但需要 UI 做“外侧格 -> 内侧 anchor”的映射再执行 core 命令）。
- 地图外圈厚度是否固定为 2（与 #30 一致），且飞机板件始终完整落在这 2 格厚的外圈区域内？

**修复方案（提案，需你点头后实施）**

- 若选 B（推荐一致性更强）：
	- `_sync_marketing_highlights()` 针对 airplane，把合法 anchor 的高亮 cells 平移到外圈区域；
	- 同时维护 `outside_pos -> inside_anchor` 映射：点击外圈格时转回 inside anchor 走现有 core 规则（不改 core 坐标体系）。
- 若选 A：
	- 仅把高亮 cells 外移（点击仍使用内侧 anchor），但会产生“高亮与可点击不一致”的风险，不建议。

**测试计划**

- 新增 UI 测试：对 airplane 生成的 highlights 应落在外圈坐标范围，并能映射回对应 inside anchor（若选 B）。

**验收**

- 飞机营销在选点时，可选点高亮位于地图外侧一圈；点击选点体验与实际摆放位置一致。

**状态**

- Implemented（待手动验收）

**修复方案**

- 选 B：飞机营销在选点时使用“地图外一圈格子”作为可点击/可高亮位置；点击后映射回地图内的 anchor 以执行现有 core 规则与 range 计算。
- UI 侧引入“隐式外边距（margin=2）”，用于让地图外区域可被 hover/click（不写入 `state.map.external_cells`，避免污染规则层的真实棋盘外组件）。

**实施记录**

- 已修改：`ui/scenes/game/map_canvas_indexer.gd`：bounds 计算增加 UI-only 隐式外边距 `margin=2`（覆盖飞机外侧交互）。
- 已修改：`ui/scenes/game/game_map_interaction_controller.gd`：
	- airplane 营销高亮点落在外圈格子；
	- 维护 `outside_pos -> inside_anchor` 映射；hover/click 时自动映射回 inside anchor（预览/范围/确认均一致）。
- 已新增：`ui/scenes/tests/airplane_marketing_outside_selection_test.gd`：验证 airplane highlights 在外圈且点击能映射回 inside anchor。
- 已更新：`ui/scenes/tests/marketing_highlights_no_drink_source_test.gd`：适配 airplane 外圈可选点机制。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（99/99，`.godot/AllTests.log`）

**验收**

- 飞机营销选点高亮显示在地图外一圈；直接点击外圈格子即可选中目标并预览/确认。

---

## 39. 重组：CEO 下方员工槽不可见

**现象/需求**

- 在重组结构界面中，CEO 下方的员工槽看不到（无法用于拖拽分配）。

**涉及代码（初步定位）**

- `ui/components/company_structure/company_structure.tscn`：`ManagerRow/ManagerScroll/ManagerContainer`（CEO 直属卡槽区域）
- `ui/components/company_structure/company_structure.gd`：`_rebuild_structure()`（创建 CEO 直属槽与下属槽）
- `ui/components/modal_panel/restructuring_modal.gd`：将 `CompanyStructure` reparent 到全屏遮罩右侧

**待澄清**

- “看不到”是指：
	- A. 该区域完全没有生成（DOM/节点缺失）；
	- B. 生成了但被滚动/裁切到屏幕外（例如 `ManagerScroll` 的 scroll 偏移不为 0，或布局高度不足）；
	- C. 生成了但透明/被遮罩盖住（样式/层级问题）。
- 你期望 CEO 的直属卡槽“始终固定在 CEO 下方可见”，还是允许在该区域内滚动查看？

**修复方案（提案，需你点头后实施）**

- 若是滚动偏移导致（B）：在进入重组模式或重建结构后，将 `ManagerScroll.scroll_vertical/horizontal` 重置为 0，并确保 `ManagerRow` 的最小高度能容纳直属槽行。
- 若是布局/裁切导致：考虑将“直属卡槽行”从 `ManagerScroll` 中拆出固定显示，仅让“经理下属槽网格”区域滚动（避免 CEO 槽被滚走）。

**测试计划**

- 扩展 `RestructuringLayoutTest`：断言 `CompanyStructure` 中 CEO 直属槽控件存在且在可视区域内（基于最小尺寸/rect 关系的几何断言）。

**验收**

- 重组界面中 CEO 下方直属员工槽稳定可见，可正常拖拽放置员工。

**状态**

- Implemented（待手动验收）

**根因**

- `CompanyStructure.set_player_data()` 可能在节点尚未 `_ready()` 前被调用（onready 引用仍为 null），导致 `_rebuild_structure()` 早退，CEO 直属卡槽未构建，最终表现为“CEO 下方看不到任何槽位”。

**修复方案**

- 若 set_player_data 发生在未 ready 阶段：记录 `_pending_rebuild=true`；在 `_ready()` 中检查并补一次 `_rebuild_structure()`，确保卡槽必定生成。

**实施记录**

- 已修改：`ui/components/company_structure/company_structure.gd`：支持“set_player_data 早于 _ready”场景的延迟重建。
- 已新增：`ui/scenes/tests/company_structure_deferred_rebuild_test.gd`：覆盖“set_player_data before _ready 仍能构建 CEO 直属槽”。
- 已修改：`ui/scenes/tests/all_tests.gd`：加入 `CompanyStructureDeferredRebuildTest`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（100/100，`.godot/AllTests.log`）

**验收**

- 进入重组界面后，CEO 下方始终可见 CEO 直属卡槽，可用于拖拽分配员工。

---

## 40. 飞机营销：仅允许 1/3/5 长度贴边；可用点仅在飞机模式显示于地图外圈；外圈无背景

**现象/需求**

- 飞机营销广告仍不符合规则：
	- 飞机营销只要求“紧贴地图外边缘”（不在地图内），且只能使用“长度为 1/3/5 的边”贴边。
	- 飞机广告的“可用点”应渲染在地图外的一圈（outside ring）。
	- 地图外圈的可用点只应在“放置飞机广告”时出现；其他营销/其他模式应隐藏。
	- 地图外圈本身不应有背景色（不应被填充为地面底色），请去掉外圈背景。

**涉及代码（初步定位）**

- 飞机广告数据（长度/厚度）与占地旋转：
	- `core/data/marketing_registry.gd` / marketing defs（已在早前修正 #4-#6 board 数据）
	- `ui/components/marketing_panel/marketing_panel.gd`：rotation 选择与 board 尺寸展示
- 飞机广告落地渲染（地图外贴边）：
	- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_marketing()`（airplane attach + rect 外移）
- 飞机广告“可用点”计算/高亮与点击映射：
	- `ui/scenes/game/game_map_interaction_controller.gd`：`_sync_marketing_highlights()`、`_on_map_cell_selected()`、`_on_map_cell_hovered()`
- 地图外圈背景（ground 填充）：
	- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_ground_and_blocked()`（当前对整个 view bounds 都填充地面色）
	- `ui/scenes/game/map_canvas_indexer.gd`：`compute_bounds()`（当前存在 UI-only 的 implicit margin）

**初步根因假设**

- 旋转/尺寸约束：目前 airplane 的 `rotation` 仍允许将“厚度=2 的那一维”旋到贴边方向，导致可用点/占地不符合“仅长度 1/3/5 贴边”的限制（应把 `footprint_size` 中等于 2 的那维当作向外厚度）。
- 可用点渲染：airplane 的可用点虽已尝试外移，但高亮/点击映射与“外圈”定义仍可能存在偏移或覆盖范围不一致。
- 外圈背景：MapCanvas 目前会对“视图 bounds 内的所有 cell”填充地面底色；即使外圈只是 UI margin，也会被填色，从而违背“外圈无背景”要求。

**确认（来自你在 #40 的补充）**

- 飞机广告的 rotation 没有意义：每条边上的方向固定（UI 不提供旋转）。
- “外圈无背景”也包括真实 `external_cells`（如 offramp），不仅是 UI 隐式外圈。

**修复方案（已实施）**

- 规则/UI：
	- 飞机广告忽略 rotation：`footprint_size` 中“等于 2 的那一维”为向外厚度，另一维为边缘长度；由“贴哪条边”决定朝向（长度沿边、厚度向外）。
	- `ui/components/marketing_panel/marketing_panel.gd`：飞机类型隐藏旋转区并强制 rotation=0。
	- `ui/scenes/game/game_map_interaction_controller.gd`：
		- 飞机高亮候选点按四条边分别生成（top/bottom 使用 horizontal size，left/right 使用 vertical size），并把可点格映射到“地图外一圈（+/-1）”；
		- 修正 bottom/right 的 outside 映射：outside 需使用 `anchor + size.(x|y)`，确保落在 `max+1` 的外圈（不再落回地图内）。
		- 兼容测试场景：当 `_scene` 不是 Node 或 headless 时，角落方向选择弹窗自动选择默认方向，避免调用 `add_child`。
	- `ui/scenes/game/map_canvas_indexer.gd`：marketing placement 的占地索引对 airplane 按贴边方向决定占地朝向（不再依赖 rotation），避免占用集合/点击索引错误。
- 渲染：
	- `ui/scenes/game/map_canvas_drawer.gd`：
		- `_draw_ground_and_blocked()` 只对“地图本体 base cells”画底色 `#faf4e0`；UI 外圈与 `external_cells` 保持透明（无背景）；
		- `_draw_marketing()` 对 airplane 按贴边方向确定渲染 rect 尺寸（厚度向外、长度沿边），并贴到地图外侧边缘。

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180`：PASS（101/101，`.godot/AllTests.log`）
- 新增/更新测试：
	- `ui/scenes/tests/map_ground_skips_outside_ring_test.gd`：断言 ground 不绘制到外圈与 external_cells
	- 更新 `ui/scenes/tests/airplane_marketing_outside_render_test.gd`：rotation 不影响渲染朝向；角落 col 贴上边时尺寸为 length×thickness
	- 更新 `ui/scenes/tests/airplane_marketing_outside_selection_test.gd`：覆盖右/下外圈点击映射与角落选择路径

**状态**

- Implemented（待你手动验收视觉/交互细节）

---

## 41. 重组：左侧员工面板过宽；仍看不到 CEO 下属槽（需定位根因）

**现象/需求**

- 重组结构阶段左侧员工卡牌面板过宽。
- 目前仍无法看见 CEO 下方的员工槽（CEO 直属卡槽）。

**涉及代码（初步定位）**

- 重组全屏面板与左右分栏：
	- `ui/components/modal_panel/restructuring_modal.tscn`：`Split(HSplitContainer)` / `split_offset`
- 左侧员工卡牌区（HandArea）：
	- `ui/components/hand_area/hand_area.tscn` / `ui/components/hand_area/hand_area.gd`
- 右侧公司结构（CompanyStructure）：
	- `ui/components/company_structure/company_structure.tscn`：`ManagerRow/ManagerScroll/ManagerContainer`
	- `ui/components/company_structure/company_structure.gd`：`_rebuild_structure()`（构建 CEO 直属槽）

**初步根因假设**

- 左侧过宽：`HSplitContainer.split_offset` 固定值偏大（420）+ HandArea 宽度策略导致左侧占用过多。
- CEO 槽不可见：更可能是“布局高度为 0/被折叠”问题，而非未创建：
	- `CompanyStructure` 内部 `VBoxContainer/ManagerRow/ManagerScroll` 的 size_flags / custom_minimum_size 不足，导致在实际场景树尺寸计算后该区域高度趋近 0，从而槽位看不到；
	- 或者重组面板/滚动容器导致 CEO 槽被挤出可视区域。

**确认（来自你在 #41 的补充）**

- 能看到顶部 CEO 卡，但看不到下方卡槽（CEO 直属槽）。
- 左侧可以更窄：右侧尽可能宽，左侧只要够 3 列卡牌滚动即可。

**修复方案（已实施）**

- 左侧过宽：
	- `ui/components/modal_panel/restructuring_modal.tscn`：将 `Split.split_offset` 从 420 调整为 320。
	- `ui/components/hand_area/hand_area.gd`：进入 `restructuring` display_mode 时将 `HandArea.custom_minimum_size.x` 限制到 `<=320`，退出后恢复默认值（仅影响重组面板）。
- CEO 直属槽不可见：
	- 根因是 `CompanyStructure` 的 `ManagerScroll` 缺少稳定高度（在某些布局组合下会被压到接近 0），导致“槽位实际上已构建但不可见”。
	- `ui/components/company_structure/company_structure.tscn`：
		- 为根 `VBoxContainer` 增加 `size_flags_vertical=EXPAND_FILL`；
		- 为 `ManagerRow` 增加 `size_flags_vertical=EXPAND_FILL`；
		- 为 `ManagerScroll` 增加 `custom_minimum_size.y`（确保卡槽区域始终有可见高度）。

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180`：PASS（101/101，`.godot/AllTests.log`）
- 扩展测试：`ui/scenes/tests/restructuring_layout_test.gd` 增加断言：
	- 重组模式 HandArea 最小宽度 <= 320
	- CompanyStructure.ManagerScroll 有正的最小高度

**状态**

- Implemented（待你手动验收：左侧更窄/CEO 直属槽可见）

---

## 42. 飞机营销：放置不受道路/距离影响；可用点全边可选；影响范围为跨全图条带（宽=1/3/5）

**现象/需求**

- 飞机广告的可用点不需要考虑道路等因素；且不受员工距离限制影响。
- 飞机广告的影响范围计算错误：应覆盖“飞机飞过整张地图”的条带区域，条带宽度等于飞机长度（1/3/5），并横跨整张地图。
- 目前实现导致边缘大量点不可用、影响房屋集合不正确。

**涉及代码（定位）**

- 放置验证：
	- `gameplay/actions/initiate_marketing/validation.gd`（airplane 的占地/距离/边缘校验）
- 放置应用（写入 marketing_instances / marketing_placements）：
	- `gameplay/actions/initiate_marketing/apply.gd`
- 影响范围计算（结算时计算受影响房屋）：
	- `modules/base_marketing/rules/entry.gd`：`_get_airplane_house_ids`
- UI 可用点/映射/预览：
	- `ui/scenes/game/game_map_interaction_controller.gd`：`_sync_marketing_highlights()` / `_on_map_cell_selected()` / `_on_map_cell_hovered()`
	- `ui/scenes/game/game_overlay_marketing_range.gd`（范围预览）
	- `ui/scenes/game/map_canvas_drawer.gd`（飞机营销贴边渲染）
- 其它放置校验（房屋/餐厅不应被 airplane 阻塞）：
	- `core/map/placement_validator/validators.gd`

**根因**

- 原实现将飞机板件当作“占用棋盘格”的营销板件：会被 `structure/drink_source/road` 等棋盘内因素阻塞，导致边缘大面积不可放置。
- 飞机范围计算基于 `tile_index`（tile 行/列）+ `TILE_SIZE=5`，忽略飞机长度（1/3/5），导致影响区宽度与规则不一致。
- UI 的可用点计算亦按“占地格必须为空”过滤，进一步放大不可用点的问题。

**修复方案**

- 规则对齐：
	- airplane 放在棋盘外：放置时不检查棋盘内 `structure/road/blocked/drink_source`，且不受员工 `range` 限制；
	- 仅校验：必须贴边、且飞机长度（1/3/5）对应的条带不得越出棋盘；
	- 同一边不允许飞机板件条带重叠（避免外侧区域物理重叠）。
- 影响范围：
	- `axis=row`：条带按 `start_y=world_pos.y`，覆盖 `length` 行，横跨全图 `x=min..max`；
	- `axis=col`：条带按 `start_x=world_pos.x`，覆盖 `length` 列，横跨全图 `y=min..max`；
	- `length` 从 `footprint_size` 中“非 2 的那一维”推导（厚度=2）。
- UI：
	- 飞机可用点在地图外一圈显示；点击外圈格映射到棋盘边缘起点，并携带 axis/attach（不再弹角落方向选择）。
	- 范围预览额外传入 `footprint_size`，确保预览条带宽度正确。
	- 飞机贴边渲染按 axis 直接决定朝向（row→左右，col→上下）。
- 结构放置：
	- `PlacementValidator.validate_no_marketing_overlap` 忽略 airplane，避免飞机营销阻塞房屋/餐厅等棋盘内放置。

**实施记录**

- 已修改：`gameplay/actions/initiate_marketing/validation.gd`：airplane 专用校验（忽略棋盘内占用/距离；校验贴边与条带越界；同边飞机段重叠拒绝）。
- 已修改：`gameplay/actions/initiate_marketing/apply.gd`：airplane 强制 `rotation=0`；`tile_index` 改为 cell 级 start index（用于调试/回放稳定）。
- 已修改：`modules/base_marketing/rules/entry.gd`：airplane 影响范围改为“跨全图条带”，宽度由 `footprint_size` 推导。
- 已修改：`core/map/placement_validator/validators.gd`：airplane 不参与结构放置的 marketing overlap。
- 已修改：`ui/scenes/game/game_overlay_marketing_range.gd`：airplane 预览使用 `footprint_size`（不再依赖 tile_index）。
- 已修改：`ui/scenes/game/game_map_interaction_controller.gd`：
	- airplane highlights 改为按边缘生成 outside ring 可用点，并维护 outside→{anchor,axis,attach} 映射；
	- 修复 non-airplane marketing highlights 的缩进问题与占用集合构建（并忽略 airplane 占用）。
- 已修改：`ui/scenes/game/map_canvas_drawer.gd`：airplane 贴边渲染由 axis 决定朝向（兼容旧 anchor=right/bottom-1 的存档数据）。
- 已更新测试：
	- `ui/scenes/tests/marketing_highlights_no_drink_source_test.gd`：改用 radio 覆盖 drink_source 剔除逻辑（airplane 不再视为覆盖棋盘格）。
	- `core/tests/marketing_campaigns_test.gd` / `core/tests/new_milestones_brand_manager_v2_test.gd`：更新 airplane 放置坐标以匹配“条带起点=world_pos”语义。

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180`：PASS（101/101，`.godot/AllTests.log`）

**状态**

- Implemented（待你手动验收：飞机可用点/条带范围是否符合规则书视觉预期）

---

## 23. UI 配色：营销板背景/空地背景/可用点提示色

**需求**

- 营销板（board/piece）的背景色：`#98a295`
- 地图空地背景色：`#faf4e0`（不要使用当前背景纹理）
- 地图“可用点提示”颜色：`#f5b9a6`

**涉及代码（初步定位）**

- 营销板绘制：
	- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_marketing()`（营销占地矩形背景+边框）
	- `ui/components/marketing_panel/marketing_board_button.gd`：`_draw()`（板件选择按钮里的占地预览）
- 地图空地背景：
	- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_ground_and_blocked()`（目前每格绘制 `ground_tex`）
- “可用点提示”（当前为绿色 cell_highlights）：
	- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_cell_highlights()`

**确认（来自你的说明 #23）**

- 指的是地图上的营销板 piece（以及板件按钮里的占地预览），不改 MarketingPanel 面板背景。
- “空地纯色”包含 external_cells。
- “可用点提示色”只需要替换 `cell_highlights`（不要求改 structure_preview 的绿/红）。
- 营销板的预览允许加透明度（alpha）。

**修复方案**

- 将营销板背景色替换为 `#98a295`（含地图渲染与板件预览按钮）。
- 将空地底图从“绘制 ground 纹理”改为“直接 draw_rect 纯色 `#faf4e0`”（blocked overlay 保留）。
- 将 `cell_highlights` 的 fill/border 颜色替换为 `#f5b9a6`（alpha 按现有强度或你指定的强度）。

**验收**

- 地图底色为纯色 `#faf4e0`；营销板占地背景为 `#98a295`；所有“可用点提示”统一呈现为 `#f5b9a6`。

**实施记录**

- 已修改：`ui/scenes/game/map_canvas_drawer.gd`：
	- 地图空地底色改为 `#faf4e0`（包含 external_cells 显示区域）；
	- `cell_highlights` 改为 `#f5b9a6`；
	- 地图上营销板占地底色改为 `#98a295`（alpha 按当前实现保留为半透明风格）。
- 已修改：`ui/components/marketing_panel/marketing_board_button.gd`：板件按钮里的占地预览底色改为 `#98a295`（并保留 hover/pressed 的视觉变化）。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（88/88，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 24. 重组阶段拖拽员工卡：拖拽预览会变形

**现象**

- 在重组阶段拖动员工卡时，拖拽过程中的“跟随鼠标的预览卡”会改变形状/尺寸，看起来不像原本的缩略卡片。

**涉及代码**

- `ui/components/hand_area/hand_area.gd`：`_start_drag_visuals()`（创建 `_drag_preview`）
- `ui/components/company_structure/company_structure.gd`：`_start_drag_visuals()`（同样创建 `_drag_preview`）
- `ui/components/employee_card/employee_card.gd`：`setup()` / `_build_ui()`（会根据 `variant/display_scale` 重建 UI 并重设 `custom_minimum_size`）

**初步根因**

- 拖拽预览使用 `EmployeeCard.new()` 重新构建：
	- 未复制源卡的 `variant/display_scale`（或其它视觉参数）；
	- 且在 `preview.setup()` 过程中会重建 UI 并重置 `custom_minimum_size`，覆盖了预先设置的 `size_guess`，导致预览尺寸与源缩略卡不一致。

**确认（来自你的说明 #24）**

- 发生在“鼠标跟随的预览卡”（原位置的卡牌不需要处理）。

**修复方案**

- 拖拽预览卡改为“复制源卡视觉参数”：
	- 复制 `variant`、`display_scale`（以及必要的 theme/大小策略）；
	- 在 `setup()` 后再强制应用 `size_guess`（或提供一个显式的“固定缩略尺寸”模式）。
- 预览卡的额外 `scale=1.05` 若会引起“形状不像缩略卡”，可改为 1.0，仅用 alpha/描边表示拖拽态。

**验收**

- 重组阶段拖拽时，预览卡与原缩略卡在尺寸/比例上保持一致（仅允许透明度/高亮等轻量差异）。

**实施记录**

- 已修改：`ui/components/hand_area/hand_area.gd`、`ui/components/company_structure/company_structure.gd`：
	- 拖拽预览卡复制源卡的 `variant/display_scale`；
	- 取消预览卡 `scale=1.05`（保持 `Vector2.ONE`）；
	- 预览卡入树后强制回写 `custom_minimum_size/size`，避免 `_ready()` 重建 UI 时覆盖尺寸；
	- 额外兜底：viewport 为空时不再访问 `get_mouse_position()`（避免 headless/测试时脚本报错）。
- 新增：`ui/scenes/tests/drag_preview_visual_test.gd`（`DragPreviewVisualTest`）；
- 已修改：`ui/scenes/tests/all_tests.gd`：加入 `DragPreviewVisualTest`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（89/89，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 25. 重组界面布局重做：全屏覆盖；左侧仅待命卡；三列滚动；右侧公司树满宽；多管理槽下属卡槽改为网格

**需求**

- 重组阶段左侧员工卡牌不需要显示在岗员工（右侧公司结构里已有）。
- 重组面板应全屏展示（覆盖左侧区域）；当前实现没有覆盖左侧。
- 左侧员工卡牌区域可滚动，一行展示 3 名员工。
- 右侧所有空间用于展示公司树。
- 当右侧出现拥有大量管理栏位的管理岗员工时，下属卡槽不应纵向堆叠导致显示不全；改为：
	- 单个管理岗员工下方一行最多 4 个下属卡槽，可多行；
	- 相邻管理岗的下属卡槽不要互相重叠。

**涉及代码（初步定位）**

- 遮罩/覆盖范围：
	- `ui/components/modal_panel/modal_panel_base.gd`：`open(covered_rect)` 设计为“不遮挡左侧信息区”
	- `ui/components/modal_panel/restructuring_modal.tscn` / `ui/components/modal_panel/restructuring_modal.gd`
	- `ui/scenes/game/game_panel_controller.gd`：传入 `covered` rect 决定遮罩覆盖区域
- 左侧员工卡牌（HandArea）：
	- `ui/components/hand_area/hand_area.gd`：默认会构建在岗/待命/忙碌营销员三个区块
- 右侧公司结构（CompanyStructure）：
	- `ui/components/company_structure/company_structure.tscn`
	- `ui/components/company_structure/company_structure.gd`：下属卡槽目前为 VBox 纵向追加

**初步根因**

- “不覆盖左侧”是 `ModalPanelBase` 的明确设计；重组阶段需要例外（全屏）。
- `HandArea` 目前把在岗员工也展示出来，且布局为 HFlow（未限制三列）。
- `CompanyStructure` 的“下属槽”纵向增长，遇到大 `manager_slots` 时高度溢出；同时列宽固定，难以在横向充分利用空间。

**确认（来自你的说明 #25）**

- 左侧不显示忙碌营销员（busy_marketers）。
- 左侧卡牌维持当前 compact 尺寸。
- 右侧公司树希望使用“组织结构图式”的树形展示。

**修复方案（提案，需你点头后实施）**

- RestructuringModal 改为“全屏遮罩”：open 时覆盖整个 viewport rect（不再使用 `covered` 限制）。
- HandArea 在重组模式下提供一个“只显示 reserve（可拖拽）员工”的显示模式，并改为 3 列滚动网格。
- CompanyStructure 的“下属卡槽容器”改为 Grid（4 列，多行），减少垂直高度；并调整列宽/spacing，保证不会侵入相邻列产生重叠。

**验收**

- 重组遮罩全屏覆盖；左侧不再显示在岗员工；左侧卡牌三列可滚动；右侧公司结构在大管理槽时仍可完整展示/可滚动且无重叠。

**实施记录**

- 已修改：`ui/components/modal_panel/restructuring_modal.gd`：
	- `open()` 改为全屏覆盖（忽略传入的 `covered_rect`）；
	- 覆写 `_center_panel()`：面板填满覆盖区域（不再居中弹窗）；
	- 关闭时恢复 HandArea 的显示模式（避免回到底部面板后仍隐藏在岗员工）。
- 已修改：`ui/components/hand_area/hand_area.gd`：
	- 新增 `display_mode`（`default|restructuring`）；
	- 重组模式下仅渲染 reserve 卡牌，隐藏 active/busy 区块（busy_marketers 不再显示）。
- 已修改：`ui/components/company_structure/company_structure.gd`：经理下属卡槽由纵向堆叠改为 `GridContainer(columns=4)`（多行）。
- 已修改：`ui/components/company_structure/company_structure.tscn`：ManagerScroll 启用垂直滚动（AUTO）并允许纵向扩展。
- 新增：`ui/scenes/tests/restructuring_layout_test.gd`（`RestructuringLayoutTest`）；并在 `ui/scenes/tests/all_tests.gd` 纳入 AllTests。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（91/91，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 33. 营销板件数据修复：piece 命名/类型/尺寸对齐真实数据

**现象/需求**

- 当前 `modules/base_marketing/content/marketing/*.json` 中存在 piece 命名与数据错位（例如 mailbox_5/6 实为 airplane；缺失 billboard_15；airplane_4 footprint 维度错误）。
- 需要按你提供的“真实数据”修复：确保 board_number 1-16 的 type/id/footprint_size 对齐，且文件命名与 `id` 一致，避免 UI/规则/存档出现混乱。

**涉及代码（初步定位）**

- 数据文件：`modules/base_marketing/content/marketing/*.json`
- 加载：`core/modules/v2/content_catalog_loader.gd`（MarketingDef.load_from_file）
- 使用：
	- `core/data/marketing_registry.gd` / `core/data/marketing_def.gd`
	- `ui/scenes/game/map_canvas_drawer.gd`（营销绘制）
	- `ui/scenes/game/game_map_interaction_controller.gd`（营销放置可用点与预览）
	- `gameplay/actions/initiate_marketing/*`（规则校验/执行）

**修复方案**

- 修复/重命名 JSON：
	- `airplane_4.json` footprint 改为 `[1,2]`
	- 将现有 `mailbox_5.json` / `mailbox_6.json` 改为 `airplane_5.json` / `airplane_6.json`（并同步 `id/type/board_number/footprint_size`）
	- 将现有 `airplane_15.json` 改为 `billboard_15.json`（并同步 `id/type/board_number/footprint_size`）
	- 确保 mailbox 仅为 7-10，billboard 为 11-16（含 15）
- 增加回归测试：断言 MarketingRegistry 中 1-16 的 `type/footprint_size` 与规则一致（至少覆盖 airplane/mailbox/billboard 的关键尺寸）。

**验收**

- MarketingRegistry 加载后，board_number 1-16 的营销板件数据与“真实数据”一致；营销放置/渲染/结算不因命名错位而出错。

**实施记录**

- 已修改：`modules/base_marketing/content/marketing/airplane_4.json`：`footprint_size` 修正为 `[1,2]`。
- 已重命名并修正：`modules/base_marketing/content/marketing/airplane_5.json`、`modules/base_marketing/content/marketing/airplane_6.json`（原 `mailbox_5/6.json`）：同步 `id/type/footprint_size` 为 airplane。
- 已重命名并修正：`modules/base_marketing/content/marketing/billboard_15.json`（原 `airplane_15.json`）：同步 `id/type/footprint_size` 为 billboard。
- 已修正依赖 mailbox 编号范围的“全新里程碑”描述与校验（#7-#10）：
	- `modules/new_milestones/actions/place_new_restaurant_mailbox_action.gd`
	- `modules/new_milestones/README.md`
	- `ui/components/milestone_panel/milestone_panel.gd`
	- `core/tests/new_milestones_new_restaurant_v2_test.gd`
	- `core/tests/new_milestones_brand_director_v2_test.gd`
- 新增：`core/tests/marketing_board_data_test.gd`（MarketingBoardDataTest）；并在 `ui/scenes/tests/all_tests.gd` 纳入 AllTests。
- 更新：`tools/generate_manual_test_saves_manifest.gd`：注释同步 board_number=15 现为 billboard（仍 4P 可用）。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（90/90，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 26. 招聘/培训等面板统一复用员工缩略卡（EmployeeCard）

**现象/需求**

- 目前多个动作面板使用了各自的员工表示方式（自绘小卡/文本下拉等），导致风格不一致、代码分散。
- 目标：统一复用员工的缩略卡片样式（`EmployeeCard` compact）作为“选择员工”的 UI 组件。

**涉及代码（初步定位）**

- `ui/components/recruit_panel/recruit_panel.gd`：内部类 `PoolCard`（自定义 PanelContainer）
- `ui/components/train_panel/train_panel.gd`：内部类 `TrainableCard` / `TrainTargetItem`（自定义）
- `ui/components/action_panel/action_panel.gd`：部分动作使用 `OptionButton` 文本展示员工/餐厅等
- `ui/components/marketing_panel/marketing_panel.gd`：营销员选择目前为 `OptionButton`（文本）

**确认（来自你的说明 #26）**

- 统一范围：所有“选员工”的面板都统一复用员工缩略卡片。
- 招聘与培训面板需要显示“数量角标”（例如池中数量/可训练数量）。

**修复方案**

- 抽出一个可复用的“员工选择器”组件（内部以 `EmployeeCard` compact 渲染，支持选中态/禁用态/数量角标/标签）。
- RecruitPanel/TrainPanel/MarketingPanel/ProductionPanel/ActionPanel 等统一复用该组件，保留现有信号与业务流程不变（减少规则层影响）。

**实施记录**

- 新增：`ui/components/employee_picker/employee_picker.gd`：`EmployeePicker`（`EmployeeCard` compact + `badge_text/tag_text`）。
- 已修改：`ui/components/recruit_panel/recruit_panel.gd` / `ui/components/recruit_panel/recruit_panel.tscn`：招聘池改用缩略卡；右上角数量角标显示可招聘数量。
- 已修改：`ui/components/train_panel/train_panel.gd` / `ui/components/train_panel/train_panel.tscn`：培训来源/目标改用缩略卡；数量角标显示数量/库存；tag 显示“预支/在岗/步数”。
- 已修改：`ui/components/marketing_panel/marketing_panel.gd` / `ui/components/marketing_panel/marketing_panel.tscn`：营销员选择改用缩略卡（数量角标显示可用人数）。
- 已修改：`ui/components/production_panel/production_panel.gd`：生产/采购员工选择改用缩略卡（数量角标显示可用人数）。
- 已修改：`ui/components/action_panel/action_panel.gd` / `ui/components/action_panel/action_panel.tscn`：放置房屋/餐厅等上下文员工选择改用缩略卡。

**验收**

- 招聘/培训等面板中员工展示统一为缩略卡片风格；选中/禁用/数量提示一致；功能不回归。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（91/91，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 27. 地图高亮/覆盖机制统一：边框 + 透明层覆盖完整 piece

**现象/需求**

- 当前存在多种“选中/覆盖/可用点”表现方式，导致相关渲染代码分散且不一致。
- 期望统一为一种机制：高亮边框 + 带颜色的透明层覆盖完整 piece（按占地/footprint）。
- 现有明显错误：房屋被覆盖时只高亮锚点格（应覆盖房屋整个占地）。

**涉及代码（初步定位）**

- MapCanvas 内置：
	- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_selection()` / `_draw_cell_highlights()` / `_draw_structure_preview()`
	- `ui/scenes/game/map_canvas.gd`：`_selected_pos`、`set_cell_highlights()`、`set_structure_preview()`
- Overlay 体系：
	- `ui/scenes/game/game_overlay_marketing_range.gd`：将受影响房屋转成 anchor world_pos 列表（导致只覆盖锚点）
	- `ui/overlays/marketing_range_overlay.gd`：按 tile_size 绘制每格 ColorRect

**确认（来自你的说明 #27）**

- “可放置点提示”已在 #23 处理（`cell_highlights`），此处主要统一：覆盖范围 / hover / 选中。
- 颜色暂无固定映射：我会先用 placeholder 颜色；后续你可手动修改。
- 颜色的配置位置需要补充记录到本文件。

**修复方案**

- 引入 MapCanvas 的“piece overlay”数据结构（按 footprint cells），并由 MapCanvasDrawer 统一渲染：透明 fill + 高亮 border（只绘制外轮廓，不画内部网格线）。
- 将营销范围覆盖从独立 `MarketingRangeOverlay(ColorRect)` 收敛到 MapCanvas 的 overlay 机制；同时将“受影响房屋”从 anchor 单格改为房屋完整占地 cells。

**验收**

- 地图上所有高亮/覆盖提示采用同一视觉风格，且覆盖到 piece 的完整占地；房屋覆盖不再只显示锚点格。

**颜色配置位置**

- 营销范围覆盖（placeholder 颜色）：`ui/scenes/game/game_overlay_marketing_range.gd`：`RANGE_FILL_COLOR` / `RANGE_BORDER_COLOR` / `RANGE_BORDER_WIDTH`
- 可放置点提示（已在 #23 固定为 `#f5b9a6`）：`ui/scenes/game/map_canvas_drawer.gd`：`_draw_cell_highlights()`
- 结构/footprint 预览（默认绿/红）：`ui/scenes/game/map_canvas_drawer.gd`：`_draw_structure_preview()`（也支持在 `preview_info` 里用 `highlight_fill/highlight_border/highlight_border_width` 覆盖）

**实施记录**

- 已修改：`ui/scenes/game/map_canvas.gd`：新增 `_piece_overlays` + `set_piece_overlay()/clear_piece_overlay()`，作为统一高亮数据入口。
- 已修改：`ui/scenes/game/map_canvas_drawer.gd`：
	- 新增 `_draw_cells_overlay()`：按 cells 绘制透明 fill + 外轮廓 border；
	- 新增 `_draw_piece_overlays()`：绘制 MapCanvas 上的通用 overlay；
	- `cell_highlights/structure_preview` 改为复用同一绘制机制（减少重复渲染代码）。
- 已修改：`ui/scenes/game/game_overlay_marketing_range.gd`：不再实例化 `MarketingRangeOverlay`，改为写入 MapCanvas 的 `piece overlay`（保持行为不变，仅统一渲染路径）。
- 已修改：`ui/scenes/game/game_overlay_utils.gd`：新增 `get_house_footprint_cells()`，用于把“受影响房屋”展开为完整占地 cells（修复只高亮锚点格）。
- 新增：`ui/scenes/tests/marketing_range_full_footprint_test.gd`（`MarketingRangeFullFootprintTest`）并纳入 `ui/scenes/tests/all_tests.gd`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（95/95，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 28. 移动餐厅：餐厅选项改为可阅读；切换时高亮当前餐厅

**现象/需求**

- move_restaurant 动作面板提供餐厅 id 选项，但地图上餐厅缺少可读标记，玩家不知道正在移动的是哪个餐厅。
- 期望：
	- 餐厅选项用“可读的”信息展示（而非仅 `rest_0`）；
	- 在切换餐厅时，高亮当前选中的餐厅。

**涉及代码（初步定位）**

- `ui/components/action_panel/action_panel.gd`：`_rebuild_restaurant_option()`（目前直接用 id 作为显示文本）
- `ui/components/restaurant_placement/restaurant_placement_overlay.gd`：`set_selected_restaurant()` 会触发 `highlight_requested`
- `ui/scenes/game/game_map_interaction_controller.gd`：`on_restaurant_highlight_requested()`（当前只高亮“可放置锚点”，未高亮被选餐厅）
- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_restaurant()`（当前绘制 logo，无 id/编号）

**确认（来自你的说明 #28）**

- 餐厅显示格式选 C：`餐厅 1 @ (x,y)`（隐藏内部 id）。
- 地图上的餐厅标记仅在 move_restaurant 模式显示。

**修复方案**

- ActionPanel 的餐厅 OptionButton 使用“可读 label + metadata=restaurant_id”模式。
- move_restaurant 模式下在地图上高亮当前选中的餐厅（入口 anchor 匹配）。

**实施记录**

- 已修改：`ui/components/restaurant_placement/restaurant_placement_overlay.gd`：
	- `set_map_data()` 记录 map_data；
	- 新增 `get_restaurant_display_label()`（`餐厅 N @ (x,y)`）用于 UI 展示；
	- move_restaurant 提示文案改用可读 label（隐藏内部 id）。
- 已修改：`ui/components/action_panel/action_panel.gd`：`_rebuild_restaurant_option()` 通过 overlay 的 `get_restaurant_display_label()` 展示可读 label（metadata 保持为 restaurant_id）。
- 已修改：`ui/scenes/game/map_canvas.gd`：新增 move_restaurant 的选中餐厅 anchor 状态与 set/clear 方法。
- 已修改：`ui/scenes/game/game_map_interaction_controller.gd`：`on_restaurant_highlight_requested()` 在 move_restaurant 时将选中餐厅 entrance_pos 写入 MapCanvas，用于渲染高亮；并在切换/退出模式时清理。
- 已修改：`ui/scenes/game/map_canvas_drawer.gd`：`_draw_restaurant()` 在入口 anchor 匹配时绘制高亮边框。
- 新增：`ui/scenes/tests/move_restaurant_display_label_test.gd`（`MoveRestaurantDisplayLabelTest`）；并在 `ui/scenes/tests/all_tests.gd` 纳入 AllTests。

**验收**

- 玩家可直观识别下拉框中的餐厅对应地图哪个实体；切换选择时地图明确高亮当前餐厅。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（见 `.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 29. 营销面板遮挡；营销放置缺少形状预览；营销图标大小需适配 piece

**现象/需求**

- 营销面板最左侧有一小部分内容被遮挡（疑似 dock 进 RightPanel 后的裁剪/边距问题）。
- 营销 piece 放在地图上选点时，没有“占地形状（footprint）”预览。
- 地图上营销图标大小不适配实际 piece 的大小，需要缩放到合适的视觉比例。

**涉及代码（初步定位）**

- 面板布局：
	- `ui/components/marketing_panel/marketing_panel.tscn`
	- `ui/scenes/game/game.gd`：dock 到 RightPanel 的逻辑（`dock_popup_into_right_panel`）
- 营销选点与预览：
	- `ui/scenes/game/game_map_interaction_controller.gd`：marketing hover 仅调用 `preview_marketing_range`，未调用 `MapCanvas.set_structure_preview()`
- 地图营销渲染：
	- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_marketing()`（图标绘制与缩放策略）

**确认（来自你的说明 #29）**

- 遮挡表现：一些按钮与下拉框最左侧有一小部分被边框遮住。
- 营销 footprint 预览：希望 hover 就显示（预览允许加透明度）。

**修复方案**

- 修复面板遮挡：调整 MarketingPanel 内部容器的 margin/padding 或 RightPanel dock host 的裁剪/偏移，确保左侧内容不被盖住。
- 增加营销 footprint 预览：当 hover 到合法 anchor 时，计算该 board 的 rotated footprint cells，并调用 `MapCanvas.set_structure_preview()` 显示占地预览。
- 调整营销图标缩放：依据 board_rect 的尺寸自适应计算 icon_rect/product_icon 的占比（而不是固定比例），使不同 footprint 的营销板都看起来“填得刚好”。

**验收**

- 营销面板无遮挡；营销选点时地图能看到 footprint 预览；营销图标与 piece 占地匹配，不显得过大/过小。

**实施记录**

- 已修改：`ui/components/marketing_panel/marketing_panel.tscn`：增加左侧 margin，避免按钮/下拉框左侧被边框遮挡。
- 已修改：`ui/scenes/game/game_map_interaction_controller.gd`：marketing hover 到合法 anchor 时调用 `MapCanvas.set_structure_preview()` 显示 footprint 预览；离开合法 anchor 时清理预览。
- 已修改：`ui/scenes/game/map_canvas_drawer.gd`：营销 product 图标大小改为基于 board 可用区域自适应缩放，使不同 footprint 的板件视觉更匹配。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（见 `.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 30. 飞机营销板件：应贴地图外侧边缘且不在地图内；可用宽度仅 1/3/5

**需求**

- 飞机营销板块应紧贴地图外侧边缘，不在地图内。
- 可用宽度只有 1/3/5（需要合理摆放 piece 来保证）。
- 当前实现与该目标差距较大，需要修复。

**现状（初步定位）**

- 飞机目前按普通营销板件处理：在地图内占地、按 `footprint_size` 绘制矩形底色（`ui/scenes/game/map_canvas_drawer.gd:_draw_marketing()`）。
- 现有 marketing 数据存在明显错误/命名错位（例如 `airplane_4.json` 为 `[2,1]`；且 `mailbox_5.json/mailbox_6.json` 实为飞机尺寸），导致 UI 无法正确按规则渲染与预览。

**确认（来自你的说明 #30）**

- 这是纯视觉摆放：需要在外边缘对齐地图格子。
- “向外厚度”统一为 2。
- 飞机广告 piece 的尺寸以定义为准（每个编号的 piece 都已定义尺寸）；可用长度为 1/3/5。

**确认补充（来自你的说明 #2：真实营销板件数据）**

- radio 使用 id 1-3，尺寸均为 `[1,1]`
- airplane 使用 id 4-6，尺寸依次为 `[1,2]`、`[3,2]`、`[5,2]`
- mailbox 使用 id 7-10，尺寸依次为 `[2,2]`、`[2,2]`、`[1,1]`、`[1,1]`
- billboard 使用 id 11-16，尺寸依次为 `[3,2]`、`[2,2]`、`[3,1]`、`[2,1]`、`[1,1]`、`[1,1]`

**修复方案**

- 前置：先修复营销板件数据定义（见 #33），确保 airplane 的 `footprint_size` 为 `[1,2]/[3,2]/[5,2]`。
- 保持 core 的 world_pos/rotation 作为“锚点与占地规则”，仅做视觉偏移：airplane 渲染时将整块板件绘制到地图外侧边缘（与格子对齐），且不侵入地图内；角落位置用 `axis(row/col)` 决定贴哪条边。

**验收**

- 飞机营销板件视觉上贴地图外侧且不侵入地图内；尺寸/可用宽度符合 1/3/5 的规则；放置/预览/结算一致。

**实施记录**

- 已修改：`ui/scenes/game/map_canvas_drawer.gd`：`_draw_marketing()` 对 `airplane` 特判，计算 base map 的像素边界并将 rect 平移到地图外侧（角落用 `axis` 选择贴边方向）。
- 已修改：`ui/scenes/game/game_map_interaction_controller.gd`：marketing hover 的 footprint 预览在 `airplane` 时也做同样的“贴边外移”，使预览位置与最终渲染一致。
- 新增：`ui/scenes/tests/airplane_marketing_outside_render_test.gd`（`AirplaneMarketingOutsideRenderTest`）：断言飞机营销的 rect 会按 left/right/top/bottom/corner 规则绘制到地图外侧。
- 已修改：`ui/scenes/tests/all_tests.gd`：纳入 `AirplaneMarketingOutsideRenderTest`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（94/94，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 31. 关闭“点击地图格高亮”

**现象/需求**

- 鼠标点击地图格会出现蓝色选中框；你希望关闭该高亮，以保持 UI 一致性。

**涉及代码**

- `ui/scenes/game/map_canvas.gd`：`_gui_input()` 中点击写入 `_selected_pos`
- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_selection()` 绘制蓝色边框

**确认（来自你的说明 #31）**

- 点击地图格不需要高亮；hover 白色框保留（仍由 `Globals.show_cell_hover_tooltip` 控制）。

**修复方案**

- 保留 `cell_selected`/`cell_hovered` 信号用于交互逻辑，但移除 `_selected_pos` 的视觉渲染。
- hover 白色框保持现状（便于查看 tooltip）。

**验收**

- 点击地图格不再出现蓝色高亮框；其它选点/预览/高亮机制不受影响。

**实施记录**

- 已修改：`ui/scenes/game/map_canvas_drawer.gd`：`_draw_selection()` 移除蓝色选中框绘制，仅保留 hover 白框逻辑。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（91/91，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 32. 地图渲染：tile 内部细分网格线（细线）与 tile 外边缘粗线一起绘制

**需求**

- 每个 tile 内部需要有细线分割每个小单元格；视觉上类似 tile 外边缘的粗线，但内部使用细线。
- 内部细线与 tile 外边缘粗线应一起绘制。

**涉及代码（初步定位）**

- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_tile_borders()`（目前只绘制 tile 外边缘粗线）

**修复方案**

- 扩展 `_draw_tile_borders()`：
	- 保留现有外边缘粗线绘制；
	- 在 tile 内部按 `cell_size` 间距绘制 4 条竖线 + 4 条横线（tile_size=5），线宽更细、alpha 更低；
	- 确保内部线不盖住上层 piece（仍在 draw 顺序中位于 roads 与 structures 之间）。

**确认（来自你的说明 #3）**

- 内部细线参数：
	- 颜色：黑色
	- alpha：≈0.25
	- 线宽随 zoom 缩放：`max(1, cell_size*0.02)`

**测试计划**

- 增加 headless 回归测试：对给定 `tile_placements` 的 map_data，断言 MapCanvasDrawer 的 tile 分割线生成逻辑会输出“每 tile 8 条内部线”（4 竖 + 4 横），并覆盖 zoom 下线宽策略不出错。

**实施记录**

- 已修改：`ui/scenes/game/map_canvas_drawer.gd`：`_draw_tile_borders()` 追加 tile 内部细线（黑色 alpha≈0.25，线宽 `max(1, cell_size*0.02)`），并保证外边缘粗线在细线之后绘制。
- 新增：`ui/scenes/tests/tile_internal_grid_lines_test.gd`（`TileInternalGridLinesTest`）：断言每 tile 输出 8 条内部线，并覆盖 40/100 两种 `cell_size` 下线宽缩放。
- 已修改：`ui/scenes/tests/all_tests.gd`：纳入 `TileInternalGridLinesTest`。

**验证**

- `GameSmokeTest`：PASS（`.godot/GameSmokeTest.log`）
- `AllTests`：PASS（见 `.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 43. 营销放置：点击选点后预览固定，不再跟随鼠标，直到确认/取消

**现象/需求**

- 营销板件在地图上选择放置点时，hover 会显示占地与范围预览（这是对的）。
- 但玩家点击选中一个可用点后，预览仍会随鼠标 hover 移动；你希望改为：点击后预览固定在该位置，直到玩家确认或取消。

**涉及代码**

- `ui/scenes/game/game_map_interaction_controller.gd`
	- `_on_map_cell_hovered()`：hover 时刷新占地预览与范围 overlay
	- `_on_map_cell_selected()`：点击时写入 MarketingPanel 选中目标

**根因**

- 当前“预览/范围”的刷新完全绑在 hover：
	- 点击只更新了 `MarketingPanel` 的 `_selected_target`，但 `GameMapInteractionController` 对非 airplane 类型没有记录“已选中目标”；
	- hover 事件持续触发 `set_structure_preview` / `preview_marketing_range`，导致预览一直移动。

**修复方案**

- 在地图点击合法放置点时（所有营销类型），写入 `_payload["selected_target"]` 作为“已固定”的标志。
- `_on_map_cell_hovered()` 检测到 `selected_target != (-1,-1)` 时直接 return，停止 hover 刷新（直到 confirm/cancel 或重新进入选点）。
- 为了允许确认前改选：再次点击新的合法点时，先临时清除 `selected_target` 刷新一次预览，再写入新的 `selected_target`。

**测试计划**

- 新增 headless 回归测试：用 fake `map_canvas`/`overlay_controller` 驱动 `GameMapInteractionController`：
	- 点击后 hover 到其它点不应再触发 `set_structure_preview` / `preview_marketing_range`；
	- 再次点击新点仍可更新预览（允许改选）。

**实施记录**

- 已修改：`ui/scenes/game/game_map_interaction_controller.gd`：
	- 点击合法营销点时写入 `_payload["selected_target"]`（所有营销类型）；
	- `_on_map_cell_hovered()` 在已选 target 时停止 hover 刷新，从而锁定预览直到确认/取消；
	- 再次点击时会先清掉 `selected_target`，确保点击可以刷新预览（允许改选）。
- 新增：`ui/scenes/tests/marketing_selection_freeze_test.gd`（`MarketingSelectionFreezeTest`）：覆盖“点击锁定/hover 不再移动/再次点击可改选”。
- 已修改：`ui/scenes/tests/all_tests.gd`：纳入 `MarketingSelectionFreezeTest`。

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180`：PASS（`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 44. 重组结构：CEO 直属槽可见；管理岗员工卡不随下属槽拉宽（保持 compact 且居中）

**现象/需求**

- 你仍然看不到 CEO 下方的直属员工槽（只能看到顶部 CEO 卡）。
- 右侧公司树中，带有多个下属槽位的管理员工会被拉宽（例如执行副总裁被拉到 4 张卡宽）；你希望管理员工卡片保持 compact 尺寸不变，并在其下属槽位区域上方居中。

**涉及代码（初步定位）**

- `ui/components/modal_panel/restructuring_modal.tscn`：Split 子区（HandHost/CompanyHost）的 size_flags 可能导致右侧在垂直方向被挤压，从而 ManagerScroll 高度不足。
- `ui/components/company_structure/company_structure.gd`：CEO 直属槽（CardSlot）与下属槽（GridContainer）位于同一列 VBox 中，VBox 会让上方 CardSlot 横向填满列宽，导致 EmployeeCard 被拉伸。

**根因假设**

- CEO 直属槽不可见：RestructuringModal 的 `HandHost/CompanyHost` 未设置 `size_flags_vertical=EXPAND_FILL` 时，Split 在某些尺寸下会给子区过小高度，导致 CompanyStructure 内的 `ManagerScroll` 被压缩到接近 0。
- 管理岗卡片被拉宽：直属槽（CardSlot）被 VBoxContainer 横向强制填满，而该列宽度由下方“4 列下属槽网格”的宽度决定，导致直属卡随列宽拉伸。

**修复方案**

- RestructuringModal：为 `HandHost/CompanyHost` 设置 `size_flags_vertical=EXPAND_FILL`，确保右侧 CompanyStructure 有稳定高度展示 CEO 直属槽区域。
- CompanyStructure：用 `CenterContainer` 包裹 CEO 直属 `CardSlot`，让直属槽保持 `custom_minimum_size=130×90` 并在列宽中水平居中，从而不随下属槽网格拉宽。

**测试计划**

- 扩展 headless 回归覆盖：
	- UI 属性测试：RestructuringModal 的 HandHost/CompanyHost 在场景中具备 `size_flags_vertical=EXPAND_FILL`。
	- UI 属性测试：CompanyStructure 直属槽外层为 CenterContainer（或等价“水平居中且不拉伸”的容器），并保持 CardSlot 的 `custom_minimum_size.x == 130`。

**实施记录**

- 已修改：`ui/components/modal_panel/restructuring_modal.tscn`：
	- `HandHost/CompanyHost.size_flags_vertical=EXPAND_FILL`，避免右侧高度被挤压导致 CEO 直属槽不可见。
- 已修改：`ui/components/company_structure/company_structure.gd`：
	- CEO 直属槽使用 `CenterContainer` 包裹 `CardSlot`，使直属员工卡保持 compact 尺寸并在下属槽网格上方居中（不随列宽拉伸）。
- 已修改：`ui/scenes/tests/restructuring_layout_test.gd`：
	- 增加断言：HandHost/CompanyHost vertical flags 为 EXPAND_FILL；
	- 增加断言：CompanyStructure 直属槽外层为 CenterContainer（用于居中防拉伸）。

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180`：PASS（`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 45. 重组结构：左侧员工卡牌区域宽度收敛到“三列 compact 卡”所需宽度

**现象/需求**

- 你选择了“2”：左侧员工卡牌区需要一行展示 3 名员工（compact 卡尺寸不变），并允许滚动。
- 当前左侧区域仍然过宽（远不止 3 张卡宽），右侧公司树可用空间被挤压。

**涉及代码（初步定位）**

- `ui/components/modal_panel/restructuring_modal.tscn`：`Split(HSplitContainer).split_offset` 影响左右区域宽度。
- `ui/components/hand_area/hand_area.gd`：重组模式下 `HandArea.custom_minimum_size.x` 影响 SplitContainer 的最小分配宽度。

**根因**

- `HSplitContainer.split_offset` 的含义不是“左侧固定宽度”，而是对分割条位置的偏移；此前将其设为 `320` 会导致左侧在大屏下仍然偏宽。
- HandArea 在重组模式下最小宽度被限制为 `<=320`，与“三列 compact 卡”的需求不匹配。

**修复方案**

- RestructuringModal：在 `open()` 后按当前 viewport 宽度动态设置 split，使左侧默认宽度≈3列所需（目标约 440px），右侧尽可能宽。
- HandArea：重组模式下将 `custom_minimum_size.x` 调整为“三列 compact 卡”所需宽度（约 440px），保证布局稳定且不会出现 2 列/过窄。

**测试计划**

- 更新 `ui/scenes/tests/restructuring_layout_test.gd`：
	- 断言重组模式 HandArea 的 `custom_minimum_size.x` 落在 3 列目标宽度范围内（避免回归到 2 列或过宽）。

**实施记录**

- 已修改：`ui/components/hand_area/hand_area.gd`：重组模式 `HandArea.custom_minimum_size.x` 固定为约 440（3 列 compact 卡所需）。
- 已修改：`ui/components/modal_panel/restructuring_modal.tscn`：`Split.split_offset` 回到 0（避免在大屏下偏移过大）。
- 已修改：`ui/components/modal_panel/restructuring_modal.gd`：`open()` 后按实际布局测量并迭代调整 split，使左侧默认宽度≈440，右侧尽可能宽。
- 已修改：`ui/scenes/tests/restructuring_layout_test.gd`：更新断言，确保重组模式 HandArea 最小宽度处于 3 列目标范围内。

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180`：PASS（`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 46. 重组结构：从公司结构拖回待命区时，drop 区域过小（只有左上角能成功）

**现象/需求**

- 重组结构阶段，从右侧公司结构中将员工卡拖回左侧待命区时，只有拖到待命区左上角才能成功。
- 期望：拖到待命区的任意位置都能成功（更符合直觉）。

**涉及代码（初步定位）**

- 拖拽目标命中：
	- `ui/components/company_structure/company_structure.gd`：`_find_drop_target()`（从公司结构开始拖拽时，用 group=`employee_card_drop_target` 判断 drop target）
	- `ui/components/hand_area/hand_area.gd`：`_ready()`（将 `reserve_container/active_container` 加入 `employee_card_drop_target` group）
- 放下后的动作映射（reserve/active）：
	- `ui/scenes/game/game_panel_controller.gd`：`_on_hand_card_dropped()`（当前仅当 `target == hand_area.reserve_container` 才认为是“拖回待命区”）

**初步根因假设**

- “待命区任意位置”里有一部分区域不属于 `reserve_container` 的 `global_rect`（例如下方空白区域/滚动容器的空白区域），导致 `_find_drop_target()` 找不到任何 target，从而 drop 无效。
- 另一个潜在因素：`_find_drop_target()` 过滤使用 `c.visible` 而不是 `c.is_visible_in_tree()`；在重组模式下 `active_section` 虽隐藏，但 `active_container.visible` 仍为 true，可能导致“命中到不可见的 drop target”从而映射错误。

**确认**

- 你的要求是：只要在“待命卡牌滚动区域（ScrollContainer）”内即可（不包含标题/边缘空白）。

**修复方案**

- 重组模式下，把 HandArea 的 `ScrollContainer` 也作为 drop target：
	- `ScrollContainer` 覆盖整个“待命卡牌滚动区域”，加入 group=`employee_card_drop_target`；
	- 同时加入标记 group=`hand_area_reserve_drop_target`，便于 action 映射为 `to_reserve=true`。
- 同时在重组模式下移除 `active_container` 的 drop target group，避免“隐藏的 active 区域”误命中。
- `GamePanelController._on_hand_card_dropped()`：将 `hand_area_reserve_drop_target`（以及 reserve_container 的祖先/后代关系）统一判定为 `to_reserve=true`。

**测试计划**

- 新增/扩展 headless 回归测试（UI 属性测试为主）：
	- 断言重组模式下存在稳定的“待命区 drop target”（例如 `ReserveDropArea` 或 reserve_container 被拉伸为 EXPAND_FILL）；
	- 断言 `_on_hand_card_dropped()` 能将 drop 到该目标解析为 `to_reserve=true`（可通过抽取一个纯函数/小 helper 来做单元测试，避免依赖完整 GameScene）。

**状态**

**实施记录**

- 已修改：`ui/components/hand_area/hand_area.gd`：
	- 新增 `scroll_container` 引用；
	- 重组模式下：`scroll_container` 加入 `employee_card_drop_target` + `hand_area_reserve_drop_target`；
	- 重组模式下：`active_container` 移出 `employee_card_drop_target`，避免隐藏区域误命中。
- 已修改：`ui/scenes/game/game_panel_controller.gd`：重组模式下，drop 到 `hand_area_reserve_drop_target`（或 reserve_container 的祖先/后代）统一解析为 `to_reserve=true`。
- 新增：`ui/scenes/tests/restructuring_reserve_drop_target_test.gd`（`RestructuringReserveDropTargetTest`）并纳入 `ui/scenes/tests/all_tests.gd`。

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180`：PASS（`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 47. 飞机营销：图标需随摆放方向旋转（长边为底）

**现象/需求**

- 飞机营销板件在地图左右两侧（贴左/贴右）时，飞机“图标/背景纹理”仍为横向，导致在竖向 rect 中被压缩。
- 期望：飞机图标随摆放方向旋转，使其长边与板件长边一致（“长边为底”），避免压缩与方向不一致。

**涉及代码（初步定位）**

- `ui/scenes/game/map_canvas_drawer.gd`：`_draw_marketing_placement()` 当前使用 `_draw_texture_aspect_fit()` 绘制营销 type texture，但未做旋转；airplane 的方向由 `axis(row/col)` 决定。

**初步根因**

- airplane 营销板件本身通过 `axis` 决定了渲染 rect 的方向（横/竖），但绘制图标时始终轴对齐，导致在竖向 rect 内缩放不符合预期。

**修复方案**

- 仅对 `type == "airplane"` 的“营销 type texture”做旋转绘制：
	- 当板件渲染 rect 为“竖向（height > width）”时，将飞机图标旋转 90° 后再做 aspect-fit（避免被压扁）。
	- 产品 icon（居中）与 board_number 徽标（右上角）保持不旋转（仍按屏幕坐标）。
- 实现方式：在 `_draw_marketing_placement()` 内对飞机图标绘制包一层 `draw_set_transform(center, rot, Vector2.ONE)`，绘制完成后恢复 transform，并使用 `draw_size=(h,w)` 交换尺寸以匹配旋转后的包围盒。

**测试计划（已落实）**

- 新增 headless 渲染行为测试：
	- 构造 airplane placement，调用 `_draw_marketing_placement()`；
	- “竖向 rect”应触发 `draw_set_transform`（旋转）调用；“横向 rect”不触发。

**状态**

**实施记录**

- 已修改：`ui/scenes/game/map_canvas_drawer.gd`：airplane 的 type texture 在竖向 rect 下旋转 90° 绘制。
- 已新增：`ui/scenes/tests/airplane_marketing_icon_rotation_test.gd` 并纳入 `ui/scenes/tests/all_tests.gd`。
- 已修改：`ui/scenes/tests/airplane_marketing_outside_render_test.gd`：补齐 `draw_set_transform()` stub（避免 FakeCanvas 缺方法）。

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180`：PASS（`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 48. 游戏日志：房屋被打上广告缺日志；采购日志缺路线；需要可读性方案

**现象/需求**

- 当前日志中：
	- 房屋因营销被“打上广告/产生需求”的过程缺少可读的日志（只有“发起营销”一条，无法追溯覆盖了哪些房屋/新增了多少需求）。
	- 采购（饮料）日志过于简略：看不到玩家选择的采购路线（从哪家餐厅出发、经过哪些饮料点/路径）。
- 同时需要避免日志过度刷屏（与玩家/事件日志混在一起会变得冗长难读）。
- 需要先提出改进方案供你审查；你点头后再实施。

**涉及代码（初步定位）**

- 日志写入：
	- `ui/scenes/game/game_event_log_controller.gd`：订阅 EventBus 并生成日志文本
	- `ui/components/game_log/game_log_panel.gd`：日志 UI（目前仅平铺列表；entries 支持 `details` 但 UI 不展示）
- 事件来源：
	- 营销结算：`core/rules/phase/marketing_settlement.gd`（产出 `round_state.marketing.processed`，包含 `affected_houses/demands_added`）
	- 阶段推进事件：`gameplay/actions/advance_phase_action.gd`
	- 饮料采购事件：`gameplay/actions/procure_drinks_action.gd`（DRINKS_PROCURED 事件未携带 route/selected_sources）

**初步根因**

- EventBus 事件缺少“可读的结构化信息”（营销结算摘要/受影响房屋列表、采购路线/来源等），导致 UI 只能输出简略文本或被迫刷大量日志。
- GameLogPanel 虽保存 `details`，但缺少“展开/查看详情”的通用交互，导致无法把“短摘要 + 可展开细节”作为统一机制。

**确认**

- 你选择了：
	- 营销日志颗粒度：A（每块营销板 1 条摘要，可展开详情）
	- 采购路线日志：A（起点餐厅 + 选中的饮料点）

**修复方案**

- 统一“短摘要 + 可展开详情”机制：
	- `GameLogPanel`：双击日志条目弹出详情窗口（显示 message + details）。
- 营销结算日志（房屋被打上广告/产生需求）：
	- 在“离开 Marketing 阶段”时，从 `round_state.marketing.processed` 生成 `demand_generated` 事件（每块板 1 条），携带 `player_id/board_number/product/demands_added/affected_house_numbers` 等（详情可展开）。
	- 同时覆盖四条路径（避免自动跳过阶段时丢事件）：
		- `gameplay/actions/advance_phase_action.gd`
		- `gameplay/actions/skip_action.gd`
		- `gameplay/actions/skip_sub_phase_action.gd`
		- `core/engine/game_engine/command_runner.gd`（auto_advance 的阶段变更事件生成）
- 饮料采购日志：
	- `DRINKS_PROCURED` 事件补充 `restaurant_id + picked_sources + selected_sources`；
	- UI 日志摘要追加“起点餐厅 + 进货点”信息（不展示完整路径坐标，详见 details）。

**实施记录**

- 已修改：`ui/components/game_log/game_log_panel.gd`：双击日志条目打开详情窗口（message + details）。
- 已修改：`ui/scenes/game/game_event_log_controller.gd`：
	- 订阅并渲染 `DEMAND_GENERATED`；
	- `DRINKS_PROCURED` 日志追加起点/进货点摘要。
- 已修改：
	- `core/engine/game_engine/command_runner.gd`：离开 Marketing 时生成 `DEMAND_GENERATED` 事件（auto_advance 路径）。
	- `gameplay/actions/advance_phase_action.gd` / `skip_action.gd` / `skip_sub_phase_action.gd`：离开 Marketing 时同样生成 `DEMAND_GENERATED`（非 auto_advance 路径）。
- 已修改：`gameplay/actions/procure_drinks_action.gd`：`DRINKS_PROCURED` 事件 data 扩展为包含起点餐厅与选定来源信息。
- 已新增：`core/tests/marketing_demand_generated_event_test.gd` 并纳入 `ui/scenes/tests/all_tests.gd`。
- 已修改：`core/tests/procure_drinks_route_rules_test.gd`：断言 `DRINKS_PROCURED` 事件包含 `restaurant_id/picked_sources`（回归保护）。

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180`：PASS（`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 49. 提供“日志验证”测试存档（便于手工审查日志改动）

**现象/需求**

- 需要一个测试存档，用于手工复核“日志事件/格式/详情展开”等改动是否生效。
- 目标：加载后即可在日志里看到一组覆盖关键场景的日志（营销结算影响房屋、采购路线等），减少手动搭建局面的成本。

**涉及代码（初步定位）**

- 手工复核存档生成：
	- `tools/generate_manual_test_saves.gd`
	- `tools/generate_manual_test_saves_manifest.gd`
	- 输出目录：`res://.savings/manual_cases/...`

**初步根因**

- 现有 manual_cases 生成逻辑会把当前状态“冻结”为 initial_state（清空 `command_history`），以减少噪音；但这会导致“加载时回放产生事件 → 复核日志”的场景无法覆盖（没有命令可回放就没有事件）。

**修复方案（提案，需你点头后实施）**

- 在 manual_cases 体系中新增一个 `logs` 用例：
	- 生成时保留少量命令历史（不冻结），确保读档回放能恢复 EventBus.history，并让日志面板可复核。
	- 存档说明 MD 里写清：打开日志、筛选、双击查看详情，检查营销结算/采购路线等条目。

**确认（来自你在 #48 的补充）**

- A：加载后即可看到历史日志（用于检查恢复/筛选/详情展示）。
- 固定为 2 人 + 基础地图。

**实施记录**

- 已修改：`tools/generate_manual_test_saves.gd`：
	- 支持 `case.freeze_as_initial=false`（允许某些用例保留命令历史用于回放）。
	- 支持 `kind=="logs"` 输出到 `res://.savings/manual_cases/logs/`。
	- 新增 builder `logs_event_review`：构造 2 人基础局面并保留命令历史，使读档回放后自动产生日志事件（营销结算需求 + 采购路线摘要）。
- 已修改：`tools/generate_manual_test_saves_manifest.gd`：新增 case `logs/event_log_review`（并设置 `freeze_as_initial=false`）。
- 已新增：`res://.savings/manual_cases/logs/event_log_review.json` + `res://.savings/manual_cases/logs/event_log_review.md`（用于手工验收）。
- 已修改：`.savings/manual_cases/README.md`：补充 logs 分类与入口。
- 已新增：`core/tests/manual_log_save_test.gd`：加载 `event_log_review.json` 后断言 EventBus.history 至少包含 `MARKETING_PLACED` / `DRINKS_PROCURED` / `DEMAND_GENERATED`，用于回归保护。
- 已修改：`ui/scenes/tests/all_tests.gd`：纳入 `ManualLogSaveTest`。

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`：PASS（`.godot/GameSmokeTest.log`）
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180`：PASS（106/106，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）

---

## 50. 日志验证存档：尽可能覆盖更多日志事件类型（便于集中审查）

**现象/需求**

- 现有 `logs/event_log_review` 会在读档回放后产生 `MARKETING_PLACED/DRINKS_PROCURED/DEMAND_GENERATED` 等日志，便于验证“营销结算/采购路线/详情展开”。
- 你希望“尽可能覆盖完整游戏中的事件”，以便集中审查其它日志（例如：招聘/培训/解雇、餐厅放置/移动、放房屋/加花园、生产食物、里程碑、阶段/回合/现金变化等）。

**涉及代码（初步定位）**

- 日志显示范围：
	- `ui/scenes/game/game_event_log_controller.gd`：`EVENT_TYPES_TO_LOG`
- 测试存档生成/回放：
	- `tools/generate_manual_test_saves.gd` / `tools/generate_manual_test_saves_manifest.gd`
	- `res://.savings/manual_cases/logs/`

**确认（来自你对 #50 的补充）**

- 覆盖范围：B（也要覆盖 EventBus 中存在但目前未显示的事件类型，因此需要扩展 `EVENT_TYPES_TO_LOG`）
- 存档组织形式：B（多个分主题存档）
- 固定：`2 人 + base map`；同时希望尽可能覆盖“失败/极端”场景

**实施方案（最终）**

- 扩展 `GameEventLogController.EVENT_TYPES_TO_LOG`，并补齐对应事件的可读日志渲染。
- 对“阶段离开时才能从 state 推导”的事件补齐发射（确保读档回放时能从 `EventBus.history` 恢复）：
	- 离开 `Dinnertime`：从 `round_state.dinnertime.sales` 拆出 `FOOD_SOLD`
	- 离开 `Marketing`：从 `round_state.marketing.processed` 拆出 `MARKETING_EXPIRED`
	- 离开 `Cleanup`：从 `round_state.cleanup.inventory_discarded` 拆出 `FOOD_DISCARDED`
	- 回合变更：补齐 `ROUND_ENDED`
	- 覆盖路径：`auto_advance` + 手动推进（`advance_phase/skip/skip_sub_phase`）
- 新增多个 logs 存档（每档覆盖 1 主题，便于你逐类审查日志）。

**实施记录**

- 已修改：`ui/scenes/game/game_event_log_controller.gd`
	- 扩展 `EVENT_TYPES_TO_LOG`（包含 `ROUND_ENDED/FOOD_SOLD/FOOD_DISCARDED/MARKETING_EXPIRED/GAME_STARTED/GAME_ENDED/...`）
	- 新增对应事件的日志文本（摘要 + details）
- 已修改：`core/engine/game_engine/command_runner.gd`
	- `_build_phase_change_events`：补齐 `ROUND_ENDED`；离开 `Dinnertime/Marketing/Cleanup` 时分别生成 `FOOD_SOLD/MARKETING_EXPIRED/FOOD_DISCARDED`
	- 新增 helper：`_build_food_sold_events_from_dinnertime_report` / `_build_marketing_expired_events` / `_build_cleanup_inventory_discarded_events`
- 已修改：`gameplay/actions/advance_phase_action.gd` / `gameplay/actions/skip_action.gd` / `gameplay/actions/skip_sub_phase_action.gd`
	- 在“非 auto_advance 的阶段推进路径”同样补齐上述事件生成（避免遗漏）
- 已修改：`tools/generate_manual_test_saves_manifest.gd`：新增 logs 用例清单（分主题）
- 已修改：`tools/generate_manual_test_saves.gd`：实现对应 builder（并修复 `PlaceHouses` 中 `place_house/add_garden` 互相占位与 Payday 薪资不足导致的生成失败）
- 已新增：`res://.savings/manual_cases/logs/` 下 5 个新存档 + 说明：
	- `event_log_employee_recruit_train`
	- `event_log_employee_fire`
	- `event_log_build_and_move`
	- `event_log_produce_and_cleanup`
	- `event_log_dinnertime_sale`
- 已修改：`.savings/manual_cases/README.md`：更新 logs 索引
- 已新增：`core/tests/manual_log_saves_coverage_test.gd` 并纳入 `ui/scenes/tests/all_tests.gd`

**验证**

- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 240`：PASS（107/107，`.godot/AllTests.log`）

**状态**

- Implemented（待手动验收）
