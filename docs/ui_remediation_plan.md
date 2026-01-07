# UI 整改计划（对齐文档/代码/规则）

> 目标：把当前已实现的 UI 组件**真正接通**到 `ui/scenes/game/game.gd` 与 `gameplay/actions/*`，让“能点能用、参数正确、不会报错”，并同步修正文档中的进度与接口描述。  
> 原则：以 `gameplay/actions/*` 的校验为**唯一真相**（Command 参数/约束），以 `ui/scenes/game/game.gd` 作为 UI 调度中枢；避免为 UI 改规则（除非确有必要且同步更新文档）。

---

## 0. 元信息

- 创建日期：2026-01-06
- 维护者：Codex（与仓库同作者协作）
- 适用版本：当前工作区（以 `git status` 为准）
- 测试基线：
  - ✅ `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 600`（`71/71 PASS`，见 `.godot/AllTests.log`）

---

## 1. 问题总览（必须整改）

> 这些问题会导致“文档宣称已集成/可用”，但实际运行不可用或行为偏离规则。

### 1.1 接口不一致（组件 ↔ game.gd）

- `ActionPanel`：`game.gd` 试图获取 `get_action_registry()`，但 `GameEngine` 仅提供 `get_available_actions/get_player_actions`，导致 ActionPanel 长期 fallback。
- `BankBreakPanel`：信号/方法名与 `game.gd` 期待完全不匹配，且没有触发入口（未调用 `_show_bank_break_panel`）。
- `MarketingPanel`：信号名/参数形态、`set_available_marketers` 参数类型与 `game.gd` 不一致；并且营销动作缺少 `board_number/product/duration` 等关键输入。
- `PriceSettingPanel`：信号名不一致；更关键的是当前玩法层 `set_price/set_discount/set_luxury_price` 是**强制动作**（无 params），而面板实现为“逐产品改价”，两者语义冲突。
- `ProductionPanel`：信号/方法不一致；玩法层 `produce_food/procure_drinks` 仅需 `employee_type`（路线可缺省自动生成），而面板实现为“选商品/选数量”。
- `RestaurantPlacementOverlay/HousePlacementOverlay`：信号参数形态与 `game.gd` 不一致；`add_garden` 缺少 `direction`。
- `MilestonePanel`：数据入口/方法不一致；`claim_milestone` 当前不是已注册 action（ActionRegistry 不包含），且面板里程碑列表硬编码。
- `DinnerTimeOverlay/DemandIndicator`：文档宣称已集成，但 `game.gd` 未接入。

### 1.2 数据来源不一致（Registry / state）

- `HandArea/CompanyStructure`：组件设计为注入 EmployeeRegistry 实例，但当前 `EmployeeRegistry` 为**静态 Registry**（由模块系统 V2 配置），`game.gd` 也不存在 `get_employee_registry()`；导致 UI 只能显示 id 或默认字段。
- 员工筛选：`game.gd` 用字符串包含判断（`find("marketer")` 等）筛员工，易漏（与 `EmployeeDef.usage_tags/role` 的数据驱动相违背）。

### 1.3 文档进度结论不准确

- `docs/ui_development_plan.md` 的 “8.* 开发进度追踪/集成状态” 把 P0/P1/P2 及集成标为 100% 完成，但与当前代码现状不符（上面多项接口/功能尚未闭环）。

---

## 2. 整改范围与非目标

### 2.1 本轮整改范围（本文件覆盖）

- 修复所有“接口不一致导致不可用”的问题。
- 让 UI → Command 参数满足 `gameplay/actions/*` 校验（不再靠猜）。
- 最小可用闭环：能在主游戏场景中完成关键交互（P0 + P1 核心动作），且不产生 SCRIPT ERROR。
- 同步更新 `docs/ui_development_plan.md`：把“进度/已知问题/集成状态/接口设计”改为真实可验证的描述。

### 2.2 非目标（除非后续单独立项）

