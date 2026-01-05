# 模块系统 V2（严格模式 / 内容与规则全模块化）

最后更新：2026-01-04

本文是 **模块系统 V2** 的最终设计方案（以“严格模式 + 零 fallback + 路线B”为核心），用于指导后续重构与实现。与旧的 `data/modules/*.json + core/modules/*_module.gd` 方案相比，V2 要求：

- **禁用模块 = 该模块内容在运行期完全不存在**（员工/里程碑/规则注册都不加载、不可引用）
- **所有阶段结算（Dinnertime/Payday/Marketing/Cleanup…）必须由模块注册**；若缺失 → **初始化直接失败**（你已确认）
- 员工/里程碑的供应池与可选集合 **从启用模块内容推导**（不再由 `GameConfig` 列硬编码列表，例如 `one_x_employee_ids`）

---

## 实现进度（落地追踪）

- ✅ M1：模块包目录与 `module.json` 严格解析/加载器
  - 代码：`core/modules/v2/module_manifest.gd`、`core/modules/v2/module_package_loader.gd`、`core/modules/v2/module_plan_builder.gd`
  - 目录：`modules/README.md`
  - 测试：`core/tests/module_package_loader_v2_test.gd`、`core/tests/module_plan_builder_v2_test.gd`（fixtures 在 `core/tests/fixtures/*`）
- ✅ M2：per-game `ContentCatalog`（替换全局静态 registry）
  - 代码：`core/modules/v2/content_catalog.gd`、`core/modules/v2/content_catalog_loader.gd`
  - 接入：`core/engine/game_engine.gd`（initialize 默认装配 V2 plan + catalog；已接管 employees/milestones/marketing/products/tiles/maps/pieces）
  - 模块：`modules/base_employees/`、`modules/base_milestones/`、`modules/base_marketing/`、`modules/base_products/`、`modules/base_pieces/`、`modules/base_tiles/`、`modules/base_maps/`（基础内容）
  - 测试：`core/tests/content_catalog_v2_test.gd`、`core/tests/module_system_v2_bootstrap_test.gd`
- ✅ M3：Pools 推导（路线B，移除 `one_x_employee_ids` 与 `employee_pool.base`）
- ✅ M4：SettlementRegistry（结算全模块化，缺失主结算器初始化失败）
  - 代码：`core/rules/settlement_registry.gd`、`core/modules/v2/ruleset.gd`、`core/modules/v2/ruleset_builder.gd`、`core/modules/v2/ruleset_loader.gd`
  - 接入：`core/engine/game_engine.gd`（V2 初始化时构建 Ruleset 并校验必需 primary settlements）
  - 改造：`core/engine/phase_manager.gd`（只走注册表；缺失直接失败；并提供 `get_marketing_rounds/get_marketing_range_calculator`）
  - 模块：`modules/base_rules/`（落盘 base_rules，注册 4 个必需 primary settlements）
  - 测试：`core/tests/settlement_registry_v2_test.gd`
- ✅ M4.1：MarketingSettlement 通用扩展字段（供模块规则组合）
  - `marketing_instance.products=[A,B,...]`：按顺序结算（每轮依次为 A/B/... 放置需求）
  - `marketing_instance.no_release=true`：到期时不释放忙碌营销员（例如品牌总监“忙碌到游戏结束”）
  - `marketing_instance.link_id`：多个营销实例共享同一营销员（例如营销经理第二张板件），最后一张到期才释放
- ✅ M4.2：基于结算日志触发里程碑事件（模块内完成）
  - 示例：模块可在 `Dinnertime enter` 的 extension settlement 中读取 `round_state.dinnertime.sales[]` 并触发自定义事件（如 `ProductSold`）以驱动里程碑领取（无 core 硬编码）
- ✅ M5：EffectRegistry（迁移 waitress/CFO 等硬编码）
  - 代码：`core/rules/effect_registry.gd`、`core/modules/v2/ruleset.gd`、`core/modules/v2/ruleset_builder.gd`（新增 `register_effect`）
  - 内容字段：`EmployeeDef.effect_ids`、`MilestoneDef.effect_ids`（`core/data/employee_def.gd`、`core/data/milestone_def.gd`）
  - 接入：V2 初始化阶段校验 “content 引用的 effect_id 必须有 handler”（缺失直接 init fail）
  - 迁移：`DinnertimeSettlement` 的平局链路/小费/CFO 加成改为通过 EffectRegistry 调用（无 legacy fallback）
  - 迁移：`PaydaySettlement` 的薪资折扣额度改为通过 EffectRegistry 调用（无 legacy fallback）
  - 迁移：`MarketingSettlement` 的 first_radio radio 需求量改为通过 EffectRegistry 调用（无 legacy fallback）
