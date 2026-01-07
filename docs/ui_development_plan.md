# 快餐连锁大亨 UI开发计划

本文档基于游戏规则 (`docs/rules.md`) 和现有代码库分析，详细列出当前UI的实现状态、缺失组件及开发计划。

---

## 一、现有UI实现状态审计

### 1.1 主菜单 (`ui/scenes/main_menu.tscn`)

| 功能项 | 实现状态 | 代码位置 | 问题描述 |
|--------|----------|----------|----------|
| 新游戏按钮 | ✅ 完成 | `ui/scenes/menus/main_menu.gd:10` | - |
| 载入游戏按钮 | ❌ 未实现 | `ui/scenes/menus/main_menu.gd:14-17` | 按钮存在但点击只输出警告 |
| 设置按钮 | ❌ 未实现 | `ui/scenes/menus/main_menu.gd:19-22` | 按钮存在但点击只输出警告 |
| 板块编辑器按钮 | ✅ 完成 | `ui/scenes/menus/main_menu.gd:24-26` | - |
| 回放测试按钮 | ✅ 完成 | `ui/scenes/menus/main_menu.gd:28-30` | - |
| 退出按钮 | ✅ 完成 | `ui/scenes/menus/main_menu.gd:32-34` | - |
| 版本号显示 | ✅ 完成 | `ui/scenes/menus/main_menu.gd:8` | 从Globals读取 |

**完成度**: 5/7 = **71%**

**缺失清单**:
- [ ] 载入游戏功能界面
- [ ] 设置菜单界面

---

### 1.2 游戏设置 (`ui/scenes/setup/game_setup.tscn`)

| 功能项 | 实现状态 | 代码位置 | 问题描述 |
|--------|----------|----------|----------|
| 玩家数量选择 | ✅ 完成 | `game_setup.gd:4` | SpinBox 2-5人 |
| 随机种子输入 | ✅ 完成 | `game_setup.gd:5` | 支持自动生成 |
| 返回按钮 | ✅ 完成 | `game_setup.gd:14-16` | - |
| 开始游戏按钮 | ✅ 完成 | `game_setup.gd:18-36` | - |
| 模块选择 | ❌ 未实现 | - | 规则支持24个模块但无UI选择 |
| 玩家名称/颜色设置 | ❌ 未实现 | - | Globals目前只有占位方法（`autoload/globals.gd:79`），无可配置字段/持久化 |
| 银行储备卡选择 | ❌ 未实现 | - | 规则要求玩家秘密选择；当前 `reserve_card_selected` 固定为 GameConfig 默认（`core/state/game_state_factory.gd:141`） |
| 初始餐厅放置顺序说明 | ❌ 未实现 | - | 规则要求逆序放置；当前 turn_order 为随机洗牌结果（`core/state/game_state_factory.gd:65`），Setup 阶段未实现逆序引导 |

**完成度**: 4/8 = **50%**

**缺失清单**:
- [ ] 模块选择界面（启用/禁用24个扩展模块）
- [ ] 玩家配置界面（名称、颜色选择）
- [ ] 银行储备卡选择界面
- [ ] 初始餐厅放置顺序说明

---

### 1.3 主游戏场景 (`ui/scenes/game/game.tscn`)

#### 1.3.1 顶栏 (TopBar)

| 功能项 | 实现状态 | 代码位置 | 问题描述 |
|--------|----------|----------|----------|
| 回合显示 | ✅ 完成 | `game.gd:45` | "回合: N" |
| 阶段显示 | ✅ 完成 | `game.gd:46-49` | "阶段: Phase / SubPhase" |
| 银行资金显示 | ✅ 完成 | `game.gd:51` | "银行: $N" |
| 当前玩家显示 | ⚠️ 基础 | `game.gd:50` | 只显示编号，无玩家详情 |
| 推进阶段按钮 | ✅ 完成 | `game.gd:142-143` | - |
| 推进子阶段按钮 | ✅ 完成 | `game.gd:145-146` | - |
| 跳过按钮 | ✅ 完成 | `game.gd:148-152` | - |
| 调试按钮 | ✅ 完成 | `game.gd:98-101` | - |
| 菜单按钮 | ✅ 完成 | `game.gd:67-69` | - |

**TopBar完成度**: 8/9 = **89%**

#### 1.3.2 游戏区域 (GameArea)

| 功能项 | 实现状态 | 代码位置 | 问题描述 |
|--------|----------|----------|----------|
| 地图滚动容器 | ✅ 完成 | `map_view.gd` | ScrollContainer |
| 地图画布绘制 | ✅ 完成 | `map_canvas.gd` | 621行，7层绘制步骤（含房屋需求层） |
| 地形渲染 | ✅ 完成 | `map_canvas.gd:293-304` | 地面+阻挡 |
| 道路渲染 | ✅ 完成 | `map_canvas.gd:306-351` | 支持形状/桥梁 |
| 饮料点渲染 | ✅ 完成 | `map_canvas.gd:414-433` | - |
| 建筑渲染 | ✅ 完成 | `map_canvas.gd:435-455` | 房屋/餐厅 |
| 营销广告牌渲染 | ✅ 完成 | `map_canvas.gd:457-483` | 含产品标记 |
| 房屋需求显示 | ✅ 完成 | `map_canvas.gd:485-540` | 图标网格 |
| 单元格悬停效果 | ✅ 完成 | `map_canvas.gd:542-550` | - |
| 单元格选中效果 | ✅ 完成 | `map_canvas.gd:542-550` | - |
| 单元格工具提示 | ✅ 完成 | `map_canvas.gd:552-608` | 详细信息 |
| 玩家信息面板 | ✅ 已实现 | `ui/components/player_panel/` | 2026-01-05 完成基础版本 |
| 员工手牌区 | ✅ 已实现 | `ui/components/hand_area/` | 2026-01-05 完成基础版本 |
| 公司结构面板 | ✅ 已实现 | `ui/components/company_structure/` | 2026-01-05 完成基础版本 |
| 库存面板 | ✅ 已实现 | `ui/components/inventory_panel/` | 2026-01-05 完成基础版本 |
| 动作面板 | ✅ 已实现 | `ui/components/action_panel/` | 2026-01-05 完成基础版本 |
| 里程碑面板 | ❌ 未实现 | - | 完全缺失 |
| 游戏日志 | ❌ 未实现 | - | 完全缺失 |
| 顺序轨 | ✅ 已实现 | `ui/components/turn_order/` | 2026-01-05 完成基础版本 |

**GameArea完成度**: 17/19 = **89%**

#### 1.3.3 底栏 (BottomBar)

| 功能项 | 实现状态 | 代码位置 | 问题描述 |
|--------|----------|----------|----------|
| 状态哈希显示 | ✅ 完成 | `game.gd:54-55` | 调试用 |
| 命令计数显示 | ✅ 完成 | `game.gd:58` | 调试用 |

**BottomBar完成度**: 2/2 = **100%**

#### 1.3.4 对话框

| 功能项 | 实现状态 | 代码位置 | 问题描述 |
|--------|----------|----------|----------|
| 菜单对话框 | ✅ 完成 | `game.tscn:129-158` | 继续/保存/退出 |
| 调试对话框 | ✅ 完成 | `game.tscn:159-180` | 状态摘要查看（bank/marketing_instances/round_state 等），非完整 JSON |
| 保存游戏功能 | ✅ 完成 | `game.gd:78-91` | 保存到user://savegame.json |
| 招聘对话框 | ❌ 未实现 | - | 完全缺失 |
| 培训对话框 | ❌ 未实现 | - | 完全缺失 |
| 营销对话框 | ❌ 未实现 | - | 完全缺失 |
| 发薪日对话框 | ❌ 未实现 | - | 完全缺失 |
| 游戏结束对话框 | ❌ 未实现 | - | 完全缺失 |

**对话框完成度**: 3/8 = **38%**

---

### 1.4 主游戏场景总体评估

**已实现功能数**: 30
**总功能数**: 38
**完成度**: 30/38 = **79%**