- 不实现完整美术资源替换/完整动画系统扩展（已有占位即可）。
- 不实现高复杂度的“采购路线手绘”交互（可以先用自动路线 + 后续扩展）。
- 不实现“里程碑手动可领取”的复杂判定逻辑（若引擎本身采用自动授予，则 UI 只展示；若要手动领取需另开设计）。

---

## 3. 整改策略（统一契约）

> 先统一“谁调用谁、参数是什么”，再做实现。此处是最终目标契约（整改过程中会逐项落地）。

### 3.1 `game.gd` 作为唯一调度者

- 子组件只做展示与输入收集，通过 `signal` 把用户意图抛给 `game.gd`。
- `game.gd` 负责：
  - 读取 `GameState`/Registry（只读）
  - 生成 `Command`
  - 调用 `game_engine.execute_command`
  - 处理错误提示/关闭面板/刷新 UI

### 3.2 Command 参数：以 gameplay 为准

- 以 `docs/ui_development_plan.md:1025` 的 UI→Command 表为**入口**，但若与 `gameplay/actions/*` 冲突，必须以 `gameplay/actions/*` 为准并回写文档。

### 3.3 Registry：UI 直接使用静态 Registry

- `EmployeeRegistry/ProductRegistry/MarketingRegistry/MilestoneRegistry` 由模块系统 V2 在 `GameEngine.initialize` 阶段配置为静态；UI 侧展示信息直接用静态查询（不再依赖注入实例）。

---

## 4. 任务分解（整改 Backlog）

> 状态：`TODO` / `DOING` / `DONE` / `BLOCKED`  
> 每个任务必须有：验收标准 + 影响文件 + 备注（含风险/回滚点）。

### 4.1 P0：先让“可用动作/基础数据展示”准确

| ID | 优先级 | 任务 | 验收标准 | 影响文件 | 状态 |
|---|---|---|---|---|---|
| R-001 | P0 | 暴露 `GameEngine.get_action_registry()` 或等价能力 | ActionPanel 不再 fallback，动作列表随阶段变化且无脚本错误 | `core/engine/game_engine.gd` | DONE |
| R-002 | P0 | ActionPanel 使用 `get_player_available_actions`（玩家可执行动作） | 当前玩家无权/缺员工的动作不出现（或灰显） | `ui/components/action_panel/action_panel.gd`, `ui/scenes/game/game.gd` | DONE |
| R-003 | P0 | UI 员工信息改用静态 `EmployeeRegistry` | 不注入 registry 也能显示员工名称/角色/能力摘要 | `ui/components/hand_area/hand_area.gd`, `ui/components/company_structure/company_structure.gd`, `ui/components/recruit_panel/recruit_panel.gd`, `ui/components/train_panel/train_panel.gd`, `ui/components/payday_panel/payday_panel.gd` | DONE |
| R-004 | P0 | `game.gd` 停止调用不存在的 `get_employee_registry()` | 运行不出现相关报错；相关注释/文档同步 | `ui/scenes/game/game.gd` | DONE |

### 4.2 P0：银行破产 UI 接入（避免“写了但永远不出现”）

| ID | 优先级 | 任务 | 验收标准 | 影响文件 | 状态 |
|---|---|---|---|---|---|
| R-010 | P0 | BankBreakPanel 与 `game.gd` 接口对齐（信号/方法） | 面板能显示并能关闭；无未连接信号 | `ui/components/bank_break/bank_break_panel.gd`, `ui/scenes/game/game.gd` | DONE |
| R-011 | P0 | 在状态更新时检测 `bank.broke_count` 变化并触发面板 | 首次/二次破产时能自动弹出 | `ui/scenes/game/game.gd` | DONE |

### 4.3 P1：营销闭环（UI→Command 参数正确）