- ✅ M5.1：晚餐“路上购买”扩展点（用于 Coffee 等）
  - 新增：`core/rules/dinnertime_route_purchase_registry.gd`（模块可注册 provider；缺失/重复 fail-fast）
  - 严格校验：provider 返回结构必须满足类型约束（`purchases[*]` 为 Dictionary；`income_by_player` 为 `int->int>=0`，越界/错误类型直接 init/结算失败）
  - 接入：`core/rules/phase/dinnertime_settlement.gd`（每个房屋售卖前应用 provider，记录 `route_purchases` 并计入收入）
  - 新增：`RulesetV2.state_initializers`（模块可在 map bake 后补充 state 字段；Coffee 用于 `coffee_shops/tokens`）
  - 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（52/52）
- ✅ M6：移除旧模块系统 V1（`data/modules/*` + `core/modules/*`）与旧入口/测试；`GameEngine.initialize()` 收敛为仅接收 V2 modules 参数（`all_tests` 35/35 通过）

## 1. 目标与非目标

### 1.1 目标（Goals）

- 每个模块都有自己独立目录 + 描述文件（不会与其他模块混在一起）。
- 新开局时根据启用模块集合构建：
  - **ContentCatalog**：员工/里程碑/营销板件/板块/地图/建筑件等内容定义
  - **Ruleset**：阶段结算器、管道修饰器、钩子、校验器、效果处理器等
  - **Pools**：员工池、里程碑池（严格由 ContentCatalog 推导）
- **Fail Fast**：缺内容/缺能力/冲突/重复定义 → 初始化失败并给出可定位的错误。
- 保持 headless 测试可持续演进：每一步重构都能用 `tools/run_headless_test.sh` 回归验证。

### 1.2 非目标（Non-goals）

- 不是“Steam Workshop/在线下载模组”系统（先做离线目录包）。
- 不承诺对旧存档/旧数据格式兼容（与“零 fallback”一致）。

---

## 2. 模块包（Module Package）目录规范

统一放在：

- `res://modules/<module_id>/`

推荐结构（约定优于配置）：

```
res://modules/<module_id>/
  module.json           # manifest：依赖/冲突/入口脚本/能力声明等
  README.md             # 描述文件：玩法、包含内容、版本、注意事项
  assets/               # UI 资源（图片/图标等，可选；由 content/visuals 引用）
    map/
      ground/ roads/ pieces/ icons/
  content/              # 纯数据（JSON），按类型分目录
    employees/
    milestones/
    marketing/          # 可选：若该模块新增营销板件
    products/           # 可选：若该模块新增产品（food/drink 等）
    tiles/ maps/ pieces/ # 可选：若该模块新增地图相关内容（maps 为 MapOption：主题/选项，不含 grid/pool）
    visuals/            # 可选：视觉映射（UI 侧使用；缺失则占位渲染，Q12=C）
  rules/                # 规则脚本（注册 settlements / hooks / pipelines / effects）
    entry.gd
  tests/                # 可选：模块自带测试（core/tests 与 ui/scenes/tests 的补充）
```

约束：

- `module_id` 必须是稳定的 `snake_case`。
- **目录内的 JSON 是权威源**（仍遵循 ADR 0001：JSON 作为版本控制中的权威数据源）。
- `content/visuals` 仅承载“资源路径 + 渲染元数据”，不加载 Texture；UI 缺失图片允许占位继续运行（不影响核心规则）。

### 2.1 视觉资源（UI 可选）

- 加载：`core/modules/v2/visual_catalog_loader.gd`（从 `modules/*/content/visuals/*.json` 构建 `VisualCatalog`）
- UI 贴图：`ui/visual/map_skin_builder.gd`（构建 `MapSkin`，缺失资源用占位贴图继续渲染，Q12=C）
- 说明：视觉资源不影响核心规则初始化；Strict Mode 仍只约束“规则/内容引用必须存在”
- 约定（key 命名）：
  - `cell_visuals`：`ground`/`blocked`（后续可扩展更多 cell feature）
  - `road_visuals`：`end`/`straight`/`corner`/`tee`/`cross`；bridge 变体为 `bridge_<shape>`（运行时旋转绘制）
  - `piece_visuals`：key = `piece_id`（例如 `house`/`house_with_garden`/`restaurant`）
  - `product_icons`：key = `product_id`（例如 `beer`/`pizza`）
  - `marketing_visuals`：key = marketing `type`（例如 `billboard`/`radio`/`mailbox`/`airplane`），并保留 `default` fallback

