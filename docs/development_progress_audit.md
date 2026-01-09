# 开发进度审计（基于当前工作区代码 + 文档）

最后更新：2026-01-08

本文件用于把“当前已完成/可验证的能力”与“仍未开发/未闭环的缺口”集中到一处，作为后续排期与对齐规则的入口文档（避免只靠零散 TODO 或过期设计稿）。

---

## 0. 信息源（建议优先级）

1. `docs/development_status.md`：里程碑状态 + 变更日志（核心事实来源）
2. `docs/ui_remediation_plan.md`：UI 接线整改的完成记录（以 code 可验证为准）
3. `docs/architecture/*`：架构拆解与关键模块说明（新同学上手入口）
4. `docs/testing.md`：headless 测试规范与运行脚本
5. `docs/rules.md`：规则摘要（用于对齐“应该怎么做”）

> 注意：个别历史设计稿存在“已实现/未实现”与代码不一致的情况（详见第 6 节）。

---

## 1. 当前开发进度（已实现 / 可验证）

### 1.1 Core/规则侧（引擎可玩闭环）

- **命令驱动与确定性**：`core/engine/game_engine.gd` 提供 `execute_command / rewind_to_command / full_replay / archive` 等能力。
- **阶段状态机**：`core/engine/phase_manager/*` 覆盖 Setup + 7 个循环阶段，并支持 Working 子阶段与 hooks/settlement 映射。
- **模块系统 V2（严格模式）**：`core/modules/v2/*` + `modules/*/module.json`，支持依赖闭包、内容装配、规则注册、缺失必需 primary settlement fail-fast。
- **地图烘焙与道路图**：`core/map/*` 支持 MapBaker/RoadGraph/PlacementValidator，UI 侧 MapCanvas 已可渲染 roads/structures/marketing/demand 等层。
- **基础动作与结算**：`gameplay/actions/*` 覆盖 recruit/train/fire/marketing/produce/procure/place/move 等；Dinnertime/Payday/Marketing/Cleanup 结算由模块注册执行（base_rules 兜底主结算器）。

### 1.2 UI 侧（主游戏场景已接线）

- **主菜单/入口**：新游戏、载入游戏、设置、板块编辑器、回放测试可用。
- **主游戏场景（`ui/scenes/game/game.tscn`）**：
  - 地图交互：MapCanvas hover/选点、餐厅放置/移动合法格高亮、营销范围预览等（`ui/scenes/game/game_map_interaction_controller.gd`）。
  - 核心面板：Recruit/Train/Marketing/定价强制动作/生产采购/放置房屋&花园/放置&移动餐厅/Payday 等已接入 `game.gd` 的 Command 执行链路。
  - 覆盖层：营销范围（`ui/overlays/marketing_range_overlay.gd`）、晚餐结果只读展示、需求指示器、缩放控件等已存在。
  - 日志与设置：`ui/components/game_log/game_log_panel.tscn` 与 `ui/dialogs/settings_dialog.tscn` 已接入；入口：游戏菜单 → 设置 / 显示-隐藏日志。
  - 信息/工具：游戏菜单提供里程碑面板与距离工具入口（两次点选起点/终点）。
- **调试面板（可交互命令）**：`ui/scenes/debug/debug_panel.tscn` + `core/debug/debug_commands/*` 已可执行调试命令（含 save/load/undo/redo 等命令入口）。

### 1.3 测试与工具

- `tools/run_headless_test.sh`：统一 headless 运行、超时与日志判定（详见 `docs/testing.md`）。
- `ui/scenes/tests/all_tests.tscn`：聚合 core 逻辑测试（以 `docs/development_status.md` 中记录的 AllTests 统计为准）。

---

## 2. 仍未开发 / 未闭环点（按优先级）

> 说明：这里的“未开发”包含两类：  
> A) **入口/交互缺失**（规则能力已有，但 UI/流程没接上）；  
> B) **规则尚未完整对齐**（当前实现是简化策略或占位）。

### 2.1 P0（已闭环）

- ✅ 主菜单“载入游戏/设置”已接入：`ui/scenes/menus/main_menu.gd`（载入固定路径 `user://savegame.json`；设置复用 `ui/dialogs/settings_dialog.tscn`）。
- ✅ GameSetup 已补齐模块/玩家/储备卡配置：`ui/scenes/setup/game_setup.gd`（Tabs：模块/玩家/储备卡；并写入 `Globals`）。
- ✅ 初始餐厅放置已按规则逆序：`core/state/game_state_factory.gd`（Setup 从 turn_order 最后一位开始）+ `gameplay/actions/skip_action.gd`（Setup 逆序轮转）。
- ✅ 储备卡选择已进入初始化：`core/engine/game_engine.gd` / `core/engine/game_engine/initializer.gd` 支持按玩家注入 `reserve_card_selected_by_player`。

### 2.2 P1（不阻塞运行，但体验/信息缺失或有 TODO）

1. ✅ **库存面板已显示冰箱容量信息**  
   - 位置：`ui/components/inventory_panel/inventory_panel.gd`（标题显示“无冰箱 / 冰箱：每种≤N”）  
   - 注入：`ui/scenes/game/game_panel_controller.gd` 会从玩家里程碑中推导 `gain_fridge` 容量并调用 `set_fridge_capacity()`

