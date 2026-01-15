# UI 视觉资源升级设计文档

## 0. 进度追踪（本仓库执行记录）

> 规则：每次实现一个小步骤，都在此处更新状态/备注，避免“文档与代码脱节”。

### 0.1 已确认决策（与仓库现状对齐）

- 房屋花园：允许按方向贴（N/E/S/W），默认在下方（S）。
- 员工配色：保持项目现有职责色（以 `core/data/employee_def.gd` / `EmployeeDef.get_role_color()` 为准）。
- SVG → PNG：安装并使用 `inkscape`（命令行）进行批量转换。
- 餐厅 Logo：进入游戏前随机分配一次，并按 `player_id` 固定绑定（保证回放/联机确定性）。
- 旧存档兼容：若 `players[*].restaurant_logo_id` 缺失，UI 侧用 `state.seed + player_id` 推导确定性兜底（不写回存档）。

### 0.2 任务状态

| 项 | 内容 | 状态 | 备注 |
|---|---|---|---|
| 0 | 文档与项目对齐 | Done | 修正 VisualCatalog schema / footprint 描述 / 转换脚本路径 |
| 5.1 | 资源准备（安装 & 转换） | Done | 已安装 Inkscape（App 路径）；已实现并执行 `tools/convert_assets.sh` |
| 5.2 | 员工卡片升级 | In Progress | 已实现 FULL/COMPACT 框架（占位头像/底部信息行）；待补齐图标/员工图片与细节调优 |
| 3 | 员工升级路线树 | In Progress | 已实现 MVP：顶栏按钮入口；Layered 布局（barycenter 排序减少交叉）；悬停高亮路径；滚轮缩放/拖拽平移/双击适配窗口；点击节点弹出详情 |
| 5.3 | 公司结构树升级 | Deferred | 本轮暂不升级公司结构树（Q12）；后续如需再单独排期 |
| 5.4 | 地图渲染升级 | In Progress | 已修复图标拉伸（按宽高比绘制）；已实现需求图标散落（确定性）/房屋花园底色/餐厅 Logo 叠加；UI：库存/晚餐订单/需求指示器/营销面板/范围 overlay 已切换至贴图图标；待手动验收与测试 |
| 5.5 | 集成测试 | In Progress | 已跑 headless：`check_compile.gd (ui+core)` / `AllTests (77/77)` PASS；待手动检查 |

### 0.3 验收反馈修复（进行中）

| ID | 内容 | 状态 | 备注 |
|---|---|---|---|
| F1 | 房屋渲染：底色 `#733651`；房屋图底部留空隙；显示 `house_id`（右上角）；文本框透明无白底 | Done | 已改：`ui/scenes/game/map_canvas_drawer.gd`（用 `house_id`，去白底；房屋贴图 bottom gap）待验收 |
| F2 | 缩略员工卡：显示员工名字；顶部整行底色为员工类别色 | Done | 已改：`ui/components/employee_card/employee_card.gd`（COMPACT 顶部整行底色+居中名字）待验收 |
| F3 | 升级路线树：全屏弹窗；唯一路线同一水平线；不显示 CEO；卡片间距 | Done | 已改：`ui/scenes/game/game_panel_controller.gd`（全屏覆盖）；`ui/components/employee_tree/*`（排除 CEO、增大间距、唯一路线对齐）待验收 |
| F4 | 左侧玩家 Tab & 顶部回合顺位：数字改餐厅 icon | Done | 已改：`ui/components/left_panel/left_panel.gd`、`ui/components/turn_order/turn_order_display.gd`、`ui/scenes/game/game_panel_controller.gd`（加载 player logo 并显示）待验收 |
| F5 | 地图餐厅：去掉旧餐厅图片；餐厅 icon 充满 2x2 区域 | Done | 已改：`ui/scenes/game/map_canvas_drawer.gd`（logo 以 aspect-fill 绘制到 2x2）待验收 |
| F6 | 载入存档：餐厅 icon 全部一样（logo_id 映射/读取） | Done | 已改：`ui/scenes/game/map_canvas.gd`（兜底 logo 分配改为 seed 洗牌，避免重复；且处理 null）；并同步到 `ui/components/left_panel/left_panel.gd`、`ui/components/turn_order/turn_order_display.gd` 待验收 |
| F7 | 地图 tile：绘制向内黑色粗边框；可选显示旋转的 tile_id（设置可关闭） | Done | 已改：`ui/scenes/game/map_canvas_drawer.gd`（tile 内描边+按 rotation 选择角落显示 tile_id）；`ui/dialogs/settings_dialog.gd`、`ui/dialogs/settings_dialog.tscn`、`autoload/globals.gd`（新增设置 `show_tile_ids`）待验收 |
| F8 | 调试面板：修复失效命令；新增“给某房屋增加需求”的营销命令 | Done | 已修复 `place_restaurant/place_house/move_restaurant/marketing` 的 position 参数格式；“查看营销”改为 `marketing_list`；已新增 `add_house_demand`（内部 action: `debug_add_house_demand`）；验证：`check_compile.gd` + `AllTests` PASS |
| F9 | 回合顺位指示器：logo 不应按原始尺寸撑开 | Done | 已改：`ui/components/turn_order/turn_order_display.gd`（TextureRect 设为 ignore min size） |
| F10 | 左侧信息面板/日志面板：启动时日志默认隐藏；左侧信息面板宽度覆盖完整区域避免露底 | Done | 已改：`ui/scenes/game/game.tscn`（LeftPanel full-rect；GameLogPanel 默认隐藏）、`ui/scenes/game/game_overlay_controller.gd`（initialize 不再强制显示日志） |
| F11 | 房屋标号：字体调大 & 增加边距（右上角） | Done | 已改：`ui/scenes/game/map_canvas_drawer.gd`（house_id 字号/边距调优） |
| F12 | Tile 边框：向内黑边框厚度调细 | Done | 已改：`ui/scenes/game/map_canvas_drawer.gd`（降低边框 thickness） |
| F13 | 房屋需求图标：调大；散落更靠中心（非角落随机） | Done | 已改：`ui/scenes/game/map_canvas_drawer.gd`（icon_size 调大；中心偏置采样；收缩散落区域） |
| F14 | 餐厅渲染：logo 居中；底色 `#f4edd1`；入口格 L 形标记；logo 去背景 | Done | 已改：`ui/scenes/game/map_canvas_drawer.gd`（居中+入口 L）；`ui/visual/map_skin.gd`（logo flood-fill 去背景） |
| F15 | 放置预览：显示半透明房屋/餐厅图片（所见即所得） | Done | 已改：`ui/scenes/game/map_canvas.gd`、`ui/scenes/game/map_canvas_drawer.gd`、`ui/components/house_placement/house_placement_overlay.gd`、`ui/scenes/game/game_panel_placement_overlays.gd`、`ui/scenes/game/game_map_interaction_controller.gd`；验证：`check_compile.gd` + `AllTests` PASS |
| F16 | 缩略员工卡：升级路线树等场景顶部名字偶发为空（setup/_ready 时序） | Pending (Review) | 方案与根因分析：`docs/employee_defs_alignment_review.md`（需你点头后再改代码） |
| F17 | 员工定义对齐：按 PDF + `road_map.png` 校准 name/id/train_to（含对照表） | Pending (Review) | 已生成对照表与改动清单：`docs/employee_defs_alignment_review.md`（需你点头后再改数据） |