---

## 3. module.json（Manifest）建议字段

建议采用显式 schema（便于 fail-fast 校验）：

```json
{
  "schema_version": 1,
  "id": "night_shift_managers",
  "name": "夜班经理",
  "version": "1.0.0",
  "priority": 100,
  "dependencies": ["base_rules", "base_employees"],
  "conflicts": [],
  "entry_script": "res://modules/night_shift_managers/rules/entry.gd",
  "provides": {
    "effects": ["employee_effect:working_multiplier_no_salary"]
  }
}
```

说明：

- `priority` 只用于 **确定性排序**（日志/调试稳定），不用于“自动覆盖冲突”。冲突应通过 `conflicts`/用户选择解决，否则 **fail**。
- `provides` 用于能力校验与错误信息聚合（见第 6 节）。

---

## 4. 严格模式（Strict Mode）行为定义

### 4.1 内容严格性（员工/里程碑“完全不存在”）

对任意一局游戏，运行期只存在：

- 由“启用模块集合（含依赖闭包）”加载得到的 `ContentCatalog`
- 由“启用模块集合”注册得到的 `Ruleset`

因此：

- 未启用模块的员工/里程碑 **不会被加载进任何 registry**（不在内存，不可查询）。
- 若任何配置/规则脚本引用了未加载的 `employee_id` / `milestone_id` → **初始化失败**（而不是运行期默默忽略或回退）。

### 4.2 决定性（Determinism）

- 模块解析顺序必须稳定：拓扑排序（依赖优先） + `(priority, id)` 稳定排序。
- ContentCatalog 的加载顺序稳定：目录枚举按文件名排序；但**重复 ID 直接报错**，不依赖“先后覆盖”。
- 若存在任何“随机抽取/洗牌/随机选择”的行为，必须使用 `RandomManager`，并记录到命令/状态中（保证回放一致）。
- 地图随机拼接同样视为“必须可重放”的随机行为：模块 `content/maps/*.json` 提供的是 **MapOptionDef（地图主题/选项）**；初始化阶段由 Ruleset 注册的 **primary map generator** 生成运行期 `MapDef`（包含 `grid_size` 与 `tiles[]` placements）。随机模式下 tile_pool 来自本局 `ContentCatalog.tiles`（按文件夹枚举的全部 tiles，排序后用本局 `RandomManager(seed)` 洗牌并**不放回**取前 N 张）；`random_rotation=true` 时每个板块 rotation 从 `[0,90,180,270]` 随机选；若 tiles 数量不足以覆盖 `grid_size.x * grid_size.y` → **初始化失败**。

---

## 5. “路线B”：供应池从模块内容推导（移除 one_x_employee_ids）

### 5.1 员工数据新增 pool 元数据（示意）

员工定义需要描述“如何进入供应池”，避免再由 `GameConfig` 列表硬编码：

```json
{
  "id": "cfo",
  "name": "cfo",
  "...": "...",
  "pool": {
    "type": "one_x"
  }
}
```

对固定数量的员工：

```json
{
  "id": "recruiter",
  "...": "...",
  "usage_tags": ["use:recruit"],
  "recruit_capacity": 1,
  "pool": {
    "type": "fixed",
    "count": 12
  }
}
```

池构建器（PoolBuilder）规则（你已确认 Q1=A，不做随机抽取）：

- `pool.type == "fixed"`：加入 `employee_pool[employee_id] += pool.count`
- `pool.type == "one_x"`：加入 `employee_pool[employee_id] += one_x_copies_by_player_count[player_count]`

> `one_x_copies_by_player_count[player_count]` 是“规则常量”，建议放在 `GameConfig.rules`（Q3=B）。

补充：员工行动次数/能力建议也尽量由数据驱动描述（严格模式）：

- Recruit：员工 `usage_tags` 包含 `use:recruit` 时，必须提供 `recruit_capacity>0`，由规则层汇总得到本回合 Recruit 子阶段总招聘次数（避免写死 CEO/招聘专员等特殊规则）。

### 5.2 里程碑池同理

