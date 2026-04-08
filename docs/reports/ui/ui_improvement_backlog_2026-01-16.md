# UI & UX 改进清单（来自 2026-01-16 反馈）

目的：把本次 1~7 条反馈拆成可验证的小任务，并在此文件内追踪进度与未决问题。

说明：
- 状态：`TODO` / `IN_PROGRESS` / `BLOCKED` / `DONE`
- 每一项在实现前，如有不清楚之处，会先在“问题”里记录并向你确认。

---

## 1) 回合顺位图标背景 + 当前玩家红框

- 状态：DONE（按你确认：仅改顶部 TurnOrderDisplay）
- 目标：
  - 顺位图标的背景色使用与地图餐厅相同的底色（当前为 `#f4edd1`）。
  - 当前行动玩家用“红色边框”高亮。
- 涉及文件：
  - `ui/components/turn_order/turn_order_display.gd`

## 2) 强制动作自动完成且不在动作面板展示；定价类仍要写日志

- 状态：DONE
- 目标（已实现）：
  - 动作面板不再出现强制动作按钮。
  - “准备离开 Working（最后子阶段点确认结束/skip）”时，若缺少定价类强制动作，则自动按默认值执行并写入日志。
  - `set_price / set_discount / set_luxury_price` 在游戏日志中可见（玩家日志）。
- 涉及文件（初步）：
  - `ui/components/action_panel/action_panel.gd`
  - `ui/scenes/game/game.gd`
  - `ui/scenes/game/game_event_log_controller.gd`

## 3) 字体整体偏小：整体调大 + 设置中提供可调选项（重点游戏日志）

- 状态：DONE（按你确认：暂时不继续扩大其它面板字号）
- 目标：
  - 默认字体更易读（尤其 `GameLogPanel`）。
  - 设置中提供调节选项，便于你手动调试。
- 已实现：
  - 设置 → Display 增加“字体倍率 / 日志字体倍率”滑条（默认值已上调）。
  - 日志条目已支持运行时刷新字号；TopBar/ActionPanel/PlayerPanel/InventoryPanel 已接入全局字体倍率（其余面板若仍偏小，可继续补齐）。
- 涉及文件：
  - `ui/components/game_log/game_log_panel.gd`
  - `ui/dialogs/settings_dialog.tscn`
  - `ui/dialogs/settings_dialog.gd`
  - `autoload/globals.gd`
- 备注：如果后续你又觉得某些面板偏小，我们再按“点名的面板”逐个接入 `font_scale`（避免一次性全局改动过大）。

## 4) 鼠标悬停单元格信息默认不显示；Display 菜单增加调试 checkbox

- 状态：DONE（tooltip + hover 高亮框均受控，默认关闭）
- 目标：
  - 默认关闭地图格子的 tooltip 信息（`pos/tile_origin/structure/...`）。
  - 设置 → Display 增加调试 checkbox（仅勾选后显示）。
- 涉及文件（初步）：
  - `ui/scenes/game/map_canvas.gd`
  - `ui/dialogs/settings_dialog.tscn`
  - `ui/dialogs/settings_dialog.gd`
  - `autoload/globals.gd`

## 5) 板块黑色边框遮挡 piece：调整绘制顺序，piece 永远在最上层

- 状态：DONE
- 目标：
  - 地图/道路/黑边框先画；建筑/广告牌等 piece 后画，避免黑边盖住。
- 涉及文件（初步）：
  - `ui/scenes/game/map_canvas_drawer.gd`
- 备注：当前 `_draw_tile_borders()` 注释写着“允许覆盖道路/建筑”，需要按新需求调整。

## 6) 升级路线缩放后卡片变糊 + 增加“适应宽度”按钮

- 状态：DONE（你已确认：滚轮缩放不再整体发糊）
- 目标：
  - 鼠标滚轮缩放后卡片/文字不再明显变糊。
  - 增加“适应宽度”按钮：缩放到填满页面宽度（类似现有“适应窗口”）。
- 涉及文件（初步）：
  - `ui/components/employee_tree/employee_tree.tscn`
  - `ui/components/employee_tree/employee_tree.gd`
  - （清晰度相关可能涉及）`ui/components/employee_tree/employee_tree_graph.gd` / `ui/components/employee_card/employee_card.gd`
  - 修复：`employee_tree_graph.gd` 的类型推断导致脚本解析失败（影响进入游戏），已修复

## 7) 调试面板：玩家选择 + 数据驱动的可选列表（招聘/培训/生产/采购等）

- 状态：DONE（按你确认：B=仅在 debug/force 模式允许非当前玩家执行）
- 目标（已实现）：
  - 调试面板里与玩家相关的命令支持选择玩家。
  - 招聘/培训/生产/采购等参数改为下拉/可选列表（从 registry/game data 读取），减少手填。
- 涉及文件：
  - `ui/scenes/debug/tabs/command_tab.gd`
  - `ui/scenes/debug/components/param_dialog.gd`
  - `core/debug/debug_commands/action_commands.gd`
  - `core/debug/debug_command_registry.gd`
  - `core/debug/debug_commands/game_commands.gd`
  - `core/debug/debug_commands/util_commands.gd`
  - `core/engine/game_engine/command_runner.gd`
  - 修复：`util_commands.gd` 缩进错误导致 DebugPanel 脚本解析失败（影响进入游戏），已修复

