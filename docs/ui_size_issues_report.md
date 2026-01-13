# UI组件大小问题完整报告（核实与修订）

> 更新时间: 2026-01-11  
> 核实范围: ui/components, ui/dialogs, ui/scenes  
> 核实方式: 仅基于 `.tscn`/`.gd` 静态检查（未在编辑器中逐组件肉眼预览；主题/字体/UI 缩放/窗口分辨率会影响最终像素）

---

## 0. 结论摘要

- 已修复：`PlayerPanel` 必现裁剪；`TurnOrderDisplay` 5 人宽度不足；`ChoiceDialog` 3+ 选项溢出；`GameLogPanel` 头部拥挤（固定两行）。
- 已修复：`GameLogPanel` 初始宽度与 `LeftArea` 最小宽度冲突导致“右侧被截断”（最小宽度下调 + `FilterRow` 可换行）。
- 已修复：`game.tscn` 顶部/主体/底部的硬编码 offset（重构为容器布局）。
- 已缓解：`ModalPanelBase`/`RestructuringModal` 小窗口溢出风险（面板尺寸 clamp + ContentHost 内部滚动）。
- 可读性优化：`EmployeeIcon`/`EmployeeCard` 尺寸与字号提升；`InventoryPanel`、`TrainPanel`、`ConfirmDialog` 等补齐滚动与最小尺寸。
- 已优化：`TopBar` 改为固定两行（InfoRow + ButtonRow），缓解窄宽下的横向拥挤（极窄窗口仍建议回归验证）。
- 已修复：若干固定宽/固定高 overlay/panel（`DinnerTimeOverlay`、里程碑 toast 等；见“额外发现”）。
- 已修复：地图缩放/平移输入被 `MapCanvas.mouse_filter` 阻断；放置提示条/提示标签遮挡地图点击（均通过 `mouse_filter=IGNORE/PASS` 修正）。
- 已优化：`MilestonePanel` 最小尺寸与文本换行（避免在 LeftPanel 窄宽下挤压/遮挡左侧公司切换按钮）。
- 已修复：`RecruitPanel` 初次打开时偶发的卡片不换行/溢出到右侧（嵌入 RightPanel/首次显示后强制重排）。

---

## 一、高风险问题（严重影响显示/较易复现）

### 1. PlayerPanel - 玩家信息面板（必现裁剪 + 宽度不足）

**文件**: `ui/components/player_panel/player_panel.tscn`

**核实结论**: 属实（已修复）

**问题（修复前，tscn）**:
- `MarginContainer` 使用 `anchors_preset = 5`（左右都为 0.5）并设置：
  - `offset_left = -40.0, offset_right = 40.0` → 内容宽度约 `80px`
  - `offset_bottom = 47.0`（未设置 `anchor_bottom`，默认 0）→ 内容高度约 `47px`
- 该 `MarginContainer` 承载标题与 `ItemsContainer`，因此会直接导致裁剪。

**问题（GD）**: `ui/components/player_panel/player_info_item.gd`
- `PlayerInfoItem._build_ui()` 设置 `custom_minimum_size = Vector2(200, 36)`，但内部 `HBoxContainer`：
  - 子节点最小宽度和为 `8+60+60+40+40 = 208`
  - `separation = 8` 且有 4 个间隔 → 额外 `32`
  - 仅子节点最小需求已约 `240px`（不含 PanelContainer 内边距）

**影响**:
- 标题、玩家列表必然被裁剪/挤压；在 4~5 玩家时尤为明显。
- 在右侧 `RightPanel` 中可能表现为“右侧区域很空，但玩家列表只显示一条/几乎不见”。

**建议**:
- `MarginContainer` 改为全屏布局（例如 `anchors_preset = 15` / `PRESET_FULL_RECT`），移除这些固定 offset。
- 重新核定 `PlayerInfoItem` 的宽度策略：要么提高 `PlayerPanel`/`PlayerInfoItem` 的最小宽度（建议 ≥260），要么减少子控件的 `custom_minimum_size.x` 并让名称列 `SIZE_EXPAND_FILL` 承担自适应压缩。

**修复（已实施）**:
- `ui/components/player_panel/player_panel.tscn`：`MarginContainer` 改为 `PRESET_FULL_RECT`；面板最小尺寸提升到 `260×200`。
- `ui/components/player_panel/player_info_item.gd`：最小宽度调整到 `240×36`（与子控件最小需求一致），避免静态推导的最小宽度冲突。

---

### 2. GameLogPanel - 游戏日志面板（最小宽度不足）