| ID | 优先级 | 任务 | 验收标准 | 影响文件 | 状态 |
|---|---|---|---|---|---|
| R-020 | P1 | MarketingPanel 补齐输入：`employee_type`/`board_number`/`product`/`duration` | 能构造满足 `initiate_marketing` 校验的 params（见 `gameplay/actions/initiate_marketing_action.gd`） | `ui/components/marketing_panel/marketing_panel.gd`, `.tscn` | DONE |
| R-021 | P1 | MapCanvas 提供“选点”信号；MarketingPanel 支持地图选点 | 可在地图点击选择 position，回填到面板并可确认 | `ui/scenes/game/map_canvas.gd`, `ui/scenes/game/game.gd` | DONE |
| R-022 | P1 | 员工筛选改为基于 `EmployeeDef.usage_tags`（`use:marketing:*`） | 不再用字符串包含判断；不会漏掉模块员工 | `ui/scenes/game/game.gd` | DONE |
| R-023 | P1 | 接入 `MarketingRangeOverlay` 作为预览（可先做 preview） | 选择类型后能显示预览；取消/确认后清理 | `ui/scenes/game/game.gd`, `ui/overlays/marketing_range_overlay.*` | DONE |

### 4.4 P1：定价/折扣/奢侈品强制动作（与玩法一致）

| ID | 优先级 | 任务 | 验收标准 | 影响文件 | 状态 |
|---|---|---|---|---|---|
| R-030 | P1 | PriceSettingPanel 改为“强制动作确认面板”（不做逐产品改价） | 执行 `set_price/set_discount/set_luxury_price` 成功后关闭；文案解释效果 | `ui/components/price_panel/price_setting_panel.gd`, `.tscn`, `ui/scenes/game/game.gd` | DONE |
| R-031 | P1 | 文档 UI→Command 表对齐（确认这些动作 params 为空） | `docs/ui_development_plan.md` 同步说明面板行为 | `docs/ui_development_plan.md` | DONE |

### 4.5 P1：生产/采购（与玩法参数一致）

| ID | 优先级 | 任务 | 验收标准 | 影响文件 | 状态 |
|---|---|---|---|---|---|
| R-040 | P1 | ProductionPanel 改为“选择员工并执行” | `produce_food` 仅传 `employee_type`；`procure_drinks` 默认自动路线也可执行 | `ui/components/production_panel/production_panel.gd`, `.tscn`, `ui/scenes/game/game.gd` | DONE |
| R-041 | P2 | 采购路线交互（后续） | 可选：提供 route 规划 UI | `ui/components/...`, `ui/overlays/...` | TODO |

### 4.6 P1：建筑放置/花园（参数齐全）

| ID | 优先级 | 任务 | 验收标准 | 影响文件 | 状态 |
|---|---|---|---|---|---|
| R-050 | P1 | RestaurantPlacementOverlay 与 `game.gd` 接口对齐（rotation/模式/可选 restaurant_id） | 能放置/移动餐厅并通过 action 校验 | `ui/components/restaurant_placement/*`, `ui/scenes/game/game.gd` | DONE |
| R-051 | P1 | HousePlacementOverlay 与 `game.gd` 接口对齐（rotation/花园方向） | `place_house` 与 `add_garden` params 符合校验（含 `direction`） | `ui/components/house_placement/*`, `ui/scenes/game/game.gd` | DONE |
| R-052 | P2 | “有效位置高亮”改为基于 PlacementValidator 扫描（可先不做） | overlay 可显示可放置位置集合 | `ui/scenes/game/game.gd` | TODO |

### 4.7 P1/P2：里程碑/晚餐/需求展示（按引擎现状定稿）

| ID | 优先级 | 任务 | 验收标准 | 影响文件 | 状态 |
|---|---|---|---|---|---|
| R-060 | P1 | MilestonePanel 改为从 `MilestoneRegistry` 渲染 + 展示玩家已获得 | 不再硬编码；不依赖不存在的 `claim_milestone` action | `ui/components/milestone_panel/*`, `ui/scenes/game/game.gd`, 文档 | DONE |
| R-061 | P2 | DinnerTimeOverlay 接入（或明确暂不接入并修文档） | `Dinnertime` 阶段有可视化反馈（哪怕是只读列表） | `ui/components/dinner_time/*`, `ui/scenes/game/game.gd`, 文档 | DONE |
| R-062 | P2 | DemandIndicator 接入（或移出“已完成”并修文档） | `Marketing`/`Dinnertime` 相关需求可视化 | `ui/components/demand_indicator/*`, `ui/scenes/game/game.gd`, 文档 | DONE |