## 1. 概述

本文档描述如何将新的高质量视觉资源整合到 Food Chain Magnate 项目中，以提升游戏的视觉效果。

### 1.1 目标

- 使用新的餐厅Logo替换现有的简单图标
- 使用新的食物/饮料图标提升产品显示效果
- 使用新的房屋和花园图片改善地图视觉
- 使用新的广告牌图片增强营销元素显示
- 参考demo图片实现更精美的员工卡片和公司结构树

### 1.2 新资源清单

#### 餐厅Logo (SVG格式)
| 文件名 | 描述 |
|--------|------|
| Fried Geese & Donkey.svg | 餐厅Logo |
| Gluttony Inc Burgers.svg | 餐厅Logo |
| Goldem Duck Diner.svg | 餐厅Logo |
| Santa Maria Pizza.svg | 餐厅Logo |
| Xango Blues Bar.svg | 餐厅Logo |

#### 食物和饮料图标 (SVG格式)
| 文件名 | 描述 | 用途 |
|--------|------|------|
| Burger - Icon.svg | 汉堡图标 | 产品显示、需求显示 |
| Pizza - Icon.svg | 披萨图标 | 产品显示、需求显示 |
| Beer - Icon.svg | 啤酒图标 | 产品显示、需求显示 |
| Lemonade - Icon.svg | 柠檬水图标 | 产品显示、需求显示 |
| Softdrink - Icon.svg | 软饮图标 | 产品显示、需求显示 |
| Burger.svg | 汉堡大图 | 详情展示 |
| Pizza.svg | 披萨大图 | 详情展示 |
| Softdrink.svg | 软饮大图 | 详情展示 |

#### 房屋和花园 (SVG格式)
| 文件名 | 描述 |
|--------|------|
| House.svg | 房屋主体图片 |
| Gate and Fence.svg | 围栏和大门 |

#### 营销元素 (SVG格式)
| 文件名 | 描述 |
|--------|------|
| Billboard.svg | 广告牌 |
| Aeroplane.svg | 飞机广告 |
| Mail Box.svg | 邮箱广告 |
| Radio - Icon.svg | 电台广告图标 |

### 1.3 Demo效果参考

根据demo图片分析：

1. **employee_card_demo.png** - 展示了精美的员工卡片设计
   - 卡片有明显的边框和阴影效果
   - 使用了角色相关的颜色主题
   - 包含员工头像/图标区域
   - 清晰的层级和信息布局

2. **employee_tree_demo.png** - 展示了公司结构树的视觉效果
   - 层级分明的树状结构
   - 连接线清晰可见
   - 卡片之间有合理的间距
   - 整体布局美观

3. **house_demo.png** - 展示了房屋在地图上的渲染效果
   - 等距视角的房屋图片
   - 清晰的轮廓和细节
   - 与地图格子良好融合

4. **hose_with_garden_demo.png** - 展示了带花园的房屋效果
   - 房屋与花园的组合显示
   - 围栏的视觉效果
   - 整体占地面积的处理

---

## 2. 员工卡片 (Employee Card) 设计

员工卡片分为两种版本：**完整版**（类似扑克牌比例）和**缩略版**（用于员工升级路线树等场景）。

### 2.1 完整版员工卡片

参考 `employee_card_demo.png`，完整版员工卡片采用扑克牌比例设计。

#### 2.1.1 视觉结构