---

## 8) 员工卡片素材补齐（Entry/工资/路程等图标）

- 状态：DONE
- 目标：
  - 将员工卡片底部的图标占位色块替换为你提供的 SVG 素材（entry_level / 工资 / 路程等）。
  - range 支持 `road`/`air`/`∞`（`air:-1` 视为无限）。
- 涉及文件：
  - `ui/components/employee_card/employee_card.gd`
  - `assets/images/Arrow in Black Circle.svg`
  - `assets/images/Bank Notes for Salary in Black Circle.svg`
  - `assets/images/Road - 2.svg` / `assets/images/Road - 3.svg`（其它数值若无对应素材则回退为文本）
  - `assets/images/Zeppelin.svg` / `assets/images/Zeppelin with 4.svg` / `assets/images/Zeppelin with Infinity Symbol.svg`

---

## 9) 员工卡片：路程图标不重复写数字 + 营销/采购图标对齐 + 无路程不渲染（null 修复）

- 状态：DONE
- 反馈点：
  - 道路路程 SVG 已自带数字，不应再额外渲染文本数字。
  - 品牌经理/品牌总监的路程图标应使用 `Zeppelin with Infinity Symbol.svg`（不再叠加飞机广告标识）。
  - manager 等员工的 range.type=null 不应显示为 “null”。
- 已实现：
  - `road` 路程：有对应 Road SVG 时不再显示数字；仅在缺图时回退为文本（如 `R1`）。
  - `air` 路程：统一使用飞艇图标；`value=-1`（无限）优先使用 `Zeppelin with Infinity Symbol.svg`（有图时不再补文字）。
  - range.type 为 null/空 时不再渲染中间路程区（避免出现 “null0”）。
- 涉及文件：
  - `ui/components/employee_card/employee_card.gd`

## 10) 地图渲染：bridge 格重复绘制（tile_g 中央 bridge 叠图）

- 状态：DONE
- 目标：
  - 同一格存在 bridge=True 的道路段时，只渲染 bridge 段，避免与其它段叠画导致视觉问题。
- 已实现：
  - Road 渲染阶段：若该格包含 bridge 段，则过滤掉非 bridge 段，仅绘制 bridge=True 的段。
- 涉及文件：
  - `ui/scenes/game/map_canvas_drawer.gd`

## 11) 放置房屋与花园：限定房屋编号 + 花园数量上限（全局 8 片）

- 状态：DONE（按你确认：玩家选择编号；place_house 直接放置 house_with_garden；花园数量仅限制 add_garden）
- 目标：
  - 可放置房屋编号仅允许 `[1, 3, 6, 9, 11, 14, 17, 19]`，用完即无。
  - 花园板件总量 8 片，用完即无。
- 已实现：
  - `place_house`：
    - UI：在动作面板的上下文区域增加“房号”下拉选择，必须选中后才能确认放置。
    - 规则：仅允许从剩余编号池中选择；放置成功后从池中移除。
    - 放置的 piece 为 `house_with_garden`（2x3/3x2），并写入 `has_garden=true`。
  - `add_garden`：
    - 仅此动作受“花园板件 8 片”的全局数量限制（`garden_supply_remaining`），执行成功后消耗 1。
  - 存档/回放确定性：
    - `state.map.house_number_supply_remaining`：剩余可放置房号（Array[int]）
    - `state.map.garden_supply_remaining`：剩余花园板件数（int，默认 8）
- 涉及文件：
  - `core/map/map_runtime/baked_map.gd`
  - `gameplay/actions/place_house_action.gd`
  - `gameplay/actions/add_garden_action.gd`
  - `ui/components/house_placement/house_placement_overlay.gd`
  - `ui/components/action_panel/action_panel.tscn`
  - `ui/components/action_panel/action_panel.gd`
  - `ui/scenes/game/game_panel_placement_overlays.gd`
  - `ui/scenes/game/game_map_interaction_controller.gd`

## 12) 升级路线：Recruit/Train 分 lane（颜色保持不变）

- 状态：DONE
- 目标：
  - 招聘与培训员工在升级路线布局上分为两类（避免同 lane 内上下混排导致读图不稳定），但颜色保持一致。
- 已实现：
  - EmployeeTree 仅在布局层把 `recruit_train` 细分为 `recruit` / `train`；颜色映射仍为同一色。
- 涉及文件：
  - `ui/components/employee_tree/employee_tree_graph.gd`
  - `ui/components/employee_tree/employee_tree_layout.gd`
  - `ui/visual/employee_role_colors.gd`

## 13) 员工卡片：背景/标题栏样式 + 1x 图标 + 管理岗位/跑腿显示规则