### 4.8 文档修订（把“完成”改成“可验证”）

| ID | 优先级 | 任务 | 验收标准 | 影响文件 | 状态 |
|---|---|---|---|---|---|
| R-070 | P0 | 修订 `docs/ui_development_plan.md` 的 8.* 进度与集成状态 | 与实际代码一致；每项附“验证方法/入口” | `docs/ui_development_plan.md` | DONE |
| R-071 | P0 | 增加“组件接口契约表”（signals/set_* 由谁调用） | 后续不再出现同名不同参的漂移 | `docs/ui_development_plan.md` 或新章节 | DONE |

### 4.9 验证与回归

| ID | 优先级 | 任务 | 验收标准 | 影响文件 | 状态 |
|---|---|---|---|---|---|
| R-080 | P0 | 每完成一组任务跑全量 headless tests 并记录 | `.godot/*.log` 无 SCRIPT ERROR；AllTests PASS | 无 | DOING |
| R-081 | P1 | 增加 UI headless smoke test（可选） | headless 加载 `game.tscn` 不超时、无报错 | `ui/scenes/tests/*` | DONE |

---

## 5. 执行顺序（建议）

1) **P0 基建**：R-001 ~ R-004  
2) **银行破产接入**：R-010 ~ R-011  
3) **营销闭环**：R-020 ~ R-023  
4) **定价强制动作**：R-030 ~ R-031  
5) **生产/采购**：R-040（路线交互 R-041 后置）  
6) **建筑放置/花园**：R-050 ~ R-051（有效位置扫描 R-052 后置）  
7) **里程碑/晚餐/需求**：R-060 ~ R-062（按引擎现状定稿）  
8) **文档修订**：R-070 ~ R-071（贯穿执行，避免堆到最后）  
9) **回归**：R-080（每阶段必做），R-081（可选）

---

## 6. 进度追踪（持续更新）

> 规则：每次改动都要更新本节（状态 + 简要说明 + 日期）。