**文件**: `ui/components/game_log/game_log_panel.tscn`

**核实结论**: 属实（已修复：头部两行 + 窄宽可换行）

**问题（修复前，tscn）**:
- 面板 `custom_minimum_size = Vector2(380, 250)`，且过滤/搜索区为单行横排，在窄宽下会互相挤压或被裁剪。

**影响**:
- 结合 `ui/scenes/game/game.tscn`：`LeftArea.custom_minimum_size = Vector2(360, 0)`，与 `GameLogPanel` 的 `380px` 存在必现冲突：默认宽度下右侧内容会被截断，需要手动拉伸 LeftArea。

**修复（已实施）**:
- `ui/components/game_log/game_log_panel.tscn`：头部改为固定两行：`TopRow(标题+全屏+清空)` + `FilterRow(玩家过滤+搜索+过滤菜单)`，避免自适应换行造成的“挤成一团”。
- `ui/components/game_log/game_log_panel.gd`：更新节点路径以匹配新结构。
- `ui/components/game_log/game_log_panel.tscn`：`FilterRow` 改为 `HFlowContainer`（窄宽自动换行）；`custom_minimum_size` 下调为 `340×240`，避免与 `LeftArea(360)` 冲突。

---

### 3. ChoiceDialog - 选择对话框（多选项时必然溢出）

**文件**: `ui/dialogs/choice_dialog.tscn`, `ui/dialogs/choice_dialog.gd`

**核实结论**: 属实（已修复：支持换行 + 自动增高）

**问题（修复前）**:
- Window 固定大小：`size = Vector2i(380, 210)`；且 `OptionsRow` 为单行容器时，3+ 选项会发生溢出。

**推导**:
- 3 个按钮最小需求：`110*3 + 12*2 = 354px` > `340px` → 必然挤压/裁剪/溢出
- 4 个按钮更严重

**修复（已实施）**:
- `ui/dialogs/choice_dialog.tscn`：`OptionsRow` 使用 `HFlowContainer`，允许按钮换行。
- `ui/dialogs/choice_dialog.gd`：根据按钮换行行数，动态增加窗口高度，并同步设置 `OptionsRow.custom_minimum_size.y`；高度会 clamp 到视口高度的 90%。

---

## 二、中等风险问题（可能影响显示，需结合分辨率/UI 缩放验证）

### 4. RecruitPanel - 招聘面板（最小高度偏小，但可滚动）

**文件**: `ui/components/recruit_panel/recruit_panel.tscn`

**核实结论**: 原问题部分属实（已优化：提升最小高度）

**现状**:
- 面板 `custom_minimum_size = Vector2(400, 260)`
- 列表区域使用 `ScrollContainer` 且 `size_flags_vertical = 3`（可滚动）

**影响**:
- 高度过小会导致可视列表区域变窄，体验上“像是被压扁”；但功能上仍可通过滚动查看全部卡片。

**建议**:
- 已将最小高度提高到 `260` 以改善默认可视区域；仍建议在高 `ui_scale` 下实测嵌入 RightPanel 的效果。
- 若出现“首次打开卡片不换行、内容溢出到右侧”的现象：已在 `ui/components/recruit_panel/recruit_panel.gd` 增加 `resized/visibility_changed` 驱动的延迟 `queue_sort()`，确保首次嵌入/首次显示后布局稳定。

---

### 5. TrainPanel - 培训面板（无滚动容器，内容易顶出）

**文件**: `ui/components/train_panel/train_panel.tscn`, `ui/components/train_panel/train_panel.gd`

**核实结论**: 属实（已修复：目标列表区增加滚动）

**问题（修复前）**:
- 面板 `custom_minimum_size = Vector2(450, 280)`
- `TrainTargetItem` 最小高度 `50px`，目标项较多时会快速累积高度
- `PathSection/PathContainer` 为 VBox 且没有滚动

**修复（已实施）**:
- `ui/components/train_panel/train_panel.tscn`：`PathSection` 内新增 `ScrollContainer` 包裹 `PathContainer`，目标列表可滚动。

---

### 6. InventoryPanel - 库存面板（宽度/高度偏小）

**文件**: `ui/components/inventory_panel/inventory_panel.tscn`, `ui/components/inventory_panel/inventory_panel.gd`

**核实结论**: 属实（已优化：提升最小尺寸 + 文本换行）

**问题（修复前）**:
- 面板 `custom_minimum_size = Vector2(200, 100)` 偏小，且单行文本在 `60px` 宽度下易被裁剪。

