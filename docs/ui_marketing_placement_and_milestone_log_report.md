# UI 整改报告：营销放置异常 & 里程碑提示/日志缺失（已在工作区修复，待你确认是否保留）

更新时间：2026-01-09  
状态：已准备并验证修复 patch（未提交）；如你希望先 review 再决定是否保留/回退，请告诉我。

---

## 0. 结论摘要（对应你已确认的需求）

### 0.1 营销放置（广告牌等）
- ✅ 选点不更新的根因：营销预览覆盖层的“中心标记”吞鼠标事件 → 已改为完全穿透（`mouse_filter=IGNORE`）
- ✅ 预览范围不正确的根因：UI 以前用硬编码“曼哈顿半径” → 已改为用 `core/rules/marketing_range_calculator.gd` 计算“受影响房屋”并高亮
- ✅ 同时展示两类信息（你确认：二者都应该显示）
	- A「可放置范围/距离」：地图绿色高亮“合法可放置格”（包含邻路/边缘/距离等规则）
	- B「受影响房屋」：hover/点击时高亮受影响房屋格
- ✅ 失败反馈：面板红字提示 + 写入游戏内日志（GameLogPanel），不再“看起来没反应”
- ✅ 当“绿色可放置格 = 0”：面板直接提示原因（例如无餐厅/超距/无道路/必须边缘等），避免误以为是 bug
- ✅ 飞机角落：点击后弹窗选择横飞/竖飞（你确认：A）

### 0.2 里程碑日志 + 游戏内提示
- ✅ 里程碑面板能看到但日志缺失的根因：从未发射 `EventBus.EventType.MILESTONE_ACHIEVED`
- ✅ 已在引擎命令执行后（包含 auto-advance）通过 `old_state/new_state` 差异推导并 emit 里程碑事件
- ✅ 游戏日志：输出“玩家X 获得里程碑：名称 (id)”
- ✅ 游戏内提示：toast（你确认：B，且需要注明获得者）

### 0.3 回归结果（headless）
- `tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 40` → `PASS`
- `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` → `72/72 PASS`

---

## 1. 你描述的现象（复述 + 初步定位）

### 1.1 营销放置（广告牌）
- 选择“广告牌广告”后：
	- 预览范围不正确
	- 点击地图后目标位置不更新
	- “确认”按钮无变化
	- 游戏日志没有明确输出（命令行也没有提示）
- 失败员工：营销实习生
- 营销类型：广告牌

### 1.2 里程碑日志
- “游戏菜单 → 里程碑”面板能看到已获得里程碑
- 但获得时未在游戏日志体现，也缺少游戏内提示（toast/弹窗/音效等）

---

## 2. 营销放置：代码链路与问题点

### 2.1 UI/交互链路（从点击到命令）
1. 右侧 ActionPanel 触发 `initiate_marketing` 动作  
2. `ui/scenes/game/game_panel_controller.gd` 分派到 `ui/scenes/game/game_panel_marketing_panels.gd:show_marketing_panel()`  
3. `MarketingPanel` 选择类型后，调用 map callback：`GameMapInteractionController.on_marketing_map_selection_requested(marketing_type, employee_type)`  
4. 地图 hover/click 由 `MapCanvas` 发出 `cell_hovered/cell_selected` 信号，`GameMapInteractionController` 负责：
	- hover：调用 `_overlay_controller.preview_marketing_range(...)`
	- click：把 world_pos 回填给 `MarketingPanel.set_selected_target(world_pos)`，并再次预览
5. `MarketingPanel` 点击确认发射 `marketing_requested`  
6. `game_panel_marketing_panels.gd:_on_marketing_requested(...)` 执行命令：
	- `Command.create("initiate_marketing", ..., {"position":[x,y], ...})`
	- 命令执行入口最终走到 `Game._execute_command` → `GameEngine.execute_command`

---

### 2.2 问题点 A：营销预览覆盖层会“吞掉鼠标点击”，导致地图选点失效（高概率命中）

**现象对应**：  
“点击地图后目标位置不更新 / 确认按钮无变化”，并且你能看到预览覆盖层。

**根因（代码级）**：  
`MarketingRangeOverlay` 本体设置了 `mouse_filter = IGNORE`，但它创建的“中心标记”及其子控件没有设置 `mouse_filter`，默认会拦截鼠标事件，导致点击落在覆盖层上而不是 MapCanvas。

- 覆盖层：`ui/overlays/marketing_range_overlay.gd:30`（设置 IGNORE）
- 范围格子 rect：`ui/overlays/marketing_range_overlay.gd:95-101`（显式 IGNORE ✅）
- **中心标记 marker / icon_label / RangeCircle 未设置 mouse_filter**：`ui/overlays/marketing_range_overlay.gd:127-169`（❌）

这会造成一个非常“直观”的问题：  
你把鼠标停在某格上（overlay 出现中心标记），随后点击——**点击被 marker 吃掉**，MapCanvas 的 `cell_selected` 收不到，自然也不会回填 target。

---

### 2.3 问题点 B：预览“范围算法”和规则/核心实现不一致（必然不正确）

**现象对应**：  
“广告牌预览范围不正确”

**现状实现**：
- `MarketingPanel` 内部用硬编码 `MARKETING_TYPES[*].range` 作为预览范围与文案：
	- `ui/components/marketing_panel/marketing_panel.gd:25-30`
	- billboard 当前写死为 `range: 2`（与规则不一致）
- `MarketingRangeOverlay` 用“曼哈顿距离菱形”来画范围：
	- `ui/overlays/marketing_range_overlay.gd:_get_tiles_in_range()`

