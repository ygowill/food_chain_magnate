# Core 与 Modules 代码审计报告（冗余 / 兜底 / 模块耦合）

更新时间：2026-01-15  
审计范围：`core/`（含 `core/modules/v2/`、`core/rules/`、`core/state/`、`core/map/`）+ `modules/`（各模块 `rules/`、`actions/`）

说明（重要）：
- 当前工作区存在大量**未提交改动**（来自另一个正在工作的 agent）。本报告**不以这些未提交改动为整改目标**，主要聚焦于其余部分的层次边界、模块耦合与“过度兜底/吞错”风险。
- 引用的行号基于本次审计时的工作区快照；若后续文件有改动，行号可能漂移。

## 整改进度追踪（本文件内更新）

约定：
- 每完成一个路线图子任务（A1/A2/A3/B1...），都在本节追加一条日志，并同步更新 checklist 状态。
- 日志尽量包含：变更点（文件/要点）、测试命令与结果（PASS/FAIL）。

### Checklist（按路线图阶段）

- [x] A1（P0.2）修复起始库存 guard（`starting_inventory` 字段误判为 method）+ 补 core test + 接入 AllTests
- [x] A2（P0.1）移除 Payday token 支付对 `coffee` 的硬编码，改为 ProductDef 标签/字段驱动 + 补测试 + 接入 AllTests
- [x] A3（P0.3）删除 new_milestones 的 `player_has_milestone` 重复实现，统一走 core（拒绝吞错）
- [x] B1（P1.4）收紧 hooks/settlement 回调契约：非 Result 返回至少 warning（DebugFlags 下升级为 failure）
- [x] B2（P1.4）补 headless test：注册返回非 Result 的 hook/settlement，期望测试失败（防回归）
- [x] C1（P1.8）落盘 `state.map/state.round_state` schema contract（core-owned/shared/module-owned）
- [x] C2（P1.8）引入 `StateSchemaRegistry`（或 RulesetV2 扩展）：模块注册持久化字段与 key 归一化规则
- [x] C3（P1.5/P1.6）迁移跨模块窥探到 registry/helper（offramp/airplane/global_effect_ids 等）
- [x] D1（P2.1）抽取 `_parse_int_value` 等重复 helper（可选）

### Checklist（后续治理：按 P1/P2 原序号继续）

- [x] E1（P1.1）将 `EventBus` autoload 从 `core/` 移到 `autoload/` 并更新 `project.godot`
- [x] E2（P1.2）将 `EmployeeDef` 的 UI 颜色映射下沉到 UI/Theme 层（core 不含颜色）
- [x] E3（P1.3）marketing 类型/范围算法去 core hardcode，改为 registry/module 驱动
- [x] E4（P2.2）抽取 Map/Marketing 冲突查询 helper（减少模块手工遍历/字段解析）
- [x] E5（P2.3）统一 provider API 返回类型（Array vs Result），或提供严格/容错双接口并文档化

### Checklist（延伸治理：继续按后续 TODO 1/2/3 顺序）

- [x] F1 收敛 `state.map.marketing_placements` 的遍历/字段解析：更多调用点统一通过 `MarketingPlacementQuery`
- [x] F2 进一步统一 registry/provider API（Result 优先 + legacy 兼容）并补契约测试防回归
- [x] F3 加强 `StateSchemaRegistry` 覆盖：模块自有 key 必须显式注册（或提供自动检测/告警）

### 变更日志