里程碑定义同样建议增加 `pool` 元数据（例如 `enabled: true`），由启用模块集合推导出 `milestone_pool`（禁用模块则不会加载这些里程碑）。

---

## 6. Ruleset：结算器、钩子与“可插拔效果”的统一注册

### 6.1 必需能力（缺失则初始化失败）

本项目的基础对局启动，至少需要下列“主结算器（Primary Settlement）”：

- `Dinnertime`：enter-settlement
- `Payday`：exit-settlement
- `Marketing`：enter-settlement（在 `before_enter` hooks 之后、`after_enter` hooks 之前执行）
- `Cleanup`：enter-settlement

规则：

- 每个必需点位 **必须且只能有 1 个 primary settlement**
- 0 个 → 初始化失败（你已确认）
- >1 个 → 初始化失败（要求通过模块冲突/选择消解，不做优先级覆盖）

### 6.2 SettlementRegistry（结算注册）

引入 `SettlementRegistry`（属于 Ruleset），提供类似：

- `register_primary(phase, point, callable, source_module_id)`
- `register_extension(phase, point, callable, priority, source_module_id)`（可选：用于“在主结算前/后插一步”）

PhaseManager 只负责：

- 推进阶段与子阶段
- 调用 hooks
- 根据“结算触发点映射”调用 `SettlementRegistry` 中对应 settlement（默认映射保持基础规则一致，但允许模块覆盖/重排）

> 结算器不再由 `PhaseManager` 直接 `preload()` 具体脚本；由模块注册提供实现，从而满足“结算也可模块化”的要求。

#### 6.2.1 Settlement Triggers（结算触发点映射，可 override）

默认情况下，PhaseManager 会在以下时点触发结算（与基础规则一致）：

- `Dinnertime`：enter → `Point.ENTER`
- `Marketing`：enter → `Point.ENTER`（且在 `BEFORE_ENTER` hooks 之后）
- `Cleanup`：enter → `Point.ENTER`
- `Payday`：exit → `Point.EXIT`

模块可以通过 Ruleset 注册覆盖映射（例如为 `OrderOfBusiness` 增加一个 enter 结算，或调整某阶段的 enter/exit 触发点），接口：

- `register_settlement_triggers_override(phase, timing, points, priority=100)`
  - `timing` 为 `"enter"` 或 `"exit"`
  - `points` 为 `Array[int]`，每个元素是 `SettlementRegistry.Point.*`
  - `points=[]` 表示移除该阶段对应时点的触发

严格约束：

- 必需的 primary settlements（例如 `Dinnertime:enter`、`Payday:exit`、`Marketing:enter`、`Cleanup:enter`）必须同时满足：
  - settlement_registry 中存在 primary
  - 且在触发点映射中“被安排会触发”（否则 init fail）

### 6.3 通用“效果系统”：消除 waitress/CFO 等硬编码

为避免在结算逻辑中写死员工 ID（例如 `waitress`、`cfo`），建议引入 **EffectRegistry**：

- 员工/里程碑数据声明 `effect_ids: [effect_id...]`
- 模块在 `rules/entry.gd` 中注册 `effect_id -> handler`
- 结算/管道在运行时根据“当前玩家拥有的 effect 集合”应用处理器

建议将 effect 的“触发点”做成可组合的 **segment**（通过字符串匹配触发），例如当前 `DinnertimeSettlement` 已使用：

- `:dinnertime:tiebreaker:`：平局链路加分
- `:dinnertime:tips:`：女服务员小费（可被里程碑覆盖）
- `:dinnertime:income_bonus:`：回合收入加成（如 CFO）
- `:dinnertime:distance_delta:`：距离修正（如番茄酱机制）
- `:dinnertime:sale_house_bonus:`：每次“成功向一个房屋售卖”后的额外奖金（如薯条厨师）

约定：`effect_id` 必须包含对应 segment，且遵循 `module_id:...` 命名规范。

示例（概念级）：

- waitress：
  - `effect_ids`: `["base_rules:dinnertime:tiebreaker:waitress", "base_rules:dinnertime:tips:waitress"]`
- cfo：
  - `effect_ids`: `["base_rules:dinnertime:income_bonus:cfo"]`
- first_radio：
  - `effect_ids`: `["base_rules:marketing:demand_amount:first_radio"]`

这样：

- waitress/CFO 的行为来自模块注册的 handler，可被替换/扩展
- 若禁用提供该 handler 的模块，但仍有数据引用该 `effect_id` → 初始化失败（Fail Fast）

