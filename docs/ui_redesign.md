# 快餐连锁大亨 UI 重构方案

> 版本：4.5
> 日期：2026-01-11
> 状态：P0-P2（增量改造）已落地并通过 headless 测试；P3-P6（Left Panel + 信息迁移 + 右侧可收起/顶栏顺序展示 + 遮罩面板体系）已落地（默认启用，可在设置切回 v1）；P7（响应式断点 + BottomBar 移除 + 面板收起体验）已落地；LeftPanel 已补齐“员工分组列表展示/宽度可拖拽/摘要信息密度优化/本回合日志联动/左侧日志入口/字号可读性提升/日志视图隐藏摘要与回合日志”；地图支持滚轮缩放、右键拖拽平移与首次加载自动 Fit；放置提示不再遮挡地图点击；重组阶段强制“查看玩家”为当前行动玩家，避免因误切换视角导致拖拽不可用；`RecruitPanel` 首次打开的 HFlow 不换行溢出已通过延迟重排修复；`GameLogPanel` 过滤行支持换行并下调最小宽度以避免默认 LeftArea 宽度下被截断；v2 布局下 RightPanel 库存面板默认隐藏（库存已在 LeftPanel 摘要展示）；放置流程的确认/取消已合并到右侧 ActionPanel，并支持 `confirm_actions=false` 的快速放置；SettingsDialog 已暴露 `ui_layout_version`（v1/v2）切换入口并可运行时应用；RightPanel 的 `dock_right` 面板已抽屉化嵌入（不再覆盖地图），并统一底部 Footer（支持双主按钮：如发薪日 [解雇所选]/[支付]）；MilestonePanel 在嵌入 RightPanel 时隐藏内部关闭按钮；RightPanel 的“返回/取消”在非地图模式下不再清空选中（仅关闭侧边 UI）；快捷键：Enter 触发 Footer 主按钮、Shift+Enter 触发次主按钮；Headless：修复 GameSmokeTest 退出时的 ObjectDB/资源泄漏警告；“左右分离新布局示意图（2.0）”仍未完整实现

---

> 重要说明：
> - 本文同时包含 **目标形态示意（第 4/5 章：Left Panel/Right Panel/Modal Panel）** 和 **基于现有实现的渐进式落地路线（第 8 章：P0-P2）**。
> - 当前仓库代码的实际进度为：**P0-P2 已完成；P3-P6（Left Panel + 信息迁移 + 右侧可收起/顶栏顺序展示 + 遮罩面板体系）已落地并默认启用（可在设置切回 v1）；P7（响应式断点 + BottomBar 移除 + 面板收起体验）已落地；LeftPanel 已补齐“员工分组列表展示/宽度可拖拽/摘要信息密度优化/本回合日志联动”；放置流程确认/取消已迁移到右侧 ActionPanel，并支持 `confirm_actions=false` 快速放置；SettingsDialog 已暴露 `ui_layout_version` 切换入口并可运行时应用；RightPanel 的 `dock_right` 面板已抽屉化嵌入（不再覆盖地图），并统一底部 Footer（支持双主按钮：如发薪日 [解雇所选]/[支付]）**；尚未进入完整的 2.0 布局重构阶段，因此游戏中不会完整出现示意图里的“Left/Right Panel 分工 + Modal Panel 体系”等结构。

## 目录