- 2026-01-15 初始化整改追踪区（待开始）
- 2026-01-15 A1（P0.2）修复 `core/state/game_state_factory.gd` 起始库存读取（移除错误 `has_method` guard），新增 `core/tests/game_state_factory_starting_inventory_test.gd` 并接入 `ui/scenes/tests/all_tests.gd`（AllTests PASS）
- 2026-01-15 A2（P0.1）移除 `core/rules/phase/payday_settlement.gd` 对 `coffee` 的字符串特例，改为 `ProductDef.tags` 驱动（`salary_token_ineligible`）；更新 `modules/coffee/content/products/coffee.json` 并新增 `core/tests/payday_salary_token_eligibility_test.gd` 接入 AllTests（AllTests PASS）
- 2026-01-15 A3（P0.3）删除 `modules/new_milestones/rules/utils.gd` 中吞错版 `player_has_milestone`，改为模块内统一调用 `StateUpdater.player_has_milestone(...)`（AllTests PASS）
- 2026-01-15 运行 headless 全量测试：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` -> PASS（79/79）
- 2026-01-15 B1（P1.4）收紧回调契约：`core/engine/phase_manager/hooks.gd` 与 `core/rules/settlement_registry.gd` 对非 Result 返回记录 warning；`DebugFlags.is_debug_mode()` 下升级为 failure（AllTests PASS）
- 2026-01-15 B2（P1.4）新增 `core/tests/callback_result_contract_test.gd`：注册返回非 Result 的 hook/settlement 并断言契约生效，已接入 AllTests（AllTests PASS）
- 2026-01-15 运行 headless 全量测试：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 120` -> PASS（80/80）
- 2026-01-15 C3（P1.5）新增 `core/rules/placement_conflict_registry.gd` 并接入模块系统 V2；`rural_marketeers` 注册 offramp 冲突 provider；`gourmet_food_critics`/`lobbyists` 改为通过 registry 查询，移除对 `state.map["rural_marketeers_offramps"]` 的跨模块窥探；更新 `core/tests/gourmet_food_critics_v2_test.gd`（AllTests PASS）
- 2026-01-15 C3（P1.6）新增 `core/rules/global_effect_list.gd`；`modules/lobbyists/rules/entry.gd` 与 `core/rules/phase/dinnertime/dinnertime_effects.gd` 改为通过 helper 读写/校验 `global_effect_ids`（AllTests PASS）
- 2026-01-15 C1（P1.8）新增文档 `docs/architecture/33a-core-state-schema-contract.md`，并更新 `docs/architecture/README.md`（落盘 state 扩展字段契约与模块扩展面约束）
- 2026-01-15 C2（P1.8）完善 `StateSchemaRegistry` 并接入反序列化：按模块注册的 int-key schema 对 `round_state/map` 归一化；`core/engine/game_engine/loader.gd` 改为先装配模块系统 V2 再 `GameState.from_dict`；修复相关模块（coffee/lobbyists/rural_marketeers/new_milestones/night_shift_managers）schema 常量/类型推断导致的编译错误；新增 `core/tests/state_schema_archive_load_test.gd` 并接入 AllTests（AllTests PASS 81/81）
- 2026-01-15 C3（P1.5/P1.6）复核：offramp 冲突与 global_effect_ids 已统一迁移到 `PlacementConflictRegistry` / `GlobalEffectList`（无跨模块 state key 窥探）；更新 checklist 状态（AllTests PASS 81/81）
- 2026-01-15 D1（P2.1）移除模块内重复 `_parse_int_value`：`modules/gourmet_food_critics/rules/entry.gd`、`modules/rural_marketeers/rules/entry.gd`、`modules/rural_marketeers/actions/place_highway_offramp_action.gd` 改用 `core/state/serialization/parse_helpers.gd`（AllTests PASS 81/81）
- 2026-01-15 E1（P1.1）将 `EventBus` 从 `core/events/event_bus.gd` 移动到 `autoload/event_bus.gd` 并更新 `project.godot` autoload 路径（AllTests PASS 81/81）
- 2026-01-15 E2（P1.2）将员工职责颜色映射从 `core/data/employee_def.gd` 下沉到 `ui/visual/employee_role_colors.gd`；UI 组件改为通过该脚本取色（AllTests PASS 81/81）
- 2026-01-15 E3（P1.3）`base_marketing` 增加 rules entry 注册 billboard/mailbox/radio/airplane 的 marketing_type handler；`core/rules/marketing_range_calculator.gd` 去掉内置 match 分支，统一走 `MarketingTypeRegistry`；`core/rules/marketing_type_registry.gd` reset 不再注册 builtin（AllTests PASS 81/81）
- 2026-01-15 E4（P2.2）新增 `core/map/marketing_placement_query.gd` 封装 marketing_placements 查询；`lobbyists`/`rural_marketeers`/`new_milestones` 移除手工遍历与字段解析，统一通过 helper 查询 airplane/占用（`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180` -> PASS 81/81）
- 2026-01-15 E5（P2.3）`core/rules/dinnertime_demand_registry.gd` provider 允许返回 `Result` 或 legacy `Array`（推荐 Result）；`core/rules/phase/dinnertime_settlement.gd` 合并 demand registry warnings（`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180` -> PASS 81/81）
- 2026-01-15 F1 继续收敛 marketing_placements 查询：`modules/new_milestones/actions/place_pizza_radio_action.gd`、`modules/new_milestones/actions/place_campaign_manager_second_tile_action.gd`、`modules/new_milestones/actions/place_new_restaurant_mailbox_action.gd`、`gameplay/actions/initiate_marketing/validation.gd` 移除“遍历 placements 查 world_pos”逻辑，统一改用 `core/map/marketing_placement_query.gd`（`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180` -> PASS 81/81）
- 2026-01-15 F2 新增契约测试 `core/tests/dinnertime_demand_registry_v2_test.gd`：Demand provider 允许返回 `Result(Array)` 或 legacy `Array`，并确保 warnings 可透传；已接入 AllTests（`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180` -> PASS 82/82）
- 2026-01-15 F3 `core/state/state_schema_registry.gd` 增加“模块自有字段 string 玩家 key”检测告警；`core/state/game_state_serialization.gd` / `core/state/game_state.gd` / `core/engine/game_engine/loader.gd` 传播反序列化 warnings；新增 `core/tests/state_schema_unregistered_module_key_warning_test.gd` 并接入 AllTests（`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 180` -> PASS 83/83）