### 6.4 MilestoneEffectRegistry（里程碑 effects.type 一次性效果）

除 `effect_ids`（持续效果）外，里程碑 JSON 还包含：

- `effects: [{type, value?, target? ...}]`：**里程碑达成时立刻应用一次**的效果（例如 `gain_card` / `ban_card`）。

为避免 `effects.type` 分散读取与“静默 no-op”，引入 **MilestoneEffectRegistry**：

- 模块在 `rules/entry.gd` 中注册 `effects.type -> handler`
- `MilestoneSystem.process_event(...)` 在成功 claim 里程碑后，逐个调用 handler 应用效果
- 严格模式：任意模块内容引用的 `effects.type` 若缺 handler → 初始化失败（Fail Fast）

> 备注：若某些 `effects.type` 属于“持续效果”（由其他规则代码在结算时读取并应用），仍需显式注册 handler（可为 no-op）以通过严格校验，并避免未来遗漏。

### 6.5 Employee Patch（受控修改员工定义）

为支持“跨模块培训链”等需求，V2 允许模块在 ruleset 装配阶段对已加载的员工定义做受控 patch：

- 接口：`RulesetRegistrarV2.register_employee_patch(target_employee_id, patch)`
- 严格模式：目标员工不存在或 patch 格式非法 → 初始化直接失败（Fail Fast）
- 当前支持字段（最小集）：
  - `add_train_to: Array[String]`：向 `EmployeeDef.train_to` 追加（去重）

### 6.6 Phase/SubPhase Hooks（阶段钩子）

为支持“夜班经理”等需要在进入阶段时写入 `round_state` 的模块，V2 允许模块注册 PhaseManager hooks：

- 接口：
  - `RulesetRegistrarV2.register_phase_hook(phase, hook_type, callback, priority)`
  - `RulesetRegistrarV2.register_sub_phase_hook(sub_phase, hook_type, callback, priority)`
- 装配：初始化阶段 `RulesetV2.apply_hooks_to_phase_manager(phase_manager)` 将 hooks 写入 PhaseManager。
- 决定性：同一个 `(phase/sub_phase, hook_type, priority)` 下，按 `source module_id` 排序，避免非稳定排序导致回放不一致。

#### 6.6.1 SubPhase Orders（子阶段顺序，可扩展/可 override）

PhaseManager 仍保留 core 的默认阶段与 Working 基础子阶段集合，但允许模块以“可控方式”调整子阶段：

- Working：
  - 插入：`register_working_sub_phase_insertion(sub_phase_name, after, before, priority)`
  - 重排：`register_working_sub_phase_order_override(order_names, priority)`
  - 严格约束：最终顺序必须包含所有基础 Working 子阶段（缺失/重复直接 init fail）。
- Cleanup：
  - 插入：`register_cleanup_sub_phase_insertion(sub_phase_name, after, before, priority)`（仅对自定义 Cleanup 子阶段序列生效）
  - 重排：`register_cleanup_sub_phase_order_override(order_names, priority)`
- 其它阶段（例如 Payday/Marketing/OrderOfBusiness）：
  - `register_phase_sub_phase_order_override(phase, order_names, priority)`：为某阶段定义一个“按名称的子阶段序列”
  - `register_named_sub_phase_hook(sub_phase_name, hook_type, callback, priority)`：为按名称子阶段注册 hooks（不绑定 phase，建议命名避免冲突）

RoundState 记录：

- Working：`round_state.working_sub_phase_order`
- Cleanup：`round_state.cleanup_sub_phase_order`
- 其它阶段：`round_state.phase_sub_phase_orders[phase_name] = Array[String]`

### 6.7 Action Availability（动作可用性，可 override）

为避免“动作允许在哪个阶段/子阶段执行”由 core 的 ActionExecutor 写死，新增 **ActionAvailabilityRegistry**：

- 默认从每个 `ActionExecutor.allowed_phases / allowed_sub_phases` 推导（保持现有行为）
- 模块可按 `action_id` 覆盖其可用点位（实现“动作可用性也可模块化注册”）
- 严格模式：覆盖指向不存在的 `action_id` → **初始化失败**

接口（Ruleset）：

- `register_action_availability_override(action_id, points, priority=100)`
  - `points` 为 `Array[Dictionary]`，每项 `{phase: String, sub_phase: String}`（`sub_phase=""` 表示该 phase 的任意子阶段）
  - 同一 `action_id` 若多模块覆盖：取 `priority` 更高者（同优先级按 `module_id` 稳定排序）