1. [概述](#概述)
2. [现有问题分析](#现有问题分析)
3. [设计原则](#设计原则)
4. [整体布局重构](#整体布局重构)
5. [核心组件重设计](#核心组件重设计)
6. [交互流程优化](#交互流程优化)
7. [信息层级与展示](#信息层级与展示)
8. [实现优先级与路线图](#实现优先级与路线图)

---

## 1. 概述

### 1.1 项目背景

本项目是《快餐连锁大亨》(Food Chain Magnate) 桌游的电子版实现。作为一款复杂的策略桌游，游戏包含大量需要同时展示的信息：地图、公司结构、员工手牌、库存、营销活动、里程碑等。当前UI实现虽然功能完整，但存在多处设计不合理之处，影响用户体验。

### 1.2 重构目标

- **不遮挡原则**：弹窗和面板不应遮挡关键游戏信息（地图、状态栏）
- **信息可达性**：玩家应能快速获取所需信息，无需多次点击
- **操作流畅性**：减少操作步骤，提供直观的交互反馈
- **视觉层次清晰**：通过合理的布局和视觉设计区分信息优先级
- **一致性**：所有组件遵循统一的设计语言和交互模式

### 1.3 参考设计

- **Board Game Arena** 的 FCM 实现：侧边栏信息展示
- **Terraforming Mars Digital**：工具栏 + 地图交互模式
- **Through the Ages Digital**：分层信息展示
- **Wingspan Digital**：优雅的卡牌展示和动画

---

## 2. 现有问题分析

### 2.1 弹窗遮挡问题（严重）

**问题描述**：
目前大量交互面板会以「居中弹窗 + 不透明背景」的形式显示（尤其是需要地图辅助决策的流程），遮挡地图关键区域，导致“选点/看范围/看道路”时需要反复关窗、移动视线或凭记忆操作。

同时，部分地图交互使用的是全屏覆盖层（Overlay）而非居中弹窗：它们通常允许继续点击地图，但缺少统一的“当前模式/下一步做什么/如何退出”的明确提示，体验上仍会显得割裂。

**影响的组件（按“表现形态”分类）**：

1) **居中弹窗（会遮挡地图）**
| 组件 | 文件位置 | 问题严重程度 |
|------|----------|-------------|
| MarketingPanel | `ui/components/marketing_panel/` | 严重 - 需要看地图选点/看范围 |
| ProductionPanel | `ui/components/production_panel/` | 中等 - 采购路线/入口参考地图（当前会预览路线，但面板仍遮挡） |
| RecruitPanel | `ui/components/recruit_panel/` | 轻微 - 不需要地图，但遮挡会打断节奏 |
| TrainPanel | `ui/components/train_panel/` | 轻微 - 不需要地图，但遮挡会打断节奏 |
| PriceSettingPanel | `ui/components/price_panel/` | 轻微 |
| PaydayPanel | `ui/components/payday_panel/` | 轻微 |
| MilestonePanel / BankBreakPanel / GameOverPanel | `ui/components/*` | 轻微/中等（更偏系统提示） |

2) **地图交互覆盖层（不阻挡点击，但缺少统一模式提示/退出一致性）**
| 组件 | 文件位置 | 问题严重程度 |
|------|----------|-------------|
| HousePlacementOverlay | `ui/components/house_placement/` | 严重 - 必须在地图上选点；需要清晰的模式提示/旋转/取消说明 |
| RestaurantPlacementOverlay | `ui/components/restaurant_placement/` | 严重 - 必须在地图上选点；需要清晰的模式提示/旋转/取消说明 |
| Distance Tool（距离工具模式） | `ui/scenes/game/game_map_interaction_controller.gd` | 中等 - 属于“工具模式”，应有显眼的状态提示 |

**当前实现方式（与问题直接相关的部分）**：
- 居中弹窗：`GamePanelController` 统一在 `_center_popup()` 中把面板居中；而面板场景普遍带 `ColorRect` 背景，视觉上几乎完全遮住地图。
```gdscript
# ui/scenes/game/game_panel_controller.gd
panel.position = (viewport_size - panel_size) / 2
```
- 放置覆盖层：`RestaurantPlacementOverlay` / `HousePlacementOverlay` 是全屏 `Control`，脚本设置 `mouse_filter = IGNORE` 以允许继续点击地图（问题不在“点不到”，而在“模式提示/退出一致性不足”）。

### 2.2 菜单与设置入口不合理（中等）

**问题描述**：
- 菜单按钮位于顶栏最右侧，但菜单弹窗居中显示
- 设置、里程碑、距离工具等功能隐藏在菜单中，需要两次点击才能访问
- 游戏日志的显示/隐藏也需要通过菜单操作

**当前菜单结构**（`game.tscn` 第206-236行）：
```
菜单
├── 继续游戏
├── 保存游戏
├── 设置
├── 显示/隐藏日志
├── 里程碑
├── 距离工具
├── 回放播放器
└── 返回主菜单
```

### 2.3 关键信息展示位置不当（中等）

**问题描述**：
- 当前玩家信息在顶栏，但玩家详细信息（现金、员工数）在右侧面板
- 库存信息与动作面板混在一起，视觉层次不清
- 回合/阶段信息字体较小，不够醒目

**当前布局**（`game.tscn`）：
```
┌─────────────────────────────────────────────────────────┐
│ TopBar: 回合 | 阶段 | 银行 | 玩家 | [按钮组]            │
├─────────┬───────────────────────────────────────────────┬───────────────┤
│ GameLog │         地图区域                              │ PlayerPanel   │
│         │                                               │ TurnOrder     │
│         │                                               │ Inventory     │
│         │                                               │ ActionPanel   │
├─────────┴───────────────────────────────────────────────┴───────────────┤
│ HandArea                    │ CompanyStructure                          │
├─────────────────────────────────────────────────────────────────────────┤
│ BottomBar: Hash | 命令数                                                │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.4 动作面板功能过载（中等）

**问题描述**：
- ActionPanel 作为“动作入口列表”本身是合理的，但当前仍存在可用性问题：
  - **不可用原因缺失**：按钮灰显仅表示“现在不能做”，但缺少“为什么不能做/还差什么”的解释（尤其是强制动作、员工驱动动作）。
  - **发现性不足**：部分动作会被自动隐藏（例如定价/折扣/奢侈品），玩家容易误以为系统缺少该机制或忘记该机制存在。
  - **信息结构弱**：动作未按阶段/重要性/强制性分组展示，也缺少“当前子阶段目标”的醒目标记。

**当前实现（关键点）**：
```gdscript
# ActionPanel 点击只发出 action_id，不包含参数/原因信息
action_requested.emit(action_id, {})

# set_enabled 仅做灰显，tooltip 仅为静态描述（非“不可用原因”）
btn.set_enabled(enabled)
```

### 2.5 地图交互模式不统一（中等）

**问题描述**：
- 营销放置需要先在弹窗中选择参数，再点击地图
- 餐厅放置直接在地图上操作
- 采购路线预览与实际操作分离
- 缺少统一的"工具模式"概念

### 2.6 底部面板空间利用不足（轻微）

**问题描述**：
- HandArea 和 CompanyStructure 平分底部空间
- 当员工较少时，大量空间浪费
- 公司结构在非重组阶段仍占用固定空间

### 2.7 缺少全局状态指示器（轻微）

**问题描述**：
- 没有明确的"当前操作模式"指示
- 没有"待完成强制动作"的醒目提示
- 没有"其他玩家状态"的快速查看方式

### 2.8 对话框样式不统一（轻微）

**问题描述**：
- ConfirmDialog、SettingsDialog、SaveLoadDialog 样式各异
- 部分使用 Window 节点，部分使用 Control 节点
- 关闭方式不统一（有的点击外部关闭，有的必须点按钮）

### 2.9 设置系统未闭环（中等，文档补充）

**问题描述**：
- `SettingsDialog` 已提供 UI 缩放、音量、确认操作等设置项，但当前仅对“全屏/vsync/分辨率”做了实际应用；`ui_scale`、`confirm_actions` 等没有贯穿到 UI 行为中。
- 音频设置存在“双配置源”风险：音频系统使用 `sound_settings.cfg`，而设置面板写入 `settings.cfg`，如果不统一职责，容易出现“调了但没效果/重启又变回去”的体验问题。

**相关实现位置**：
- `ui/dialogs/settings_dialog.gd`（保存/应用逻辑）
- `ui/scenes/game/game_overlay_controller.gd`（创建 SettingsDialog，但未统一监听 settings_changed）
- `ui/audio/sound_manager.gd` / `ui/audio/music_manager.gd`（音量配置文件）

### 2.10 重复建设风险（轻微，文档补充）

**问题描述**：
当前项目已经存在多个“可复用的 UI 基础设施”，重构方案应优先扩展与统一，而不是新增另一套：
- 工具提示系统：`HelpTooltipManager` 已存在（支持延迟显示与注册 Control）。
- UI 动画管理：`UIAnimationManager` 已存在（可用于面板弹出/滑入等）。
- 日志面板：`GameLogPanel` 已存在（过滤、清空、自动滚动）。

### 2.11 快捷键冲突与一致性（中等，文档补充）

**问题描述**：
文档中将 Space 同时用于“确认/跳过”与“按住查看地图/拖拽平移”等交互，会产生冲突。建议在设计阶段明确默认键位与冲突策略（例如 Enter 用于确认/跳过，Space 用于地图拖拽/窥视；或提供可配置键位）。

---

## 3. 设计原则

### 3.1 核心原则

#### 3.1.1 地图优先原则
地图是游戏的核心视觉元素。在**需要地图交互/观察**的流程中，UI 不应长期遮挡地图关键区域。所有面板和弹窗应优先：
- 采用侧边停靠/抽屉形式（信息/参数在侧边完成）
- 或采用轻量覆盖层（提示条/底部操作条），并保持地图可点击
- 或自动避让鼠标/选点区域（避免遮挡当前焦点）

说明：系统级强提示（例如银行破产、游戏结束）允许短暂的居中模态，但应做到信息清晰、可快速关闭、不会与地图选点流程混用。

#### 3.1.2 上下文感知原则
UI应根据当前游戏阶段和操作上下文自动调整：
- 显示与当前阶段相关的信息
- 隐藏或弱化不相关的元素
- 高亮需要用户关注的区域

#### 3.1.3 渐进式披露原则
信息按重要性分层展示：
- **第一层**：始终可见的关键信息（回合、阶段、当前玩家、现金）
- **第二层**：悬停或点击展开的详细信息（员工详情、营销详情）
- **第三层**：需要主动打开的完整信息（里程碑列表、游戏日志）

#### 3.1.4 操作可逆原则
所有操作都应提供明确的取消/返回方式：
- ESC 键统一关闭当前面板
- 点击面板外部区域关闭面板
- 提供明确的"取消"按钮

### 3.2 视觉设计规范

#### 3.2.1 颜色系统
```
主色调：
- 背景色：#1A1E24（深灰蓝）
- 面板背景：#252A32（稍浅灰蓝）
- 边框色：#3A4150（灰蓝边框）
- 强调色：#4A9EFF（蓝色，用于可交互元素）
- 警告色：#FF6B6B（红色，用于危险操作）
- 成功色：#4ADE80（绿色，用于确认/完成）

玩家颜色：
- 玩家1：#E74C3C（红）
- 玩家2：#3498DB（蓝）
- 玩家3：#2ECC71（绿）
- 玩家4：#F39C12（橙）
- 玩家5：#9B59B6（紫）
```

#### 3.2.2 字体规范
```
标题：18-24px，粗体
正文：14-16px，常规
辅助文字：12px，灰色
数值：16-20px，等宽字体
```

#### 3.2.3 间距规范
```
面板内边距：16px
元素间距：8px（紧凑）/ 12px（标准）/ 16px（宽松）
按钮最小尺寸：36px 高度
可点击区域最小：44x44px
```

#### 3.2.4 动画规范
```
面板滑入/滑出：200ms ease-out
悬停效果：100ms
按钮点击反馈：50ms
地图平移：150ms ease-in-out
```

---

## 4. 整体布局重构

### 4.1 核心设计理念

**职责分离原则**：
- **Left Panel**：信息展示（玩家数据、员工、里程碑、日志）
- **Right Panel**：操作交互（动作选择、参数配置）
- **Top Bar**：全局状态（回合、阶段、顺序轨、银行）
- **地图区域**：游戏主视图，最大化显示

### 4.2 新布局方案

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Top Bar: [回合 3] [Working/Marketing] │ [○○●○○ TurnOrder] │ [$150] │ [🔧⚙️☰] │
├───┬─────────────────────┬───────────────────────────────────┬───────────────┤
│   │ [手牌][在职][里程碑]│                                   │               │
│[1]├─────────────────────┤                                   │               │
│   │ 💰 $250             │                                   │  Right Panel  │
│[2]│ 🍔×5 🍕×3 🥤×8      │         地 图 区 域               │  (可收起)     │
│   ├─────────────────────┤        （可缩放、可拖拽）          │               │
│[3]│                     │                                   │  动作列表     │
│   │   内容区域           │                                   │  参数选择     │
│[4]│  (根据Tab切换)       │                                   │               │
│   ├─────────────────────┤                                   │               │
│[5]│ ▼ 本回合日志        │                                   │               │
│   │ · 招聘了招聘员      │                                   │               │
└───┴─────────────────────┴───────────────────────────────────┴───────────────┘
  ↑
 玩家Tab（纵向）
```

### 4.3 区域职责划分

#### 4.3.1 顶部状态栏（Top Bar）
**高度**：50px（固定）

**内容布局**：
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ [回合 3] [Working / Marketing] │ [○ ○ ● ○ ○] │ [银行: $150] │ [📏] [⚙️] [☰] │
│                                   TurnOrder                    工具  设置 菜单│
└─────────────────────────────────────────────────────────────────────────────┘
```

**TurnOrder 显示**：
- 以图标形式显示各玩家顺序位置
- 高亮当前行动玩家
- 纯展示，不可点击（选择顺序在专门的遮罩面板中完成）

**工具按钮**：
| 按钮 | 图标 | 功能 | 快捷键 |
|------|------|------|--------|
| 距离工具 | 📏 | 切换距离测量模式 | D |
| 设置 | ⚙️ | 打开设置面板 | - |
| 菜单 | ☰ | 打开游戏菜单 | ESC |

#### 4.3.2 左侧信息面板（Left Panel）
**宽度**：可由玩家拖拽调整（默认 280px，最小 200px，最大 400px）

**结构**：
```
┌───┬─────────────────────────┐
│   │ [手牌] [在职] [里程碑]  │  ← 数据类型 Tab
│[1]├─────────────────────────┤
│   │ 💰 $250                 │  ← 基础信息（始终显示）
│[2]│ 🍔×5 🍕×3 🥤×8          │
│   ├─────────────────────────┤
│[3]│                         │
│   │   内容区域               │  ← 根据 Tab 显示对应内容
│[4]│   (图标分组显示)         │
│   │                         │
│[5]├─────────────────────────┤
│   │ ▼ 本回合日志            │  ← 被查看玩家的本回合日志
│   │ · 招聘了招聘员          │
│   │ · 获得里程碑            │
└───┴─────────────────────────┘
  ↑
 玩家 Tab（纵向排列）
```

**玩家 Tab（纵向）**：
- 显示玩家编号或头像图标
- 点击切换查看不同玩家的信息
- 当前操作玩家有特殊标记

**数据类型 Tab（横向）**：
- **手牌**：待命区的员工列表
- **在职**：公司中正在工作的员工列表
- **里程碑**：该玩家已获得的里程碑

**员工显示方式（图标分组）**：
```
┌─────────────────────────────┐
│ 管理  👔 👔                  │
│ 厨房  👨‍🍳 👨‍🍳 👨‍🍳 🍔 🍔          │
│ 营销  📢 📢 📣               │
│ 其他  🛒 💰 🎯               │
└─────────────────────────────┘
鼠标悬浮显示员工详情卡片
```

**本回合日志**：
- 显示被查看玩家在本回合的操作
- 包括：招聘、培训、生产、获得里程碑等
- 不显示其他玩家或系统日志
- 点击 [查看完整日志] 打开完整日志面板

#### 4.3.3 地图区域（Map Area）
**占比**：主要区域，自适应填充

**功能**：
- 地图渲染与交互
- 覆盖层显示（营销范围、采购路线、距离工具）
- 支持缩放、拖拽、平移

**交互**：
- 鼠标滚轮：缩放
- 鼠标中键拖拽 / 空格+左键拖拽：平移
- 左键点击：选择/放置（在对应模式下）

**地图操作提示栏**（进入放置模式时显示）：
```
┌─────────────────────────────────────────┐
│ 📍 营销放置模式 │ [R] 旋转 │ [ESC] 取消 │
└─────────────────────────────────────────┘
```

#### 4.3.4 右侧操作面板（Right Panel）
**宽度**：360px（固定）
**默认状态**：收起

**行为**：
- 玩家工作时间自动展开，显示可用动作列表
- 玩家可手动收起/展开
- 展开时适度压缩地图区域
- 点击动作后，面板内容切换为参数选择

**结构**：
```
┌────────────────────────────────┐
│ [×]     当前阶段: Marketing    │
├────────────────────────────────┤
│                                │
│   可用动作：                   │
│   [📢 发起营销]                │
│   [⏭️ 跳过]                    │
│                                │
│   ─────────────────────────    │
│                                │
│   或（点击动作后）：            │
│                                │
│   选择营销类型：               │
│   ○ 广告牌  ○ 邮箱             │
│   ○ 收音机  ○ 飞机             │
│                                │
│   选择员工：                   │
│   [员工图标列表]               │
│                                │
│   选择产品：                   │
│   ○ 汉堡  ○ 披萨  ○ 饮料      │
│                                │
├────────────────────────────────┤
│      [取消]      [下一步]      │
└────────────────────────────────┘
```

### 4.4 遮罩面板（Modal Panel）

用于需要专注操作的阶段，可复用组件。

#### 4.4.1 适用场景
- **重组阶段**：调整公司结构（金字塔视图）
- **顺序选择阶段**：选择顺序轨位置

#### 4.4.2 布局
```
┌───┬─────────────────────┬─────────────────────────────────────────────────┐
│   │                     │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
│[1]│                     │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
│   │   Left Panel        │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
│[2]│   (不遮挡)          │░░░░░░░  ┌─────────────────────┐  ░░░░░░░░░░░░░░░│
│   │                     │░░░░░░░  │                     │  ░░░░░░░░░░░░░░░│
│[3]│   玩家可参考        │░░░░░░░  │   居中操作面板      │  ░░░░░░░░░░░░░░░│
│   │   其他玩家信息      │░░░░░░░  │   (重组/顺序选择)   │  ░░░░░░░░░░░░░░░│
│[4]│                     │░░░░░░░  │                     │  ░░░░░░░░░░░░░░░│
│   │                     │░░░░░░░  └─────────────────────┘  ░░░░░░░░░░░░░░░│
│[5]│                     │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│
│   │                     │░░░░░░░  [按住空格查看地图]      ░░░░░░░░░░░░░░░░│
└───┴─────────────────────┴─────────────────────────────────────────────────┘
```

**特性**：
- 遮罩覆盖地图区域和 Right Panel
- **不遮挡 Left Panel**，玩家可参考其他玩家信息
- 按住空格键可临时隐藏遮罩面板，查看地图
- 完成操作后才能返回正常游戏界面

#### 4.4.3 重组面板内容
```
┌─────────────────────────────────────────┐
│           公司结构重组                   │
├─────────────────────────────────────────┤
│                                         │
│              [CEO]                      │
│             /      \                    │
│        [经理]      [经理]               │
│        /    \          \                │
│    [员工] [员工]     [员工]             │
│                                         │
│   待命区：[员工] [员工] [员工]          │
│                                         │
│   拖拽员工调整位置                       │
│                                         │
├─────────────────────────────────────────┤
│              [确认重组]                  │
└─────────────────────────────────────────┘
```

#### 4.4.4 顺序选择面板内容
```
┌─────────────────────────────────────────┐
│           选择顺序位置                   │
├─────────────────────────────────────────┤
│                                         │
│   ┌───┬───┬───┬───┬───┬───┬───┬───┐    │
│   │ 1 │ 2 │ 3 │ 4 │ 5 │...│...│50 │    │
│   ├───┼───┼───┼───┼───┼───┼───┼───┤    │
│   │   │ ● │   │ ● │   │   │   │   │    │
│   └───┴───┴───┴───┴───┴───┴───┴───┘    │
│                                         │
│   ● = 已被其他玩家选择                   │
│   点击空位选择你的位置                   │
│                                         │
├─────────────────────────────────────────┤
│   当前选择: 位置 3                       │
│              [确认选择]                  │
└─────────────────────────────────────────┘
```

### 4.5 地图操作确认（右侧 ActionPanel）

用于建筑放置（餐厅/住宅/花园）等地图操作的最终确认。

当前实现（已落地）：
- 不再使用居中弹窗；地图侧只保留 Overlay（高亮/预览/提示）
- 右侧 ActionPanel 增加 Context 区域：展示当前放置模式信息、参数选项（餐厅/旋转/花园方向）以及 [确认]/[取消]
- 快捷键：R 旋转；ESC 取消
- 设置项 `confirm_actions`：
  - `true`（默认）：需要点右侧确认
  - `false`：点击合法格后自动确认（快速模式）

### 4.6 响应式适配

#### 4.6.1 宽屏模式（>1920px）
- Left Panel 可显示更多内容
- Right Panel 展开时对地图影响较小
- 地图区域更大

#### 4.6.2 标准模式（1280-1920px）
- 使用标准布局
- Left Panel 和 Right Panel 按需调整

#### 4.6.3 窄屏模式（<1280px）
- Left Panel 可完全收起
- Right Panel 展开时覆盖更多区域
- 简化 Top Bar 显示

---

## 5. 核心组件重设计

### 5.1 顶部状态栏（Top Bar）

#### 5.1.1 组件结构
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ [回合 3] [Working / Marketing] │ [○ ○ ● ○ ○] │ [银行: $150] │ [📏] [⚙️] [☰] │
│                                   TurnOrder                    工具  设置 菜单│
└─────────────────────────────────────────────────────────────────────────────┘
```

#### 5.1.2 TurnOrder 显示
- 以玩家颜色图标显示各玩家顺序位置
- 高亮当前行动玩家
- 纯展示，不可点击
- 悬浮显示玩家名称和顺序位置

#### 5.1.3 工具按钮组
| 按钮 | 图标 | 功能 | 快捷键 |
|------|------|------|--------|
| 距离工具 | 📏 | 切换距离测量模式 | D |
| 设置 | ⚙️ | 打开设置面板 | - |
| 菜单 | ☰ | 打开游戏菜单 | ESC |

#### 5.1.4 实现要点
```gdscript
# 新文件：ui/components/top_bar/top_bar.gd
class_name TopBar
extends Control

signal tool_toggled(tool_id: String, active: bool)
signal menu_requested()

@export var round_label: Label
@export var phase_label: Label
@export var turn_order_display: TurnOrderDisplay
@export var bank_label: Label
@export var tool_buttons: HBoxContainer

func update_state(state: GameState) -> void:
    round_label.text = "回合 %d" % state.round_number
    phase_label.text = _format_phase(state.phase, state.sub_phase)
    bank_label.text = "银行: $%d" % state.bank.total
    turn_order_display.update_order(state.turn_order, state.get_current_player_id())
```

### 5.2 左侧信息面板（Left Panel）

#### 5.2.1 组件结构
```
┌───┬─────────────────────────┐
│   │ [手牌] [在职] [里程碑]  │
│[1]├─────────────────────────┤
│   │ 💰 $250                 │
│[2]│ 🍔×5 🍕×3 🥤×8          │
│   ├─────────────────────────┤
│[3]│                         │
│   │   内容区域               │
│[4]│   (图标分组显示)         │
│   │                         │
│[5]├─────────────────────────┤
│   │ ▼ 本回合日志            │
│   │ · 招聘了招聘员          │
└───┴─────────────────────────┘
```

#### 5.2.2 玩家 Tab（纵向）
- 显示玩家编号或颜色图标
- 点击切换查看不同玩家信息
- 当前操作玩家有特殊边框标记
- 被查看的玩家 Tab 高亮显示

#### 5.2.3 数据类型 Tab（横向）
- **手牌**：待命区员工（图标分组列表）
- **在职**：公司中工作的员工（图标分组列表）
- **里程碑**：该玩家已获得的里程碑列表

#### 5.2.4 员工图标分组显示
```
┌─────────────────────────────┐
│ 管理  👔 👔                  │
│ 厨房  👨‍🍳 👨‍🍳 👨‍🍳 🍔 🍔          │
│ 营销  📢 📢 📣               │
│ 其他  🛒 💰 🎯               │
└─────────────────────────────┘
```
- 按员工类型分组显示图标
- 一行可显示多个员工，节省空间
- 鼠标悬浮显示员工详情卡片
- 忙碌状态的员工有特殊标记（如灰色遮罩）

#### 5.2.5 本回合日志
- 显示被查看玩家在本回合的操作
- 包括：招聘、培训、生产、获得里程碑等
- 不显示其他玩家或系统日志
- 可折叠/展开
- 点击 [查看完整日志] 打开完整日志面板

#### 5.2.6 实现要点
```gdscript
# 新文件：ui/components/left_panel/left_panel.gd
class_name LeftPanel
extends Control

signal player_selected(player_id: int)
signal full_log_requested()

@export var player_tabs: VBoxContainer  # 纵向玩家Tab
@export var data_tabs: TabContainer     # 横向数据Tab
@export var basic_info: Control         # 现金、库存
@export var content_area: Control       # 手牌/在职/里程碑
@export var log_section: Control        # 本回合日志

var _current_view_player_id: int = 0
var _game_state: GameState

func set_view_player(player_id: int) -> void:
    _current_view_player_id = player_id
    _update_display()
    player_selected.emit(player_id)

func update_state(state: GameState) -> void:
    _game_state = state
    _update_player_tabs(state)
    _update_display()

func _update_display() -> void:
    var player_data = _game_state.players[_current_view_player_id]
    basic_info.update_player(player_data)
    _update_content_area(player_data)
    _update_log(player_data)
```

### 5.3 右侧操作面板（Right Panel）

#### 5.3.1 组件结构
```
┌────────────────────────────────┐
│ [<] [×]  当前阶段: Marketing   │  ← 可收起/关闭
├────────────────────────────────┤
│                                │
│   可用动作：                   │
│   ┌────────────────────────┐  │
│   │ 📢 发起营销             │  │
│   └────────────────────────┘  │
│   ┌────────────────────────┐  │
│   │ ⏭️ 跳过本阶段           │  │
│   └────────────────────────┘  │
│                                │
└────────────────────────────────┘

点击动作后切换为参数选择：

┌────────────────────────────────┐
│ [←]       发起营销             │  ← 返回动作列表
├────────────────────────────────┤
│                                │
│   选择营销类型：               │
│   ○ 广告牌  ○ 邮箱             │
│   ○ 收音机  ○ 飞机             │
│                                │
│   选择员工：                   │
│   [员工图标列表]               │
│                                │
│   选择产品：                   │
│   ○ 汉堡  ○ 披萨  ○ 饮料      │
│                                │
├────────────────────────────────┤
│      [取消]      [下一步]      │
└────────────────────────────────┘
```

#### 5.3.2 行为规则
- **默认状态**：收起（只显示一个展开按钮）
- **自动展开**：玩家工作时间开始时自动展开
- **手动控制**：玩家可随时收起/展开
- **内容切换**：点击动作后，内容切换为参数选择界面

#### 5.3.3 面板类型
| 面板类型 | 触发动作 | 需要地图交互 |
|----------|----------|--------------|
| ActionListPanel | 默认 | 否 |
| RecruitPanel | recruit | 否 |
| TrainPanel | train | 否 |
| MarketingPanel | initiate_marketing | 是 |
| ProductionPanel | produce_food | 否 |
| ProcurementPanel | procure_drinks | 是（路线预览） |
| PricingPanel | set_price/discount/luxury | 否 |
| PaydayPanel | fire | 否 |

#### 5.3.4 实现要点
```gdscript
# 新文件：ui/components/right_panel/right_panel.gd
class_name RightPanel
extends Control

signal action_confirmed(action_id: String, params: Dictionary)
signal panel_collapsed()
signal panel_expanded()

@export var collapse_button: Button
@export var close_button: Button
@export var title_label: Label
@export var content_stack: Control  # 用于切换不同面板内容

var _is_collapsed: bool = true
var _current_panel: String = "action_list"

func expand() -> void:
    _is_collapsed = false
    _animate_expand()
    panel_expanded.emit()

func collapse() -> void:
    _is_collapsed = true
    _animate_collapse()
    panel_collapsed.emit()

func show_action_list(available_actions: Array) -> void:
    _current_panel = "action_list"
    _show_panel("action_list", {"actions": available_actions})

func show_action_panel(action_id: String, state: GameState, player_id: int) -> void:
    _current_panel = action_id
    _show_panel(action_id, {"state": state, "player_id": player_id})
```

### 5.4 遮罩面板（Modal Panel）

#### 5.4.1 基类设计
```gdscript
# 新文件：ui/components/modal_panel/modal_panel_base.gd
class_name ModalPanelBase
extends Control

signal completed(result: Dictionary)
signal cancelled()

@export var overlay: ColorRect      # 半透明遮罩
@export var panel_container: Control # 居中面板容器
@export var confirm_button: Button
@export var cancel_button: Button

var _peek_map_key_held: bool = false

func _input(event: InputEvent) -> void:
    # 按住空格查看地图
    if event is InputEventKey and event.keycode == KEY_SPACE:
        if event.pressed and not _peek_map_key_held:
            _peek_map_key_held = true
            _hide_panel_show_map()
        elif not event.pressed and _peek_map_key_held:
            _peek_map_key_held = false
            _show_panel_hide_map()

func _hide_panel_show_map() -> void:
    panel_container.visible = false
    overlay.modulate.a = 0.3  # 降低遮罩透明度

func _show_panel_hide_map() -> void:
    panel_container.visible = true
    overlay.modulate.a = 0.7  # 恢复遮罩透明度

func show_modal() -> void:
    visible = true
    _animate_in()

func hide_modal() -> void:
    _animate_out()
```

#### 5.4.2 重组面板
```gdscript
# 新文件：ui/components/modal_panel/restructuring_panel.gd
class_name RestructuringPanel
extends ModalPanelBase

@export var pyramid_view: CompanyPyramidView
@export var reserve_area: EmployeeReserveArea

func setup(state: GameState, player_id: int) -> void:
    var player_data = state.players[player_id]
    pyramid_view.set_structure(player_data.company_structure)
    reserve_area.set_employees(player_data.reserve_employees)

func _on_confirm_pressed() -> void:
    var new_structure = pyramid_view.get_structure()
    completed.emit({"structure": new_structure})
    hide_modal()
```

#### 5.4.3 顺序选择面板
```gdscript
# 新文件：ui/components/modal_panel/turn_order_selection_panel.gd
class_name TurnOrderSelectionPanel
extends ModalPanelBase

@export var order_track: TurnOrderTrackInteractive
@export var selection_label: Label

var _selected_position: int = -1

func setup(state: GameState, player_id: int) -> void:
    var occupied = state.turn_order.get_occupied_positions()
    order_track.set_occupied(occupied)
    order_track.position_clicked.connect(_on_position_clicked)

func _on_position_clicked(position: int) -> void:
    _selected_position = position
    selection_label.text = "当前选择: 位置 %d" % position
    confirm_button.disabled = false

func _on_confirm_pressed() -> void:
    if _selected_position >= 0:
        completed.emit({"position": _selected_position})
        hide_modal()
```

### 5.5 地图操作确认弹窗

> 现状说明：目前“餐厅/房屋放置”已改为通过右侧 `ActionPanel` 的上下文区完成「选点 → 预览/提示 → 右侧确认/取消」，Overlay 仅保留地图提示/预览职责；因此本节的 `PlacementConfirmDialog` 更适合用于未来的“快速模式”（例如单击直接放置）或需要额外确认的高风险操作，可作为可选项延后实现。

#### 5.5.1 组件结构
```
┌─────────────────────────────┐
│      确认放置餐厅？          │
├─────────────────────────────┤
│                             │
│   位置: (3, 5)              │
│   方向: 北 ↑                │
│                             │
│   [R] 旋转                  │
│                             │
├─────────────────────────────┤
│   [取消]        [确认放置]  │
└─────────────────────────────┘
```

#### 5.5.2 实现要点
```gdscript
# 新文件：ui/components/confirm_dialog/placement_confirm_dialog.gd
class_name PlacementConfirmDialog
extends Control

signal confirmed(params: Dictionary)
signal cancelled()
signal rotation_changed(direction: int)

@export var title_label: Label
@export var position_label: Label
@export var direction_label: Label
@export var rotate_hint: Label

var _position: Vector2i
var _direction: int = 0  # 0=北, 1=东, 2=南, 3=西
var _placement_type: String

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_R:
            _rotate()
        elif event.keycode == KEY_ESCAPE:
            _on_cancel_pressed()

func _rotate() -> void:
    _direction = (_direction + 1) % 4
    _update_direction_display()
    rotation_changed.emit(_direction)

func setup(type: String, pos: Vector2i, initial_direction: int = 0) -> void:
    _placement_type = type
    _position = pos
    _direction = initial_direction
    title_label.text = "确认放置%s？" % _get_type_name(type)
    position_label.text = "位置: (%d, %d)" % [pos.x, pos.y]
    _update_direction_display()

func _on_confirm_pressed() -> void:
    confirmed.emit({
        "position": _position,
        "direction": _direction
    })
    hide()
```

### 5.6 地图操作提示栏

#### 5.6.1 组件结构
进入放置模式时，在地图上方显示：
```
┌─────────────────────────────────────────┐
│ 📍 营销放置模式 │ [R] 旋转 │ [ESC] 取消 │
└─────────────────────────────────────────┘
```

#### 5.6.2 实现要点
```gdscript
# 新文件：ui/components/map_toolbar/map_toolbar.gd
class_name MapToolbar
extends Control

signal cancel_requested()

@export var mode_label: Label
@export var hints_container: HBoxContainer

func enter_mode(mode: String, hints: Array[Dictionary]) -> void:
    mode_label.text = _get_mode_display_name(mode)
    _build_hints(hints)
    _animate_show()

func exit_mode() -> void:
    _animate_hide()

func _build_hints(hints: Array[Dictionary]) -> void:
    # 清除旧提示
    for child in hints_container.get_children():
        child.queue_free()
    # 添加新提示
    for hint in hints:
        var label = Label.new()
        label.text = "[%s] %s" % [hint.key, hint.action]
        hints_container.add_child(label)

func _get_mode_display_name(mode: String) -> String:
    match mode:
        "marketing_placement": return "📍 营销放置模式"
        "restaurant_placement": return "🏪 餐厅放置模式"
        "house_placement": return "🏠 房屋放置模式"
        "distance_tool": return "📏 距离测量模式"
        _: return mode
```

### 5.7 完整日志面板（Full Log Panel）

从 Left Panel 的 [查看完整日志] 按钮打开，显示所有玩家和系统的完整日志。

#### 5.7.1 组件结构
```
┌────────────────────────────────┐
│ [×]        游戏日志            │
├────────────────────────────────┤
│ 🔍 [搜索...]  [筛选 ▼]        │
├────────────────────────────────┤
│ 回合 3 - Working              │
│ ├─ 玩家1 招聘了 招聘员        │
│ ├─ 玩家2 培训了 厨师长        │
│ └─ 玩家1 发起营销 (广告牌)    │
│                                │
│ 回合 2 - Dinnertime           │
│ ├─ 房屋#5 购买了 2个汉堡      │
│ └─ 玩家1 收入 $45             │
│                                │
│ [加载更多...]                  │
└────────────────────────────────┘
```

#### 5.7.2 功能
- 按回合/阶段分组显示
- 支持搜索和筛选（按玩家、按动作类型）
- 点击日志条目可高亮相关地图位置
- 支持折叠/展开回合

### 5.8 设置面板（Settings Panel）

#### 5.8.1 组件结构
```
┌────────────────────────────────┐
│ [×]        设置                │
├────────────────────────────────┤
│ 🔊 音频                        │
│   主音量    [━━━━━●━━━] 80%   │
│   音乐      [━━━━●━━━━] 70%   │
│   音效      [━━━━━●━━━] 80%   │
│   □ 静音                       │
│                                │
│ 🖥️ 显示                        │
│   □ 全屏模式                   │
│   □ 垂直同步                   │
│   UI缩放    [━━━●━━━━━] 100%  │
│                                │
│ 🎮 游戏                        │
│   □ 自动保存                   │
│   ☑ 操作前确认                 │  ← 对应 confirm_actions（需要闭环落地）
│   □ 显示提示                   │
│   动画速度  [━━━●━━━━━] 1.0x  │
│                                │
│      [重置默认]    [应用]      │
└────────────────────────────────┘
```

---

## 6. 交互流程优化

### 6.1 统一的操作模式系统

#### 6.1.1 模式定义
游戏中的操作分为两类：
- **即时操作**：不需要地图交互，在侧边栏中完成（招聘、培训、定价）
- **地图操作**：需要在地图上选择位置（营销放置、餐厅放置、房屋放置）

#### 6.1.2 模式状态机
```
┌─────────────┐
│   空闲模式   │ ←──────────────────────────────┐
└──────┬──────┘                                 │
       │ 点击动作按钮                            │
       ▼                                        │
┌─────────────┐                                 │
│ 侧边栏打开  │                                 │
└──────┬──────┘                                 │
       │ 需要地图交互？                          │
       ├─── 否 ───→ 在侧边栏完成 ───→ 确认/取消 ─┤
       │                                        │
       ▼ 是                                     │
┌─────────────┐                                 │
│ 地图选点模式 │                                 │
│ (工具栏显示) │                                 │
└──────┬──────┘                                 │
       │ 点击地图位置                            │
       ▼                                        │
┌─────────────┐                                 │
│ 预览确认    │ ───→ 确认/取消 ─────────────────┘
└─────────────┘
```

#### 6.1.3 实现建议（优先复用现有架构）
当前项目已存在 `GameMapInteractionController`（内部 `_mode` + `begin_selection/clear_selection` + 监听 `MapCanvas` 的 `cell_selected/cell_hovered`）。因此建议：
1. **以现有 map_controller 为唯一模式入口**：所有需要地图交互的面板都通过回调/方法请求进入某个模式（营销面板已采用该模式）。
2. **统一模式提示输出**：新增轻量 `MapModeBar`（或沿用本方案中的 MapToolbar），由 `map_controller` 提供“当前模式、下一步、快捷键、退出方式”数据驱动显示。
3. **弱化/延后全局 ModeManager**：只有当跨面板状态协作变复杂（例如引入“预览确认层级”、串联多个子步骤）时，再考虑抽出 `InteractionModeManager`；但它应当包装并复用现有 map_controller，而非替换。

（可选）如果后续确实需要更强的状态机，可以将其实现为“对现有 map_controller 的上层协调器”，并确保 headless 测试中不依赖 `Window`。

### 6.2 各阶段交互流程

#### 6.2.1 Setup 阶段（初始设置）
```
流程：放置初始餐厅
1. 系统自动进入"餐厅放置模式"
2. 地图上高亮显示可放置位置
3. 玩家点击位置 → 显示餐厅预览
4. 确认放置 → 切换到下一个玩家
```

#### 6.2.2 Restructuring 阶段（重组公司）
```
流程：调整公司结构
1. 底部面板自动展开公司结构区
2. 玩家拖拽员工调整位置
3. 实时显示结构有效性
4. 点击"确认重组"提交
```

#### 6.2.3 Order of Business 阶段（决定顺序）
```
流程：选择顺序轨位置
1. 顺序轨组件高亮显示
2. 可选位置有明显标记
3. 点击位置 → 确认选择
4. 显示选择结果
```

#### 6.2.4 Working 阶段（工作时间）
```
子阶段流程：
┌─────────────────────────────────────────────────────────────┐
│ Recruit → Train → Marketing → GetFood → GetDrinks →        │
│ PlaceHouses → PlaceRestaurants                              │
└─────────────────────────────────────────────────────────────┘

每个子阶段：
1. 底部动作栏显示当前可用动作
2. 点击动作 → 打开对应侧边栏
3. 完成操作或跳过
4. 自动进入下一子阶段
```

#### 6.2.5 Dinnertime 阶段（晚餐时间）
```
流程：自动结算
1. 显示晚餐时间覆盖层
2. 逐步展示销售过程（可配置速度）
3. 高亮当前处理的房屋和餐厅
4. 显示收入动画
5. 结算完成后自动进入下一阶段
```

#### 6.2.6 Payday 阶段（发薪日）
```
流程：解雇和支付
1. 侧边栏显示员工列表和薪资
2. 可选择解雇员工
3. 显示总支出预览
4. 确认支付
```

### 6.3 快捷键系统

#### 6.3.1 全局快捷键
| 快捷键 | 功能 | 说明 |
|--------|------|------|
| ESC | 取消/关闭 | 关闭当前面板或取消当前操作 |
| Enter | 确认/跳过 | 默认确认当前操作或跳过当前阶段（避免与“地图拖拽/窥视”冲突） |
| Space（按住） | 地图辅助 | 建议用于“临时隐藏浮层/进入地图拖拽模式”（可配置；与确认解耦） |
| D | 距离工具 | 切换距离测量模式 |
| L | 日志 | 显示/隐藏游戏日志 |
| M | 里程碑 | 显示里程碑面板 |
| Tab | 切换玩家视图 | 查看其他玩家信息 |
| 1-9 | 快速动作 | 执行对应编号的动作 |
| R | 旋转 | 仅在放置/预览相关模式中生效 |

#### 6.3.2 地图快捷键
| 快捷键 | 功能 |
|--------|------|
| 鼠标滚轮 | 缩放地图 |
| 鼠标中键拖拽 | 平移地图（现状已支持） |
| Space + 左键拖拽 | 平移地图（可选，提升触控板/无中键设备体验） |
| Home | 重置地图视图（建议补齐） |
| +/- | 缩放地图 |

#### 6.3.3 实现要点
```gdscript
# 在 game.gd 中添加（示意：建议为 map_controller 补齐 get_mode()/is_idle() 等只读接口）
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_ESCAPE:
                _handle_escape()
            KEY_ENTER, KEY_KP_ENTER:
                _handle_confirm_or_skip()
            KEY_D:
                toggle_distance_tool()
            KEY_L:
                toggle_game_log()
            KEY_M:
                show_milestone_panel()
            KEY_TAB:
                _cycle_player_view()

func _handle_escape() -> void:
    # 优先取消地图选点/工具模式；其次关闭当前面板；最后打开菜单
    if _map_controller != null:
        var mode := ""
        if _map_controller.has_method("get_mode"):
            mode = str(_map_controller.call("get_mode"))
        if not mode.is_empty():
            _map_controller.clear_selection()
            return
    if _is_any_panel_open():
        _close_all_panels()
        return
    _on_menu_pressed()
```

### 6.4 拖拽交互优化

#### 6.4.1 员工卡拖拽
```
拖拽场景：
1. 重组阶段：拖拽员工到公司结构树
2. 手牌区：拖拽调整员工顺序

视觉反馈：
- 拖拽时卡片半透明
- 有效放置区域高亮
- 无效区域显示禁止图标
- 放置时有吸附效果
```

#### 6.4.2 地图拖拽
```
拖拽场景：
1. 平移地图视图
2. 框选多个元素（未来功能）

实现：
- 使用鼠标中键或按住空格+左键拖拽
- 拖拽时显示手型光标
- 支持惯性滚动
```

---

## 7. 信息层级与展示

### 7.1 信息优先级分类

#### 7.1.1 第一层：始终可见
| 信息 | 位置 | 展示形式 |
|------|------|----------|
| 回合数 | 顶部状态栏 | 大字体数字 |
| 当前阶段 | 顶部状态栏 | 文字 + 进度指示器 |
| 银行资金 | 顶部状态栏 | 数字 |
| 当前玩家 | 顶部状态栏/底部信息栏 | 颜色标识 + 名称 |
| 玩家现金 | 底部信息栏 | 数字 |
| 库存数量 | 底部信息栏 | 图标 + 数字 |

#### 7.1.2 第二层：悬停/点击展开
| 信息 | 触发方式 | 展示形式 |
|------|----------|----------|
| 员工详情 | 悬停员工卡 | 浮动卡片 |
| 营销详情 | 悬停地图营销标记 | 工具提示 |
| 房屋需求 | 悬停房屋 | 工具提示 |
| 餐厅信息 | 悬停餐厅 | 工具提示 |
| 动作说明 | 悬停动作按钮 | 工具提示 |

#### 7.1.3 第三层：主动打开
| 信息 | 入口 | 展示形式 |
|------|------|----------|
| 游戏日志 | 工具栏按钮 | 左侧边栏 |
| 里程碑列表 | 工具栏按钮 | 右侧边栏 |
| 其他玩家详情 | 点击玩家卡片 | 弹出面板 |
| 游戏设置 | 菜单 | 右侧边栏 |

### 7.2 工具提示系统

#### 7.2.1 设计规范
```
┌─────────────────────────────┐
│ 标题（粗体）                │
├─────────────────────────────┤
│ 主要信息                    │
│ 次要信息（灰色）            │
├─────────────────────────────┤
│ 操作提示（斜体）            │
└─────────────────────────────┘
```

#### 7.2.2 示例
```
员工卡工具提示：
┌─────────────────────────────┐
│ 厨师长 (Chef)               │
├─────────────────────────────┤
│ 生产能力：5 个食物          │
│ 薪资：$15                   │
│ 状态：空闲                  │
├─────────────────────────────┤
│ 点击查看详情                │
└─────────────────────────────┘

营销标记工具提示：
┌─────────────────────────────┐
│ 广告牌 - 汉堡               │
├─────────────────────────────┤
│ 所有者：玩家1               │
│ 剩余时间：2 回合            │
│ 影响范围：4 格              │
├─────────────────────────────┤
│ 悬停查看范围                │
└─────────────────────────────┘
```

#### 7.2.3 实现要点
```gdscript
# 新文件：ui/components/tooltip/rich_tooltip.gd
class_name RichTooltip
extends Control

@export var title_label: Label
@export var content_container: VBoxContainer
@export var hint_label: Label

var _show_delay: float = 0.3
var _hide_delay: float = 0.1
var _timer: Timer

func show_for_target(target: Control, data: Dictionary) -> void:
    _populate(data)
    _position_near(target)
    _timer.start(_show_delay)

func _populate(data: Dictionary) -> void:
    title_label.text = data.get("title", "")
    _clear_content()

    for line in data.get("content", []):
        var label = Label.new()
        label.text = line.text
        if line.get("secondary", false):
            label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
        content_container.add_child(label)

    hint_label.text = data.get("hint", "")
    hint_label.visible = not hint_label.text.is_empty()
```

### 7.3 状态变化反馈

#### 7.3.1 数值变化动画
```
现金变化：
- 增加：绿色数字向上飘动 "+$50"
- 减少：红色数字向下飘动 "-$30"

库存变化：
- 增加：图标闪烁 + 数字跳动
- 减少：图标抖动 + 数字跳动
```

#### 7.3.2 状态转换动画
```
阶段切换：
- 阶段指示器滑动到新位置
- 顶部状态栏短暂高亮
- 可选：全屏阶段名称提示（淡入淡出）

玩家切换：
- 玩家卡片切换动画
- 底部面板内容更新动画
```

#### 7.3.3 操作反馈
```
成功操作：
- 按钮短暂变绿
- 可选：成功音效

失败操作：
- 按钮短暂变红 + 抖动
- 显示错误提示
- 可选：失败音效
```

### 7.4 玩家信息展示

#### 7.4.1 当前玩家详情
```
┌─────────────────────────────────────┐
│ 👤 玩家1                    $250    │
├─────────────────────────────────────┤
│ 员工：12  餐厅：3  里程碑：2        │
├─────────────────────────────────────┤
│ 库存：🍔×5  🍕×3  🥤×8              │
└─────────────────────────────────────┘
```

#### 7.4.2 其他玩家概览
```
点击当前玩家卡片展开：
┌─────────────────────────────────────┐
│ 所有玩家                            │
├─────────────────────────────────────┤
│ ● 玩家1  $250  员工:12  餐厅:3     │
│ ○ 玩家2  $180  员工:8   餐厅:2     │
│ ○ 玩家3  $320  员工:15  餐厅:4     │
│ ○ 玩家4  $95   员工:6   餐厅:1     │
└─────────────────────────────────────┘
● = 当前玩家
```

---

## 8. 实现优先级与路线图

### 8.1 优先级分类

#### P0 - 核心体验（必须实现）
在不推倒重来的前提下，优先解决最影响体验的问题：地图被遮挡、模式不清晰、高频入口深藏、设置不生效。最大化复用现有组件与控制器（`GamePanelController` / `GameMapInteractionController` / `GameOverlayController`）。

| 任务 | 描述 | 涉及文件 | 工作量 |
|------|------|----------|--------|
| 弹窗停靠改造 | 将 Recruit/Train/Marketing/Production/Payday 等“居中弹窗”改为右侧停靠/抽屉展示，地图交互时不遮挡地图 | `ui/scenes/game/game_panel_controller.gd` + `ui/scenes/game/game.tscn` + 相关 panel 场景 | 中 |
| 地图模式提示条 | 新增 MapModeBar（或 MapToolbar），统一显示当前模式/下一步/快捷键/退出方式 | 新建 `ui/components/map_mode_bar/`（或复用 `ui/components/map_toolbar/`）+ `ui/scenes/game/game_map_interaction_controller.gd` | 小 |
| TopBar 高频入口 | 日志/里程碑/距离工具/设置提升到 TopBar 一键入口；菜单只保留低频项 | `ui/scenes/game/game.tscn` + `ui/scenes/game/game.gd` | 小 |
| 设置闭环 | 让 `ui_scale`/`confirm_actions`/音量等设置真正生效，并统一配置文件职责 | `ui/dialogs/settings_dialog.gd` + `ui/scenes/game/game_overlay_controller.gd` + `ui/audio/*` | 中 |
| 对话框一致性 | 飞机角落方向选择等临时弹窗复用统一对话框组件，减少风格漂移 | `ui/scenes/game/game_map_interaction_controller.gd` + `ui/dialogs/*` | 小 |

#### P1 - 重要改进（应该实现）
在 P0 稳定后，增强信息层次、可解释性与一致性，逐步减少“分散的信息/重复点击”。

| 任务 | 描述 | 涉及文件 | 工作量 |
|------|------|----------|--------|
| 查看玩家（view_player） | 区分“当前行动玩家”与“查看玩家”，支持快速查看其他玩家摘要/库存/里程碑 | `ui/components/player_panel/` + 相关信息面板 | 中 |
| ActionPanel 可解释性 | 增加分组/排序/强制动作提示，并在灰显时显示不可用原因 | `ui/components/action_panel/` | 中 |
| 日志增强 | 在现有 GameLogPanel 上增加按玩家/关键字过滤与快捷入口 | `ui/components/game_log/` + `ui/scenes/game/game.tscn` | 中 |
| 工具提示统一 | 在现有 HelpTooltipManager 基础上补齐关键组件的 help_key 与内容 | `ui/components/help_tooltip/` + 相关组件注册 | 小 |
| 面板样式统一 | 统一 panel 的背景/边距/按钮行布局（优先复用现有场景样式） | `ui/components/*` | 中 |

#### P2 - 体验优化（可以实现）
进一步提升用户体验，增加便利功能。

| 任务 | 描述 | 涉及文件 | 工作量 |
|------|------|----------|--------|
| 完整日志视图 | 在现有 GameLogPanel 基础上做“全屏/抽屉模式 + 搜索/筛选” | 修改 `ui/components/game_log/` 或新增轻量容器 | 中 |
| 员工详情悬浮卡 | 实现鼠标悬浮显示员工详情（优先与 HelpTooltipManager 统一） | 新建 `ui/components/employee_tooltip/`（或扩展现有 tooltip） | 小 |
| 快捷键系统 | 统一 ESC/Enter/Space/R 的行为，并避免冲突 | 修改 `ui/scenes/game/game.gd` | 小 |
| 数值变化动画 | 实现现金/库存变化动画 | 新建动画相关代码 | 中 |
| 信息面板自适应 | 逐步调整底部/左侧信息区域占比（优先做可折叠/可调高度，而非一次性移除） | `ui/scenes/game/game.tscn` | 小 |

#### P3 - 锦上添花（未来考虑）
非必要但能提升体验的功能。

| 任务 | 描述 | 工作量 |
|------|------|--------|
| 迷你地图 | 右下角显示迷你地图 | 中 |
| 响应式布局 | 支持不同屏幕尺寸 | 大 |
| 主题系统 | 支持明暗主题切换 | 中 |
| 音效系统 | 完善 UI 音效 | 中 |
| 教程系统 | 新手引导 | 大 |

### 8.2 实现路线图

#### 第一阶段：核心框架（P0）
**目标**：在保留现有 UI 结构的前提下，显著减少遮挡并统一“模式提示/入口/设置”

```
步骤：
1. 将关键居中弹窗改为右侧停靠/抽屉（优先 Marketing/Production）
2. 新增 MapModeBar（模式提示条），接入 map_controller 的模式状态
3. TopBar 增加日志/里程碑/距离/设置快捷入口；精简菜单
4. 设置闭环：ui_scale/confirm_actions/音量实际生效
5. 统一临时弹窗（飞机角落方向选择等）
6. 集成测试（保持 headless 可运行）
```

**验收标准**：
- [x] Marketing/Production 等关键面板打开时不遮挡地图选点区域（右侧停靠替代居中；仍建议做一次视觉确认）
- [x] 任意地图交互模式都有明确模式提示条（MapModeBar：营销/放置/距离工具）
- [x] 日志/里程碑/距离/设置为一键入口（TopBar 新增快捷按钮；距离工具支持 D）
- [x] SettingsDialog 中的关键设置（至少 ui_scale/音量/确认操作）在游戏内可验证生效（音频写入 sound_settings.cfg；ui_scale 应用到 Window.content_scale_factor；confirm_actions 影响“确认结束”）

**P0 实施记录（代码落地）**：
- 弹窗停靠改造：Recruit/Train/Price/Production/Marketing/Milestone/Payday 由居中改为右侧停靠
- 地图模式提示条：新增 `MapModeBar` 并接入 `GameMapInteractionController.mode_changed`
- TopBar 高频入口：新增日志/里程碑/距离/设置按钮；`D` 直接切换距离工具
- 设置闭环：音频统一写入 `user://sound_settings.cfg`（新增 mix 区），修复 SoundManager 覆盖写配置问题；ui_scale/confirm_actions 运行时生效
- 对话框一致性：新增 `ChoiceDialog`，飞机角落方向选择复用统一对话框

**P0 自动化测试**（headless）：
```bash
tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

#### 第二阶段：面板完善（P1）
**目标**：增强信息层次、可解释性与一致性（不强制大重写）

```
步骤：
1. 引入 view_player（查看玩家）机制，支持快速查看其他玩家信息
2. ActionPanel 增加分组/排序/不可用原因提示
3. 日志增强：按玩家/关键字过滤与快捷打开
4. 工具提示补齐关键组件与内容
5. 统一面板样式与对话框行为
6. 集成测试
```

**验收标准**：
- [x] 能在不影响行动的情况下查看其他玩家摘要信息（PlayerPanel 点击切换“查看玩家”；TopBar 显示“查看: 玩家X”）
- [x] 灰显动作可解释（灰显时 tooltip 显示不可用原因；强制动作加【强制】前缀并优先展示）
- [x] 工具提示覆盖关键 UI 元素与核心机制（TopBar 按钮/玩家面板/既有关键面板已注册 HelpTooltipManager）
- [x] 对话框/面板关闭方式一致（ESC：优先关闭顶层对话框，其次关闭阶段面板/取消地图模式；仍建议补充更多面板的 ESC 行为一致性验证）

**P1 实施记录（代码落地）**：
- view_player：点击 PlayerPanel 切换查看玩家；库存/手牌/公司结构随查看玩家切换，行动仍以当前行动玩家为准
- ActionPanel：灰显动作 tooltip 显示不可用原因；强制动作高亮（前缀 + 排序）；取消 auto-hide 提升发现性
- GameLogPanel：新增玩家过滤与关键字搜索（保持原类型过滤）
- HelpTooltip：补齐 TopBar/PlayerPanel 的帮助条目与注册

**P1 自动化测试**（headless）：
```bash
tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

#### 第三阶段：体验优化（P2）
**目标**：提升整体用户体验

```
步骤：
1. 完整日志视图：全屏/抽屉模式 + 搜索/筛选
2. 员工详情悬浮卡：与现有 Tooltip 系统统一
3. 快捷键系统：统一 ESC/Enter/Space/R 行为并避免冲突
4. 数值变化动画：现金/库存变化反馈
5. 信息面板自适应：底部/左侧区域可折叠/可调占比
6. 设置补齐：动画速度/键位等（可选）
7. 集成测试
```

**验收标准**：
- [x] 完整日志可搜索/筛选，且能快速定位到相关玩家/事件（新增全屏日志窗口；沿用玩家过滤/关键字搜索）
- [x] 员工/地图关键元素有一致的悬浮信息展示（员工卡已接入 HelpTooltipManager；地图元素可后续补齐）
- [x] 快捷键在不同模式下行为一致且无冲突（ESC 关闭/取消；D 切换距离工具；R 在放置模式下旋转）
- [x] 关键数值变化有清晰的视觉反馈（现金/库存变化脉冲提示）
- [x] 信息面板在不同屏幕尺寸下仍可用（底部面板支持一键折叠，释放地图空间）

**P2 实施记录（代码落地）**：
- 完整日志视图：GameLogPanel 增加“全屏”按钮，打开 `FullLogWindow`（与来源日志实时同步新增条目）
- 员工详情悬浮卡：EmployeeCard 悬浮触发 HelpTooltipManager（自动补齐 employee_* 条目，优先保留内置文案）
- 快捷键系统：新增 R 旋转（餐厅/房屋放置），避免与 D/ESC 冲突
- 数值变化动画：现金/库存变化脉冲提示（headless 自动跳过）
- 信息面板自适应：BottomPanel 支持“隐藏/显示”切换，MainContent 自动扩展

**P2 自动化测试**（headless）：
```bash
tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

### 8.3 文件变更清单

#### 新建文件（P0-P2 实际已新增）
```
ui/components/map_mode_bar/
├── map_mode_bar.gd
└── map_mode_bar.tscn

ui/dialogs/
├── choice_dialog.gd
└── choice_dialog.tscn

ui/components/game_log/
├── full_log_window.gd
└── full_log_window.tscn
```

> 注：员工悬浮提示在 P2 阶段选择“复用 HelpTooltipManager + EmployeeCard”方式实现，因此没有新增 `ui/components/employee_tooltip/`。

#### 规划新建文件（P3+ / 布局 2.0）
```
ui/components/top_bar/        # 可选：将 game.tscn 顶栏组件化
ui/components/left_panel/     # 左侧信息面板（玩家纵向 Tab + 数据 Tab + 内容区）
ui/components/right_panel/    # 右侧操作面板（抽屉/可收起）
ui/components/modal_panel/    # 遮罩面板体系（不遮挡 Left Panel）
```

#### 修改文件（P0-P2 已改动的核心路径；非穷举）
```
ui/scenes/game/game_panel_controller.gd          # 弹窗停靠改造（替代统一居中）
ui/scenes/game/game_map_interaction_controller.gd # 模式提示条/模式统一出口
ui/scenes/game/game_overlay_controller.gd         # SettingsDialog 监听与入口统一
ui/scenes/game/game.gd                            # 快捷键与入口整合
ui/scenes/game/game.tscn                          # TopBar 快捷按钮 + 结构微调
ui/dialogs/settings_dialog.gd                     # 设置闭环（ui_scale/confirm_actions/音量）
ui/components/action_panel/action_panel.gd        # 分组/不可用原因提示
ui/components/game_log/game_log_panel.gd          # 过滤/搜索增强（可选）
```

#### 可能废弃的文件
```
（不建议在 P0/P1 阶段立即废弃任何组件）
后续若确实引入新的 Left/Right Panel 大框架，再逐步将 player_panel/inventory_panel 等“数据展示组件”迁移/合并，并保留旧实现一段时间用于回滚。
```

### 8.4 风险与注意事项

#### 8.4.1 兼容性风险
- 现有的面板控制器（`game_panel_controller.gd`）需要大幅修改
- 事件信号可能需要调整
- 存档/回放功能需要验证兼容性

#### 8.4.2 性能考虑
- 侧边栏动画应使用 Tween 而非每帧更新
- 工具提示应有延迟显示，避免频繁创建
- 地图覆盖层应按需渲染

#### 8.4.3 测试要点
- 所有阶段的操作流程
- 快捷键在各种状态下的行为
- 面板打开/关闭的边界情况
- 多玩家切换时的状态同步

### 8.5 迁移策略

#### 8.5.1 渐进式迁移
建议采用渐进式迁移策略，而非一次性重写：

1. **保留旧组件**：在新组件开发期间保留旧组件
2. **功能开关**：使用配置开关切换新旧UI
3. **逐步替换**：一个面板一个面板地替换
4. **充分测试**：每次替换后进行完整测试

#### 8.5.2 回滚方案
- 保留旧组件代码至少一个版本周期
- 使用 Git 分支管理 UI 重构
- 准备快速回滚脚本

### 8.6 当前开发进度（截至 2026-01-10）

> 说明：当前仓库代码已完成 **P0-P2 增量改造**，并已落地 **P3-P5（Left Panel + 信息迁移 + 右侧可收起/顶栏顺序展示，默认启用）**；尚未实现第 4/5 章示意图中的完整“2.0 左右分离新布局”（Left/Right Panel 分工 + Modal Panel 体系）。

#### 8.6.1 已落地（P0-P2 增量改造）
- [x] 右侧抽屉面板：Recruit/Train/Marketing/Production/Payday/Price/Milestone 等以 `popup_layout=dock_right` 进入 RightPanel 的 DockHost（带“返回/关闭”栏），不再覆盖地图（`ui/scenes/game/game.tscn` + `ui/scenes/game/game_panel_controller.gd`）
- [x] MapModeBar：地图交互模式提示条（`ui/components/map_mode_bar/` + `ui/scenes/game/game.gd` 监听地图模式变化）
- [x] TopBar 快捷入口：日志/里程碑/距离/设置一键入口（`ui/scenes/game/game.tscn`）
- [x] 设置闭环：`ui_scale`/`confirm_actions`/音量配置生效并统一职责（`ui/dialogs/settings_dialog.gd` + `autoload/globals.gd` + `ui/audio/sound_manager.gd`）
- [x] view_player：区分“当前行动玩家”与“查看玩家”（入口目前为点击 `PlayerPanel`；库存/手牌/公司结构跟随查看玩家切换）
- [x] ActionPanel 可解释性：灰显动作 tooltip 显示不可用原因；强制动作更醒目；取消 auto-hide 提升可发现性（`ui/components/action_panel/action_panel.gd`）
- [x] 日志增强：玩家过滤 + 关键字搜索（`ui/components/game_log/game_log_panel.gd`）
- [x] 完整日志窗口：GameLogPanel “全屏”按钮打开 FullLogWindow，并与来源日志实时同步新增条目（`ui/components/game_log/full_log_window.*`）
- [x] 员工悬浮信息：EmployeeCard 悬浮接入 HelpTooltipManager（`ui/components/employee_card/employee_card.gd`）
- [x] 快捷键：ESC 统一关闭/取消；D 切换距离工具；R 在放置模式下旋转（`ui/scenes/game/game.gd`）
- [x] 信息面板自适应：BottomPanel 支持“隐藏/显示”切换（`ui/scenes/game/game.tscn`）

**已验证的自动化测试（headless）**：
```bash
tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

#### 8.6.2 已落地（P3：Left Panel 骨架，v2 默认启用）
- [x] 布局开关：新增 `Globals.ui_layout_version`（1=当前布局；2=LeftPanel 试验布局），读取 `user://settings.cfg` 的 `[display] ui_layout_version`
- [x] LeftPanel 骨架：`ui/components/left_panel/left_panel.*`（玩家纵向 Tab + 摘要区 + 日志/里程碑 Tab 骨架）
- [x] 日志嵌入：v2 布局下复用原 `GameLogPanel` 实例并嵌入 `LeftPanel` 的“日志”Tab（不复制日志状态）
- [x] view_player 联动：LeftPanel 的玩家纵向 Tab 可切换 view_player；摘要随 view_player 更新（现金/库存）

#### 8.6.3 已落地（P4：信息迁移到 Left Panel，v2 默认启用）
- [x] 手牌/在职：LeftPanel 的“手牌/在职”Tab 使用“员工图标分组密集展示”（reserve/busy/employees），用于日常查看（图标后续可替换为图片）
- [x] 公司结构详情（重组）：保留 `HandArea` + `CompanyStructure` 在 BottomPanel（v2 默认隐藏），重组阶段由 `RestructuringModal` 临时 reparent 复用（避免 LeftPanel 常驻展示复杂树结构）
- [x] 里程碑迁移：LeftPanel 的“里程碑”Tab 直接嵌入 `MilestonePanel`（关闭按钮在嵌入模式下隐藏）
- [x] 本回合日志摘要：LeftPanel 底部新增“本回合日志”折叠区（按 view_player + 本回合过滤）并可一键切到“日志”Tab
- [x] BottomPanel 降级：v2 布局默认隐藏 BottomPanel（避免重复展示）；仍保留 v1 布局不变

**启用方式（开发者开关）**：
```ini
# user://settings.cfg
[display]
ui_layout_version=2
```
> 注：SettingsDialog 已暴露该开关（显示 -> UI布局）；默认已为 `ui_layout_version=2`，可切回 `ui_layout_version=1`。

#### 8.6.4 已落地（P5：Right Panel 可收起 + 顶栏顺序展示）
- [x] 顶栏顺序展示：新增 `TurnOrderDisplay` 并接入状态同步（显示玩家顺序并高亮当前行动玩家）
- [x] 右侧面板可收起：TopBar 新增“隐藏/显示操作”按钮（RightPanel show/hide，先不做动画）
- [x] 去重：v1 下右侧 `TurnOrderTrack` 仅在 `OrderOfBusiness` 阶段显示；v2 下 `TurnOrderTrack` 不再作为常驻交互入口（由 P6 遮罩面板接管选位）

#### 8.6.5 已落地（P6：Modal Panel 体系（重组/顺序选择）+ Space 窥视地图，v2 默认启用）
- [x] 遮罩基类：新增 `ui/components/modal_panel/modal_panel_base.*`（覆盖 CenterSplit，不遮挡 LeftArea；ESC 关闭；Space 按住窥视地图）
- [x] 重组遮罩面板：新增 `RestructuringModal`，复用 `HandArea` + `CompanyStructure` 并迁入遮罩面板；确认执行 `submit_restructuring`
- [x] 顺序选择遮罩面板：新增 `TurnOrderSelectionModal`，在遮罩面板完成 `OrderOfBusiness` 选位；确认执行 `choose_turn_order`
- [x] 接入：仅在 `ui_layout_version=2` 时启用；`Restructuring` / `OrderOfBusiness` 阶段自动弹出；可用 ESC 关闭（关闭后仍可通过动作入口再次打开）
- [x] v1 兼容：`ui_layout_version=1` 时不启用遮罩面板，仍使用右侧 `TurnOrderTrack` 完成选位

**P6 自动化测试（headless）**：
```bash
tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

#### 8.6.6 已落地（P7：响应式与清理）
- [x] BottomBar 移除：移除底部 Hash/命令数占位栏；调试信息迁入 DebugDialog；底部面板开关迁入 MenuDialog
- [x] 响应式断点：按窄屏/标准/宽屏调整 LeftArea/RightPanel 目标宽度与 TopBar 信息密度
- [x] 面板收起体验：TopBar 增加 LeftArea “隐藏/显示信息”开关；RightPanel show/hide 在非 headless 下增加滑入/滑出动画
- [x] view_player 主入口收敛（v2）：`ui_layout_version=2` 下隐藏右侧 `PlayerPanel`，将“查看玩家”入口收敛到 LeftPanel 的玩家纵向 Tab

**P7 自动化测试（headless）**：
```bash
tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

#### 8.6.7 尚未落地 / 与示意图（2.0）存在差距
- [x] Left Panel 员工图标分组展示：手牌/在职 Tab 使用“员工图标分组密集展示”（图标后续可替换为图片）
- [x] Left Panel 宽度可拖拽：LeftArea 支持拖拽调整宽度（200-400），并记住用户手动调整
- [x] Left Panel 摘要信息密度优化：库存使用 emoji + 摘要双行展示
- [x] Left Panel 本回合日志联动：按“回合开始”分割，默认只展示当前回合该玩家日志
- [x] 放置确认：确认/取消合并到右侧 ActionPanel；`confirm_actions=false` 时点击合法格自动确认（快速模式）
- [x] v2 布局切换入口：SettingsDialog 暴露 `ui_layout_version`（v1/v2），切换后运行时即时应用
- [x] v2 默认启用：默认 `ui_layout_version=2`（可在设置切回 `ui_layout_version=1`）
- [x] RightPanel 抽屉化：`dock_right` 的弹窗（Recruit/Train/Marketing/Production/Payday/Price/Milestone）嵌入 RightPanel，不再覆盖地图
- [x] RightPanel 进一步对齐示意图：统一“动作列表 -> 参数页”的导航/返回与底部 Footer（Recruit/Marketing/Production/Price/Train/Payday 已接入；支持双主按钮：Payday [解雇所选]/[支付]；对应 panel 内部按钮行在嵌入模式下隐藏；MilestonePanel 在嵌入模式下隐藏内部关闭按钮；返回/取消在非地图模式下不清空地图选中）

#### 8.6.8 当前 `ui/scenes/game/game.tscn` 实际结构快照
```
TopBar（内联 HBoxContainer）
  ├─ ToggleLeftPanel（隐藏/显示信息）
  └─ ToggleRightPanel（隐藏/显示操作）
MainContent（HSplitContainer）
  ├─ LeftArea: GameLogPanel（v1）/ LeftPanel（v2，内部嵌入 GameLogPanel）
  └─ CenterSplit（HSplitContainer）
      ├─ GameArea: MapView + Canvas + MapModeBar
      └─ RightPanel: HeaderRow（返回/关闭） + DefaultStack（PlayerPanel/TurnOrderTrack/InventoryPanel/ActionPanel） + DockHost（dock_right 弹窗抽屉） + FooterRow（取消/双主按钮/确认）
BottomPanel（HSplitContainer）: HandArea + CompanyStructure
MenuDialog：新增 ToggleBottomPanel（显示/隐藏底部面板）
DebugDialog：显示 Hash/命令数（仅调试窗口内）
```

### 8.7 后续开发计划（P3+：对齐“左右分离新布局示意图”）

> 总体策略：继续保持“渐进式迁移 + 可回滚”，通过 **布局版本开关** 与 **组件封装**，逐步把现有信息展示/操作组件迁移到 Left/Right Panel 框架下；每个阶段都要求 headless 测试通过，并补充一次人工 UI 走查。

#### P3 - Left Panel 骨架（最小可用）+ 布局开关
**目标**：让游戏内出现“左侧信息面板”的基本形态，且不破坏现有流程。

**工作项**：
1) 引入布局版本开关（例如 `Globals.ui_layout_version` 或 ProjectSettings），支持 v1（经典布局）/v2（新布局）切换，默认已为 v2
2) 新建 `ui/components/left_panel/`：提供
   - 玩家纵向 Tab（切换 view_player）
   - 基础摘要区（当前查看玩家的现金/库存概览等，先做最小展示）
   - 数据类型 Tab（先只放 1-2 个 tab：例如“日志/里程碑”，逐步扩展）
3) 在 v2 布局下将当前左侧 `GameLogPanel` 替换为 `LeftPanel`（内部可先复用/嵌入现有 `GameLogPanel`）

**验收标准**：
- 能在不影响行动的情况下用“玩家纵向 Tab”切换 view_player
- 现有 `GameLogPanel` 能在 Left Panel 中继续使用（或以折叠区形式出现）
- `game_smoke_test` + `all_tests` headless 通过

**P3 实施记录（代码落地）**：
- 新增 LeftPanel：`ui/components/left_panel/left_panel.gd`、`ui/components/left_panel/left_panel.tscn`
- 布局节点调整：`ui/scenes/game/game.tscn` 新增 `LeftArea`，并在其中同时放置 `GameLogPanel`（v1）与 `LeftPanel`（v2）
- 布局开关：`autoload/globals.gd` 新增 `ui_layout_version`（读取 `user://settings.cfg` 的 `[display] ui_layout_version`）
- 日志嵌入：`ui/scenes/game/game.gd` 根据 `ui_layout_version` 将 `GameLogPanel` 复用并嵌入 `LeftPanel` 的日志 Tab
- view_player 联动：`ui/scenes/game/game_panel_controller.gd` 将 LeftPanel 的 `player_selected` 接入 view_player，并同步 LeftPanel 的摘要/高亮

**P3 自动化测试（headless）**：
```bash
tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

#### P4 - 信息迁移：手牌/公司结构/里程碑/日志整合到 Left Panel
**目标**：把“纯信息展示”从底部/右侧迁入 Left Panel，逐步降低 BottomPanel 重要性。

**工作项**：
1) Left Panel 的数据 Tab 扩展为：手牌/在职/里程碑/日志（先复用现有 `HandArea`/`CompanyStructure`/`MilestonePanel` 的展示逻辑，优先嵌入而非重写）
2) 将“本回合日志”作为 Left Panel 的折叠区：默认展示 view_player 的本回合日志，提供“查看完整日志”入口（复用 FullLogWindow）
3) 逐步调整 BottomPanel：先提供“默认收起/可展开”，等 Left Panel 信息覆盖后再讨论移除

**验收标准**：
- Left Panel 能完成查看手牌/公司结构/里程碑/日志的主要需求
- BottomPanel 即使收起也不影响常规回合操作
- headless 测试通过 + 人工走查（至少一局完整回合流程）

**P4 实施记录（代码落地）**：
- LeftPanel 扩展 Tab：新增“手牌/在职/里程碑/日志”四个 Tab，并新增底部“最近日志”折叠区（`ui/components/left_panel/left_panel.*`）
- 手牌/公司结构迁移：v2 布局下复用原 `HandArea`/`CompanyStructure` 实例并嵌入 LeftPanel（`ui/scenes/game/game.gd`）
- 重组阶段引导：进入 `Restructuring` 时 LeftPanel 自动切到“在职”Tab（`ui/components/left_panel/left_panel.gd`）
- 里程碑迁移：LeftPanel 内嵌 `MilestonePanel`，并新增 `show_close_button` 以支持嵌入模式隐藏关闭按钮（`ui/components/milestone_panel/milestone_panel.gd`）
- BottomPanel 降级：v2 布局默认隐藏 BottomPanel（避免重复展示），保留 v1 布局不变（`ui/scenes/game/game.gd`）

**P4 自动化测试（headless）**：
```bash
tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

#### P5 - Right Panel 抽屉化 + TurnOrder 移至 TopBar 展示
**目标**：让 Right Panel 符合示意图“可收起”的交互，并把 TurnOrder 从右侧迁到顶栏。

**工作项**：
1) 新建 `ui/components/right_panel/`：抽屉式收起/展开（含动画），并与 `GamePanelController` 停靠面板兼容
2) 将 TurnOrder 改为 TopBar “纯展示”（必要时拆分 `TurnOrderTrack`：display-only 与 interactive 两种模式）
3) 顺序选择入口从 TopBar/阶段流程触发，但交互在专门的面板中完成（见 P6）