**关键缺失（阻塞正常游戏流程）**:
1. ~~玩家信息面板~~ ✅ 已实现
2. ~~员工手牌区~~ ✅ 已实现
3. ~~公司结构面板~~ ✅ 已实现
4. ~~动作面板~~ ✅ 已实现
5. 游戏结束界面 - 无法正常结束游戏

---

### 1.5 地图画布 (`ui/scenes/game/map_canvas.gd`)

| 功能项 | 实现状态 | 代码位置 | 问题描述 |
|--------|----------|----------|----------|
| 分层渲染架构 | ✅ 完成 | `_draw()` | 7个绘制步骤（含房屋需求层） |
| 动态皮肤加载 | ✅ 完成 | `_ensure_skin()` | 支持模块化纹理 |
| 占位符降级 | ✅ 完成 | `MapSkin` | 缺失资源不崩溃 |
| 外部单元格支持 | ✅ 完成 | `_external_cells_by_pos` | 扩展地图边界 |
| 鼠标交互 | ✅ 完成 | `_gui_input()` | 悬停+点击 |
| 建筑放置预览 | ❌ 未实现 | - | 需要放置时高亮有效位置 |
| 营销范围预览 | ❌ 未实现 | - | 需要显示影响区域 |
| 采购路线绘制 | ❌ 未实现 | - | 需要显示采购员路径 |
| 距离计算可视化 | ❌ 未实现 | - | 需要显示到餐厅的距离 |
| 缩放功能 | ❌ 未实现 | - | 大地图需要缩放 |

**完成度**: 5/10 = **50%**

---

### 1.6 板块编辑器 (`ui/scenes/tools/tile_editor.tscn`)

| 功能项 | 实现状态 | 代码位置 | 问题描述 |
|--------|----------|----------|----------|
| 板块加载 | ✅ 完成 | `tile_editor.gd:62-68` | - |
| 板块创建 | ✅ 完成 | `tile_editor.gd:70-78` | - |
| 板块保存 | ✅ 完成 | `tile_editor.gd:80-130` | 支持user://备用 |
| 板块验证 | ✅ 完成 | `tile_editor.gd:132-140` | - |
| 网格编辑 | ✅ 完成 | `tile_editor.gd:224-236` | 6x6按钮 |
| 阻挡设置 | ✅ 完成 | `tile_editor.gd:142-146` | - |
| 道路编辑 | ✅ 完成 | `tile_editor.gd:148-173` | 方向+桥梁 |
| 饮料点编辑 | ✅ 完成 | `tile_editor.gd:175-190` | - |
| 建筑放置编辑 | ✅ 完成 | `tile_editor.gd:192-222` | - |

**完成度**: 9/9 = **100%**

---

## 二、按游戏规则阶段分析缺失UI

### 2.0 阶段零：设置阶段 (Setup)

说明：引擎将 `Setup` 作为“开局落子”阶段（不属于规则的 7 个循环阶段）。当前实现中，`place_restaurant` 动作允许在 `Setup` 执行，但 UI 尚无入口（仅有调试用推进按钮）。

**现状（基于代码）**:
- 玩家行动顺序使用初始化后的 `state.turn_order`（`core/state/game_state_factory.gd:65`），由 `state.get_current_player_id()` 决定当前操作者（`gameplay/actions/place_restaurant_action.gd:36`）。
- `place_restaurant`（初始放置）限制每位玩家仅能放 1 个餐厅（`gameplay/actions/place_restaurant_action.gd:68-73`）。
- 若需对齐规则中的“逆序放置”/说明文本，可能需要在 `Setup` 阶段引擎侧显式支持或在进入 `Setup` 时调整 turn_order（当前未实现）。

**必需 UI/交互（最小可玩）**:
- 基础动作入口：`action_panel`（至少能触发 `place_restaurant`）
- 地图交互：`restaurant_placement_overlay` + `rotation_select`（可复用后续 PlaceRestaurants 子阶段）

### 2.1 阶段一：重组公司 (Restructuring)

**规则摘要** (rules.md 145-151行):
> 1. 所有玩家同时秘密地将自己手中的员工卡分为两堆：本回合"在岗"和"待命"
> 2. CEO卡总是"在岗"
> 3. 所有玩家同时展示"在岗"的员工卡，并按照公司结构规则排列在CEO下方
> 4. 如果放置的员工数量超出公司结构可容纳的上限，除了CEO外的所有员工都将变为"待命"状态

**数据来源** (`GameState.players[]`):
```gdscript
{
    "employees": [],           # 所有员工ID列表
    "reserve_employees": [],   # 待命区员工
    "busy_marketers": [],      # 忙碌营销员
    "company_structure": {     # 公司结构
        "ceo_slots": 3,        # CEO卡槽数
        "structure": []        # 当前结构（当前未用于规则计算）
    }
}
```

**现状差异（基于代码）**:
- 当前引擎在进入 `Restructuring` 时会自动将 `reserve_employees` 合并到 `employees`，并仅做“公司容量约束”（`modules/base_rules/rules/entry.gd:142`，`core/engine/phase_manager/working_flow.gd:23`）；未实现“秘密分堆/拖拽排布/确认提交”的交互与对应动作。
- 因此若要按规则实现重组 UI，需要同时补齐：状态结构（如何表达层级汇报关系）+ 对应的 gameplay action（提交/校验/回滚）。

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `hand_area` | 员工手牌区 | 显示玩家所有员工卡，支持拖拽 | `players[].employees` | P0 |
| `company_structure_panel` | 公司结构面板 | 金字塔式卡槽布局，CEO固定顶部 | `players[].company_structure` | P0 |
| `employee_card` | 员工卡牌组件 | 单张卡牌显示：名称、薪水、能力、培训路径 | `EmployeeDef` | P0 |
| `slot_indicator` | 卡槽指示器 | 显示CEO/经理剩余卡槽数 | `company_structure.ceo_slots` | P1 |
| `busy_marker` | 忙碌标记 | 显示忙碌营销员状态 | `players[].busy_marketers` | P1 |
| `restructure_confirm_btn` | 确认重组按钮 | 提交公司结构 | - | P0 |

---

### 2.2 阶段二：决定顺序 (Order of Business)

**规则摘要** (rules.md 153-158行):
> 1. 根据公司结构中的"空余卡槽"数量决定选择顺序
> 2. 拥有"首个飞机营销"里程碑的玩家，计算时额外增加2个空余卡槽
> 3. 如果空余卡槽数量相同，则上一回合顺序靠前的玩家先选
> 4. 玩家从顺序轨上选择一个空位，放置自己的顺序标记

**数据来源** (`GameState`):
```gdscript
var turn_order: Array[int] = []           # 当前回合顺序
var selection_order: Array[int] = []      # 选择顺序（按空余卡槽排序）
```

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `turn_order_track` | 顺序轨 | 显示N个位置供选择 | `turn_order` | P0 |
| `empty_slots_display` | 空余卡槽显示 | 显示每个玩家的空余卡槽数 | 计算值 | P1 |
| `selection_highlight` | 选择高亮 | 当前玩家选择时的位置高亮 | `selection_order` | P0 |
| `milestone_bonus_indicator` | 里程碑加成指示 | 显示飞机营销+2效果 | `players[].milestones` | P2 |

---

### 2.3 阶段三：工作时间 (Working 9-5)

这是最复杂的阶段，当前引擎定义为 7 个子阶段：`Recruit` / `Train` / `Marketing` / `GetFood` / `GetDrinks` / `PlaceHouses` / `PlaceRestaurants`（见 `core/engine/phase_manager/definitions.gd:42`）。

#### 2.3.1 子阶段：招聘 (Recruit)

**规则摘要** (rules.md 166-172行):
> - 招聘次数等于在岗可招聘员工的recruit_capacity之和
> - 每次可拿取一张入门级员工卡（左上角有"1"标志）到待命区
> - 即使某员工牌堆已空，仍可招聘后立即培训