执行语义：

- 引擎执行命令时会先检查 `ActionAvailabilityRegistry`，若动作在当前 `(phase, sub_phase)` 不可用则直接失败（Fail Fast）
- 兼容旧语义：当 `state.sub_phase==""` 时，忽略子阶段限制（仅按 phase 过滤）

### 6.8 Pending Phase Actions（阶段内待处理动作）

为支持“本阶段结算后立刻要求玩家执行若干动作，未完成前禁止推进阶段”的规则点，提供一个最小的通用机制：

- 模块可在任意规则/结算中写入 `round_state.pending_phase_actions[phase_name] = Array`（由模块自定义条目结构）。
- `PhaseManager.advance_phase(...)` 会在推进前检查：若当前阶段对应的 Array 非空，则返回失败（严格阻断推进）。
- 由模块的动作执行器负责弹出/清空对应条目（清空后即可继续推进）。

约束建议：

- 该机制只负责“阻断推进”，不规定 UI/动作形态；模块仍需自行注册动作并保证回放确定性。

---

## 7. 建议的基础模块拆分（base_rules 等）

### 7.1 推荐的“可玩基线”模块集合（不强制）

为了能启动基础对局，推荐默认勾选：

- `base_rules`：提供所有必需的 primary settlements + 基础规则管道 + 基础 effect handlers
- `base_employees`：提供基础员工 JSON（含 `pool`/`effects` 元数据）
- `base_milestones`：提供基础里程碑 JSON（含 `pool`/触发器定义）

说明：

- 引擎不会强制启用任何模块；但若缺失必需能力/内容 → **初始化失败**（严格模式）。

### 7.2 base_rules 建议职责（你要求给出建议）

`base_rules` 应至少包含：

- `SettlementRegistry` 必需主结算器：
  - `dinnertime_enter`
  - `payday_exit`
  - `marketing_enter`
  - `cleanup_enter`
- 基础管道与可扩展点（供其他模块注册）：
  - `PricingPipeline`（价格修饰器）
  - `MarketingRangeCalculator`（营销范围）
  - `DinnertimeTiebreakers`（平局规则链）
  - `Income/Cost modifiers`（收入/成本修饰链）
- 基础效果 handlers（对齐 base_employees/base_milestones 中声明的 effect_id）

---

## 8. 初始化装配流程（Fail Fast）

建议 `GameEngine.initialize()` 的新流程（概念级）：

1. 读取“玩家选择的模块列表”（UI/命令行/测试场景提供）
2. 解析模块闭包（dependencies）并做冲突检查（conflicts）
3. 按确定性顺序加载 module.json，并构建 `ModulePlan`（顺序、来源、版本）
4. 从启用模块加载 `ContentCatalog`（employees/milestones/marketing…）
   - 重复 ID → fail
5. 构建 `Ruleset`（执行每个模块的 `entry_script.register(builder)`）
6. 校验必需能力：
   - 缺 primary settlement / effect handler / pipeline 关键点 → fail
7. 构建 Pools（employee_pool / milestone_pool）并创建初始 `GameState`
8. 将 `ModulePlan`（id/version/hash）写入 `state.modules` 或新的 `state.module_plan`（用于存档/回放校验）

---

## 9. 分阶段重构落地计划（建议）

为降低一次性重构风险，建议按阶段推进（每阶段都加 headless 回归）：

1. **引入 Module Package 目录与 Manifest 解析器**（不改现有运行时逻辑，只做并行能力）
2. **引入 ContentCatalog（按启用模块加载）**，并逐步替换 `EmployeeRegistry/MilestoneRegistry/MarketingRegistry` 的静态全局缓存
3. **实现 PoolBuilder（从员工/里程碑数据推导）**，删除 `GameConfig.employee_pool.one_x_employee_ids` 等字段与相关解析
4. **引入 SettlementRegistry + PhaseManager 改为“调用注册表”**，并将 base_rules 模块接入（缺失则 init fail）
5. **抽离硬编码员工效果为 EffectRegistry**（先迁移 waitress/CFO，再扩展到更多员工/里程碑）
6. 删除旧模块系统与旧数据目录的残留入口（`data/modules`、旧 registry 静态缓存等）

每个阶段的测试要求：

- 优先把新能力写成 `core/tests/*_test.gd`，并挂到 `ui/scenes/tests/all_tests.tscn`
- 统一用 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`