**验收标准**：
- Right Panel 可一键收起，地图区域获得空间
- TurnOrder 在 TopBar 可见且正确高亮当前行动玩家
- headless 测试通过 + 人工走查（包含顺序相关阶段）

**P5 实施记录（代码落地）**：
- 顶栏顺序展示：新增 `ui/components/turn_order/turn_order_display.*` 并在 TopBar 中实例化
- 右侧面板可收起：TopBar 新增“隐藏/显示操作”按钮（先做 show/hide；动画留待 P7 统一处理）
- 去重：右侧 `TurnOrderTrack` 仅在 `OrderOfBusiness` 阶段显示（v1 仍使用其完成选位；v2 已在 P6 迁移到遮罩面板）

**P5 自动化测试（headless）**：
```bash
tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

#### P6 - Modal Panel 体系（重组/顺序选择）+ Space 窥视地图
**目标**：实现文档 4.4/5.4 的遮罩面板体系：遮罩地图与 Right Panel，但不遮挡 Left Panel；统一确认/取消与快捷键。

**工作项**：
1) 新建 `ui/components/modal_panel/`：`ModalPanelBase`（遮罩/容器/确认取消/ESC/Space 窥视地图）
2) 重组面板：将公司结构重组流程迁入 Modal Panel（避免遮挡 Left Panel）
3) 顺序选择面板：把“可点击选位”从常驻 TurnOrder 展示中移除，集中到 Modal Panel 中完成

**验收标准**：
- 遮罩面板打开时 Left Panel 仍可见（可参考信息）
- 按住 Space 可临时“窥视地图”（可选：如果与现有地图输入冲突，需重新定义键位并在设置中可配置）
- headless 测试通过 + 人工走查（重组/顺序选择全流程）

**P6 实施记录（代码落地）**：
- 新增遮罩基类：`ui/components/modal_panel/modal_panel_base.*`（覆盖 CenterSplit；ESC 取消；Space 窥视地图）
- 新增重组遮罩：`ui/components/modal_panel/restructuring_modal.*`（临时 reparent `HandArea` + `CompanyStructure`；确认执行 `submit_restructuring`）
- 新增顺序选择遮罩：`ui/components/modal_panel/turn_order_selection_modal.*`（内嵌 `TurnOrderTrack`；确认执行 `choose_turn_order`）
- 接入控制器：`ui/scenes/game/game_panel_controller.gd`（仅 `ui_layout_version=2` 启用；`Restructuring` / `OrderOfBusiness` 阶段自动弹出；v1 保持右侧 `TurnOrderTrack` 选位）

**P6 自动化测试（headless）**：
```bash
tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