**问题**：  
营销影响范围在规则与核心实现里并不是一个简单“曼哈顿半径”：
- `billboard`：影响四向相邻房屋（不是半径 2）
- `mailbox`：同街区（block）房屋集合（不是半径 3）
- `airplane`：整行/整列（tile row/col）
- `radio`：以放置点所在 tile 为中心的 3×3 tile 覆盖到的房屋（边缘会裁剪），也不是简单半径

核心范围算法已经存在（且是对齐规则的方向）：  
`core/rules/marketing_range_calculator.gd`（billboard/mailbox/radio/airplane 的 house_id 集合计算）

结论：  
当前 UI 预览必然会“看起来不对”，并且会误导玩家。

---

### 2.4 问题点 C：失败反馈缺失（导致“看起来什么都没发生”）

`ui/scenes/game/game_panel_marketing_panels.gd:_on_marketing_requested()` 只在 `result.ok` 时做清理/关闭。  
失败时不做任何 UI 提示，也不写入 GameLogPanel：
- 见 `ui/scenes/game/game_panel_marketing_panels.gd:213-234`

因此玩家会感知到：
- 点了确认没反应
- 没有明确日志（GameLogPanel 只记录 EventBus 事件；失败不属于 EventBus 事件）

附带点：即使命令行里有 `GameLog.warn("命令执行失败: ...")`，也不等同于“游戏内日志”，且对玩家不友好。

---

### 2.5 “营销实习生 + 广告牌”为什么会失败（规则层说明）

你提到失败员工为“营销实习生”、类型为“广告牌广告”，这一组合在规则层是**允许**的，但放置失败通常来自以下硬性条件：

- 员工卡（`modules/base_employees/content/employees/marketer.json`）的可放置距离是 `road 2`，因此需要满足：
	- 你至少有 1 家餐厅（否则距离判定无法通过）
	- 放置点在公路距离 2 以内
- 广告牌放置点还必须：
	- 在空格（非道路）上，且该格无建筑
	- 与道路相邻
	- 不与其他营销板件占用同一格

本次整改后：地图绿色高亮会直接告诉你“哪些格满足上述所有条件”，且失败时会在面板/游戏日志中给出明确原因。

---

## 3. 里程碑日志：代码链路与问题点

### 3.1 现状链路
- UI 侧日志面板订阅了 `EventBus.EventType.MILESTONE_ACHIEVED` 并会写入 GameLogPanel：
	- `ui/scenes/game/game_event_log_controller.gd:16-33`（订阅）
	- `ui/scenes/game/game_event_log_controller.gd:96-97`（写日志）

### 3.2 根因：从未有人 emit 这个事件（因此日志必然缺失）
全工程搜索不到任何：
`EventBus.emit_event(EventBus.EventType.MILESTONE_ACHIEVED, ...)`

里程碑系统只会：
- 修改 `state.players[*].milestones`
- 记录到 `state.round_state["milestones_auto_awarded"]`（便于调试/回合内追踪）
	- `core/rules/milestone_system.gd:54-66`

因此你会看到：
- 里程碑面板能显示（它读的是 state）
- 但事件日志面板不会显示（它等的是 EventBus 事件）

---

## 4. 已实施整改（可验收）

### 4.1 营销放置（广告牌等）

已完成：
- 选点失效：修复覆盖层吞点击（`ui/overlays/marketing_range_overlay.gd`）
- A「可放置范围/距离」：地图绿色高亮“合法可放置格”（`ui/scenes/game/game_map_interaction_controller.gd:_sync_marketing_highlights()`）
- B「受影响房屋」预览：用 `core/rules/marketing_range_calculator.gd` 计算 house 集合并高亮（`ui/scenes/game/game_overlay_marketing_range.gd`）
- 失败反馈：面板红字 + 写入 GameLogPanel（`ui/components/marketing_panel/marketing_panel.tscn`、`ui/scenes/game/game_panel_marketing_panels.gd`）
- 飞机角落：弹窗选择横飞/竖飞，并将 `axis` 传入 `initiate_marketing`（`ui/scenes/game/game_map_interaction_controller.gd` 等）

验收建议：
1. 进入 Working → Marketing 子阶段，打开“发起营销”
2. 选择“广告牌”：地图应出现绿色高亮可放置格；hover/点击时应高亮受影响房屋
3. 点击非绿色格：应提示不可放置；点击绿色格：目标位置更新，确认按钮可用
4. 故意触发失败（例如超距/无餐厅）：应出现红字错误，同时 GameLogPanel 有“营销放置失败 …”

### 4.2 里程碑日志 + 提示

已完成：
- 引擎在命令执行完成后推导并 emit `MILESTONE_ACHIEVED`（`core/engine/game_engine/command_runner.gd`）
- GameLogPanel 输出包含获得者与里程碑名称（`ui/scenes/game/game_event_log_controller.gd`）
- 游戏内 toast：所有玩家可见，并注明获得者（`ui/scenes/game/game_overlay_controller.gd`）

验收建议：
1. 触发任意里程碑（例如与营销相关的 `first_radio`）
2. 观察：游戏日志出现“玩家X 获得里程碑 …”，同时顶部出现 toast

---

## 5. 后续整改计划（可选）

### P0（体验补齐）✅ 已完成
- 当“绿色可放置格”为 0 时，在面板直接提示原因（例如：你还没有餐厅 / 全部位置超距 / 必须邻路/边缘等）

### P1（体验优化）
- 飞机在角落 hover 时：可选显示 row/col 两种预览，或在未选择方向时不显示预览（你更偏好哪种？）
- hover 预览节流/缓存（避免在大地图上频繁计算）

### P2（增强）
- 里程碑 toast：增加音效/点击跳转到“游戏菜单 → 里程碑”