```text
┌─────────────────────────────────┐
│◢                                │  ← 左上角三角形 (仅entry_level显示)
│                                 │
│         [员工名称]              │  ← 中间上方
│                                 │
│                                 │
│       ┌─────────────┐           │
│       │             │           │
│       │  [员工图片]  │           │  ← 中央区域
│       │             │           │
│       └─────────────┘           │
│                                 │
│    ─────────────────────────    │
│    [员工效果描述文字]            │  ← 中间偏下
│    ─────────────────────────    │
│                                 │
└─────────────────────────────────┘
```

#### 2.1.2 尺寸规格

| 属性 | 值 | 说明 |
| ---- | -- | ---- |
| 卡片宽度 | 180px | 扑克牌比例 |
| 卡片高度 | 252px | 宽高比约 5:7 |
| 圆角半径 | 8px | |
| 边框宽度 | 2px | |
| 内边距 | 12px | |
| Entry三角形 | 24x24px | 左上角 |
| 员工图片区 | 120x120px | 居中 |

#### 2.1.3 Entry Level 三角形

- 位置：左上角
- 颜色：与角色主色相同
- 仅当员工为 entry_level 时显示

### 2.2 缩略版员工卡片

用于员工升级路线树、手牌区等需要紧凑显示的场景。

#### 2.2.1 视觉结构

```text
┌─────────────────────────────────┐
│          [员工名称]             │  ← 第一行：仅名称
├─────────────────────────────────┤
│                                 │
│       [员工效果描述]            │  ← 中间区域：效果文字
│                                 │
├─────────────────────────────────┤
│  [E]      [路程]      [$]       │  ← 底部三图标
└─────────────────────────────────┘
```

#### 2.2.2 尺寸规格

| 属性 | 值 | 说明 |
| ---- | -- | ---- |
| 卡片宽度 | 130px | 保持当前尺寸 |
| 卡片高度 | 90px | 保持当前尺寸 |
| 圆角半径 | 4px | |
| 图标尺寸 | 16x16px | 底部三个图标 |

#### 2.2.3 底部图标说明

| 位置 | 图标 | 说明 |
| ---- | ---- | ---- |
| 左下角 | Entry Level图标 | 仅entry_level员工显示，否则留空 |
| 中间 | 路程图标 | 显示员工的路程值（待收集资源） |
| 右下角 | 工资图标 | 显示薪资等级（待收集资源） |

### 2.3 颜色方案

两种版本共用相同的角色颜色编码：

| 角色类型 | 主色 | 用途 |
| -------- | ---- | ---- |
| manager | #4A90D9 | 经理类 |
| recruit_train | #7B68EE | 招聘/培训类 |
| produce_food | #E67E22 | 食物生产类 |
| procure_drink | #27AE60 | 饮料采购类 |
| price | #F1C40F | 定价类 |
| marketing | #E74C3C | 营销类 |
| new_shop | #9B59B6 | 开店类 |
| special | #1ABC9C | 特殊能力类 |

### 2.4 待收集资源清单

| 资源 | 用途 | 状态 |
| ---- | ---- | ---- |
| Entry Level 三角形/图标 | 标识入门级员工 | 待收集 |
| 路程图标 | 缩略卡底部中间 | 待收集 |
| 工资图标 | 缩略卡底部右侧 | 待收集 |
| 各员工图片 | 完整卡中央 | 待收集 |

---

## 3. 员工升级路线树 (Employee Upgrade Tree) 设计

参考 `employee_tree_demo.png`，这是一个展示游戏中所有员工及其升级路线的独立视图组件。

### 3.1 功能说明

员工升级路线树用于：

- 展示游戏中所有可用的员工类型
- 显示员工之间的升级关系
- 帮助玩家规划招聘和培训策略

### 3.2 布局设计

采用**从左到右**的水平布局，使用类似 ELK (Eclipse Layout Kernel) 的 layered 算法进行排版。

#### 3.2.1 视觉结构

```text
Layer 0          Layer 1          Layer 2          Layer 3
(Entry Level)    (Level 2)        (Level 3)        (Level 4+)

┌─────────┐      ┌─────────┐      ┌─────────┐
│ Trainee │─────▶│ Cook    │─────▶│ Chef    │
└─────────┘      └─────────┘      └─────────┘
                       │
                       └────────▶┌─────────┐
                                 │ Exec    │
┌─────────┐      ┌─────────┐     │ Chef    │
│ Errand  │─────▶│ Cart    │     └─────────┘
│ Boy     │      │ Operator│
└─────────┘      └─────────┘

┌─────────┐      ┌─────────┐      ┌─────────┐
│ Recruit │─────▶│ HR      │─────▶│ HR      │
│ Girl    │      │         │      │ Director│
└─────────┘      └─────────┘      └─────────┘
    │
    └───────────▶┌─────────┐
                 │ Trainer │
                 └─────────┘

... (更多员工)
```

#### 3.2.2 层级定义

| 层级 (Layer) | X位置 | 包含员工 |
| ------------ | ----- | -------- |
| Layer 0 | 0 | 所有 entry_level 员工 |
| Layer 1 | 1 | 从 entry_level 升级一次的员工 |
| Layer 2 | 2 | 从 Layer 1 升级的员工 |
| Layer N | N | 依此类推 |

### 3.3 节点设计

每个节点使用**缩略版员工卡片**（参见 2.2 节）。

#### 3.3.1 节点尺寸

| 属性 | 值 |
| ---- | -- |
| 节点宽度 | 130px |
| 节点高度 | 90px |
| 水平间距 | 60px |
| 垂直间距 | 20px |
| 层级间距 | 200px |

### 3.4 连接线设计

#### 3.4.1 线条样式