#### P7 - 响应式与清理（移除 BottomBar、断点适配、视觉统一）
**目标**：对齐文档的响应式策略与整体一致性，收敛旧布局遗留。

**工作项**：
1) 窄屏/标准/宽屏断点：Left/Right Panel 的最小宽度、可收起策略、TopBar 信息密度调整
2) 移除 BottomBar（Hash/命令数等调试信息迁入 Debug 菜单或可选显示）
3) 统一视觉样式与间距：面板背景、按钮行、标题层级、hover/press 反馈（优先复用现有样式，避免引入新主题系统）

**验收标准**：
- 不同分辨率下布局不溢出、可操作
- BottomBar 从默认 UI 中移除且不影响调试能力
- headless 测试通过 + 人工走查（至少覆盖窄屏与宽屏）

**P7 实施记录（代码落地）**：
- BottomBar 移除：`ui/scenes/game/game.tscn` 移除 BottomBar；Hash/命令数迁入 DebugDialog；底部面板开关迁入 MenuDialog
- 响应式断点：`ui/scenes/game/game.gd` 新增窄屏/标准/宽屏布局参数（LeftArea/RightPanel 宽度 + TopBar 密度）
- 面板收起体验：TopBar 增加 ToggleLeftPanel；RightPanel show/hide 在非 headless 下增加滑入/滑出动画