2. ✅ **员工卡拖拽交互已补齐（视觉 + drop 目标检测）**  
   - 位置：`ui/components/hand_area/hand_area.gd`（拖拽预览 + drop target 检测与高亮）  
   - Drop target：`ui/components/company_structure/company_structure.gd` 的 `CardSlot` 已加入 group `employee_card_drop_target` 并支持高亮

3. ✅ **距离覆盖层接口与高亮规则已补齐**  
   - 位置：`ui/overlays/distance_overlay.gd`（支持 `set_map_data()` / `show_distances()`；高亮支持 house_id/restaurant_id 映射）  
   - 接线：`ui/scenes/game/game_overlay_distance.gd`（挂到 `map_canvas` 并同步 tile_size/map_offset）

4. ✅ **Restructuring 阶段已替换“简化策略”并对齐规则书核心规则**  
   - 在岗/待命切换：不再自动把 `reserve_employees` 合并到在岗；改为在重组阶段通过动作 `restructure_employee` 切换（UI 侧支持将员工卡在“在岗/待命”区域间拖拽：`ui/components/hand_area/hand_area.gd` + `ui/scenes/game/game_panel_controller.gd`）。  
   - UX 门禁：Restructuring（`round>1`）阶段隐藏/禁用 `skip`，避免误点导致流程卡住（`ui/components/action_panel/action_panel.gd` + `gameplay/actions/skip_action.gd`）。  
   - 提交制（hotseat）：新增动作 `submit_restructuring`，要求 **所有玩家提交后才能离开 Restructuring**（通过 `round_state.pending_phase_actions["Restructuring"]` 门禁 + `modules/base_rules/rules/phase_and_map.gd:_on_restructuring_before_exit` 校验）。提交后会轮转到下一位未提交玩家；全员提交后自动推进到下一阶段。  
   - 严格结构数据：`player.company_structure.structure` 作为“金字塔结构”数据模型。重组阶段可通过拖拽设置 CEO 直属槽（内部动作 `set_company_structure_direct`）与经理下属（内部动作 `set_company_structure_report`）；提交时会优先尊重该布局与已设置的 reports，并自动补齐剩余 reports（经理优先直连 CEO；reports 仅包含非经理员工）。提交后禁止再执行 `restructure_employee`（避免提交后继续修改）。  
   - UI 可视化：公司结构面板会展示 CEO 直属槽与每位经理的下属列表（基于 `company_structure.structure` + 当前在岗员工生成预览）。员工卡拖拽仅在 Restructuring 且未提交时启用。  
   - 超限惩罚：离开重组阶段时若公司结构超限（含“经理数量超过 CEO 卡槽”），则按规则书处理为“除 CEO 外全部转为待命”（`modules/base_rules/rules/phase_and_map.gd:_on_restructuring_before_exit`）。  
   - 仍未覆盖：规则书所述的“秘密分堆/同时揭示”。

### 2.3 P2（后续增强/可选复杂交互）

1. ✅ **采购路线可视化（自动路线预览）**（不含手绘规划）  
   - 入口：`Working/GetDrinks` 打开生产面板并选择采购员后，地图显示自动规划路线  
   - 参考：`docs/ui_remediation_plan.md` 的 R-041（DONE；手绘规划仍为可选增强）

2. ✅ **更通用的“有效位置扫描/高亮”**（不仅限餐厅放置）  
   - 参考：`docs/ui_remediation_plan.md` 的 R-052（DONE；餐厅/房屋放置均已支持高亮）

3. **更完整的存档/回放 UX**  
   - 例如：多个存档槽、存档列表、回放时间线 UI（目前更偏开发调试入口：菜单保存/DebugPanel 命令）。

---

## 3. 规则/内容层的已知缺口（非 UI）

1. **6 人地图生成未实现**  
   - 位置：`modules/base_rules/rules/phase_and_map.gd`（明确返回 failure）  
   - 备注：规则书要求 6 人需配合“新区域”模块；当前工作区默认玩家数上限可能未开放到 6。

2. **部分素材仍为占位**  
   - 位置：`modules/movie_stars/assets/map/icons/README.md`（缺少若干 png 占位说明）

3. **抽象基类占位**  
   - 位置：`gameplay/validators/base_validator.gd` 的 `validate()` 返回“未实现”（期望由子类实现；若有人直接实例化会导致误用）。

---

## 4. 推荐的下一步（按“最小增量可验证”排序）

1. **（暂时跳过）Restructuring：补齐“秘密分堆/同时揭示 + 金字塔层级建模”**  
   - 说明：当前按 hotseat 推进，暂不引入隐藏信息流程；保留为后续规则对齐项。

2. **P2 深交互**：采购路线规划、通用高亮扫描、回放 UX  
   - 建议以“可视化但不改变规则”为第一阶段（例如先画出规则自动生成的 route）。

---

## 5. 验证清单（改动后建议跑）

- 全量 headless：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`
- 启动冒烟（UI/场景）：`tools/run_headless_test.sh res://ui/scenes/tests/game_smoke_test.tscn GameSmokeTest 60`
- UI 冒烟：启动游戏场景，至少覆盖：新游戏 → 执行动作 → 存档 → DebugPanel/菜单退出 → 重新进入并加载（若实现 load）。

---

## 6. 文档一致性问题（需要标注/更新）

- `docs/ui_development_plan.md` 中部分“未实现/完全缺失”的结论与代码现状不一致（例如里程碑面板/游戏日志/营销范围预览/缩放等）；建议以 `docs/ui_remediation_plan.md` 与实际场景/脚本为准，并逐步修正文档为单一事实来源（SSOT）。