| 属性 | 值 |
| ---- | -- |
| 线条颜色 | #666666 (默认) |
| 高亮颜色 | #4A90D9 (悬停时) |
| 线条宽度 | 2px |
| 箭头大小 | 8px |
| 线条样式 | 贝塞尔曲线 |

#### 3.4.2 连接线绘制规则

- 从源节点的**右侧中点**出发
- 到目标节点的**左侧中点**结束
- 使用水平方向的贝塞尔曲线，避免交叉
- 箭头指向目标节点

### 3.5 交互设计

#### 3.5.1 基本交互

| 操作 | 效果 |
| ---- | ---- |
| 悬停节点 | 高亮该节点及其所有升级路径 |
| 点击节点 | 显示员工详细信息弹窗 |
| 滚轮 | 缩放视图 |
| 拖拽背景 | 平移视图 |

#### 3.5.2 缩放和平移

| 功能 | 实现方式 |
| ---- | -------- |
| 缩放范围 | 0.5x - 2.0x |
| 缩放步长 | 0.1x |
| 平移 | 鼠标拖拽或滚动条 |
| 适应窗口 | 双击背景自动缩放适应 |

### 3.6 Layered 布局算法

#### 3.6.1 算法步骤

```text
1. 层级分配 (Layer Assignment)
   - 所有 entry_level 员工分配到 Layer 0
   - 根据升级关系，将目标员工分配到源员工层级 + 1

2. 节点排序 (Node Ordering)
   - 在每层内，根据连接关系排序节点
   - 目标：最小化连接线交叉

3. 坐标计算 (Coordinate Assignment)
   - X坐标：layer_index * layer_spacing
   - Y坐标：在层内均匀分布，考虑连接关系

4. 边路由 (Edge Routing)
   - 计算贝塞尔曲线控制点
   - 避免与节点重叠
```

#### 3.6.2 伪代码

```gdscript
func layout_employee_tree(employees: Array, upgrades: Dictionary) -> void:
    # 1. 分配层级
    var layers = _assign_layers(employees, upgrades)

    # 2. 每层内排序
    for layer in layers:
        _order_nodes_in_layer(layer, upgrades)

    # 3. 计算坐标
    for layer_idx in range(layers.size()):
        var layer = layers[layer_idx]
        var x = layer_idx * LAYER_SPACING
        var total_height = layer.size() * (NODE_HEIGHT + NODE_SPACING)
        var start_y = -total_height / 2

        for node_idx in range(layer.size()):
            var node = layer[node_idx]
            node.position = Vector2(x, start_y + node_idx * (NODE_HEIGHT + NODE_SPACING))

    # 4. 绘制连接线
    _draw_upgrade_connections(upgrades)
```

### 3.7 实现要点

#### 3.7.1 数据结构

```gdscript
# 员工升级关系
var upgrade_paths: Dictionary = {
    "trainee": ["cook"],
    "cook": ["chef", "executive_chef"],
    "errand_boy": ["cart_operator"],
    "recruiting_girl": ["hr", "trainer"],
    # ...
}
```

#### 3.7.2 组件结构

```text
ui/components/employee_tree/
├── employee_tree.gd           # 主控制脚本
├── employee_tree.tscn         # 场景文件
├── employee_tree_node.gd      # 节点组件（使用缩略卡片）
├── employee_tree_edge.gd      # 连接线组件
└── employee_tree_layout.gd    # 布局算法
```

---

## 4. 地图元素设计

### 4.1 房屋与花园渲染

参考 `house_demo.png` 和 `hose_with_garden_demo.png`，使用新的SVG资源替换现有占位图片。

#### 4.1.1 尺寸定义（来自 modules/base_pieces/content/pieces/）

根据项目现有实现（模块定义 + 放置/加花园规则），各元素占地如下：

| 类型 | 形态/方向 | 实际占地 | 说明 |
| ---- | -------- | -------- | ---- |
| 房屋 (house) | - | **2 x 2** | 基础住宅 |
| 花园扩展 | N/S | **2 x 1** | 贴在房屋上方/下方（两格） |
| 花园扩展 | E/W | **1 x 2** | 贴在房屋左侧/右侧（两格） |
| 带花园房屋 (house_with_garden) | N/S | **2 x 3** | 房屋(2x2) + 花园(2x1) |
| 带花园房屋 (house_with_garden) | E/W | **3 x 2** | 房屋(2x2) + 花园(1x2) |

说明：

- 允许按方向贴（N/E/S/W），默认方向为下方（S）。
- 数据层：`house_with_garden` 在模块定义中为 `3x2` 的矩形 footprint（`[[1,1,1],[1,1,1]]`），并允许 `rotation`（0/90/180/270）表达 `3x2` / `2x3` 两种外形；因此无需在模块 JSON 中把 footprint 固定改成 `2x3`。

**重要：所有尺寸应根据游戏实际格子大小动态计算，不应写死像素值。**

#### 4.1.2 房屋 (宽2 x 高2) 设计图

房屋图片作为背景填满整个 2x2 区域，序号和需求图标覆盖在上面。

```text
┌─────────────────────────────────────────────────────────────────┐
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░┌──┐░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░│12│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  ← 序号覆盖在背景上
│ ░░└──┘░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░🍔░░░░░░░░🍕░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░🍺░░░░░░░░🥤░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  ← 需求图标覆盖在背景上
│ ░░░░░░░░░🍋░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │    可以散落在任意位置
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░░░╱╲░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░░╱░░╲░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░╱────╲░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  ← 房屋图片作为背景
│ ░░░░░░░░░░░░░░░░░░░░│░░░░│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │    填满整个 2x2 区域
│ ░░░░░░░░░░░░░░░░░░░░│░▢▢░│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░└────┘░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
├─────────────────────────────────┬───────────────────────────────┤
│            格子 1               │            格子 2             │
├─────────────────────────────────┼───────────────────────────────┤
│            格子 3               │            格子 4             │
└─────────────────────────────────┴───────────────────────────────┘

整体占地：2x2 格子
渲染层级（从下到上）：
  1. 紫色底色
  2. 房屋图片（背景，填满宽度，底部留边距）
  3. 房屋序号（左上角）
  4. 需求图标（散落）
```