**P7 自动化测试（headless）**：
```bash
tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60
```

#### 每阶段通用要求（强制）
- 自动化：每次合入后至少跑一次 headless `game_smoke_test` + `all_tests`
- 人工：每个阶段至少做一次“从进入游戏到结束一回合”的 UI 走查（用于验证布局/遮挡/快捷键/可用性）
- 文档：在本节下更新对应阶段的勾选进度、验收结果与测试日志摘要

---

## 附录

### A. 术语表

| 术语 | 说明 |
|------|------|
| 侧边栏 (Side Panel) | 从屏幕边缘滑出的面板 |
| 工具栏 (Toolbar) | 悬浮在地图上方的操作提示栏 |
| 覆盖层 (Overlay) | 叠加在地图上的半透明信息层 |
| 工具提示 (Tooltip) | 悬停时显示的信息气泡 |
| 模式 (Mode) | 当前的交互状态（空闲/选点/预览等） |

### B. 参考资源

- Godot 4 UI 最佳实践
- Board Game Arena FCM 实现
- Terraforming Mars Digital UI 设计
- Material Design 3 组件规范

### C. 修订历史

| 版本 | 日期 | 修改内容 |
|------|------|----------|
| 1.0 | 2026-01-10 | 初始版本 |
| 2.0 | 2026-01-10 | 设计稿：提出左右分离目标布局（Left Panel 信息展示 + Right Panel 操作交互 + Modal Panel 等），作为后续演进方向（未落地） |
| 2.1 | 2026-01-09 | 对照当前实现修正文档：区分“居中弹窗”与“地图覆盖层”；补充设置未闭环/重复建设风险/快捷键冲突；将路线图调整为以现有控制器为核心的渐进式迁移，优先解决遮挡与模式提示问题 |
| 2.2 | 2026-01-09 | P0 已落地：停靠弹窗/MapModeBar/TopBar 快捷入口/设置闭环/统一选择对话框；通过 headless smoke + all tests |
| 2.3 | 2026-01-09 | P1 已落地：view_player/ActionPanel 不可用原因/日志过滤搜索/Tooltip 补齐；通过 headless smoke + all tests |
| 2.4 | 2026-01-09 | P2 已落地：全屏日志/员工悬浮信息/快捷键与旋转/数值变化动画/底部面板折叠；通过 headless smoke + all tests |
| 2.5 | 2026-01-10 | 修正文档状态：澄清“P0-P2 已落地，但 2.0 示意布局未实现”；补充当前进度差距清单与 P3+ 后续开发计划 |
| 2.6 | 2026-01-10 | P3 已落地：Left Panel 骨架 + `ui_layout_version` 布局开关（默认关闭）；通过 headless smoke + all tests |
| 2.7 | 2026-01-10 | P4 已落地：Left Panel 信息迁移（手牌/公司结构/里程碑/最近日志）；通过 headless smoke + all tests |
| 2.8 | 2026-01-10 | P5 已落地：Right Panel 可收起 + 顶栏顺序展示；通过 headless smoke + all tests |
| 2.9 | 2026-01-10 | P6 已落地：Modal Panel 体系（重组/顺序选择）+ Space 窥视地图（默认关闭）；通过 headless smoke + all tests |
| 3.0 | 2026-01-10 | P7 已落地：响应式断点 + BottomBar 移除 + 面板收起体验；通过 headless smoke + all tests |
| 3.1 | 2026-01-10 | v2 入口收敛：隐藏右侧 PlayerPanel 的 view_player 入口；LeftPanel 摘要修正库存展示；通过 headless smoke + all tests |
| 3.2 | 2026-01-10 | LeftPanel 摘要增强：补充员工分组计数（管理/厨房/营销/其他）；通过 headless smoke + all tests |
| 3.3 | 2026-01-10 | 放置流程：确认/取消合并到右侧 ActionPanel（Overlay 去除底部按钮）；LeftPanel：实现“员工图标分组密集展示”（可替换图片）；通过 headless smoke + all tests |
| 3.4 | 2026-01-10 | 放置覆盖层：确认/取消后自动退出（Overlay 自动隐藏，避免残留提示）；通过 headless smoke + all tests |
| 3.5 | 2026-01-10 | LeftPanel：LeftArea 宽度可拖拽（200-400）+ 本回合日志过滤（按“回合开始”切分）；通过 headless smoke + all tests |
| 3.6 | 2026-01-10 | 放置流程：`confirm_actions=false` 时点击合法格自动确认（快速模式）；LeftPanel：摘要区信息密度优化（库存 emoji + 双行展示）；通过 headless smoke + all tests |
| 3.7 | 2026-01-10 | SettingsDialog：暴露 `ui_layout_version`（v1/v2）并在运行时应用布局切换；通过 headless smoke + all tests |
| 3.8 | 2026-01-10 | 默认启用 v2 布局：`Globals.ui_layout_version=2`；修正 v2 切回 v1 时 BottomPanel 偏移/按钮状态；通过 headless smoke + all tests |
| 3.9 | 2026-01-10 | RightPanel 抽屉化：`dock_right` 弹窗嵌入 RightPanel（Header 返回/关闭），不再覆盖地图；通过 headless smoke + all tests |
| 4.0 | 2026-01-10 | RightPanel Footer：`dock_right` 抽屉统一底部 [取消]/[确认]（Marketing/Production/Price/Train），嵌入模式隐藏面板内部按钮；通过 headless smoke + all tests |
| 4.1 | 2026-01-10 | RightPanel Footer：扩展为双主按钮（Payday [解雇所选]/[支付]）+ Recruit 改为“选择→确认”；修复 Payday 列表渲染缩进问题；通过 headless smoke + all tests |
| 4.2 | 2026-01-10 | MilestonePanel：嵌入 RightPanel 时隐藏内部关闭按钮行；通过 headless smoke + all tests |
| 4.3 | 2026-01-10 | RightPanel：返回/取消在非地图模式下不再清空地图选中；OverlayController：hide_all_overlays 不再隐藏“状态驱动”的需求/晚餐遮罩；通过 headless smoke + all tests |
| 4.4 | 2026-01-10 | 快捷键：Enter/Shift+Enter 触发 RightPanel Footer 主/次按钮；通过 headless smoke + all tests |
| 4.5 | 2026-01-10 | Headless：修复 GameSmokeTest 退出时的 ObjectDB/资源泄漏（DebugCommandRegistry/DebugPanel dispose + GameScene 控制器释放）；通过 headless smoke + all tests |