| 日期 | ID | 状态变更 | 说明 |
|---|---|---|---|
| 2026-01-06 | R-000 | DONE | 建立整改计划文件；确认 AllTests 71/71 PASS |
| 2026-01-06 | R-001 | DONE | 新增 `GameEngine.get_action_registry()`（修正缩进后 AllTests PASS） |
| 2026-01-06 | R-002 | DONE | ActionPanel 支持按玩家灰显不可执行动作；`game.gd` 注入 current_player_id 与 registry |
| 2026-01-06 | R-003 | DONE | HandArea/CompanyStructure/Recruit/Train/Payday 改为读取静态 EmployeeRegistry；Payday 使用 `salary` 字段 |
| 2026-01-06 | R-004 | DONE | 移除 `game.gd` 对 `get_employee_registry()` 的调用 |
| 2026-01-06 | R-080 | DONE | 回归：AllTests `71/71 PASS`（见 `.godot/AllTests.log`） |
| 2026-01-06 | R-010 | DONE | `game.gd` 按 BankBreakPanel 现有 API/信号接入（`set_bankruptcy_info/show_with_animation`） |
| 2026-01-06 | R-011 | DONE | 新增 `_check_bank_break`：检测 `bank.broke_count` 变化并自动弹窗 |
| 2026-01-06 | R-080 | DONE | 回归：AllTests `71/71 PASS`（见 `.godot/AllTests.log`） |
| 2026-01-06 | R-020 | DONE | MarketingPanel 参数补齐并对齐 `initiate_marketing`（`board_number/product/duration/position`） |
| 2026-01-06 | R-021 | DONE | MapCanvas 新增 `cell_selected/cell_hovered`；营销面板可进入地图选点并回填 |
| 2026-01-06 | R-022 | DONE | 营销员筛选改为解析 `EmployeeDef.usage_tags`（并按 `busy_marketers` 数量扣减） |
| 2026-01-06 | R-080 | DONE | 回归：AllTests `71/71 PASS`（见 `.godot/AllTests.log`） |
| 2026-01-06 | R-030 | DONE | PriceSettingPanel 改为强制动作确认面板；确认后执行 `set_price/set_discount/set_luxury_price`（无 params） |
| 2026-01-06 | R-080 | DONE | 回归：AllTests `71/71 PASS`（见 `.godot/AllTests.log`） |
| 2026-01-06 | R-023 | DONE | 接入 MarketingRangeOverlay 预览：营销选型后 hover/选点显示范围；取消/确认清理 |
| 2026-01-06 | R-080 | DONE | 回归：AllTests `71/71 PASS`（见 `.godot/AllTests.log`） |
| 2026-01-06 | R-031 | DONE | 文档对齐：`set_price/set_discount/set_luxury_price` 为无 params 强制动作；PriceSettingPanel 为确认面板 |
| 2026-01-06 | R-040 | DONE | ProductionPanel 改为“选员工并执行”；game.gd 使用 EmployeeDef.can_produce/can_procure 过滤可用员工 |
| 2026-01-06 | R-080 | DONE | 回归：AllTests `71/71 PASS`（见 `.godot/AllTests.log`） |
| 2026-01-06 | R-050 | DONE | RestaurantPlacementOverlay 支持 move/place 模式、rotation 与 restaurant_id 选择；game.gd 用 MapCanvas 选点回填并执行 action |
| 2026-01-06 | R-051 | DONE | HousePlacementOverlay 支持 place_house(rotation+position) 与 add_garden(house_id+direction)；game.gd 执行参数对齐校验 |
| 2026-01-06 | R-080 | DONE | 回归：AllTests `71/71 PASS`（见 `.godot/AllTests.log`） |
| 2026-01-06 | R-060 | DONE | MilestonePanel 改为从 MilestoneRegistry 渲染（只读）；移除 `claim_milestone` UI 调用与相关信号 |
| 2026-01-06 | R-080 | DONE | 回归：AllTests `71/71 PASS`（见 `.godot/AllTests.log`） |
| 2026-01-06 | R-061 | DONE | `Dinnertime` 阶段自动弹出 DinnerTimeOverlay（从 `round_state["dinnertime"]` 生成只读订单列表）；银行破产弹窗关闭后会恢复显示 |
| 2026-01-06 | R-062 | DONE | 接入 DemandIndicator：在 `Dinnertime` 阶段标记已成交房屋需求（绿色 satisfied），并对齐 MapCanvas world_origin 偏移 |
| 2026-01-06 | R-080 | DONE | 回归：AllTests `71/71 PASS`（见 `.godot/AllTests.log`） |
| 2026-01-06 | R-070 | DONE | 修订 `docs/ui_development_plan.md` 8.*：进度/集成状态与实际代码对齐，并补充每项“验证入口” |
| 2026-01-06 | R-071 | DONE | 为 `docs/ui_development_plan.md` 增补 4.7“组件接口契约表”（signals/set_* 调用关系） |
| 2026-01-06 | R-081 | DONE | 新增 `game.tscn` headless smoke test：`ui/scenes/tests/game_smoke_test.tscn`（并修复加载 game 场景暴露的脚本解析/节点路径错误） |
| 2026-01-06 | R-080 | DONE | 回归：GameSmokeTest PASS（见 `.godot/GameSmokeTest.log`）+ AllTests `71/71 PASS`（见 `.godot/AllTests.log`） |

---

## 7. 变更记录（可选，便于回溯）

- 2026-01-06：创建本文件，作为后续整改单一事实来源（SSOT）。