## 结论概览

当前代码结构总体方向是正确的：`core/` 大部分为可复用的引擎/规则逻辑，`modules/` 通过 RulesetV2 注册扩展点接入。主要问题集中在：
- **个别 core 逻辑仍出现“按模块特例硬编码”**（破坏模块隔离）。
- **hooks/settlement 回调契约不严格**（非 `Result` 返回被静默忽略，导致吞错）。
- **模块之间通过 `state.map/state.round_state` 的“隐式 key 契约”产生耦合**（跨模块窥探彼此状态结构）。
- **序列化后字典 key 类型变化（int -> string）**与“运行时强断言/强假设”之间存在断裂，影响加载存档后的稳定性。

下面按优先级列出问题与整改方案。

---

## P0（必须优先修复）

### P0.1 core 出现模块特例：Payday 用 token 支付时硬编码排除 `coffee`

证据：
- `core/rules/phase/payday_settlement.gd:191`：`_count_food_drink_tokens()` 中 `if product_id == "coffee": continue`
- `core/rules/phase/payday_settlement.gd:246`：`_pay_with_tokens()` 中 `if pid == "coffee": continue`

问题：
- `core/` 的工资结算属于“基础规则/引擎层”能力，不应对某个模块产品 id（`coffee`）做硬编码分支。否则：
  - 模块隔离被破坏：新增/替换产品体系时，core 仍带着历史模块特例。
  - 行为可解释性下降：读 core 代码时无法通过“产品定义/标签”推导规则，只能猜“为什么 coffee 被排除”。

整改建议（最小风险）：
- 将“可用于薪资 token 支付”的资格变成**数据驱动**：
  1) 在 `ProductDef` 增加明确字段（例如 `counts_as_salary_token: bool`），或增加标签（例如 `salary_token_eligible` / `salary_token_ineligible`）。
  2) `PaydaySettlement` 仅按该字段/标签判定，不再写死 `coffee`。
  3) Coffee 模块在其产品定义里声明 `coffee` 不可用于薪资 token（如果这确实是规则要求）。
- 补测试：
  - 启用/不启用 coffee 模块时，Payday token 逻辑都保持一致且可预测（不依赖字符串特例）。

---

### P0.2 起始库存逻辑被“错误兜底”静默禁用（字段误判为 method）

证据：
- `core/state/game_state_factory.gd:143`：`if def != null and def.has_method("starting_inventory"):` 然后读取 `def.starting_inventory`

问题：
- `starting_inventory` 是字段（property），不是方法。`has_method("starting_inventory")` 将几乎永远为 false，导致所有产品的起始库存默认为 0（即使定义里配置了非零）。
- 这是典型的“过度兜底 + 静默失败”：逻辑看起来在“兼容缺字段”，实际把正确数据通道关闭了。

整改建议（最小风险）：
- 直接移除错误 guard，或改成正确的字段访问策略：
  - 若 `ProductDef` 保证始终有该字段：直接 `v = int(def.starting_inventory)`。
  - 若确实存在老数据/不同类型 def：用 `def.get("starting_inventory", 0)`（但要明确类型校验，避免再次静默吞错）。