**数据来源**:
```gdscript
var employee_pool: Dictionary = {}  # employee_id -> count（供应池）
# players[].employees 中的员工定义有 usage_tags 和 recruit_capacity
```

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `recruit_panel` | 招聘面板 | 显示可招聘员工列表 | `employee_pool` | P0 |
| `recruit_counter` | 招聘次数计数器 | 显示剩余招聘次数 | 计算值 | P0 |
| `employee_pool_card` | 供应池卡牌 | 显示员工+剩余数量 | `employee_pool[id]` | P0 |
| `recruit_btn` | 招聘按钮 | 点击招聘指定员工 | - | P0 |
| `employee_detail_popup` | 员工详情弹窗 | 显示完整能力说明 | `EmployeeDef` | P1 |

#### 2.3.2 子阶段：培训 (Train)

**规则摘要** (rules.md 174-182行):
> - 每次培训一名"待命"区员工
> - 将被培训的卡放回供应区，拿取目标职位新卡
> - 培训时只需最终职位有卡可用，中间过程可缺货

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `train_panel` | 培训面板 | 显示可培训员工及路径 | `reserve_employees` | P0 |
| `train_path_display` | 培训路径显示 | 显示员工→目标的培训链 | `EmployeeDef.train_to` | P0 |
| `train_target_select` | 目标选择器 | 选择培训目标职位 | `employee_pool` | P0 |
| `train_confirm_btn` | 确认培训按钮 | 执行培训操作 | - | P0 |

#### 2.3.3 子阶段：发起营销活动 (Working/Marketing)

**规则摘要** (rules.md 184-198行):
> - 每位在岗营销员可发起一次营销活动
> - 类型：广告牌、邮箱、收音机（需与公路相邻）、飞机（边缘）
> - 选择一种食物/饮品，放置对应数量配件（=持续回合数）
> - 发起后营销员进入"忙碌"状态

**数据来源**:
```gdscript
var marketing_instances: Array[Dictionary] = []  # 活跃营销活动
# map.marketing_placements 存储位置信息
```

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `marketing_panel` | 营销面板 | 选择营销员和类型 | `employees` | P0 |
| `marketing_type_select` | 类型选择器 | 广告牌/邮箱/收音机/飞机 | `EmployeeDef` | P0 |
| `marketing_placement_overlay` | 放置覆盖层 | 地图上显示可放置位置 | `map` | P0 |
| `marketing_range_preview` | 范围预览 | 显示营销影响区域 | 计算值 | P1 |
| `product_select` | 产品选择器 | 选择广告的食物/饮品 | `ProductDef` | P0 |
| `duration_select` | 持续时间选择 | 选择活动持续回合数 | - | P0 |

#### 2.3.4 子阶段：获取食物 (GetFood)

**规则摘要** (rules.md 200-212行):
> - 厨房员工生产食物

**数据来源**:
```gdscript
# players[].inventory = {product_id: count}
```

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `production_panel` | 生产面板 | 显示厨房员工及可生产食物 | `employees` | P0 |
| `inventory_preview` | 库存预览 | 显示操作后的库存变化 | `inventory` | P1 |

#### 2.3.5 子阶段：获取饮品 (GetDrinks)

**规则摘要** (rules.md 200-212行):
> - 采购员从餐厅出发沿路线移动，不允许U型转弯
> - 每个饮品点每回合只能被同一采购员拾取一次

**数据来源**:
```gdscript
# players[].inventory = {product_id: count}
# map.cells[][].drink_source = {type: "product_id"}
```

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `procurement_overlay` | 采购覆盖层 | 地图上规划采购路线 | `map` | P0 |
| `route_drawer` | 路线绘制器 | 绘制采购员移动路径 | - | P0 |
| `drink_source_marker` | 饮料点标记 | 高亮可拾取的饮料点 | `map.drink_source` | P1 |
| `inventory_preview` | 库存预览 | 显示操作后的库存变化 | `inventory` | P1 |

#### 2.3.6 子阶段：放置房屋和花园 (Place Houses & Gardens)

**规则摘要** (rules.md 214-216行):
> - 在岗的相关员工可放置新房屋或为已有房屋添加花园

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `place_house_panel` | 房屋放置面板 | 选择放置类型 | `employees` | P0 |
| `valid_position_overlay` | 有效位置覆盖层 | 高亮可放置位置 | `map` | P0 |
| `garden_target_select` | 花园目标选择 | 选择要添加花园的房屋 | `map.houses` | P0 |

#### 2.3.7 子阶段：放置或移动餐厅 (PlaceRestaurants)

**规则摘要** (rules.md 218-226行):
> - 本地/区域经理可放置新餐厅或移动已有餐厅
> - 不再受"一个板块只能有一个入口"限制
> - 使用经理后，所有餐厅获得"免下车"能力（所有角落都是入口）

**数据来源**:
```gdscript
# players[].restaurants = ["rest_1", "rest_2", ...]   # 餐厅ID列表
# state.map.restaurants[restaurant_id] = {anchor_pos, entrance_pos, cells, rotation, owner, ...}
# players[].drive_thru_active = bool
```

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `restaurant_panel` | 餐厅面板 | 选择放置/移动操作 | `restaurants` | P0 |
| `restaurant_placement_overlay` | 餐厅放置覆盖层 | 显示2x2有效位置 | `map` | P0 |
| `rotation_select` | 朝向选择器 | 选择入口朝向 | - | P0 |
| `drive_thru_indicator` | 免下车指示器 | 显示免下车激活状态 | `drive_thru_active` | P2 |

---

### 2.4 阶段四：晚餐时间 (Dinnertime)

**规则摘要** (rules.md 228-260行):
> 1. 按房屋编号从小到大处理
> 2. 找满足需求的餐厅，选择"单价+距离"最低者
> 3. 相同则比女服务员数量，再比回合顺序
> 4. 收入 = (单价×数量) + 额外奖励，花园翻倍单价
> 5. 女服务员额外赚3（或5）
> 6. CFO加成50%（向上取整）
> 7. 银行破产处理

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `dinnertime_panel` | 晚餐面板 | 显示销售流程 | - | P1 |
| `sale_animation` | 销售动画 | 逐个房屋处理动画 | `map.houses` | P2 |
| `distance_overlay` | 距离覆盖层 | 显示房屋到餐厅距离 | `RoadGraph` | P2 |
| `income_breakdown` | 收入明细 | 单价×数量+奖励+加成 | - | P1 |
| `waitress_tips_display` | 女服务员收入 | 显示额外小费 | - | P1 |
| `cfo_bonus_display` | CFO加成显示 | 显示50%加成 | - | P1 |
| `bank_warning` | 银行破产警告 | 银行资金不足提示 | `bank.total` | P0 |
| `reserve_card_reveal` | 储备卡揭示 | 首次破产时显示所有玩家选择 | `reserve_cards` | P0 |

---

### 2.5 阶段五：发薪日 (Payday)

**规则摘要** (rules.md 262-276行):
> 1. 可解雇任意员工（忙碌营销员通常不能解雇）
> 2. 为所有带"$"标志员工支付$5
> 3. 招聘经理/人力资源的未使用招聘次数可抵扣薪水
> 4. 最低支付$0

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `payday_panel` | 发薪日面板 | 显示薪资计算 | `employees` | P0 |
| `fire_select` | 解雇选择 | 多选要解雇的员工 | `employees` | P0 |
| `salary_list` | 薪资列表 | 每位员工的薪水 | `EmployeeRules.requires_salary(...)` + `rules.salary_cost` | P0 |
| `discount_display` | 折扣显示 | 显示招聘经理折扣 | 计算值 | P1 |
| `total_salary` | 总薪资汇总 | 显示最终应付金额 | - | P0 |
| `pay_confirm_btn` | 确认支付按钮 | 执行支付 | - | P0 |

---

### 2.6 阶段六：营销活动结算 (Marketing / Settlement)

**规则摘要** (rules.md 278-294行):
> 1. 按营销板块编号从小到大处理
> 2. 需求上限：普通房屋3个，有花园5个
> 3. 各类型影响范围不同
> 4. 移除一个持续时间配件，配件归零则回收

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `marketing_settlement_panel` | 营销结算面板 | 显示结算流程 | `marketing_instances` | P1 |
| `demand_generation_anim` | 需求生成动画 | 显示需求添加到房屋 | - | P2 |
| `marketing_countdown` | 营销倒计时 | 显示剩余持续回合 | `remaining_duration` | P1 |
| `marketer_release_notice` | 营销员解放通知 | 活动结束时的提示 | - | P2 |