**修复（已实施）**:
- `ui/components/inventory_panel/inventory_panel.tscn`：最小尺寸提升到 `220×180`。
- `ui/components/inventory_panel/inventory_panel.gd`：数量显示改为两行（名称 + `×数量`），避免窄宽裁剪。

---

### 7. TurnOrderDisplay - 回合顺序显示（宽度略不足；高度为 0 不是核心问题）

**文件**: `ui/components/turn_order/turn_order_display.tscn`, `ui/components/turn_order/turn_order_display.gd`

**核实结论**: 属实（已修复：最小宽度提升）

**问题（修复前）**:
- 根节点 `custom_minimum_size = Vector2(150, 0)`
- 每个徽章 `custom_minimum_size = Vector2(26, 26)`，容器 `separation = 6`
- 5 人局最小宽度需求约：`26*5 + 6*4 = 154px` > `150px`

**修复（已实施）**:
- `ui/components/turn_order/turn_order_display.tscn`：最小宽度调整为 `160px`（覆盖 5 人局最小需求）。

---

### 8. ModalPanelBase / RestructuringModal - 遮罩面板固定最小尺寸（小窗口可能溢出）

**文件**: `ui/components/modal_panel/modal_panel_base.tscn`, `ui/components/modal_panel/modal_panel_base.gd`, `ui/components/modal_panel/restructuring_modal.tscn`

**核实结论**: 属实（已缓解：尺寸 clamp + ContentHost 内部滚动）

**更正（针对原报告 12）**:
- `Panel.layout_mode = 0` 并不意味着“不会居中”，因为 `ModalPanelBase.open()` 会调用 `_center_panel()` 进行居中与边距 clamp。

**问题（修复前）**:
- `ModalPanelBase.Panel.custom_minimum_size = Vector2(820, 600)`
- `RestructuringModal.Panel.custom_minimum_size = Vector2(980, 640)`
- 当 `covered_rect` 比该尺寸更小时，面板会超出可覆盖区域（需要“缩小 panel.size”或内部滚动策略）

**修复（已实施）**:
- `ui/components/modal_panel/modal_panel_base.gd`：`_center_panel()` 会将 `panel.size` clamp 到 `covered_rect`（预留边距），避免面板超出覆盖区域。
- `ui/components/modal_panel/modal_panel_base.tscn` / `ui/components/modal_panel/restructuring_modal.tscn` / `ui/components/modal_panel/turn_order_selection_modal.tscn`：`ContentHost` 改为 `ScrollContainer`（禁用水平滚动），内容可在面板变小时纵向滚动。

---

## 三、布局结构问题（响应式适配）

### 9. game.tscn - 主游戏场景（固定高度/硬编码 offset）

**文件**: `ui/scenes/game/game.tscn`

**核实结论**: 属实（已修复：重构为容器布局）

**现状（修复后）**:
- `ui/scenes/game/game.tscn` 使用 `UIRoot: VBoxContainer` 组织 `TopBar / MainContent / BottomPanel`，移除硬编码 offset。
- `BottomPanel` 显示/隐藏通过 `visible` 控制，`MainContent` 会在容器内自动占用剩余空间。

**潜在影响**:
- 小宽度窗口下，`TopBar` 内按钮数量很多：已改为两行布局以缓解；极窄窗口仍可能需要进一步的“收纳/折叠菜单”策略。

**建议**:
- 当前已完成“容器布局”改造；后续如要继续提升窄屏体验，可考虑将部分按钮收进菜单/更多操作区。

---

## 四、对话框窗口问题（固定尺寸）

### 10. ConfirmDialog - 确认对话框

**文件**: `ui/dialogs/confirm_dialog.tscn`, `ui/dialogs/confirm_dialog.gd`

**核实结论**: 属实（已缓解：长文本可滚动）

**问题（修复前）**:
- `size = Vector2i(350, 180)` 固定大小，长文本可能被裁剪。

**修复（已实施）**:
- `ui/dialogs/confirm_dialog.tscn` / `ui/dialogs/confirm_dialog.gd`：消息区改为 `ScrollContainer`，长文本不再被裁剪（改为滚动查看）。

---

## 五、动态创建 UI 的尺寸问题（误报/可接受项修正）

### 11. MarketingPanel - 营销面板

**文件**: `ui/components/marketing_panel/marketing_panel.gd`, `ui/components/marketing_panel/marketing_type_button.gd`

**核实结论**: 原报告为误报（MarketingTypeButton 已有明确尺寸）