- 补测试：
  - 构造一个 `ProductDef.starting_inventory = 2` 的产品，`GameStateFactory` 创建玩家时应写入初始库存。

---

### P0.3 模块重复实现 core 逻辑 + 过度兜底吞错：`player_has_milestone`

证据：
- 模块版本（吞错）：`modules/new_milestones/rules/utils.gd:3`（任何结构/类型异常都直接 `return false`）
- core 严格版本：`core/state/state_updater/employees_and_milestones.gd:107`（assert + 明确结构要求）

问题：
- 同一个领域规则（玩家是否拥有里程碑）在 core 与模块出现两套语义：
  - core：fail-fast（断言/严格结构）
  - module：fail-silent（出错当作“没有”）
- 这会导致“状态结构坏了”时行为不可预测：某些路径直接暴露错误、某些路径继续运行但结果错误（更难排查）。

整改建议（最小风险）：
- 删除 `modules/new_milestones/rules/utils.gd:3` 的重复实现，统一改为调用 `StateUpdater.player_has_milestone(...)`（或直接调用 `EmployeesAndMilestones.player_has_milestone`）。
- 若模块确实需要“非阻断查询”，也不要 `return false` 吞错：
  - 返回 `Result`，由调用方决定是否降级；
  - 或在降级时至少记录 warning（可 greppable）。

---

## P1（结构性耦合/边界问题：会持续制造维护成本）

### P1.1 core 内部放置了 Node/autoload（边界泄漏）

证据：
- `autoload/event_bus.gd:4`：`extends Node`
- `project.godot:26`：`EventBus="*res://autoload/event_bus.gd"`

问题：
- 依据仓库约定：`core/` 应尽量避免 UI/Node 依赖，以保持可复用与可测试性。
- `EventBus` 作为 autoload Node 更像是“应用层设施”，放在 `autoload/` 更符合分层（目前 `GameLog/DebugFlags/Globals/SceneManager` 都在 `autoload/`）。

整改建议：
- 将 `EventBus` 移动到 `autoload/`（或 `ui/` 下的全局脚本目录）并更新 `project.godot`。
- 若 core 需要事件机制：在 core 内保留纯逻辑的“事件记录/回放结构”（RefCounted），由应用层 Node 负责桥接。

整改结果：
- 已完成（见变更日志 E1）

---

### P1.2 UI 展示映射混入 core 数据类型（EmployeeDef 含颜色表）

证据：
- 颜色映射已下沉到 UI 层：`ui/visual/employee_role_colors.gd:1`
- UI 使用：`ui/components/employee_card/employee_card.gd:6` 等通过 `EmployeeRoleColors` 获取展示色

问题：
- “颜色 hex”属于 UI 表现层；放入 core 会让 core 无法脱离 UI 语义独立演进（例如换主题/换配色/换表达方式）。
- 注释中还提到“部分规则依赖颜色”（例如 new_milestones 里提到“颜色不变”），这进一步把 UI 表现与规则语义绑死。

整改建议（推荐方案）：
- core 只保留稳定枚举/分类：例如 `role`（或 `color_id` 作为“印刷颜色类别”的稳定 id）。
- UI 层维护 `role/color_id -> Color` 的映射（可在 `ui/` 或 `data/theme/`）。
- 若规则确实依赖“颜色不变”：规则应依赖 `color_id`（稳定语义），而不是依赖某个 UI hex 值。

整改结果：
- 已完成（见变更日志 E2）

---

### P1.3 marketing 类型仍有 core 硬编码（弱化“registry-first”的模块化）

证据：
- `modules/base_marketing/module.json`：增加 `entry_script`，由模块注册基础 marketing type
- `modules/base_marketing/rules/entry.gd:1`：注册 billboard/mailbox/radio/airplane 的 range handler
- `core/rules/marketing_range_calculator.gd:1`：统一走 `MarketingTypeRegistry.get_range_handler(...)`

问题：
- 当前同时存在两套扩展机制：
  - core 内置 match 分支（强耦合）
  - registry handler（可扩展）
- 这会让“base marketing 也是模块”的目标无法彻底落地：基础类型仍绑定在 core。