#### 4.1.3 花园 (宽2 x 高1) 设计图

花园图片作为背景填满整个 宽2 x 高1 区域，位于房屋下方。

```text
┌─────────────────────────────────────────────────────────────────┐
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░░░░░ │
│ ░░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░│░░░░░ │  ← 围栏
│ ░░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░🌳░░░░░░🌸░░░░░░🌳░░░░░░🌸░░░░░░🌳░░░░░░🌸░░░░░░░░░░░░░░ │  ← 花园图片作为背景
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │    填满整个 宽2x高1 区域
│ ░░░░░🌸░░░░░░🌳░░░░░░🌸░░░░░░🌳░░░░░░🌸░░░░░░🌳░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
├─────────────────────────────────┬───────────────────────────────┤
│           格子 1                │           格子 2              │
└─────────────────────────────────┴───────────────────────────────┘

整体占地：宽2 x 高1 格子
位置：在房屋下方
底色：绿色 (#22C55E 或类似)
花园图片作为背景填满整个区域
```

#### 4.1.4 带花园房屋 (宽2 x 高3) 设计图

房屋在上（宽2 x 高2），花园在下（宽2 x 高1）。序号和需求图标覆盖在整个区域上。

```text
┌─────────────────────────────────────────────────────────────────┐
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░┌──┐░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░│ 5│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  ← 序号在整个 宽2x高3 左上角
│ ░░└──┘░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░🍔░░░░░░░░🍕░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░🍺░░░░░░░░🥤░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  ← 需求图标可散落在整个区域
│ ░░░░░░░░░🍋░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░░░╱╲░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░░╱░░╲░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  ← 房屋背景 (宽2 x 高2)
│ ░░░░░░░░░░░░░░░░░░░░╱────╲░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░│░░░░│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░│░▢▢░│░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░└────┘░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
├─────────────────────────────────┬───────────────────────────────┤
│            格子 1               │            格子 2             │  ← 房屋上半部分
├─────────────────────────────────┼───────────────────────────────┤
│            格子 3               │            格子 4             │  ← 房屋下半部分
├─────────────────────────────────┼───────────────────────────────┤
│ ░░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░░│░░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░┌─┐░ │
│ ░░│░│░│░│░│░│░│░│░│░│░│░│░│░│░░│░░│░│░│░│░│░│░│░│░│░│░│░│░│░│░ │  ← 花园背景 (宽2 x 高1)
│ ░░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░░│░░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░└─┘░ │
│ ░░░░░🌳░░░░░░🌸░░░░░░🌳░░░░░░░│░░░░░🌸░░░░░░🌳░░░░░░🌸░░░░░░░ │
│ ░░░░░🌸░░░░░░🌳░░░░░░🌸░░░░░░░│░░░░░🌳░░░░░░🌸░░░░░░🌳░░░░░░░ │
├─────────────────────────────────┼───────────────────────────────┤
│            格子 5               │            格子 6             │  ← 花园
└─────────────────────────────────┴───────────────────────────────┘

整体占地：宽2 x 高3 格子
组成：
  - 上部：房屋背景 (宽2 x 高2) - 格子 1,2,3,4 - 紫色底色
  - 下部：花园背景 (宽2 x 高1) - 格子 5,6 - 绿色底色
渲染层级（从下到上）：
  1. 底色（房屋区域紫色，花园区域绿色）
  2. 房屋图片（上部 宽2x高2 区域背景）
  3. 花园图片（下部 宽2x高1 区域背景）
  4. 房屋序号（整个 宽2x高3 左上角）
  5. 需求图标（可散落在整个 宽2x高3 区域）
```

#### 4.1.5 渲染层级说明

所有元素按以下顺序从下到上渲染：

| 层级 | 元素 | 说明 |
| ---- | ---- | ---- |
| 1 | 底色 | 房屋区域紫色，花园区域绿色 |
| 2 | 房屋/花园图片 | 作为背景，填满各自区域 |
| 3 | 房屋序号 | 覆盖在背景上，左上角 |
| 4 | 需求图标 | 覆盖在背景上，散落分布 |

#### 4.1.6 渲染规格