---

### 2.7 阶段七：清理 (Cleanup)

**规则摘要** (rules.md 296-304行):
> 1. 无冰箱的玩家丢弃所有库存
> 2. 收回所有员工卡
> 3. "即将开业"餐厅翻面
> 4. 移除本回合获得的里程碑类型

**必需UI组件**:

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `inventory_discard_confirm` | 库存丢弃确认 | 无冰箱时的清理提示 | `inventory` | P1 |
| `fridge_display` | 冰箱显示 | 显示可保留上限 | `milestones` | P1 |
| `restaurant_flip_anim` | 餐厅翻面动画 | "即将开业"→"欢迎光临" | - | P2 |
| `milestone_removal_notice` | 里程碑移除通知 | 显示被移除的类型 | `milestone_pool` | P1 |

---

### 2.8 通用UI组件

| 组件ID | 组件名称 | 功能描述 | 数据绑定 | 优先级 |
|--------|----------|----------|----------|--------|
| `player_info_panel` | 玩家信息面板 | 显示所有玩家状态摘要 | `players[]` | P0 |
| `current_player_detail` | 当前玩家详情 | 显示当前玩家完整信息 | `get_current_player()` | P0 |
| `inventory_panel` | 库存面板 | 显示食物/饮品数量 | `inventory` | P0 |
| `milestone_tracker` | 里程碑追踪器 | 已获得/可获得里程碑 | `milestones`, `milestone_pool` | P1 |
| `game_log` | 游戏日志 | 事件历史记录 | - | P1 |
| `action_panel` | 动作面板 | 当前可用操作列表 | `ActionAvailabilityRegistry` | P0 |
| `settings_menu` | 设置菜单 | 音量/语言/显示设置 | `Globals` | P1 |
| `load_game_dialog` | 载入游戏对话框 | 选择存档文件 | - | P1 |
| `game_over_panel` | 游戏结束面板 | 显示排名和统计 | `players[]` | P0 |
| `help_tooltip` | 帮助提示 | 悬停显示规则说明 | - | P2 |

---

## 三、开发计划

### 3.1 第一阶段：核心交互框架 (P0)

**目标**: 实现基本可玩的游戏循环

**预计组件数量**: 15个核心组件

#### 3.1.1 玩家信息面板 (`ui/components/player_panel/`)

**功能需求**:
- 显示所有玩家的摘要信息（编号、名称、颜色、现金、员工数、餐厅数）
- 高亮显示当前玩家
- 点击可展开查看详情

**文件结构**:
```
ui/components/player_panel/
├── player_panel.tscn      # 主面板场景
├── player_panel.gd        # 主面板脚本
├── player_info_item.tscn  # 单个玩家信息项
└── player_info_item.gd    # 单个玩家信息项脚本
```

**接口设计**:
```gdscript
class_name PlayerPanel extends Control

signal player_selected(player_id: int)

func set_game_state(state: GameState) -> void
func set_current_player(player_id: int) -> void
func refresh() -> void
```

**验收标准**:
- [ ] 正确显示所有玩家的基本信息
- [ ] 当前玩家有视觉区分（边框/背景色）
- [ ] 现金变化时有更新动画或即时刷新
- [ ] 点击玩家项触发 `player_selected` 信号

---

#### 3.1.2 员工卡牌组件 (`ui/components/employee_card/`)

**功能需求**:
- 显示员工卡牌信息：名称、等级、薪水标记、能力描述、培训路径
- 支持选中/拖拽状态
- 支持点击查看详情

**文件结构**:
```
ui/components/employee_card/
├── employee_card.tscn     # 卡牌场景
├── employee_card.gd       # 卡牌脚本
└── employee_card_data.gd  # 卡牌数据类
```

**接口设计**:
```gdscript
class_name EmployeeCard extends Control

signal card_clicked(employee_id: String)
signal card_drag_started(employee_id: String)
signal card_drag_ended(employee_id: String, drop_position: Vector2)

@export var employee_id: String
@export var show_salary_indicator: bool = true
@export var draggable: bool = true

func setup(employee_def: Dictionary) -> void
func set_selected(selected: bool) -> void
func set_busy(busy: bool) -> void
```

**验收标准**:
- [ ] 正确显示员工名称和等级标记
- [ ] 需要薪水的员工显示"$"标记
- [ ] 选中状态有视觉反馈（边框高亮）
- [ ] 忙碌状态有视觉遮罩
- [ ] 支持拖拽操作（可配置）

---

#### 3.1.3 员工手牌区 (`ui/components/hand_area/`)

**功能需求**:
- 显示玩家拥有的所有员工卡
- 支持选中多张卡牌
- 支持拖拽到公司结构面板

**文件结构**:
```
ui/components/hand_area/
├── hand_area.tscn         # 手牌区场景
└── hand_area.gd           # 手牌区脚本
```

**接口设计**:
```gdscript
class_name HandArea extends Control

signal cards_selected(employee_ids: Array[String])
signal card_dropped(employee_id: String, target: Control)

func set_employees(employees: Array[String], busy_marketers: Array[String]) -> void
func get_selected_employees() -> Array[String]
func clear_selection() -> void
```

**验收标准**:
- [ ] 正确显示所有员工卡牌
- [ ] 支持单选和多选模式
- [ ] 拖拽卡牌时有视觉反馈
- [ ] 忙碌营销员单独区分显示

---

#### 3.1.4 公司结构面板 (`ui/components/company_structure/`)

**功能需求**:
- 金字塔式布局，CEO固定顶部
- 显示卡槽数量和已占用数
- 支持拖放员工到卡槽
- 支持从卡槽移除员工

**文件结构**:
```
ui/components/company_structure/
├── company_structure.tscn  # 主面板场景
├── company_structure.gd    # 主面板脚本
├── card_slot.tscn          # 卡槽场景
└── card_slot.gd            # 卡槽脚本
```

**接口设计**:
```gdscript
class_name CompanyStructure extends Control

signal structure_changed(new_structure: Dictionary)
signal slot_overflow_warning()

func set_player_data(player: Dictionary) -> void
func get_current_structure() -> Dictionary
func reset() -> void
func validate() -> Result  # 检查结构是否合法
```

**验收标准**:
- [ ] CEO始终显示在顶部
- [ ] 正确显示CEO卡槽数（3或根据储备卡调整）
- [ ] 经理卡槽正确显示（2-10个）
- [ ] 拖放员工到卡槽有视觉反馈
- [ ] 超出卡槽限制时显示警告

---

#### 3.1.5 顺序轨组件 (`ui/components/turn_order/`)

**功能需求**:
- 显示N个位置（2-5人游戏）
- 支持点击选择位置
- 显示已选择的玩家标记

**文件结构**:
```
ui/components/turn_order/
├── turn_order_track.tscn   # 顺序轨场景
├── turn_order_track.gd     # 顺序轨脚本
├── order_slot.tscn         # 位置槽场景
└── order_slot.gd           # 位置槽脚本
```

**接口设计**:
```gdscript
class_name TurnOrderTrack extends Control

signal position_selected(position: int)

func set_player_count(count: int) -> void
func set_current_selections(selections: Dictionary) -> void  # position -> player_id
func set_selectable(can_select: bool, player_id: int) -> void
func highlight_available_positions() -> void
```

**验收标准**:
- [ ] 根据玩家数量正确显示位置数
- [ ] 已选位置显示玩家标记/颜色
- [ ] 可选位置有高亮提示
- [ ] 点击触发选择事件

---

#### 3.1.6 库存面板 (`ui/components/inventory_panel/`)

**功能需求**:
- 显示所有产品类型及数量
- 使用图标+数字形式
- 显示冰箱容量限制（如有）

**文件结构**:
```
ui/components/inventory_panel/
├── inventory_panel.tscn    # 库存面板场景
├── inventory_panel.gd      # 库存面板脚本
├── product_item.tscn       # 产品项场景
└── product_item.gd         # 产品项脚本
```