整改建议（分步、低风险）：
1) 让 base 模块（`modules/base_marketing`）在 ruleset 注册 billboard/mailbox/radio/airplane 的 handler；
2) `MarketingRangeCalculator` 移除 `match`，统一走 `MarketingTypeRegistry.get_range_handler(type)`；
3) `MarketingTypeRegistry.reset()` 不再注册 builtin（或仅注册空壳，强制由 ruleset 配置填充）。

整改结果：
- 已完成（见变更日志 E3）

---

### P1.4 hooks/settlement 回调允许非 Result 返回并被静默忽略（吞错）

证据：
- `core/engine/phase_manager/hooks.gd:181`：`_run_hooks()` 仅在 `result is Result` 时处理，否则当作成功
- `core/rules/settlement_registry.gd:58`：`run()` 对 primary/extension 同样仅在 `r is Result` 时处理，否则静默成功

问题：
- 这会把“回调实现错误（忘记 return Result / 返回了 bool/null）”变成**无声失败**：
  - 该回调的错误不会中断流程
  - warning 不会被记录
  - 表现可能是状态缺字段、后续规则崩溃，定位成本高

整改建议：
- 收紧契约：所有 hooks/settlement callback 必须返回 `Result`。
- 兼容期策略（二选一）：
  1) 严格：非 `Result` 直接 `Result.failure("... must return Result")`
  2) 过渡：非 `Result` 记录 warning（含 source/phase/point/callback），并在 DebugFlags 下升级为 failure

---

### P1.5 模块之间通过 `state.map` key 产生隐式耦合（模块-模块耦合）

典型证据 1：`gourmet_food_critics` 直接读取 `rural_marketeers` 的状态 key
- `modules/gourmet_food_critics/rules/entry.gd:105`：读取 `state.map["rural_marketeers_offramps"]` 来做互斥校验

典型证据 2：`lobbyists` 也直接读取相同 key
- `modules/lobbyists/actions/place_lobbyists_extra_map_tile_action.gd:190`：读取 `state.map["rural_marketeers_offramps"]` 来禁止扩边

问题：
- 这种做法本质是“模块 A 通过另一个模块 B 的私有存储结构推断世界状态”，隐含契约包括：
  - key 名称固定
  - value 类型固定（Array[Dictionary]）
  - Dictionary 内结构固定（例如 `{"pos": Vector2i}`）
- 一旦 rural_marketeers 重构数据结构，gourmet/lobbyists 会无感损坏；而依赖关系不会在 module.json 里体现（难以组合测试）。

整改建议（更可维护的扩展面）：
- 引入 core-owned 的“查询/约束”扩展点，替代跨模块窥探：
  - 例：新增 `MapOccupancyRegistry`/`PlacementConflictRegistry`
  - rural_marketeers 注册 “offramp 占用格” 提供者
  - gourmet_food_critics / lobbyists 只调用 core API 查询“某世界格是否被外部 piece 占用/冲突”
- 如果短期不想引入 registry：至少将 `rural_marketeers_offramps` 视为**公共协议字段**并落盘到文档（类型、字段、含义、版本迁移），避免“私有结构被读取”。

---

### P1.6 “全局效果 global_effect_ids”作为共享总线：生命周期/归属不清

证据：
- 写入：`modules/lobbyists/rules/entry.gd:90` 将 effect ids 写到 `state.map["global_effect_ids"]`
- 读取：`core/rules/phase/dinnertime/dinnertime_effects.gd:135` 同时从 `state.round_state` 与 `state.map` 读取 `global_effect_ids`

问题：
- 这是一个“共享 key”，但缺少明确 contract：
  - 由谁创建？谁清理？
  - 允许重复吗？允许写入非 string 吗？
  - 该列表是“永久全局”还是“本回合全局”？（core 同时读两个来源暗示存在两类，但没有显式协议）
- 多模块叠加时，容易出现重复写入/不清理/类型漂移。

整改建议：
- 明确分层与生命周期（二选一）：
  1) **只保留一种存储**：例如永久性放 `state.map.global_effect_ids`，回合性放 `state.round_state.global_effect_ids`，并在文档规定“谁负责清理”；
  2) 引入 `GlobalEffectList` 的 core helper（封装 add/remove/validate），禁止模块直接写裸数组。

---

### P1.7 存档序列化：int-key 字典 -> string-key 字典，导致加载后断言失败/逻辑失效