| 属性 | 值 | 说明 |
| ---- | -- | ---- |
| 格子大小 | 动态 | 根据游戏实际 cell_size 计算 |
| 房屋底色 | 紫色 (#8B5CF6 或类似) | 覆盖房屋占地区域 |
| 花园底色 | 绿色 (#22C55E 或类似) | 覆盖花园占地区域 |
| 房屋图片宽度 | 100% 占地宽度 | 填满宽度 |
| 房屋图片底部边距 | 约 5-10% 占地高度 | 底部留出小段距离 |
| 序号位置 | 整个占地区域左上角 | 距边缘 2-4px |
| 渲染层级 | 5 | 在道路之上，营销之下 |

#### 4.1.7 房屋序号设计

| 属性 | 值 |
| ---- | -- |
| 位置 | 整个占地区域的左上角 |
| 字体大小 | 相对于格子大小的 25% |
| 背景 | 半透明白色圆角矩形 (rgba(255,255,255,0.8)) |
| 文字颜色 | 黑色 |
| 内边距 | 2px |

#### 4.1.8 需求图标散落显示

模拟真实桌游中食物/饮料token散落在房屋上的效果。

**重要：需求图标和序号都可以覆盖在房屋/花园图片上，房屋/花园图片作为背景。**

**散落规则：**

- 图标可以散落在整个占地区域的任意位置
- 图标可以覆盖在房屋/花园图片上
- 图标之间保持最小间距（相对于格子大小）
- 最多显示 6 个需求图标
- 图标大小相对于格子大小动态计算

**散落算法：**

```gdscript
func _calculate_demand_positions(demands: Array, piece_rect: Rect2, cell_size: float) -> Array[Vector2]:
    var positions: Array[Vector2] = []
    var icon_size = cell_size * 0.3  # 图标大小相对于格子
    var min_spacing = cell_size * 0.1  # 最小间距

    # 可用区域：整个占地区域
    var available_rect = piece_rect

    for demand in demands:
        var pos = _find_valid_position(positions, available_rect, icon_size, min_spacing)
        if pos != Vector2.INF:
            positions.append(pos)

    return positions
```

#### 4.1.9 需要替换的资源文件

**新资源来源路径：**

- 房屋和花园：`/Users/qinkai/Downloads/Organiser and Accessories - Food Chain Magnate - Mk III/Assets/Houses/`
  - `House.svg` - 房屋图片
  - `Gate and Fence.svg` - 围栏和花园

以下是 `modules/base_pieces/assets/map/pieces/` 中需要替换的占位资源：

| 当前文件 | 新资源来源 | 说明 |
| -------- | ---------- | ---- |
| `house.png` | `Houses/House.svg` 转换 | 宽2x高2 房屋图片 |
| `house_with_garden.png` | `Houses/House.svg` + `Houses/Gate and Fence.svg` 组合 | 宽2x高3 带花园房屋 |
| `garden_large.png` | `Houses/Gate and Fence.svg` 转换 | 宽2x高1 花园图片 |

**转换要求：**

- 输出格式：PNG-24 with alpha
- 房屋图片：宽高比适配 宽2x高2 格子（宽:高 = 1:1）
- 花园图片：宽高比适配 宽2x高1 格子（宽:高 = 2:1）
- 带花园房屋：宽高比适配 宽2x高3 格子（宽:高 = 2:3）

**⚠️ 需要修改的定义文件：**

`modules/base_pieces/content/pieces/house_with_garden.json`:

```json
// 当前（错误）：
"footprint_mask": [[1, 1, 1], [1, 1, 1]]  // 宽3 x 高2

// 需要修改为：
"footprint_mask": [[1, 1], [1, 1], [1, 1]]  // 宽2 x 高3
```

### 4.2 食物/饮料图标

**新资源来源路径：**

`/Users/qinkai/Downloads/Organiser and Accessories - Food Chain Magnate - Mk III/Assets/Food & Drinks/`

#### 4.2.1 图标用途

| 场景 | 图标尺寸 | 用途 |
| ---- | -------- | ---- |
| 地图需求显示 | 16x16 | 房屋上方的需求图标 |
| 库存面板 | 24x24 | 库存数量显示 |
| 生产面板 | 32x32 | 生产选项显示 |
| 详情弹窗 | 64x64 | 大图展示 |

#### 4.2.2 图标映射

| 产品ID | 源文件路径 | 颜色主题 |
| ------ | ---------- | -------- |
| burger | `Food & Drinks/Burger - Icon.svg` | #8A5E27 |
| pizza | `Food & Drinks/Pizza - Icon.svg` | #E67E22 |
| beer | `Food & Drinks/Beer - Icon.svg` | #F1C40F |
| lemonade | `Food & Drinks/Lemonade - Icon.svg` | #2ECC71 |
| soda | `Food & Drinks/Softdrink - Icon.svg` | #E74C3C |

**大图资源（用于详情展示）：**

| 产品ID | 源文件路径 |
| ------ | ---------- |
| burger | `Food & Drinks/Burger.svg` |
| pizza | `Food & Drinks/Pizza.svg` |
| soda | `Food & Drinks/Softdrink.svg` |

### 4.3 餐厅Logo

**新资源来源路径：**

`/Users/qinkai/Downloads/Organiser and Accessories - Food Chain Magnate - Mk III/Assets/Restaurant Logos/`

#### 4.3.1 分配规则（与仓库实现一致）

- 进入游戏前：为每个玩家随机分配一个 Logo（使用 `state.seed` 派生的独立 RNG，保证回放/联机确定性）。
- 绑定方式：写入 `GameState.players[i].restaurant_logo_id`，并按 `player_id` 固定（同一玩家的所有餐厅共用同一 Logo）。

#### 4.3.2 Logo 资源编号（logo_id → 贴图）

| logo_id | VisualCatalog `piece_visuals` key | 贴图（项目内） |
| ------ | --------------------------------- | -------------- |
| 0 | `restaurant_logo_fried_geese_donkey` | `res://modules/base_pieces/assets/map/logos/fried_geese_donkey.png` |
| 1 | `restaurant_logo_gluttony_inc_burgers` | `res://modules/base_pieces/assets/map/logos/gluttony_inc_burgers.png` |
| 2 | `restaurant_logo_golden_duck_diner` | `res://modules/base_pieces/assets/map/logos/golden_duck_diner.png` |
| 3 | `restaurant_logo_santa_maria_pizza` | `res://modules/base_pieces/assets/map/logos/santa_maria_pizza.png` |
| 4 | `restaurant_logo_xango_blues_bar` | `res://modules/base_pieces/assets/map/logos/xango_blues_bar.png` |

#### 4.3.3 Logo显示位置

| 场景 | 尺寸 | 位置 |
| ---- | ---- | ---- |
| 地图上 | `cell_size * 0.8` | 餐厅占地区域中心 |
| 玩家面板 | 48x48 | 玩家信息区（TODO） |
| 餐厅详情 | 128x128 | 详情弹窗顶部（TODO） |

### 4.4 营销元素

**新资源来源路径：**

`/Users/qinkai/Downloads/Organiser and Accessories - Food Chain Magnate - Mk III/Assets/Marketing/`

#### 4.4.1 营销类型

| 类型 | 源文件路径 | 范围 | 描述 |
| ---- | ---------- | ---- | ---- |
| 广告牌 | `Marketing/Billboard.svg` | 2格 | 路边广告 |
| 邮箱 | `Marketing/Mail Box.svg` | 3格 | 邮件广告 |
| 电台 | `Marketing/Radio - Icon.svg` | 5格 | 电台广告 |
| 飞机 | `Marketing/Aeroplane.svg` | 全图 | 飞机横幅 |

#### 4.4.2 营销显示效果

**广告牌渲染：**

- 位置：道路旁边的格子
- 朝向：面向道路
- 附加：显示广告的产品图标

**范围指示器：**

- 颜色：半透明蓝色 (rgba(74,144,217,0.3))
- 边框：虚线
- 动画：轻微脉冲

### 4.5 Visual Catalog 更新

需要更新模块的视觉目录配置：

#### 4.5.1 base_pieces 模块

```json
{
  "schema_version": 1,
  "piece_visuals": {
    "house": {
      "texture": "res://modules/base_pieces/assets/map/pieces/house.png",
      "offset_px": [0, 0],
      "scale": [1, 1]
    },
    "house_with_garden": {
      "texture": "res://modules/base_pieces/assets/map/pieces/house_with_garden.png",
      "offset_px": [0, 0],
      "scale": [1, 1]
    }
  }
}
```

#### 4.5.2 base_products 模块

```json
{
  "schema_version": 1,
  "product_icons": {
    "burger": { "texture": "res://modules/base_products/assets/map/icons/burger.png" },
    "pizza": { "texture": "res://modules/base_products/assets/map/icons/pizza.png" }
  }
}
```

> 备注：当前 VisualCatalog schema_version=1 仅要求 `texture` 字段（其余字段不会被加载）；不同场景尺寸由 UI 绘制时缩放。若后续需要 `icon_small` 等多尺寸字段，需要升级 schema 并扩展加载器。

---

## 5. 开发计划

### 5.1 阶段一：资源准备

#### 5.1.1 SVG转PNG批量处理

**任务清单：**

1. 创建资源转换脚本 `tools/convert_assets.sh`
2. 转换所有SVG文件为多分辨率PNG
3. 组织资源文件到项目目录结构

**目录结构：**

```text
modules/
├── base_pieces/
│   └── assets/
│       └── map/
│           └── pieces/
│               ├── house.png
│               ├── house@2x.png
│               ├── house_with_garden.png
│               ├── house_with_garden@2x.png
│               └── fence.png
├── base_products/
│   └── assets/
│       └── map/
│           └── icons/
│               ├── burger.png
│               ├── burger_16.png
│               ├── pizza.png
│               ├── pizza_16.png
│               ├── beer.png
│               ├── lemonade.png
│               └── soda.png
├── base_marketing/
│   └── assets/
│       └── map/
│           └── icons/
│               ├── billboard.png
│               ├── mailbox.png
│               ├── radio.png
│               └── airplane.png
└── base_restaurants/
    └── assets/
        └── logos/
            ├── gluttony_inc.png
            ├── santa_maria.png
            ├── xango_blues.png
            ├── golden_duck.png
            └── fried_geese.png
```

#### 5.1.2 资源导入配置

为每个PNG资源创建 `.import` 配置：

```ini
[remap]
importer="texture"
type="CompressedTexture2D"

[deps]
source_file="res://modules/base_pieces/assets/map/pieces/house.png"

[params]
compress/mode=0
mipmaps/generate=true
```

### 5.2 阶段二：员工卡片升级

#### 5.2.1 任务分解

| 步骤 | 任务 | 文件 |
| ---- | ---- | ---- |
| 1 | 创建角色图标资源 | `ui/components/employee_card/assets/icons/` |
| 2 | 重构场景结构 | `employee_card.tscn` |
| 3 | 更新脚本逻辑 | `employee_card.gd` |
| 4 | 添加动画效果 | `employee_card.gd` |
| 5 | 测试拖拽功能 | 手动测试 |

#### 5.2.2 代码修改清单

**employee_card.gd 修改：**

```gdscript
# 新增常量
const CARD_SIZE = Vector2(150, 120)
const ICON_SIZE = Vector2(32, 32)

# 新增变量
var _role_icon: TextureRect
var _hover_tween: Tween

# 修改 _build_ui() 方法
func _build_ui() -> void:
    # 使用新的布局结构
    pass

# 新增方法
func _load_role_icon(role: String) -> Texture2D:
    var path = "res://ui/components/employee_card/assets/icons/%s.png" % role
    return load(path) if ResourceLoader.exists(path) else null
```

### 5.3 阶段三：公司结构树升级

#### 5.3.1 任务分解

| 步骤 | 任务 | 文件 |
| ---- | ---- | ---- |
| 1 | 实现连接线绘制 | `company_structure.gd` |
| 2 | 优化布局算法 | `company_structure.gd` |
| 3 | 增强拖拽反馈 | `company_structure.gd` |
| 4 | 添加缩放功能 | `company_structure.gd` |
| 5 | 测试层级显示 | 手动测试 |

#### 5.3.2 新增类

```gdscript
# 连接线绘制器
class ConnectionLineDrawer:
    var _canvas: CanvasItem
    var _line_color: Color = Color("#666666")
    var _line_width: float = 2.0

    func draw_connection(from: Vector2, to: Vector2) -> void:
        # 绘制贝塞尔曲线连接
        pass
```

### 5.4 阶段四：地图渲染升级

#### 5.4.1 任务分解

| 步骤 | 任务 | 文件 |
| ---- | ---- | ---- |
| 1 | 更新Visual Catalog配置 | `modules/*/content/visuals/*.json` |
| 2 | 替换房屋纹理 | `map_skin.gd` |
| 3 | 替换产品图标 | `map_skin.gd` |
| 4 | 替换营销图标 | `map_skin.gd` |
| 5 | 添加餐厅Logo支持 | `map_canvas_drawer.gd` |
| 6 | 测试地图渲染 | 手动测试 |

#### 5.4.2 MapSkin 修改

MapSkin 在本仓库中不新增专用 API；Logo 作为 `piece_visuals` 贴图随 VisualCatalog 加载并在地图绘制时叠加：

- 资源配置：在 `modules/base_pieces/content/visuals/pieces.json` 增加 `restaurant_logo_*` 条目（对应 `res://modules/base_pieces/assets/map/logos/*.png`）。
- 绑定方式：新游戏初始化写入 `GameState.players[*].restaurant_logo_id`，并按 `player_id` 固定。
- 渲染方式：地图绘制 `restaurant` 时按 `owner(player_id)` 叠加对应 Logo。

### 5.5 阶段五：集成测试

#### 5.5.1 测试清单

| 测试项 | 验证内容 |
| ------ | -------- |
| 员工卡片显示 | 图标、颜色、文字正确显示 |
| 员工卡片交互 | 悬停、选中、拖拽效果正常 |
| 公司结构树 | 层级显示、连接线、拖拽放置 |
| 地图房屋 | 新纹理正确渲染 |
| 地图产品图标 | 需求显示正确 |
| 地图营销 | 广告牌等元素正确显示 |
| 餐厅Logo | 各餐厅Logo正确显示 |
| 性能测试 | 无明显卡顿 |

#### 5.5.2 回归测试

确保以下功能不受影响：

- 游戏存档/读档
- 回放功能
- 多人游戏同步
- 所有现有UI交互

---

## 6. 技术注意事项

### 6.1 SVG处理

Godot 4.x 对SVG的支持有限，建议：

1. 使用Inkscape批量转换为PNG
2. 保留原始SVG作为源文件
3. 生成多分辨率版本 (1x, 2x)

### 6.2 性能优化

1. **纹理图集**：将小图标合并为图集减少draw call
2. **延迟加载**：大型纹理按需加载
3. **缓存**：缓存常用纹理引用

### 6.3 兼容性

1. 保持现有API不变
2. 使用feature flag控制新旧UI切换
3. 提供降级方案

---

## 7. 附录

### 7.1 资源转换脚本

```bash
#!/bin/bash
# tools/convert_assets.sh

INKSCAPE="$(command -v inkscape || true)"
if [ -z "$INKSCAPE" ] && [ -x "/Applications/Inkscape.app/Contents/MacOS/inkscape" ]; then
  INKSCAPE="/Applications/Inkscape.app/Contents/MacOS/inkscape"
fi
SRC_DIR="/Users/qinkai/Downloads/Organiser and Accessories - Food Chain Magnate - Mk III/Assets"
DST_DIR="./modules"

# 依赖检查
if [ -z "$INKSCAPE" ]; then
  echo "ERROR: inkscape not found on PATH"
  exit 1
fi

# 转换房屋
$INKSCAPE "$SRC_DIR/Houses/House.svg" \
    --export-type=png \
    --export-filename="$DST_DIR/base_pieces/assets/map/pieces/house.png" \
    --export-width=100

# 转换食物图标
for icon in "Burger" "Pizza" "Beer" "Lemonade" "Softdrink"; do
    $INKSCAPE "$SRC_DIR/Food & Drinks/$icon - Icon.svg" \
        --export-type=png \
        --export-filename="$DST_DIR/base_products/assets/map/icons/${icon,,}.png" \
        --export-width=32
done

# 转换餐厅Logo
# ...
```

### 7.2 颜色参考表

| 名称 | HEX | RGB | 用途 |
| ---- | --- | --- | ---- |
| Primary Blue | #4A90D9 | 74,144,217 | 选中、高亮 |
| Manager | #4A90D9 | 74,144,217 | 经理角色 |
| Recruit | #7B68EE | 123,104,238 | 招聘角色 |
| Food | #E67E22 | 230,126,34 | 食物生产 |
| Drink | #27AE60 | 39,174,96 | 饮料采购 |
| Price | #F1C40F | 241,196,15 | 定价角色 |
| Marketing | #E74C3C | 231,76,60 | 营销角色 |
| Shop | #9B59B6 | 155,89,182 | 开店角色 |
| Special | #1ABC9C | 26,188,156 | 特殊角色 |