**接口设计**:
```gdscript
class_name InventoryPanel extends Control

signal product_clicked(product_id: String)

func set_inventory(inventory: Dictionary) -> void  # product_id -> count
func set_fridge_capacity(capacity: int) -> void    # -1表示无冰箱
func highlight_product(product_id: String) -> void
```

**验收标准**:
- [ ] 正确显示所有产品图标和数量
- [ ] 数量变化时有更新反馈
- [ ] 有冰箱时显示容量限制
- [ ] 超出容量时有警告提示

---

#### 3.1.7 动作面板 (`ui/components/action_panel/`)

**功能需求**:
- 根据当前阶段/子阶段显示可用动作
- 点击执行对应动作
- 显示动作的简要说明

**文件结构**:
```
ui/components/action_panel/
├── action_panel.tscn       # 动作面板场景
├── action_panel.gd         # 动作面板脚本
├── action_button.tscn      # 动作按钮场景
└── action_button.gd        # 动作按钮脚本
```

**接口设计**:
```gdscript
class_name ActionPanel extends Control

signal action_requested(action_id: String, params: Dictionary)

func set_available_actions(action_ids: Array[String]) -> void
func set_action_enabled(action_id: String, enabled: bool) -> void
func show_action_params_dialog(action_id: String) -> void
```

**验收标准**:
- [ ] 根据阶段正确显示可用动作
- [ ] 不可用动作灰显或隐藏
- [ ] 点击触发动作请求事件
- [ ] 需要参数的动作弹出参数对话框

---

#### 3.1.8 招聘面板 (`ui/components/recruit_panel/`)

**功能需求**:
- 显示可招聘的入门级员工
- 显示供应池剩余数量
- 显示剩余招聘次数
- 支持点击招聘

**接口设计**:
```gdscript
class_name RecruitPanel extends Control

signal recruit_requested(employee_id: String)

func set_employee_pool(pool: Dictionary) -> void
func set_recruit_count(remaining: int, total: int) -> void
func refresh() -> void
```

**验收标准**:
- [ ] 只显示入门级员工（level=1）
- [ ] 正确显示供应池数量
- [ ] 数量为0时禁用招聘按钮
- [ ] 招聘次数用尽时禁用所有按钮

---

#### 3.1.9 培训面板 (`ui/components/train_panel/`)

**功能需求**:
- 显示待命区可培训员工
- 显示培训路径（当前→可选目标）
- 显示目标职位供应状态

**接口设计**:
```gdscript
class_name TrainPanel extends Control

signal train_requested(employee_id: String, target_id: String)

func set_trainable_employees(employees: Array[String]) -> void
func set_employee_pool(pool: Dictionary) -> void
func show_train_path(employee_id: String) -> void
```

**验收标准**:
- [ ] 只显示待命区员工
- [ ] 正确显示培训路径
- [ ] 目标职位无货时有提示
- [ ] 支持多步培训（跳过中间职位）

---

#### 3.1.10 发薪日面板 (`ui/components/payday_panel/`)

**功能需求**:
- 显示所有需要薪水的员工
- 支持选择要解雇的员工
- 显示折扣计算
- 显示最终薪资

**接口设计**:
```gdscript
class_name PaydayPanel extends Control

signal fire_employees(employee_ids: Array[String])
signal pay_confirmed()

func set_employees(employees: Array[String], busy: Array[String]) -> void
func set_discount(amount: int) -> void
func calculate_total() -> int
```

**验收标准**:
- [ ] 正确列出所有需薪水员工
- [ ] 选择解雇后实时更新总额
- [ ] 正确显示折扣应用
- [ ] 最低显示$0

---

#### 3.1.11 游戏结束面板 (`ui/components/game_over/`)

**功能需求**:
- 显示玩家排名（按现金）
- 显示各玩家统计数据
- 返回主菜单按钮

**接口设计**:
```gdscript
class_name GameOverPanel extends Control

signal return_to_menu_requested()

func set_final_state(state: GameState) -> void
func show_with_animation() -> void
```

**验收标准**:
- [ ] 正确按现金排序显示排名
- [ ] 显示每位玩家的最终现金
- [ ] 显示基本统计（回合数、员工数等）
- [ ] 点击返回正确跳转到主菜单

---

#### 3.1.12 银行破产处理UI

**功能需求**:
- 第一次破产时揭示所有储备卡
- 显示CEO卡槽变化
- 第二次破产时触发游戏结束

**验收标准**:
- [ ] 正确显示所有玩家的储备卡
- [ ] 显示票数统计和最终CEO卡槽数
- [ ] 第二次破产后显示游戏结束面板

---

### 3.2 第二阶段：完善游戏流程 (P1)

**目标**: 完整实现7个阶段的UI交互

#### 任务清单

| 组件ID | 组件名称 | 依赖 | 预计工作量 |
|--------|----------|------|------------|
| `marketing_panel` | 营销活动面板 | `employee_card`, `map_canvas` | 中 |
| `marketing_placement_overlay` | 营销放置覆盖层 | `map_canvas` | 中 |
| `procurement_overlay` | 采购路线覆盖层 | `map_canvas` | 高 |
| `place_house_panel` | 房屋放置面板 | `map_canvas` | 低 |
| `restaurant_panel` | 餐厅管理面板 | `map_canvas` | 中 |
| `dinnertime_panel` | 晚餐结算面板 | - | 中 |
| `milestone_tracker` | 里程碑追踪器 | - | 低 |
| `game_log` | 游戏日志 | - | 低 |
| `settings_menu` | 设置菜单 | - | 低 |
| `load_game_dialog` | 载入游戏对话框 | - | 低 |

---

### 3.3 第三阶段：增强体验 (P2)

**目标**: 提升用户体验和视觉效果

#### 任务清单

| 功能 | 描述 | 预计工作量 |
|------|------|------------|
| 动画系统 | 卡牌移动、销售流程、翻面动画 | 高 |
| 距离可视化 | 显示到餐厅的距离路径 | 中 |
| 营销范围预览 | 显示营销影响的房屋 | 中 |
| 帮助系统 | 规则悬停提示、新手引导 | 中 |
| 音效系统 | 背景音乐、操作反馈音 | 中 |
| 回放播放器 | 加载存档、步进播放 | 高 |
| 地图缩放 | 大地图的缩放功能 | 中 |

---

## 四、技术规范

### 4.1 目录结构

```
ui/
├── components/                    # 可复用UI组件
│   ├── player_panel/
│   ├── employee_card/
│   ├── hand_area/
│   ├── company_structure/
│   ├── turn_order/
│   ├── inventory_panel/
│   ├── action_panel/
│   ├── recruit_panel/
│   ├── train_panel/
│   ├── payday_panel/
│   ├── marketing_panel/
│   ├── game_over/
│   └── game_log/
├── overlays/                      # 地图覆盖层
│   ├── placement_overlay.gd
│   ├── procurement_overlay.gd
│   └── marketing_range_overlay.gd
├── dialogs/                       # 对话框
│   ├── settings_dialog.tscn
│   ├── load_game_dialog.tscn
│   └── confirm_dialog.tscn
├── scenes/                        # 场景
│   ├── main_menu.tscn
│   ├── setup/
│   ├── game/
│   └── tools/
├── visual/                        # 视觉系统
│   ├── map_skin.gd
│   └── map_skin_builder.gd
└── theme/                         # 主题资源
    └── default_theme.tres
```

### 4.2 组件通信模式

```gdscript
# 方式1: 通过 EventBus（跨组件通信，确定性事件）
EventBus.emit_event(EventBus.EventType.EMPLOYEE_RECRUITED, {"player_id": player_id, "employee_id": employee_id})
EventBus.subscribe(EventBus.EventType.EMPLOYEE_RECRUITED, Callable(self, "_on_employee_recruited"), 100, "ui")

# 方式2: 通过父节点中介（同一场景内）
# 子组件发出信号，父节点game.gd处理并转发

# 方式3: 直接引用（紧密耦合的组件）
hand_area.cards_selected.connect(_on_cards_selected)
```

### 4.3 状态绑定模式