**现状**:
- `MarketingTypeButton.custom_minimum_size = Vector2(110, 84)`，并由 `HFlowContainer` 承载，可换行

**建议**:
- 无需因“未知尺寸”单独处理；若要做响应式，可在窄屏下减少按钮信息密度或缩小按钮高度。

---

### 12. ProductionPanel - 生产面板

**文件**: `ui/components/production_panel/production_panel.gd`

**核实结论**: 低风险（`OptionButton` 高度由主题决定，`custom_minimum_size.y = 0` 并非问题）

**建议**:
- 如确实观察到不同平台高度不一致，再考虑统一设置 `custom_minimum_size.y`（例如 32）。

---

### 13. LeftPanel - 左侧面板

**文件**: `ui/components/left_panel/left_panel.gd`

**核实结论**: 低风险（玩家数上限为 5，且 tabs 为纵向）

**现状**:
- 玩家按钮 `custom_minimum_size = Vector2(44, 44)`，并放在 `VBoxContainer` 内
- `TurnOrderTrack/TurnOrderDisplay` 等处也将玩家数 clamp 到 `0~5`

**建议**:
- 仅在非常小的窗口高度或 `ui_scale` 很大时，才需要为 tabs 增加滚动（可作为后续优化）。

---

## 六、低风险项复核（原报告条目）

### 14. EmployeeCard - 员工卡片

**文件**: `ui/components/employee_card/employee_card.tscn`, `ui/components/employee_card/employee_card.gd`

**核实结论**: 已优化（更偏向可读性）

- `custom_minimum_size` 已调整为 `130×90`，并同步提高字号与描述区高度；描述截断长度从 30 调整到 40。

**备注**:
- 卡牌变大后密度降低（每行可显示更少卡牌），但更利于阅读与交互（符合“优先可读性”目标）。

---

### 15. EmployeeIcon - 员工图标

**文件**: `ui/components/employee_icon/employee_icon.tscn`

**核实结论**: 已优化（更偏向可读性）

- `custom_minimum_size` 已调整为 `32×32`，FallbackLabel 字号调整为 14，提升高 DPI/高 `ui_scale` 下的可读性。

**备注**:
- 图标变大后 LeftPanel 图标行会更早换行，但已有 `ScrollContainer`，不会影响功能性。

---

### 16. PaydayPanel - 发薪日面板

**文件**: `ui/components/payday_panel/payday_panel.tscn`, `ui/components/payday_panel/payday_panel.gd`

**核实结论**: 基本合理（已使用 ScrollContainer）

- 列表区为 `ScrollContainer` + `SalaryItem.custom_minimum_size = Vector2(300, 40)`；面板最小尺寸 `400x350` 主要影响默认弹窗尺寸，不会阻止显示全部条目。

**建议**:
- 确保在嵌入 RightPanel 时隐藏 ButtonRow 的情况下，Footer 的双按钮与滚动区域不冲突（需运行验证）。

---

### 17. MilestonePanel - 里程碑面板

**文件**: `ui/components/milestone_panel/milestone_panel.tscn`, `ui/components/milestone_panel/milestone_panel.gd`

**核实结论**: 基本合理（已使用 ScrollContainer）

- 列表区为 `ScrollContainer`（纵向滚动）。
- 已修复窄宽下的“最小宽度挤压/遮挡 LeftPanel 左侧 PlayerTabs”风险：
  - `MilestonePanel.custom_minimum_size`：`420×400` → `280×260`
  - `MilestoneItem.custom_minimum_size`：`380×70` → `0×70`
  - 名称/描述启用自动换行（适配 LeftPanel 的较窄内容列）。

---

### 18. CompanyStructure - 公司结构面板

**文件**: `ui/components/company_structure/company_structure.tscn`, `ui/components/company_structure/company_structure.gd`

**核实结论**: 基本合理（在容器布局下由最小尺寸驱动）

- 面板最小尺寸 `450×250`；卡槽 `130×90` 与 CEO 卡槽数量（3）在宽度 450 内可居中排列。
- `game.tscn` 已改为容器布局，`BottomPanel` 不再是固定 250px；高度由 `HandArea/CompanyStructure` 的最小尺寸与窗口高度共同决定。

**建议**:
- 若后续要支持更窄窗口，可考虑让 BottomPanel 高度可拖拽，并为 CompanyStructure 增加横向滚动或缩放策略。

---

## 七、额外发现：类似的“固定宽/固定高”模式（宽度问题补充）

这些不一定是 bug，但在小窗口/高 `ui_scale` 下可能出现溢出：