根因证据：
- `core/state/serialization/json_safe.gd:12`：Dictionary key 全部被 `str(k)`，写入 JSON 时不可避免
- `core/state/serialization/round_state_parser.gd:9`：只对少量 round_state 字段做了 int-key 归一化
- 多处运行时代码明确拒绝 string key：
  - `core/utils/round_state_counters.gd:19`：`assert(not all.has(str(player_id)))`

受影响的模块例子（均使用 per-player int key）：
- Coffee：`modules/coffee/actions/place_or_move_coffee_shop_action.gd:219` 明确报错 “不应包含字符串玩家 key”
- Lobbyists：`modules/lobbyists/rules/entry.gd:104` 初始化 `pending[i] = false`（int key）
- New Milestones：`modules/new_milestones/rules/marketing_initiation.gd:96` 写入 `pending[int(command.actor)] = {...}`
- Base Rules：`modules/base_rules/rules/phase_and_map.gd:80` 初始化 `restructuring.submitted[pid] = false`（int key，嵌套在 `round_state.restructuring` 内）
- Night Shift Managers：`modules/night_shift_managers/rules/entry.gd:69` 写入 `working_employee_multipliers[pid] = {...}`（int key）
- Rural Marketeers：`modules/rural_marketeers/rules/entry.gd:258` 遍历 `pending.keys()`，并在 `pid is int` 时才处理（string key 会被跳过，导致加载后 pending 丢失）

风险：
- 玩家在中途存档/读档后，某些模块 action 将无法执行或 pending 无法被消化；
- 更隐蔽的是：部分逻辑会“跳过处理”（因为 key 类型不符），导致规则悄悄失效而非显式报错。

整改建议（推荐）：
- 把“模块扩展的 round_state/map 字段 schema”纳入可注册体系（见下方整改方案 P1.8），从而在反序列化阶段统一做 key 归一化：
  - modules 声明哪些字段是 `{player_id(int) -> ...}`，加载时把 `"0"` 转回 `0`
  - 同时可以做类型校验，避免运行时才炸
- 过渡期替代方案（更粗暴但有效）：
  - 在 `RoundStateParser.parse_round_state()` 增加“通用归一化”：当某个 Dictionary 的 keys **全部**是数字字符串时，统一转为 int key（并递归处理）。  
    风险是可能误转“本该用数字字符串作为 key 的字典”，需评估现有 round_state 是否存在这类结构。

---

### P1.8 建议补齐“模块扩展面”文档与机制（消除隐式契约）

目前模块扩展主要通过两条路径叠加：
- **注册式扩展**（推荐）：RulesetV2 registries（actions/effects/settlement/hooks/providers）
- **状态字典扩展**（风险点）：模块直接在 `state.map`/`state.round_state` 增删字段（缺 schema/版本/解析注册）

建议新增两件事（可逐步落地）：
1) `StateSchemaRegistry`（或挂到 `RulesetV2`）：
   - 模块注册：`state.map.<key>` / `state.round_state.<key>` 的类型、是否持久化、key 归一化规则（int-key/string-key）、版本迁移函数
2) 文档化的 contract（建议放到 `docs/architecture/`）：
   - core-owned key 列表（map/round_state）与类型
   - shared key（例如 global_effect_ids、pending_phase_actions）的写入规则与清理职责
   - 模块自有 key 的命名规则：必须 module_id 前缀，禁止抢占 core key

---

## P2（优化项：减少重复与未来维护成本）

### P2.1 模块内重复的数值解析/容错 helper

证据：
- `modules/gourmet_food_critics/rules/entry.gd:118`：`_parse_int_value`
- `modules/rural_marketeers/rules/entry.gd:344`：`_parse_int_value`
- `modules/rural_marketeers/actions/place_highway_offramp_action.gd:219`：`_parse_int_value`

整改建议：
- 统一使用 `core/state/serialization/parse_helpers.gd`（或在 `core/utils/` 提供通用 `parse_int_value`），避免每个模块手写一份且行为不一致。

---

### P2.2 Map/Marketing 冲突检测存在多处“遍历 + 手工字段解析”

现象：
- 例如 lobbyists 对 `state.map.marketing_placements` 遍历查 airplane（`modules/lobbyists/actions/place_lobbyists_extra_map_tile_action.gd:174`），类似逻辑在其他模块也可能出现（offramp/营销互斥等）。