```gdscript
# 读取状态（只读）
func _update_display() -> void:
    var state := Globals.current_game_engine.get_state()
    var player := state.players[state.current_player_index]
    cash_label.text = "$%d" % player.cash

# 执行操作（通过Command）
func _on_action_requested(action_id: String, params: Dictionary) -> void:
    var cmd := Command.create(action_id, player_id, params)
    var result := Globals.current_game_engine.execute_command(cmd)
    if result.ok:
        _update_display()
    else:
        _show_error(result.error)
```

### 4.4 命名规范

- 场景文件: `snake_case.tscn`
- 脚本文件: `snake_case.gd`
- 类名: `PascalCase`
- 信号名: `snake_case`（动词过去式，如 `card_selected`）
- 方法名: `snake_case`（动词开头，如 `set_data`, `get_value`）

### 4.5 Phase / SubPhase 常量表（避免同名歧义）

> 注意：`Marketing` 既是主阶段（营销结算），也是 `Working` 的子阶段（发起营销），UI 文案与日志需要显式区分。

**Phase（核心）**:
- `Setup`（开局落子，非循环阶段）
- `Restructuring`
- `OrderOfBusiness`
- `Working`
- `Dinnertime`
- `Payday`
- `Marketing`（结算阶段）
- `Cleanup`
- `GameOver`

**WorkingSubPhase**:
- `Recruit`
- `Train`
- `Marketing`（发起营销子阶段）
- `GetFood`
- `GetDrinks`
- `PlaceHouses`
- `PlaceRestaurants`

### 4.6 UI → Command 对照表（核心动作）

> 说明：向量参数统一用 `[x, y]` 数组（与 `require_vector2i_param` 对齐）；具体参数以对应 `gameplay/actions/*_action.gd` 为准。

| 交互/面板 | action_id | actor | params（示例） | 备注 |
|---|---|---:|---|---|
| 推进阶段 | `advance_phase` | -1 | `{}` | 系统命令（`Command.create_system`） |
| 推进子阶段 | `advance_phase` | -1 | `{"target":"sub_phase"}` | 系统命令（`Command.create_system`） |
| 跳过 | `skip` | 当前玩家 | `{}` | 玩家命令 |
| 选择顺序轨位置 | `choose_turn_order` | 当前玩家 | `{"position": 0}` | `OrderOfBusiness` |
| 招聘 | `recruit` | 当前玩家 | `{"employee_type":"<entry_level_employee_type>"}` | `Working/Recruit` |
| 培训 | `train` | 当前玩家 | `{"from_employee":"<employee_type>","to_employee":"<employee_type>"}` | `Working/Train` |
| 发起营销 | `initiate_marketing` | 当前玩家 | `{"employee_type":"<employee_type>","board_number":<board_number>,"product":"<product_id>","position":[x,y],"duration":<n>}` | `Working/Marketing`（duration 可省略） |
| 生产食物 | `produce_food` | 当前玩家 | `{"employee_type":"<employee_type>"}` | `Working/GetFood` |
| 采购饮料 | `procure_drinks` | 当前玩家 | `{"employee_type":"<employee_type>","restaurant_id":"<restaurant_id>","route":[[x1,y1],[x2,y2],...]}` | `Working/GetDrinks`（restaurant_id/route 可省略其一） |
| 放置房屋 | `place_house` | 当前玩家 | `{"position":[x,y],"rotation":0}` | `Working/PlaceHouses` |
| 添加花园 | `add_garden` | 当前玩家 | `{"house_id":"<house_id>","direction":"E"}` | `Working/PlaceHouses` |
| 放置餐厅 | `place_restaurant` | 当前玩家 | `{"position":[x,y],"rotation":0}` | `Setup` 与 `Working/PlaceRestaurants` 都可用 |
| 移动餐厅 | `move_restaurant` | 当前玩家 | `{"restaurant_id":"<restaurant_id>","position":[x,y],"rotation":0}` | `Working/PlaceRestaurants` |
| 设定价格 | `set_price` | 当前玩家 | `{}` | `Working` 强制动作（无 params，仅确认） |
| 设定奢侈品价格 | `set_luxury_price` | 当前玩家 | `{}` | `Working` 强制动作（无 params，仅确认） |
| 设定折扣 | `set_discount` | 当前玩家 | `{}` | `Working` 强制动作（无 params，仅确认） |
| 解雇员工 | `fire` | 当前玩家 | `{"employee_id":"<employee_type>","location":"reserve"}` | `Payday`（location 可省略，默认自动推断） |

---

### 4.7 组件接口契约表（signals / set_*）

> 统一约定：子组件只负责展示与输入收集，通过 `signal` 抛出用户意图；`ui/scenes/game/game.gd` 负责读取 `GameState`/Registry、组装 `Command` 并 `execute_command`。

| 组件 | game.gd 调用（主要 set_*） | 组件 signal（game.gd 监听） | 说明/入口 |
|---|---|---|---|
| `ActionPanel` | `set_game_state(state)` / `set_current_player(player_id)` / `set_action_registry(registry)` | `action_requested(action_id, params)` | 右侧动作列表；点击动作后由 `game.gd` 决定是否弹窗或直接执行 |
| `TurnOrderTrack` | `set_player_count(n)` / `set_current_selections({position:player_id})` / `set_selectable(can_select, player_id)` | `position_selected(position)` | `OrderOfBusiness` 阶段点选位置后执行 `choose_turn_order` |
| `HandArea` | `set_employees(employees, reserve, busy_marketers)` | `cards_selected(employee_ids)` | 当前仅记录日志（重组公司交互后续完善） |
| `CompanyStructure` | `set_player_data(current_player)` | `structure_changed(new_structure)` | 当前仅记录日志（重组公司提交逻辑后续完善） |
| `RecruitPanel` | `set_employee_pool(state.employee_pool)` / `set_recruit_count(remaining,total)` | `recruit_requested(employee_type)` | `Working/Recruit` 打开；确认后执行 `recruit` |
| `TrainPanel` | `set_employee_pool(state.employee_pool)` / `set_trainable_employees(reserve_employees)` / `set_train_count(remaining,total)` | `train_requested(from_employee,to_employee)` | `Working/Train` 打开；确认后执行 `train` |
| `PaydayPanel` | `set_employees(employees,busy_marketers)` / `set_player_cash(cash)` / `set_discount(discount)` | `fire_employees(employee_ids)` / `pay_confirmed()` | `Payday` 打开；解雇走 `fire`，确认后系统推进阶段 |
| `BankBreakPanel` | `set_bankruptcy_info(count,before,after)` / `show_with_animation()` | `bankruptcy_acknowledged()` / `game_end_triggered()` | 银行破产事件自动弹出（`bank.broke_count` 增加） |
| `MarketingPanel` | `set_available_marketers(entries)` / `set_available_boards(boards_by_type)` / `set_map_selection_callback(cb)` / `set_selected_target(pos)` | `marketing_requested(employee_type,board_number,position,product,duration)` / `cancelled()` | `Working/Marketing` 打开；面板请求地图选点并预览范围 |
| `PriceSettingPanel` | `set_mode(price|discount|luxury)` / `set_current_prices(prices)` | `price_confirmed(action_id)` / `cancelled()` | 强制动作确认：确认后直接执行对应 action（无 params） |
| `ProductionPanel` | `set_production_type(food|drinks)` / `set_available_producers(employee_types)` / `set_current_inventory(inv)` | `production_requested(employee_type,production_type)` / `cancelled()` | 选员工后执行 `produce_food/procure_drinks`（路线交互 TBD） |
| `RestaurantPlacementOverlay` | `set_mode(place_restaurant|move_restaurant)` / `set_map_data(state.map)` / `set_available_restaurants(ids)` / `set_selected_position(pos)` | `placement_confirmed(position,rotation,restaurant_id)` / `cancelled()` | 地图选点回填；确认后执行 `place_restaurant/move_restaurant` |
| `HousePlacementOverlay` | `set_mode(place_house|add_garden)` / `set_map_data(state.map)` / `set_selected_position(pos)` | `house_placement_confirmed(position,rotation)` / `garden_confirmed(house_id,direction)` / `cancelled()` | 地图选点回填；确认后执行 `place_house/add_garden` |
| `MilestonePanel` | `set_milestone_pool(state.milestone_pool)` / `set_player_milestones(player.milestones)` | `cancelled()` | 只读展示（自动授予）；当前缺少 UI 入口（需要按钮/菜单触发 `_show_milestone_panel()`） |
| `DinnerTimeOverlay` | `set_pending_orders(orders)` / `show_overlay()` | `phase_completed()` | `Dinnertime` 阶段自动弹出，只读展示 `round_state["dinnertime"]` |
| `DemandIndicator` | `set_tile_size(size)` / `set_map_offset(offset)` / `set_house_demands(data)` | - | `Dinnertime` 阶段标记成交房屋需求（绿色 satisfied；位置对齐 MapCanvas world_origin） |
| `MapCanvas` | `set_game_state(state)` | `cell_selected(world_pos)` / `cell_hovered(world_pos)` | 地图选点信号用于营销/放置等交互；hover 触发营销范围预览 |