- `ui/components/map_mode_bar/map_mode_bar.tscn`：原 `Bar` 固定宽 `480px` → 已改为容器布局（自适应宽度/高度，支持换行）。
- `ui/components/map_mode_bar/map_mode_bar.tscn`：补充 `TitleLabel/HintLabel.mouse_filter = IGNORE`，避免提示条遮挡地图点击。
- `ui/components/house_placement/house_placement_overlay.tscn`、`ui/components/restaurant_placement/restaurant_placement_overlay.tscn`：原 `HintPanel` 固定宽 `300px` → 已改为容器布局（自适应宽度/高度，支持换行）；并补充 `HintLabel.mouse_filter = IGNORE`，避免遮挡地图点击。
- `ui/components/dinner_time/dinner_time_overlay.tscn`：原 `CenterPanel` 固定 `480×360`，底部按钮条固定宽 `260px` → 已改为容器布局（CenterMargin 动态边距，尽量保持 `480` 宽；窄屏自动占满）。
- `ui/scenes/game/game_overlay_controller.gd`：里程碑 toast 原固定宽 `520px` → 已改为基于父容器宽度 clamp（保留左右边距），并挂载到 `GameArea`，避免遮住 LeftPanel 的公司切换按钮。
- `ui/scenes/game/map_canvas.gd` / `ui/scenes/game/map_view.gd`：MapCanvas 原 `mouse_filter=STOP` 会导致 MapView 收不到滚轮/拖拽事件 → 已改为 `PASS`；并增加默认 `fit_to_view` 与右键拖拽平移（窄宽/大地图更易用）。

---

## 八、总结表格（已修订，包含宽度问题）

| 优先级 | 组件 | 核实结论 | 主要问题 | 状态 |
|--------|------|----------|----------|----------|
| **高** | PlayerPanel | 属实（必现） | anchors/offset 导致裁剪 + PlayerInfoItem 宽度不足 | 已修复（容器布局 + 最小宽度重算） |
| **高** | GameLogPanel | 属实 | 头部控件挤压 | 已修复（固定两行头部） |
| **高** | ChoiceDialog | 属实（3+ 选项必现） | 选项按钮溢出 | 已修复（HFlow 换行 + 自动增高） |
| 中 | InventoryPanel | 属实 | 宽高偏小 + 文本易裁剪 | 已优化（最小尺寸 + 文本换行） |
| 中 | TrainPanel | 属实 | 无滚动，目标项多时易顶出 | 已修复（目标列表滚动） |
| 中 | TurnOrderDisplay | 属实 | 宽度 150 < 5 人需求 154 | 已修复（150→160） |
| 中 | ModalPanelBase / RestructuringModal | 属实 | 小窗口可能溢出 | 已缓解（尺寸 clamp + 内部滚动） |
| 中 | game.tscn | 属实 | 固定高度 + 硬编码 offset | 已修复（容器布局） |
| 低 | RecruitPanel | 部分属实 | 高度偏小但可滚动 | 已优化（最小高度 260） |
| 低 | EmployeeCard | —— | 可读性偏紧 | 已优化（130×90 + 字号） |
| 低 | EmployeeIcon | —— | 高 DPI 下偏小 | 已优化（32×32 + 字号） |
| 低 | MarketingPanel / ProductionPanel / LeftPanel | 原报告误报或低风险 | —— | 无需优先处理 |

---

## 九、后续验证/优化顺序（更新）

1. **回归验证（优先）**:
   - 不同窗口尺寸（窄/矮）与不同 `ui_scale` 下的整体布局（含 `BottomPanel` 显示/隐藏切换）。
2. **窄屏体验**:
   - `TopBar` 已改为两行布局；仍建议在极窄窗口下观察是否需要进一步的“收进菜单/更多按钮”策略。
3. **固定宽度组件**:
   - “额外发现”中的固定宽/固定高 overlay/panel：目前已针对已发现项做了容器化/视口 clamp；后续若新增类似 UI，可按同策略处理。

---

## 十、无明显问题/已具备滚动的组件（复核后保留）

以下组件有 ScrollContainer 或布局相对自适应，暂未发现静态必现问题（仍建议在 `ui_scale` > 1.0 下做一次肉眼回归）：

- PaydayPanel（列表区可滚动）
- MilestonePanel（列表区可滚动）
- HandArea（列表区可滚动）
- CompanyStructure（结构区布局稳定；BottomPanel 高度由容器与最小尺寸共同决定）
- ProductionPanel（主体区可滚动）
- MarketingPanel（类型按钮可换行）