整改建议：
- 将常用查询抽到 core（`MapRuntime` 或新的 query helper）：
  - `MarketingPlacementQuery.find_by_type(...)`
  - `MapOccupancyQuery.is_world_pos_occupied(...)`
- 模块只依赖 query API，减少对底层字典结构的扩散依赖。

---

### P2.3 Provider API 的返回类型不一致，容易诱发“吞错式兜底”

现象（设计层面）：
- 某些 registry 要求 provider 返回 `Result`（例如 `core/rules/dinnertime_route_purchase_registry.gd:7`），因此可携带 error/warnings，并能 fail-fast。
- 某些 registry 要求 provider 返回原生 `Array`（例如 `core/rules/dinnertime_demand_registry.gd:7`），因此模块侧若遇到结构/类型错误，通常只能 `return []`（吞错）或 `assert`（直接崩）。

风险：
- 长期会形成两类模块代码风格并存：一类严格失败，一类“兜底返回空”，导致同类问题定位成本差异巨大。

整改建议（可选，偏架构一致性）：
- 将“返回 Array”升级为“返回 Result.value=Array”，或提供双接口（严格/容错）并统一文档规范。

---

## 附录：modules 使用到的 state key（字符串字面量提取）

说明：
- 这是通过静态提取 `modules/` 中出现的 `state.map["..."]` / `state.round_state["..."]` 等字面量得到的**粗略清单**，用于暴露“共享 key 总线”与命名/归属问题。
- 由常量拼出来的 key（例如 `rural_marketeers_offramp_pending`、`lobbyists_extra_tile_pending`、`new_milestones_*_pending` 等）不一定会出现在此处，但它们往往更需要纳入 schema registry 做序列化归一化。

modules 读取/写入的 `state.map` key（去重）：
- core-owned（基础地图结构）：`cells`、`grid_size`、`tile_grid_size`、`houses`、`restaurants`、`marketing_placements`、`tile_placements`
- core-owned（扩展点，建议文档化）：`external_cells`、`external_tile_placements`、`tile_supply_remaining`
- module-owned（应保持 module_id 前缀/可识别性）：`coffee_shops`、`next_coffee_shop_id`、`rural_marketeers_offramps`

modules 读取/写入的 `state.round_state` key（去重，含 get/has/bracket 形式）：
- core-owned/shared（多模块依赖，需明确 contract）：`pending_phase_actions`、`order_of_business`、`restructuring`、`bankruptcy`、`milestones_auto_awarded`、`train_events`、`dinnertime`
- module-owned（建议保持 module_id 前缀或嵌套到 module root 下）：`coffee`、`coffee_shop_triggers_used`、`kimchi`、`rural_marketeers`、`new_milestones_bank_burn`、`working_employee_multipliers`、`marketing_rounds`、`force_next_phase`

## 整改路线图（建议按阶段推进）

### 阶段 A：P0 修复（短平快、可回归）
- A1 修复起始库存 guard（`core/state/game_state_factory.gd:143`），补 1 个 core test 覆盖。
- A2 移除 Payday 对 `coffee` 的硬编码；改为 ProductDef 字段/标签驱动；补测试覆盖“coffee 不计入/计入”的期望行为。
- A3 删除 new_milestones 的 `player_has_milestone` 重复实现；统一走 core，并在必要时改为 `Result` 返回而非吞错。

### 阶段 B：收紧回调契约（减少吞错）
- B1 `SettlementRegistry.run()` 与 `Hooks._run_hooks()`：非 `Result` 返回至少输出 warning；在 DebugFlags 下升级为 failure。
- B2 补一个 headless test：注册一个返回非 Result 的 hook/settlement，期望测试失败（防止回归）。

### 阶段 C：模块耦合治理（建立“显式扩展面”）
- C1 定义并落盘 `state.map/state.round_state` 的 schema contract（core-owned/shared/module-owned）。
- C2 引入 `StateSchemaRegistry`（或 RulesetV2 扩展）：让模块注册其持久化字段与 key 归一化规则。
- C3 将“跨模块窥探”逐步迁移到 registry/provider：
  - offramp/airplane/extra tile 等冲突 -> `PlacementConflictRegistry`
  - 全局效果 -> `GlobalEffectList` helper 或 registry

### 阶段 D：清理重复工具函数（可选）
- D1 抽取 `_parse_int_value`、pos_key 等常用小工具到 core/utils，并在模块中替换引用。