## 五、验收标准清单

### 5.1 P0阶段验收（核心交互）

#### 玩家信息显示
- [ ] 所有玩家基本信息正确显示
- [ ] 当前玩家有明确视觉区分
- [ ] 现金变化实时更新

#### 员工管理
- [ ] 员工手牌正确显示所有卡牌
- [ ] 卡牌信息完整（名称、等级、薪水标记）
- [ ] 支持拖拽卡牌到公司结构
- [ ] 公司结构正确显示CEO和卡槽

#### 回合顺序
- [ ] 顺序轨正确显示位置数量
- [ ] 可点击选择空位置
- [ ] 已选位置显示玩家标记

#### 招聘培训
- [ ] 招聘面板显示入门级员工
- [ ] 正确显示供应池数量
- [ ] 培训路径正确显示
- [ ] 招聘/培训操作可执行

#### 发薪日
- [ ] 正确列出需薪水员工
- [ ] 支持选择解雇员工
- [ ] 正确计算折扣和总额
- [ ] 支付操作可执行

#### 游戏流程
- [ ] 游戏可以正常开始
- [ ] 阶段切换正确
- [ ] 银行破产正确处理
- [ ] 游戏结束显示排名

### 5.2 P1阶段验收（完整流程）

#### 营销系统
- [ ] 营销员选择正确
- [ ] 地图上可选择放置位置
- [ ] 产品和持续时间可选
- [ ] 营销活动正确记录

#### 生产采购
- [ ] 厨房员工生产操作可执行
- [ ] 采购路线可绘制
- [ ] U型转弯限制正确
- [ ] 库存正确更新

#### 建筑放置
- [ ] 房屋放置位置可选
- [ ] 花园添加操作可执行
- [ ] 餐厅放置/移动可执行
- [ ] 免下车状态正确显示

#### 结算显示
- [ ] 晚餐销售过程可视
- [ ] 收入明细正确
- [ ] 营销效果正确应用

#### 其他功能
- [ ] 里程碑追踪正确
- [ ] 游戏日志记录完整
- [ ] 设置菜单可用
- [ ] 存档载入可用

### 5.3 P2阶段验收（增强体验）

- [ ] 核心操作有动画反馈
- [ ] 距离计算有可视化
- [ ] 营销范围有预览
- [ ] 音效系统正常工作
- [ ] 新手引导完整
- [ ] 回放功能可用
- [ ] 大地图可缩放

---

## 六、风险与注意事项

### 6.1 性能考虑

- **地图重绘**: `map_canvas.gd` 使用 `_draw()` 重绘，避免每帧完全重绘，仅在状态变化时 `queue_redraw()`
- **卡牌实例**: 员工卡牌可能较多（每玩家10+张），考虑使用对象池
- **日志面板**: 使用虚拟列表（ItemList）避免过多节点

### 6.2 状态同步

- UI更新必须在 `execute_command()` 返回后进行
- 避免UI直接修改 `GameState`
- 使用信号在命令执行后触发UI更新

### 6.3 多人游戏预留

- 当前为本地多人，按当前玩家过滤信息显示
- 保持"秘密信息"（如手牌、储备卡）的隐藏能力
- 为未来网络同步预留接口

### 6.4 已知技术债务

- `map_canvas.gd` 已有621行，考虑拆分渲染层
- 缺少统一的UI主题（Theme资源）
- 缺少组件单元测试

---

## 七、开发顺序建议

```
Week 1-2: P0核心组件
├── 玩家信息面板
├── 员工卡牌组件
├── 员工手牌区
└── 公司结构面板

Week 3-4: P0核心组件续
├── 顺序轨组件
├── 库存面板
├── 动作面板
└── 招聘面板

Week 5-6: P0收尾
├── 培训面板
├── 发薪日面板
├── 游戏结束面板
└── 银行破产UI

Week 7-8: P1营销/生产
├── 营销面板
├── 营销放置覆盖层
├── 生产面板
└── 采购覆盖层

Week 9-10: P1建筑/结算
├── 房屋放置面板
├── 餐厅面板
├── 晚餐结算面板
└── 营销结算面板

Week 11-12: P1其他
├── 里程碑追踪器
├── 游戏日志
├── 设置菜单
└── 载入游戏对话框

Week 13+: P2增强
├── 动画系统
├── 音效系统
├── 帮助系统
└── 回放播放器
```

---

*文档创建日期: 2026-01-05*
*最后更新: 2026-01-06*
*基于代码版本: 0.1.0*

---

## 八、开发进度追踪

### 8.1 P0 阶段进度

| 组件 | 状态 | 完成日期 | 文件位置 | 备注 |
|------|------|----------|----------|------|
| player_panel (玩家信息面板) | ✅ 已接入 | 2026-01-05 | `ui/components/player_panel/` | 显示所有玩家摘要，高亮当前玩家（验证：进入 `game.tscn` 右侧） |
| employee_card (员工卡牌) | ✅ 已接入 | 2026-01-05 | `ui/components/employee_card/` | 显示单张员工卡（验证：`hand_area/company_structure` 渲染卡牌信息） |
| hand_area (员工手牌区) | ✅ 已接入 | 2026-01-05 | `ui/components/hand_area/` | 分区显示在岗/待命/忙碌员工（验证：进入 `game.tscn` 底部左侧） |
| company_structure (公司结构) | ✅ 已接入 | 2026-01-05 | `ui/components/company_structure/` | 金字塔式卡槽布局（验证：进入 `game.tscn` 底部右侧） |
| turn_order_track (顺序轨) | ✅ 已接入 | 2026-01-05 | `ui/components/turn_order/` | 支持点击选择位置（验证：`OrderOfBusiness` 点击顺序轨） |
| inventory_panel (库存面板) | ✅ 已接入 | 2026-01-05 | `ui/components/inventory_panel/` | 显示产品类型及数量（验证：右侧库存随结算/生产变化） |
| action_panel (动作面板) | ✅ 已接入 | 2026-01-05 | `ui/components/action_panel/` | 根据阶段显示可用动作（验证：右侧动作列表随阶段变化） |
| recruit_panel (招聘面板) | ✅ 已接入 | 2026-01-05 | `ui/components/recruit_panel/` | 入门级员工招聘（验证：`Working/Recruit` 点击 `recruit`） |
| train_panel (培训面板) | ✅ 已接入 | 2026-01-05 | `ui/components/train_panel/` | 选择培训源与目标（验证：`Working/Train` 点击 `train`） |
| payday_panel (发薪日面板) | ✅ 已接入 | 2026-01-05 | `ui/components/payday_panel/` | 解雇选择与薪资结算（验证：`Payday` 点击 `fire`） |
| game_over_panel (游戏结束) | ✅ 已接入 | 2026-01-05 | `ui/components/game_over/` | 显示排名和统计数据（验证：进入 `GameOver` 自动弹出） |
| bank_break_panel (银行破产) | ✅ 已接入 | 2026-01-06 | `ui/components/bank_break/` | 首次/二次破产弹窗（验证：bank.broke_count 增加自动弹出） |

**P0 完成度**: 12/12 = **100%** ✅

### 8.2 P1 阶段进度