- 状态：DONE
- 目标：
  - 员工卡片背景色与餐厅底色一致（`#f4edd1`）。
  - 顶部标题栏填满宽度并贴紧卡片上边缘，标题文字居中（Label 充满标题栏）。
  - 针对 `1x` 员工，在左下角 entry_level 图标位显示 `1x in Black Circle.svg`。
  - 管理岗位若无岗位效果描述，则显示 `manager_slots` 数量。
  - 跑腿伙计（`errand_boy`）不显示距离/路程信息。
  - 底部图标行固定贴底（不再紧挨说明文字）。
  - 图标显示尺寸保持不变且三枚图标大小一致（避免因 SVG 分辨率变化导致 UI 变大）。
  - SVG 图标清晰度提升（提高 svg import scale）。
- 涉及文件：
  - `ui/components/employee_card/employee_card.gd`
  - `assets/images/1x in Black Circle.svg`
  - `assets/images/*.svg.import`（相关员工卡片图标：`svg/scale=4.0`）

## 14) 放置花园：东西侧围栏贴图旋转 + 旋转板块放置判定/位置修复

- 状态：DONE
- 反馈点：
  - 花园在东西侧放置时围栏贴图方向不正确。
  - 板块已旋转时，花园的合法/非法位置判定与落点有错位（合法不能放、非法能放）。
- 已实现：
  - 判定：以房屋 `cells` 的 bounding box 计算花园目标格（避免依赖 `anchor_pos` 在旋转板块下不再是左上角导致的错位）。
  - 应用：添加花园后按 `direction` 计算 `house_with_garden` 的 `rotation` 与 `anchor_pos`（保持结构写入与后续交互一致）。
  - 渲染：花园围栏贴图在纵向花园（E/W）时旋转 90° 绘制。
- 涉及文件：
  - `core/map/placement_validator/garden_attachment.gd`
  - `gameplay/actions/add_garden_action.gd`
  - `ui/scenes/game/map_canvas_drawer.gd`

## 15) 房屋需求 token：缩小到当前的 2/3 且不重叠（不遮挡房屋 ID）

- 状态：DONE
- 反馈点：
  - 需求 token 希望从“3 倍版本”缩小到当前的 2/3 或更小。
  - token 之间不应重叠。
  - 需求 token 放置后不能遮盖房屋 ID。
  - token 大小应固定；每次新增需求时允许重新布局所有 token（位置可以变化），以保证不重叠且不遮挡 ID。
- 已实现：
  - token 绘制大小固定（不再按“是否放得下”动态缩放）。
  - 布局种子包含需求内容：新增/移除需求会触发本房屋所有 token 重新布局。
  - 布局严格避免 token 与 token 重叠，并保留房屋 ID 区域不被覆盖。
- 涉及文件：
  - `ui/scenes/game/map_canvas_drawer.gd`

## 16) 调试面板：参数弹窗可选玩家 + “生产/采购”改为直接加库存（不再依赖员工）

- 状态：DONE
- 反馈点：
  - 与玩家相关的命令弹窗里看不到玩家选择（例如放置餐厅、招聘员工等）。
  - “生产食物/采购饮料”等不应通过增加员工实现；期望直接给指定玩家增加库存。
- 已实现：
  - 参数弹窗内新增“目标玩家”下拉，提交时同步到 Debug 面板顶部的玩家选择。
  - 新增 internal 动作 `debug_add_inventory`，并将 debug 的 `produce/procure` 改为直接增加库存（保留命令历史/回放一致性）。
- 涉及文件：
  - `ui/scenes/debug/components/param_dialog.gd`
  - `ui/scenes/debug/tabs/command_tab.gd`
  - `core/debug/debug_commands/action_commands.gd`
  - `gameplay/actions/debug_add_inventory_action.gd`
  - `core/engine/game_engine/action_setup.gd`

## 17) 晚餐日志：房屋消费记录 + 晚餐总结报告（按玩家/按品类/按产品）

- 状态：DONE
- 反馈点：
  - 晚餐时间的房屋消费记录没有体现在游戏日志中。
  - 晚餐阶段结束前需要一份总结：每位玩家晚餐总收入，以及按分类汇总（食物/饮料/服务员/CFO 等），并给出每种食物/饮料的赚钱总数。
- 已实现：
  - 新增事件 `DINNERTIME_REPORT`（离开 Dinnertime 时发射，包含该回合晚餐结算快照），保证日志可从事件历史稳定恢复。
  - 游戏日志输出：每个房屋的消费/收入记录，以及晚餐总结（按玩家/按分类/按产品）。
- 涉及文件：
  - `autoload/event_bus.gd`
  - `core/engine/game_engine/command_runner.gd`
  - `gameplay/actions/advance_phase_action.gd`
  - `gameplay/actions/skip_action.gd`
  - `gameplay/actions/skip_sub_phase_action.gd`
  - `gameplay/actions/choose_turn_order_action.gd`
  - `ui/scenes/game/game_event_log_controller.gd`

## 18) 游戏日志：长文本自动换行（不再截断）

- 状态：DONE
- 反馈点：
  - 游戏日志中某一行日志超出宽度就看不到了，希望自动换行便于阅读。
- 已实现：
  - 日志消息改为可自动换行并按内容撑高（长文本不再被截断/省略）。
- 涉及文件：
  - `ui/components/game_log/game_log_panel.gd`