| 组件 | 状态 | 完成日期 | 文件位置 | 备注 |
|------|------|----------|----------|------|
| marketing_panel (营销面板) | ✅ 已接入 | 2026-01-06 | `ui/components/marketing_panel/` | 发起营销输入收集（验证：`Working/Marketing` 点击 `initiate_marketing`） |
| price_setting_panel (价格设置) | ✅ 已接入 | 2026-01-06 | `ui/components/price_panel/` | 强制动作确认面板（`set_price/set_discount/set_luxury_price` 无 params；验证：`Working` 点击对应动作） |
| restaurant_placement (餐厅放置) | ✅ 已接入 | 2026-01-06 | `ui/components/restaurant_placement/` | 地图选点 + rotation + move 模式（未实现“有效位置扫描/高亮”；验证：`place_restaurant/move_restaurant`） |
| house_placement (房屋放置) | ✅ 已接入 | 2026-01-06 | `ui/components/house_placement/` | 地图选点放房 + 选房添加花园（`add_garden` 需 `direction`；验证：`place_house/add_garden`） |
| milestone_panel (里程碑面板) | ⚠️ 已实现未入口 | 2026-01-06 | `ui/components/milestone_panel/` | 只读展示（里程碑自动授予，不支持手动领取；当前缺少 UI 入口） |
| dinner_time_overlay (晚餐时间) | ✅ 已接入 | 2026-01-06 | `ui/components/dinner_time/` | 只读展示 `round_state["dinnertime"]`（验证：进入 `Dinnertime` 阶段自动弹出） |
| demand_indicator (需求指示器) | ✅ 已接入 | 2026-01-06 | `ui/components/demand_indicator/` | `Dinnertime` 阶段标记已成交房屋需求（satisfied；验证：进入 `Dinnertime`） |
| production_panel (生产面板) | ✅ 已接入 | 2026-01-06 | `ui/components/production_panel/` | 选员工并执行（采购路线交互未实现，默认走规则自动路线；验证：`produce_food/procure_drinks`） |

**P1 完成度（已接入）**: 7/8 = **87%** ⚠️

### 8.3 P2 阶段进度

| 组件 | 状态 | 完成日期 | 文件位置 | 备注 |
|------|------|----------|----------|------|
| settings_dialog (设置对话框) | ⚠️ 已实现未入口 | 2026-01-06 | `ui/dialogs/settings_dialog/` | 组件已实现；`game.gd` 有 `show_settings_dialog()` 但当前无按钮入口 |
| game_log_panel (游戏日志) | ⚠️ 已实现未入口 | 2026-01-06 | `ui/components/game_log/` | 面板已创建但无 UI 入口（`game.gd.toggle_game_log()` 暂无触发点） |
| help_tooltip (帮助提示) | ⚠️ 已加载未使用 | 2026-01-06 | `ui/components/help_tooltip/` | 管理器已在 `game.gd` 初始化，但当前没有实际 tooltip 数据源接入 |
| distance_overlay (距离覆盖层) | ⚠️ 已实现未入口 | 2026-01-06 | `ui/overlays/` | 工具方法已实现（`show_distance_overlay`），但暂无触发入口 |
| marketing_range_overlay (营销范围) | ✅ 已接入 | 2026-01-06 | `ui/overlays/` | 发起营销时 hover/选点预览范围（验证：`initiate_marketing` 选类型后移动鼠标） |
| ui_animation_manager (动画系统) | ⚠️ 已加载未使用 | 2026-01-06 | `ui/visual/` | 管理器已在 `game.gd` 初始化，但当前未被组件调用 |
| confirm_dialog (确认对话框) | ⚠️ 已实现未入口 | 2026-01-06 | `ui/dialogs/` | 组件已实现，但当前无使用点（可用于危险操作二次确认） |

**P2 完成度（已接入）**: 1/7 = **14%** ⚠️

### 8.4 集成状态

| 场景 | 状态 | 完成日期 | 备注 |
|------|------|----------|------|
| game.tscn 布局重构 | ✅ 完成 | 2026-01-05 | HSplitContainer 布局，右侧面板+底部面板 |
| game.gd 组件绑定 | ✅ 完成 | 2026-01-05 | _update_ui_components() 方法 |
| 信号连接 | ✅ 完成 | 2026-01-05 | action_requested, position_selected 等信号已连接 |
| 阶段面板集成 | ✅ 完成 | 2026-01-06 | recruit/train/payday/game_over/bank_break/dinnertime 等按需加载或自动弹出 |
| P1 组件集成 | ⚠️ 部分 | 2026-01-06 | 大部分面板已接入；`milestone_panel` 当前缺少 UI 入口 |
| P2 组件集成 | ⚠️ 部分 | 2026-01-06 | `marketing_range_overlay/zoom_control` 已接入；settings/log/confirm/distance/tooltip/animation 仍缺入口或未被调用 |

### 8.5 已知问题

1. ~~**tscn UID 引用**: game.tscn 使用硬编码 UID 引用新组件，首次打开需要 Godot 重新生成 UID~~ ✅ 已解决
2. ~~**EmployeeRegistry 未注入**: hand_area 和 company_structure 需要注入 EmployeeRegistry 以获取员工定义~~ ✅ game.gd 中已处理
3. ~~**动作执行未连接**: action_panel 的 action_requested 信号尚未连接到 game.gd 的命令执行~~ ✅ 已连接
4. ~~**银行破产 UI**: 首次/二次破产的特殊处理界面尚未实现~~ ✅ 已完成
5. **MilestonePanel 无 UI 入口**：面板可渲染且已对齐引擎数据，但当前没有按钮/动作可打开
6. **P2 组件入口缺失**：settings/game_log/confirm_dialog/distance_overlay 已实现但未接入到主界面
7. **采购路线交互未实现**：`procure_drinks` 当前 UI 仅选择员工，路线由规则自动生成（暂无可视化/手绘）

### 8.6 下一步计划

1. 完成文档对齐：更新进度/集成状态 + 增补接口契约表（见本文件 8.* 与 `docs/ui_remediation_plan.md`）
2. 增加 `milestone_panel/settings_dialog/game_log_panel` 的 UI 入口（按钮/菜单/快捷键其一）
3. 增加 `procure_drinks` 的路线交互与可视化（可复用 `distance_overlay`）
4. 餐厅/房屋放置：增加“有效位置扫描/高亮”（目前仅支持地图点选回填）

### 8.7 新增组件（2026-01-06）

| 组件 | 路径 | 功能描述 |
|------|------|----------|
| zoom_control | `ui/components/zoom_control/` | 地图缩放控制按钮组 |
| replay_player | `ui/components/replay_player/` | 游戏回放播放控制器 |
| sound_manager | `ui/audio/` | 音效播放管理器 |
| music_manager | `ui/audio/` | 背景音乐管理器 |
| audio_system_initializer | `ui/audio/` | 音频系统初始化器 |

### 8.8 地图缩放功能

- **map_view.gd**: 添加缩放支持
  - 鼠标滚轮缩放（25% - 200%）
  - 平滑缩放动画
  - 中键拖拽平移
  - `zoom_in()` / `zoom_out()` / `reset_zoom()` / `fit_to_view()` 方法
  - `center_on_position()` 定位到指定坐标

- **map_canvas.gd**: 添加辅助方法
  - `get_base_size()` - 获取基础尺寸
  - `get_cell_size()` - 获取单元格尺寸
  - `get_grid_size()` - 获取网格尺寸

### 8.9 音效系统架构

```
ui/audio/
├── sound_manager.gd      # 音效管理器（单例）
├── sound_manager.tscn
├── music_manager.gd      # 背景音乐管理器（单例）
├── music_manager.tscn
├── audio_system_initializer.gd  # 初始化器
├── audio_system_initializer.tscn
├── sfx/                  # 音效文件目录
│   ├── ui_button_click.wav
│   ├── ui_panel_open.wav
│   └── ...
└── music/                # 背景音乐目录
    ├── menu.ogg
    ├── game_calm.ogg
    └── ...
```

**音效类别**:
- UI: 界面交互音效
- ACTION: 游戏动作音效
- EVENT: 事件提示音效
- AMBIENT: 环境音效

---

*文档创建日期: 2026-01-05*
*最后更新: 2026-01-06*
*基于代码版本: 0.1.0*
