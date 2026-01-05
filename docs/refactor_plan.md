# 重构整改计划（高内聚 / 低耦合 / 零 fallback）

最后更新：2026-01-05

本计划用于**落盘追踪**本仓库的结构整改与重构进度，目标是：

- 清除所有“fallback/兼容旧数据/静默降级”代码路径（Fail Fast）。
- 让每个文件职责清晰、内聚度高、耦合度低，便于后续扩展与测试。
- 将“规则实现”从“流程编排/状态机”中剥离出来，形成可组合、可测试的规则模块。

> 约定：每完成一个工作项，需要同步更新本文件的状态，并（如适用）补齐/调整 `core/tests/*` 与 `ui/scenes/tests/all_tests.tscn` 覆盖，确保回归可控。

---

## 0. 关键决策（需你点头后才会实施）

在开始改代码之前，需要先统一以下决策，否则“零 fallback”会直接影响存档、数据文件、以及开发期容错体验。

### D0.1 “fallback” 的定义范围（已确认）

我建议按下面定义执行（你可调整）：

- ✅ 必须清除（典型 fallback/兼容）：
  - **读取配置/存档失败后改用硬编码默认值继续跑**（会掩盖问题）。
  - **兼容旧 schema 字段**（例如加载时悄悄丢字段/改字段类型/自动补默认）。
  - **缺参/缺字段时自动推断/自动选择**导致行为不确定或难追踪（除非这是明确的规则）。
- ⚠️ 需要你确认是否也要清除：
  - API 形式上的 `fallback` 参数（例如 `get_rule_int(rule_key, fallback)` 这种“给默认值”）。
  - 数据解析中的 “coerce + fallback default”（例如 `_coerce_int_array(value, [0,90,180,270])`）。

**结论：**
- ✅ 容错解析（coerce/default）也要移除；解析不对直接失败（Fail Fast）。

### D0.2 存档兼容策略（已确认）

当前存在“兼容旧存档”行为（示例见 `core/state/game_state.gd`）。

**选项 A（最严格，推荐以满足“零 fallback”）：**
- 只接受当前 `schema_version` 的存档。
- 版本不匹配直接失败（明确报错），不做迁移、不做字段兼容。

**选项 B（可控迁移，不算静默 fallback）：**
- 明确的版本迁移（`schema_version` 驱动、可测试、可追踪）。
- 仍然允许加载旧存档，但不允许“静默修复”；迁移必须是显式且可验证的。

**结论：**
- ✅ 不需要兼容旧数据：旧存档/旧 schema 直接拒绝加载（不做迁移）。

### D0.3 GameConfig 缺失/错误策略（已确认）

当前存在“GameConfig 加载失败则回退到硬编码默认值”的路径（见 `core/state/game_state.gd`）。

**结论：**
- ✅ `GameConfig` 缺失/错误：直接报错退出，要求修复配置/数据。

### D0.4 CEO/公司结构“根员工”是否固定为 `ceo`（已确认：A）

当前代码中存在若干处将 `ceo` 视为“公司结构根员工/不可解雇”的硬编码点（见 `gameplay/actions/fire_action.gd`、`core/rules/company_structure_rules.gd`、`gameplay/validators/company_structure_validator.gd`、`core/data/game_config.gd`）。

**选项 A（短期最稳）：**
- 继续把 `ceo` 作为保留 ID（根员工一定是 `ceo`），只把“不可解雇”改为数据驱动字段（去掉 `employee_id == "ceo"` 判断）。

**选项 B（更模块化）：**
- 引入员工字段/标签（例如 `role: "ceo"` 或 `company_root: true`），公司结构规则不再写死 `ceo`，由启用模块的员工数据决定“根员工”是谁。
- 需要同步约束：开局必须且只能存在 1 个根员工；且 `GameConfig.player.starting_employees`/初始公司结构与之匹配，否则 init fail。

### D0.5 产品（burger/pizza/soda/lemonade/beer）是否也纳入模块内容（已确认：B，已落地）

当前存在产品集合相关硬编码（已整改为模块化 + 严格校验）：
- 产品集合由 `modules/*/content/products/*.json` 定义（基础模块：`modules/base_products/`）
- `ProductDef/ProductRegistry` 统一提供产品集合与标签（如 `drink`/`food`），替代 `_is_drink()` 与手写列表
- `modules/base_tiles/content/tiles/*.json` 的 `drink_sources.type` 仍使用产品 id，但初始化时校验必须存在且带 `drink` tag（已修正历史遗留 `cola` → `soda`）
- `core/data/game_config.gd` 的 `player_starting_inventory` 仍显式列出 key，但初始化时严格校验其 key 集合与本局产品集合一致（missing/extra 均 init fail）

**选项 A（短期最小改动）：**
- 产品仍由 `GameConfig.player.starting_inventory` 的 keys 决定；动作校验/饮品判断改为读取 state/config（不再在代码写死列表）。

**选项 B（更彻底，推荐）：**
- 新增 `products` 作为模块内容类型：`modules/<module>/content/products/*.json`（并新增 `modules/base_products/`）。
- 由 `ProductDef/ProductRegistry` 统一定义产品集合与标签（如 `drink`），并在初始化时校验：
  - 任意引用到的 product_id（营销/库存/饮料源/生产）必须存在（否则 init fail）。

### D0.6 营销板件按玩家数“移除”是否数据化（已确认：B，已落地）

当前 `core/rules/marketing_rules.gd` 写死：
- 2 人：移除 `12,15,16`
- 3 人：移除 `15,16`
- 4 人：移除 `16`

✅ 已迁移到 `modules/*/content/marketing/*.json`（新增 `min_players/max_players`），由数据决定可用性，并保持旧规则结果一致；已移除对硬编码 `MarketingRules.get_removed_board_numbers()` 的依赖。

### D0.7 是否要求“所有里程碑 effects.type 必须有对应实现/handler”（已确认：B）

当前 `modules/base_milestones/content/milestones/*.json` 中存在 17 种 effect type，但只有一部分在代码中被读取；未被读取的效果目前是“静默 no-op”（不符合严格模式的 Fail Fast 精神）。

**选项 A（短期容忍）：**
- 允许存在“暂未实现的 effect type”，但要有清单与计划；不在 init 时失败。

**选项 B（严格模式一致性）：**
- 建立统一的里程碑 effect 注册/校验机制：所有加载到本局的 milestone effect type 必须可处理，否则 init fail。
- 这要求：要么先实现/拆出所有 base_milestones 中尚未落地的 effect；要么把未实现的里程碑拆到单独模块并默认不启用。

### D0.8 地图视觉资源（图片化 + 模组打包）策略（已确认：Q12=C，Q13=A，Q14=A，Q15=A）

- ✅ visuals 定义独立放在 `modules/<module_id>/content/visuals/*.json`（不混入 `TileDef/PieceDef/ProductDef`）
- ✅ UI 渲染主路径采用 `Control._draw()` 单画布分层（便于后续替换贴图/做层级）
- ✅ 图片资源以“多张 PNG 文件”组织（后续如需 atlas 再做优化）
- ✅ 缺失图片资源 **不导致 init fail**：UI 允许占位渲染继续运行（核心规则仍保持严格模式）

---

## 1. 现状问题清单（已扫描）

### 1.1 超大文件 / 职责混杂（低内聚）

- `core/engine/phase_manager.gd`（1706 行）
  - 同时承担：阶段 FSM、子阶段 FSM、钩子系统、Payday/Dinnertime/Marketing/Cleanup 结算、破产规则、强制动作检查、距离/选路等辅助函数。
  - 典型问题：改任何规则都容易引发意外回归；测试粒度难切；文件跨度过大导致 review 成本高。
- `gameplay/actions/procure_drinks_action.gd`（594 行）
  - 同时承担：动作校验/状态变更 + 路线生成 + 路线校验 + 拾取逻辑 + 辅助解析与缓存。
- `core/engine/game_engine.gd`（687 行）、`core/state/game_state.gd`（661 行）
  - 长度尚可接受，但需要审视“职责边界”是否持续膨胀（例如引擎同时做太多一致性/不变量/IO）。

### 1.2 已确认的 fallback / 兼容代码点（需要清除）

> 说明：这里只列出当前扫描到的显式“fallback/兼容旧”语义点；后续整改会以“全局搜 + code review”补齐。

- `core/data/game_config.gd`
  - `get_one_x_count()`：`# fallback: 兼容旧逻辑`（缺配置时回退硬编码）。
- `core/state/game_state.gd`
  - `create_initial_state_with_rng()`：GameConfig 加载失败回退硬编码默认值。
  - `create_initial_state_with_rng()`：未注入 RNG 时回退本地 RNG shuffle（会影响确定性与可追踪性）。
  - `from_dict()`：兼容旧存档字段（例如 `edge_ports` 丢弃）。
- `core/map/tile_def.gd` / `core/map/piece_def.gd` / `core/map/map_def.gd`
  - `_coerce_*`：容错解析 + fallback 默认值（是否保留需要 D0.1 决策）。

### 1.3 重复逻辑 / 不必要耦合

- 距离/范围逻辑重复：
  - `gameplay/actions/initiate_marketing_action.gd` 的 road/air range
  - `gameplay/actions/procure_drinks_action.gd` 的 road/air range
- RoundState 计数写法分裂：
  - `production_counts` / `procurement_counts` / `marketing_used` 等各自实现“嵌套字典计数”，可收敛为统一工具。

---

## 2. 目标架构（文件职责划分）

### 2.1 PhaseManager 的目标职责

`core/engine/phase_manager.gd` 重构后只保留：

- 阶段/子阶段枚举与顺序定义
- 推进逻辑（“决定 next phase/sub-phase”）
- 钩子系统（register/unregister/run hooks）
- 编排调用：在正确的阶段切换点调用对应的“规则模块”

**不再直接实现**：Payday/Dinnertime/Marketing/Cleanup/破产/强制动作 等具体规则。

### 2.2 规则模块化（建议目录）

> 目录名可调整，以最小迁移成本为主。

- `core/rules/phase/`
  - `payday_settlement.gd`
  - `dinnertime_settlement.gd`
  - `marketing_settlement.gd`
  - `cleanup_settlement.gd`
- `core/rules/economy/`
  - `bankruptcy_rules.gd`
- `core/rules/working/`
  - `mandatory_actions_rules.gd`
- `core/utils/`
  - `round_state_counters.gd`（统一计数器读写）
  - `coerce.gd`（若决定保留容错解析）
  - `range_utils.gd`（统一 road/air 范围判断）

---

## 3. 进度追踪（Checklist）

状态标记：

- ⏳ 待开始
- 🚧 进行中
- ✅ 完成
- 🧊 暂缓（需决策/外部依赖）

### 3.0 决策与基线

- ✅ D0：确认“零 fallback”定义与边界（见第 0 节）
- ✅ D1：确认存档兼容策略（严格拒绝 vs 显式迁移）
- ✅ D2：确认 GameConfig 缺失/错误策略（fail-fast vs dev-only fallback）
- ✅ B0：补充“全局 fallback 搜索”规范与关键字清单（并固化到本文件）
  - 搜索目标（优先级从高到低）：
    - “吞错继续跑”：`if not xxx.ok: continue` / `return Result.success()` / `return`（不报错）等
    - “容错解析/类型兜底”：`int(value)`/`float(value)`/`str(value)` 直接 coerce；`dict.get(key, default)` 用默认值继续跑
    - “兼容旧 schema”：`compat`/`legacy`/`migration` 分支、旧字段名兼容、自动补字段
  - 关键字建议（ripgrep）：
    - `rg -n \"fallback|compat|legacy|migration|coerce|tolerant|ignore\" -S`
    - `rg -n \"\\.get\\([^,]+,[^)]+\\)\" core gameplay -S`（重点审查默认值是否掩盖错误）
    - `rg -n \"to_int\\(|to_float\\(|int\\(|float\\(\" core gameplay -S`（重点审查是否是“解析容错”而非规则）
  - 整改准则：
    - 若是“规则默认值”（设计明确、确定性、可测试）：保留，但要让接口语义清晰（例如 `duration` 省略=默认值）
    - 若是“容错/吞错/兼容旧”：改为 `Result.failure(...)` 或 `assert(...)`（按调用栈可控性选择），并补齐测试覆盖

### 3.1 统一工具（先减耦合、再拆文件）

- ✅ U1：新增 `core/utils/round_state_counters.gd`，统一 round_state 的 per-player/per-key 计数读写
  - 目标：替换 `production_counts/procurement_counts/marketing_used/...` 的重复实现
- ✅ U2：新增 `core/utils/range_utils.gd`，统一 `road/air` 范围判断（以“玩家餐厅入口”为起点）
  - 目标：替换 `initiate_marketing_action.gd` 与 `procure_drinks_action.gd` 的重复 range 逻辑
- ✅ U3：移除 `TileDef/PieceDef/MapDef` 的 `_coerce_*`（改为严格校验并返回错误；不新增 `coerce.gd`）
  - D0.1 已确认“容错解析也要移除”，因此选择 Fail Fast 路线
- ✅ U4：拆分 `core/state/game_state.gd`（降低耦合/提高清晰度）
  - 抽取：序列化/反序列化到 `core/state/game_state_serialization.gd`
  - 抽取：初始状态构建到 `core/state/game_state_factory.gd`
  - 抽取：地图运行时（RoadGraph 缓存/查询/失效 + baked map 写入）到 `core/map/map_runtime.gd`
  - 收敛：`GameState` 不再内置 map 默认结构；由 `GameStateFactory` 初始化为 `{}`，并由 `MapRuntime.apply_baked_map()` 写入完整字段（含 `next_restaurant_id`）
  - 迁移：所有调用点（engine/rules/actions/tests/docs）统一改用 `MapRuntime.*`
- ✅ U5：新增“发起营销扩展点”注册表（`MarketingInitiationRegistry`），并接入模块系统 V2（Ruleset 注册 + GameEngine 配置 + `initiate_marketing` 调用）
- ✅ U6：新增通用里程碑事件 `RestaurantPlaced`（在 `place_restaurant` 动作中触发），用于支持 “FIRST NEW RESTAURANT” 等模块化里程碑
- ✅ U7：`MarketingSettlement` 支持“同一营销员绑定多个营销实例”的延迟返还（基于 `marketing_instance.link_id`）
  - 收紧：`MapRuntime` 运行时查询不再静默返回空值（缺字段/类型错/越界直接 assert fail-fast）
  - 收紧：`GameStateSerialization` 坐标解码不允许非整数 float（`_decode_map/_decode_value` 返回 `Result` 并用 `_parse_int` 校验）
- ✅ U8：`MarketingSettlement` 支持“多商品营销”（`marketing_instance.products=[A,B,...]` 按顺序结算）与 `no_release=true`（到期不释放营销员）

### 3.2 清除 fallback / 兼容路径（Fail Fast）

- ✅ F1：`core/data/game_config.gd` 移除 `get_one_x_count()` 的 fallback 分支（缺配置直接失败）
- ✅ F2：`core/state/game_state.gd` 移除 “GameConfig 加载失败 -> 硬编码默认值” 路径
- ✅ F3：`core/state/game_state.gd` 移除 “无 rng_manager -> 本地 RNG shuffle” 路径（强制注入）
- ✅ F4：拒绝旧存档/旧 schema（不做迁移、不做字段兼容）
  - `Globals.SCHEMA_VERSION` / `GameState.SCHEMA_VERSION` 已提升为 `2`
  - `GameEngine.load_from_archive()` 仅接受当前 schema，并强制要求 `rng` 与命令 `timestamp`
- ✅ F5：移除“找不到匹配地图就随便选/用空地图占位”的 fallback
  - `core/data/game_data.gd`：`get_map_for_player_count()` 无匹配直接失败
  - `core/engine/game_engine.gd`：`initialize()` 选择地图失败直接返回错误
- ✅ F6：存档创建 fail-fast（不允许未初始化/空 rng/空 checkpoint）
  - `core/engine/game_engine.gd`：`create_archive()` 改为返回 `Result`，并强制要求初始化完成
- ✅ F7：移除规则读取 fallback
  - `core/state/game_state.gd`：`get_rule_int(rule_key)` 缺规则直接 `assert` 失败
- ✅ F8：存档/回放解析收紧（Fail Fast）
  - `core/engine/game_engine.gd`：`load_from_archive()` 强制要求 `current_index` 且必须为整数；`schema_version` 禁止非整数 float
  - `core/engine/game_engine/replay.gd`：恢复 RNG 时 `rng_calls` 必须存在且为整数（不再默认 `0`）
  - `core/engine/game_engine/archive.gd`：序列化 checkpoint metadata 时 `rng_calls` 必须存在（不再默认 `0`）
  - 新增测试：`core/tests/archive_fail_fast_test.gd`
- ✅ F9：不变量校验收紧（Fail Fast）
  - `core/engine/game_engine/invariants.gd`：移除 `.get(..., default)` 兜底；缺字段/类型错误直接 `Result.failure`
  - `core/engine/game_engine.gd`：初始化与 load_from_archive 的基线计算改为 `Result` 驱动（失败直接报错）
  - 新增测试：`core/tests/invariants_fail_fast_test.gd`
- ✅ F10：RoundState 严格反序列化与 key 归一化（Fail Fast）
  - `core/state/game_state_serialization.gd`：`_parse_round_state()` 严格校验 `action_counts/price_modifiers/immediate_train_pending` 等结构，并将玩家 key 从数字字符串归一化为 `int`
  - `core/rules/pricing_pipeline.gd`：移除字符串玩家 key 兼容分支（发现异常直接 `assert`）
  - `core/utils/round_state_counters.gd`：增加断言，禁止字符串玩家 key 混入
  - `core/rules/phase/payday_settlement.gd`：对 `round_state.recruit_used` 禁止字符串玩家 key
  - 调整测试：`core/tests/recruit_on_credit_rules_test.gd` 移除 `"0"` 兜底
  - 新增测试：`core/tests/round_state_fail_fast_test.gd`
- ✅ F11：EmployeeRules 清理 player/round_state 访问兜底（Fail Fast）
  - `core/rules/employee_rules.gd`：`player.employees/reserve_employees/busy_marketers` 必须存在且为 `Array[String]`（移除 `Dictionary`/`str()` 容错分支）
  - `core/rules/employee_rules.gd`：`round_state.action_counts` 必须存在且为 `Dictionary`；计数值必须为非负 `int`（缺字段/类型错直接 `assert`）
- ✅ F12：放置/子阶段推进相关兜底清理（Fail Fast）
  - `core/map/placement_validator.gd`：移除 `map_ctx.get(..., default)` / `cell.get(..., default)` 的静默兜底；缺字段/类型错直接 `assert`
  - `core/map/house_number_manager.gd`：`next_house_number` / `houses` 缺失不再默认，改为 `assert` fail-fast
  - `core/state/game_state_factory.gd` / `core/engine/phase_manager/working_flow.gd`：`round_state.sub_phase_passed` 初始化为“每玩家一个 bool”（移除 `.get(pid,false)` 语义兜底）
  - `gameplay/actions/*`（place/move_restaurant、place_house、add_garden、skip/advance_phase）：移除 `state.map.get(..., default)` / `validate_result.value.get(..., default)` 等兜底，强制必填字段存在
- ✅ F13：公司结构/强制动作相关兜底清理（Fail Fast）
  - `core/rules/company_structure_rules.gd`：移除 `player.get(..., default)` / `dict.get(..., default)` / `_to_employee_id` 等容错；要求 `employees/reserve_employees/company_structure.ceo_slots` 结构严格
  - `core/rules/working/mandatory_actions_rules.gd`：移除 `mandatory_actions_completed.get(pid, [])` 等默认值；缺字段/类型错直接失败
  - `core/engine/phase_manager/working_flow.gd` / `gameplay/validators/company_structure_validator.gd`：移除默认值兜底，缺字段/类型错直接 fail-fast
- ✅ B1：严格解析 Employee/Marketing/Milestone 的 JSON 定义（Fail Fast）
  - `core/data/employee_def.gd` / `core/data/marketing_def.gd` / `core/data/milestone_def.gd`：`from_json/load_from_file` 改为返回 `Result`；移除 `str()/int()` 容错转换与静默默认
  - `core/data/*_registry.gd`：加载失败不再仅 `log error`，改为 `assert` fail-fast
  - `modules/*/content/employees/*.json`：移除 `aliases` 字段；修正 `errand_boy.range`（与采购规则对齐）
  - 里程碑：允许 `trigger.filter` 省略（语义=空 filter），但类型错误直接失败

### 3.3 拆分 PhaseManager（降低核心耦合）

- ✅ P1：抽取 Payday 结算到 `core/rules/phase/payday_settlement.gd`
- ✅ P2：抽取 Cleanup 结算到 `core/rules/phase/cleanup_settlement.gd`
- ✅ P3：抽取 Dinnertime 结算到 `core/rules/phase/dinnertime_settlement.gd`
  - 现有 `PricingPipeline` 保持为 pricing 细节模块
- ✅ P4：抽取 Marketing 结算到 `core/rules/phase/marketing_settlement.gd`
  - 保持/复用 `core/rules/marketing_range_calculator.gd`
- ✅ P5：抽取破产规则到 `core/rules/economy/bankruptcy_rules.gd`
- ✅ P6：抽取强制动作检查到 `core/rules/working/mandatory_actions_rules.gd`
- ✅ P7：PhaseManager 收敛为“编排层”，仅调用上述模块并聚合 warnings/result

### 3.4 瘦身动作（把复杂逻辑下沉为可测规则/服务）

- ✅ A1：重构 `gameplay/actions/procure_drinks_action.gd`：
  - 路线解析/默认路径生成/路线校验/拾取来源下沉到独立模块（建议：`core/rules/drinks_procurement.gd`）
  - Action 仅做：参数校验 → 调用规则模块 → 写 state → 产出 events
- ✅ A2：重构 `gameplay/actions/initiate_marketing_action.gd`：
  - range 判断改用 `core/utils/range_utils.gd`
  - round_state 计数改用 `core/utils/round_state_counters.gd`
- ✅ A3：统一 Produce/Recruit/Train 等动作里对 round_state 的写入方式（消除“各自造轮子”）
  - `production_counts` / `procurement_counts` / `house_placement_counts` / `recruit_used` / `marketing_used` 均收敛到 `core/utils/round_state_counters.gd`
- ✅ A4：收紧所有 `gameplay/actions/*` 的 `command.params` 解析（Fail Fast）
  - 移除 `command.params.get(..., default)` / `str()` / `int()` 容错转换；缺参/类型错直接失败
  - 新增 `ActionExecutor.require_array_param()` / `require_vector2i_param()`；其中整数解析允许 `float` 但必须是整值（兼容 JSON 数字表示），否则失败

### 3.5 回归与验收

- ✅ T1：每个阶段拆分完成后，补齐/调整对应 `core/tests/*`（或新增测试）覆盖关键分支
  - 新增 `core/tests/fail_fast_parsing_test.gd`：覆盖 MapRuntime/GameStateSerialization/MapBaker 的 fail-fast 行为（拒绝静默容错与隐式默认）
  - 新增 `core/tests/round_state_fail_fast_test.gd`：覆盖 round_state 的 key 归一化与严格解析（禁止字符串玩家 key）
  - `all_tests` 通过（含超时脚本）：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 90`（26/26）
- ✅ T2：`ui/scenes/tests/all_tests.tscn` 通过（headless autorun）
- ✅ T3：定义“文件规模阈值”并执行清理（例如单文件建议 ≤ 400 行；超出需说明或继续拆）
  - 阈值规则（默认适用于 `core/`、`gameplay/` 的生产代码）：
    - 目标：单文件 `*.gd` ≤ 400 行（粗略以 `wc -l` 计数；允许少量波动）
    - 硬上限：> 800 行必须拆分（否则 review/测试成本过高）
    - 例外：`core/tests/`、`ui/`（测试/工具脚本）允许适度超标，但超过 500 行仍建议拆出 helper
  - 已清理（本轮落地）：
    - `core/rules/drinks_procurement.gd` (124)：已拆分为 `core/rules/drinks_procurement/*`，并保留对外 API `resolve_procurement_plan()` / `serialize_route()`
    - `core/state/game_state.gd` (210)：已拆分出 `core/state/game_state_serialization.gd` (306) / `core/state/game_state_factory.gd` (93)，并把地图运行时迁移到 `core/map/map_runtime.gd` (200)
  - 超标清单（当前 `>400` 行，按行数降序）：
    - 生产代码（`core/`、`gameplay/`）：
      - `core/engine/game_engine.gd` (438)：已拆分 `core/engine/game_engine/*`（action_setup/archive/checkpoints/invariants/replay/diagnostics）；主文件仍略超 400，后续可继续拆 `load_from_archive/execute_command`
      - `core/map/piece_def.gd` (436)：地图/件定义，暂时保留（后续按职责拆）
      - `core/rules/phase/dinnertime_settlement.gd` (433)：阶段结算，暂时保留（后续按“服务/计价/写回 round_state”拆）
      - `core/map/road_graph.gd` (431)：算法实现，暂时保留（后续按“构图/最短路/查询接口”拆）
      - `core/map/tile_def.gd` (428)：板块定义解析，暂时保留（后续按“解析/校验/查询”拆）
      - `core/map/placement_validator.gd` (411)：放置校验，暂时保留（后续按“共用校验/类型校验”拆）
      - `core/engine/phase_manager.gd` (407)：已拆分 `core/engine/phase_manager/*`（definitions/hooks/working_flow）；主文件仍略超 400，后续可继续拆 `advance_phase/advance_sub_phase` 的流程编排
    - 例外（`core/tests/`、`ui/`）：
      - `core/tests/marketing_campaigns_test.gd` (448)：测试文件（测试例外），暂时保留
      - `core/tests/dinnertime_settlement_test.gd` (445)：测试文件（测试例外），暂时保留
      - `ui/scenes/tools/tile_editor.gd` (431)：编辑器工具脚本（UI 例外），暂时保留

### 3.6 模块系统 V2（严格模式：内容/规则/结算全模块化）

- ✅ D3：落盘模块系统 V2 设计与关键决策
  - 设计：`docs/architecture/60-modules-v2.md`
  - ADR：`docs/decisions/0002-modules-v2-strict-mode.md`
  - `docs/design.md`：补充 V2 总览并标记 V1 待迁移
- ✅ M1：引入模块包目录与 manifest 解析（`res://modules/<module_id>/module.json`）
  - 新增：`core/modules/v2/module_manifest.gd`（严格解析）
  - 新增：`core/modules/v2/module_package_loader.gd`（按目录枚举并 fail-fast）
  - 新增：`core/modules/v2/module_plan_builder.gd`（依赖闭包/冲突检测/确定性拓扑排序）
  - 新增：`modules/README.md`（模块包目录约定）
  - 新增测试：`core/tests/module_package_loader_v2_test.gd`、`core/tests/module_plan_builder_v2_test.gd` + `core/tests/fixtures/*`
  - 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（34/34）
- ✅ M2：引入 per-game `ContentCatalog`（按启用模块加载），替换全局静态 registry（Employee/Milestone/Marketing）
  - 新增：`core/modules/v2/content_catalog.gd`（每局内容容器）
  - 新增：`core/modules/v2/content_catalog_loader.gd`（按启用模块加载 employees/milestones/marketing）
  - 更新：`core/engine/game_engine.gd`（initialize 默认装配 V2 plan + catalog；employees/milestones/marketing 均由 ContentCatalog 装配；默认启用 `base_marketing`）
  - 新增测试：`core/tests/content_catalog_v2_test.gd`、`core/tests/module_system_v2_bootstrap_test.gd`（`all_tests` 34/34 通过）
- ✅ M3：实现从内容推导 Pools（路线B），并删除 `GameConfig.employee_pool.one_x_employee_ids` 等列表型硬编码字段
  - 已确认：`1x` 员工不做随机抽取；按玩家人数决定“每种 1x 员工卡”的张数（2–3人=1，4人=2，5人=3）
  - 已确认：路线B（更彻底）：`employee_pool.base` / `one_x_employee_ids` / `milestones.pool` 均从 `GameConfig` 移除
  - 已确认：`one_x_count_by_player_count` 移入 `GameConfig.rules`（规则常量），Pools 从内容元数据推导
  - ✅ 已新增 `core/modules/v2/pool_builder.gd`，并改造 `core/state/game_state_factory.gd` 使用其构建 `employee_pool/milestone_pool`（回归通过）
  - ✅ 已移除 `data/config/game_config.json` 中的 `employee_pool` 与 `milestones.pool`（schema_version=2），`one_x_employee_copies_by_player_count` 移入 `rules`
- ✅ M4：引入 `SettlementRegistry` 并改造 PhaseManager 为“仅编排调用”；缺主结算器初始化直接失败（Fail Fast）
  - 新增：`core/rules/settlement_registry.gd`（primary/extension；primary 以 priority=100 为分界；Fail Fast）
  - 新增：`core/modules/v2/ruleset.gd`、`core/modules/v2/ruleset_builder.gd`、`core/modules/v2/ruleset_loader.gd`
  - 接入：`core/engine/game_engine.gd`（V2 初始化时构建 Ruleset，并校验必需 primary settlements）
  - 改造：`core/engine/phase_manager.gd`（只调用注册表；缺 `SettlementRegistry` 直接失败）
  - 落盘：`modules/base_rules/`（base_rules 模块包，注册 4 个必需 primary settlements）
  - 新增测试：`core/tests/settlement_registry_v2_test.gd`（缺失/重复 primary fail-fast + 调用链路）
- ✅ M5：引入 `EffectRegistry`（员工/里程碑声明 effect_id），迁移 waitress/CFO 等硬编码到模块 handlers
  - 新增：`core/rules/effect_registry.gd`（`effect_id -> handler`，重复注册 fail-fast；强制 `module_id:` 前缀）
  - 接入：`core/modules/v2/ruleset.gd`、`core/modules/v2/ruleset_builder.gd`（新增 `register_effect`）
  - 内容：`core/data/employee_def.gd`、`core/data/milestone_def.gd` 新增 `effect_ids` 字段解析（命名强制 `module_id:...`）
  - 严格校验：`RulesetV2.validate_content_effect_handlers()` + `GameEngine._apply_modules_v2()`（content 引用缺 handler → init fail）
  - 迁移：`core/rules/phase/dinnertime_settlement.gd` 改为通过 EffectRegistry 计算 tiebreak/tips/bonus（无 legacy 分支）
  - 迁移：`core/rules/phase/payday_settlement.gd` 将 recruiting_manager/hr_director 薪资折扣额度改为通过 EffectRegistry 计算（无 legacy 分支）
  - 收紧：`core/rules/phase/payday_settlement.gd` 的 `salary_total_delta` 改为从里程碑 JSON `effects.value` 读取（`first_train=-15`），不再依赖 `GameConfig.rules.salary_first_train_discount`
  - 收紧：`core/rules/phase/cleanup_settlement.gd` 的冰箱容量改为从里程碑 JSON `effects.value` 读取（`gain_fridge`），不再依赖 `GameConfig.rules.fridge_capacity_per_product`
  - 收紧：`core/rules/phase/dinnertime_settlement.gd` 与 `modules/base_rules/rules/entry.gd` 的女服务员小费提升改为从里程碑 JSON `effects.value` 读取（`waitress_tips`），不再依赖 `GameConfig.rules.waitress_tips_with_milestone`
  - 迁移：`core/rules/phase/marketing_settlement.gd` 将 first_radio 的 radio 需求量（demand_amount=2）改为通过 EffectRegistry 计算（无 legacy 分支）
  - base_rules：`modules/base_rules/rules/entry.gd` 注册 `base_rules:dinnertime:*` effect handlers；并将 `waitress/cfo/first_have_100(ceo_get_cfo)` 写入 `effect_ids`
  - base_rules：注册 `base_rules:payday:salary_discount:*` effect handlers；并将 `recruiting_manager/hr_director` 写入 `effect_ids`
  - base_rules：注册 `base_rules:marketing:demand_amount:first_radio` effect handler；并将 `first_radio` 写入 `effect_ids`
  - 新增测试：`core/tests/effect_registry_v2_test.gd` + fixtures `core/tests/fixtures/modules_v2_effects_validation/`（缺 handler init fail + 命名校验 + 每出现一次调用一次）
  - 新增覆盖：`core/tests/marketing_campaigns_test.gd` 增加“MarketingSettlement 注入 EffectRegistry”用例
  - 新增覆盖：`core/tests/payday_salary_test.gd` 增加 “first_train 的 salary_total_delta 来自 milestone JSON effects.value” 用例
  - 覆盖确认：`core/tests/cleanup_inventory_test.gd` 中的 `first_throw_away`（gain_fridge=10）用例现在验证的是 milestone JSON `effects.value`
  - 覆盖确认：`core/tests/dinnertime_settlement_test.gd` 中的 `first_waitress`（waitress_tips=5）用例现在验证的是 milestone JSON `effects.value`
  - 回归：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（34/34）
- ✅ M5.1：引入 `DinnertimeRoutePurchaseRegistry` + `RulesetV2.state_initializers`（模块可注册“晚餐路上购买”结算与追加 state 字段；Coffee 模块使用）；补齐 strict 校验与回归：新增 `core/tests/dinnertime_route_purchase_registry_v2_test.gd`（52/52）
- ✅ M6：删除旧模块系统/旧入口（`data/modules`、旧 registry 静态缓存等），并补齐严格模式测试覆盖

- ✅ M7：迁移剩余“硬编码规则点”到数据/模块（已确认 D0.4–D0.7，严格模式）
  - ✅ E1（员工）：解雇规则不应写死 `employee_id == "ceo"`（`gameplay/actions/fire_action.gd`）
    - 已实现：新增 `EmployeeDef.can_be_fired`，并由 `ceo.json` 声明 `false`
    - 结果：解雇校验不再依赖硬编码 `ceo` 分支；严格模式下仍保证“CEO 不可解雇”
  - ✅ E2（营销板件）：按玩家人数移除的 board_number 不应写死在 `MarketingRules`（`core/rules/marketing_rules.gd`）
    - 已实现：`modules/base_marketing/content/marketing/*.json` 增加 `min_players/max_players`，按数据推导可用性
  - ✅ E3（产品集合）：营销允许的产品、饮品类别判断不应写死在代码（`initiate_marketing_action.gd` / `_is_drink`）
    - 已实现：新增 `products` 内容类型 + `base_products` 模块（路线B），并在初始化严格校验产品引用
  - ✅ E4（里程碑 effects）：effects.type 读取分散且存在未实现 effect type 的“静默 no-op”
    - 已实现：新增 `MilestoneEffectRegistry`（`effects[*].type -> handler`），并在初始化严格校验“所有里程碑 effects.type 必须有 handler”（缺失直接 init fail）
    - 已实现：`MilestoneSystem` 统一在 claim 后立即应用 `effects`（一次性效果），并记录 `round_state.milestones_auto_awarded`
    - 已实现：触发点补齐（与规则书对齐）
      - Recruit：`recruit_used==3` 触发 `first_hire_3`
      - Payday：按“实际支付 paid”触发 `PaySalaries`，支持 `paid.gte` 过滤（`first_pay_20_salaries`）
      - CashReached：在银行向玩家支付现金时检查 `$20/$100`（`first_have_20/first_have_100`）
    - 已实现：`ban_card` 禁用只作用于获得者（若已有则自动移除并归还供应池），并在 Recruit/Train 阶段校验禁用卡不可获得
    - 已实现：默认禁止同一 Train 子阶段链式培训“本子阶段新培训得到”的员工；`multi_trainer_on_one` 里程碑允许例外
    - 已实现：`first_have_100` 的 CEO CFO 能力从**下一回合**开始生效（不影响达成当回合）
  - 回归与文档要求：
    - 每完成一个子项（E1/E2/E3/E4）必须：
      - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`
      - 更新 `docs/development_status.md` 与本文件进度
      - 对当次改动涉及的 `*.gd` 进行“tab 缩进检查”（禁止混用空格）

- ✅ M8：地图图片化（视觉资源模块化 + UI 渲染预留）
  - ✅ V1：新增 `VisualCatalog/VisualCatalogLoader`（`modules/*/content/visuals/*.json`），并接入 headless 测试 `VisualCatalogLoaderV2Test`
  - ✅ V2：实现 `MapSkin/MapSkinBuilder`（Texture 加载 + 缺失占位，Q12=C）
  - ✅ V3：Map 烘焙补齐 `tile_placements` 元数据（为 tile 底图/边界与调试预留）
  - ✅ V4：`MapView` 重构为 `MapCanvas(Control._draw)` 分层渲染（ground/road/drink/piece/marketing/selection）
  - ✅ V4.1：MapCanvas 贴图 key 扩展（道路 shape+运行时旋转 + bridge 独立 key；营销按 type + product badge；房屋需求叠加 product icons）
  - ✅ V5：为 `base_tiles/base_pieces/base_products/base_marketing` 落盘 `content/visuals` 与 `assets/` 目录约定（先占位，后替换真实美术）
- ✅ V6：生成并落盘真实 PNG（ground/road/bridge/pieces/product_icons/marketing_icons），替换占位贴图（AllTests 36/36）

---

## 3.3 Repo 清洁与边界收敛（2026-01-05 审计）

本节用于跟踪“结构/文件放置/硬编码/重复实现”的整理工作，优先处理**低风险高收益**项（忽略生成物、搬迁遗留输入数据），再进入更大规模的边界收敛（autoload/core 解耦）。

### R0 基线（每次整改的护栏）

- ✅ R0.1：Headless 全量测试通过（`AllTests 71/71`，见 `.godot/AllTests.log`）

### R1 Repo 清洁（生成物隔离）

- ✅ R1.1：新增 `.gitignore`，忽略 `.godot/`、`.tmp_home/`、`.godot_home/`、`.history/` 等生成/本地目录
- ✅ R1.2：移除误放置的迁移运行产物目录（删除 `data/migration/`）

### R2 迁移数据归位（tools/）

- ✅ R2.1：将 legacy `.tres` seeds 从 `data/migration/` 迁移到 `tools/migration/legacy_seeds/`
- ✅ R2.2：更新迁移脚本默认路径与输出目录（`tools/migration/out_legacy_json/`），避免向 `data/` 写入“非运行期权威数据”

### R3 Autoload/core 边界（降低耦合）

- ✅ R3.1：消除 `core/*` 对 `Globals` 的直接依赖（引入 `core/engine/game_constants.gd`；存档 schema/version 不再从 Globals 读取）
- ✅ R3.2：去重默认模块列表与 `modules_v2_base_dir` 默认值（引入 `core/engine/game_defaults.gd`，供 `autoload/globals.gd` 与 `GameEngine.initialize` 共用）
- ✅ R3.3：收敛 “`;` 分隔多模块根目录” 的解析逻辑为单一实现（引入 `core/modules/v2/module_dir_spec.gd`，替换 `GameEngine`/`VisualCatalogLoader`/`TileEditor` 3 处重复）

### R4 小而关键的健壮性修补（不改变对外规则）

- ✅ R4.1：`EventBus` 发射事件前校验 `Callable.is_valid()`，避免订阅者释放后的回调崩溃（并清理失效订阅）
- ✅ R4.2：`GameLog` 文件写入改为明确的 append 语义（存在则 `READ_WRITE + seek_end`，不存在则 `WRITE` 创建；避免潜在截断/覆盖）
- ✅ R4.3：清理/隔离未使用的 legacy API（删除 `GameData.load_from_dirs` 等旧入口，避免误用）

### R5 Autoload 细节收敛（低风险）

- ✅ R5.1：`Globals` 的 `SCHEMA_VERSION/MIN/MAX_PLAYERS` 常量统一引用 core 常量来源（避免漂移）

### R6 GameEngine 去重（低风险）

- ✅ R6.1：`_apply_modules_v2()` 不再重复 reset 各全局 Registry（统一由 `_reset_modules_v2()` 负责）
- ✅ R6.2：抽取模块系统 V2 装配/校验/重置到 `core/engine/game_engine/modules_v2.gd`，`GameEngine` 保留薄封装（降低主文件体积与漂移风险）
- ✅ R6.3：抽取 ActionRegistry 装配（ruleset validators/executors + ActionAvailability 编译）到 `core/engine/game_engine/action_wiring.gd`，`GameEngine._setup_action_registry()` 变为薄封装

### R7 二次审计：硬编码/重复逻辑（低风险优先）

- ✅ R7.0：二次全局扫描（硬编码/重复逻辑）
  - 发现：地图层重复常量（`TILE_SIZE=5` 与 `0/90/180/270` 旋转列表在多处重复）
  - 发现：`tools/check_compile.gd` 默认扫描未包含 `res://modules_test`（可能漏掉测试模块 entry 脚本编译错误）
  - 备注：`ceo`/产品 id 等字符串仍存在，但属于已确认决策（D0.4/D0.5）范围内的“保留 ID/内容 id”，不在本轮低风险整改的优先级里
- ✅ R7.1：地图层常量去重：旋转角/方向/TILE_SIZE 统一由 `core/map/map_utils.gd` 提供（避免漂移）
- ✅ R7.2：工具补齐：`tools/check_compile.gd` 默认 roots 增加 `res://modules_test`（避免漏检）

---

## 4. 工作流约定（每次整改的最小闭环）

每个工作项（例如 U1/P3/A1）遵循：

1) 明确边界：要拆什么、拆到哪里、保留哪些对外 API
2) 先写/改测试（或至少先定位现有测试覆盖点）
3) 小步迁移：保持编译/运行通过
4) 更新本文件 checklist 状态与“变更摘要”

---

## 5. 变更摘要（流水账）

- 2025-12-30：落盘整改计划到 `docs/refactor_plan.md`
- 2025-12-30：实现配置/状态/地图定义的严格解析（Fail Fast），清除容错/兼容路径：`GameConfig`、`GameState`、`TileDef/PieceDef/MapDef`
- 2025-12-30：存档加载改为严格 schema（拒绝旧版本），并强制 `rng` 与命令 `timestamp`
- 2025-12-30：移除地图选择/空地图占位 fallback；存档创建改为 fail-fast；移除 `get_rule_int(..., fallback)`；`all_tests` headless 通过
- 2025-12-31：补齐 T1 测试覆盖：新增 `core/tests/fail_fast_parsing_test.gd` 并接入 `ui/scenes/tests/all_tests.gd`；`all_tests` 23/23 通过（超时脚本）
- 2025-12-31：清理存档/回放默认值：`load_from_archive` 不再默认 `current_index`；`schema_version/current_index/rng_calls` 均要求严格整数；新增 `core/tests/archive_fail_fast_test.gd`；`all_tests` 24/24 通过（超时脚本）
- 2025-12-31：收紧引擎 invariants：缺字段/类型错误不再被默认值掩盖；新增 `core/tests/invariants_fail_fast_test.gd`；`all_tests` 25/25 通过（超时脚本）
- 2025-12-30：新增带硬超时的 headless 测试脚本 `tools/run_headless_test.sh`，并补充到 `docs/testing.md`
- 2025-12-31：修复 `core/engine/phase_manager.gd` 在离开 `Payday` 时错误回滚并提前 `return` 导致阶段无法推进/测试卡死
- 2025-12-31：抽离阶段结算模块（Payday/Cleanup/Dinnertime/Marketing）到 `core/rules/phase/*_settlement.gd`，并将 `core/engine/phase_manager.gd` 收敛为编排调用；`all_tests` headless 通过
- 2025-12-31：抽离银行破产规则到 `core/rules/economy/bankruptcy_rules.gd`，并在 `core/rules/phase/dinnertime_settlement.gd` 中接入
- 2025-12-31：抽离强制动作规则到 `core/rules/working/mandatory_actions_rules.gd`，并在 `core/engine/phase_manager.gd` 与 `core/tests/mandatory_actions_test.gd` 中接入
- 2025-12-31：完成 `procure_drinks` 规则下沉：新增 `core/rules/drinks_procurement.gd`，瘦身 `gameplay/actions/procure_drinks_action.gd` 为编排层；路线/饮料源解析改为严格校验；`all_tests` headless 通过
- 2025-12-31：完成 `initiate_marketing` 瘦身：新增 `core/utils/range_utils.gd` 与 `core/utils/round_state_counters.gd`，并在 `gameplay/actions/initiate_marketing_action.gd` 中接入；同时收紧参数/地图字段校验为 Fail Fast；`all_tests` headless 通过
- 2025-12-31：统一 round_state 计数写法：`produce_food`/`procure_drinks`/`place_house`/`add_garden`/`recruit` 接入 `core/utils/round_state_counters.gd`，删除重复计数工具代码；`all_tests` headless 通过
- 2025-12-31：T3：拆分 `core/rules/drinks_procurement.gd` 为 `core/rules/drinks_procurement/*`（输入解析/起点解析/默认选路/路线校验/拾取来源），主入口文件收敛并保持对外 API 不变；`all_tests` headless 通过
- 2025-12-31：收紧 `procure_drinks` / `drinks_procurement` 的参数解析为严格类型校验（移除 `str()`/`int()` 容错转换）；`all_tests` headless 通过
- 2025-12-31：拆分 `core/engine/game_engine.gd` 为 `core/engine/game_engine/*`（action_setup/archive/checkpoints/invariants/replay/diagnostics），降低单文件规模并保持行为不变；`all_tests` headless 通过
- 2025-12-31：拆分 `core/engine/phase_manager.gd` 为 `core/engine/phase_manager/*`（definitions/hooks/working_flow），降低单文件规模并保持行为不变；`all_tests` headless 通过
- 2026-01-01：整理并落盘“剩余硬编码规则点”清单与整改计划（E1–E4），新增待确认决策 D0.4–D0.7
- 2026-01-01：M5：修复 `core/tests/payday_salary_test.gd` 的缩进/结构错误，恢复可编译状态（为“结算必须注入 EffectRegistry”做准备）
- 2026-01-01：M5：修正结算调用点统一注入 `phase_manager`（PhaseManager/fixtures/tests），避免无 EffectRegistry 的隐式调用路径
- 2026-01-01：M5：移除 `core/engine/phase_manager.gd` 的 legacy settlement fallback（缺 `SettlementRegistry` 直接失败）
- 2026-01-01：M5：headless 回归通过：`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60`（34/34）
- 2026-01-01：收紧里程碑效果应用：`PricingPipeline` 与 OrderOfBusiness 的“首个降价/首个营销奖励/首个飞机营销空余卡槽”改为读取里程碑 JSON `effects.value`（`base_price_delta`/`sell_bonus`/`turnorder_empty_slots`），并移除对 `GameConfig.rules.marketing_bonus_per_unit` / `oob_first_airplane_bonus_slots` 等冗余常量的依赖；新增回归 `core/tests/milestone_effect_values_test.gd`；`all_tests` 35/35 通过（60s 超时脚本）
- 2025-12-31：A4：收紧 `gameplay/actions/*` 的 `command.params` 解析：新增 `core/actions/action_executor.gd` 严格解析工具（array/vector2i/int/string）；移除 actions 中 `command.params.get` / `str()` / `int()` 容错；`all_tests` headless 通过
- 2025-12-31：B1：收紧 Employee/Marketing/Milestone 定义加载为严格解析（Fail Fast），并移除员工 `aliases` 兼容字段；`all_tests` headless 通过
- 2025-12-31：拆分 `core/state/game_state.gd`：抽取 `GameStateSerialization/GameStateFactory/MapRuntime` 并迁移地图相关调用点；`all_tests` headless（90s 超时）通过
- 2025-12-31：收紧 `gameplay/validators/company_structure_validator.gd` 参数解析（`employee_id`/`to_reserve` 必填且严格类型），并更新 `core/tests/company_structure_test.gd`；`all_tests` headless（90s 超时）通过
- 2025-12-31：清理 `MapRuntime` 的静默兜底（缺字段/类型错/越界直接 assert），并收紧 `GameStateSerialization` 的 map 坐标解码（拒绝非整数 float）；`all_tests` headless（90s 超时）通过
- 2025-12-31：清理 `core/map/map_baker.gd` 的默认值/假设分支（含“piece_def 缺失则假设 2x2”）并收紧工具函数为 assert fail-fast；`all_tests` headless（90s 超时）通过
- 2025-12-31：U4 补充收敛：`GameState` 移除 map 默认结构；`GameStateFactory` 初始化 `state.map={}` 并清空 `_road_graph`；`MapRuntime.apply_baked_map()` 负责写入 `next_restaurant_id`；`core/tests/fail_fast_parsing_test.gd` 增补覆盖；`all_tests` headless（90s 超时）通过
- 2025-12-31：F8 补充收紧：`Command.from_dict()` 改为严格解析并返回 `Result`；`GameEngine.load_from_archive()` 使用该解析并拒绝缺字段/非整数 float；`drinks_procurement` 的 `route` 坐标解析支持 JSON 整值 float；扩展 `core/tests/archive_fail_fast_test.gd` 覆盖；`all_tests` headless（90s 超时）通过
- 2025-12-31：F11：收紧 `core/rules/employee_rules.gd`：移除 `player.get(..., default)` / `str()` 容错分支与 round_state.action_counts 默认值兜底（缺字段/类型错直接 assert）；`all_tests` headless（90s 超时）通过
- 2025-12-31：F12：清理放置/子阶段推进相关兜底：`PlacementValidator/HouseNumberManager` 移除默认值兜底并改为 assert fail-fast；`sub_phase_passed` 对每玩家强制 bool 初始化；相关 actions 移除 `.get(..., default)`；`all_tests` headless（90s 超时）通过（26/26）
- 2025-12-31：F13：恢复并收紧公司结构/强制动作：新增 `core/rules/company_structure_rules.gd`（空槽计算 + 容量收敛到预备区）；`MandatoryActionsRules` 移除 `mandatory_actions_completed.get(pid, [])` 等兜底并严格要求结构；`WorkingFlow/CompanyStructureValidator` 移除 `.get(..., default)`；补齐相关测试；`all_tests` headless（90s 超时）通过（26/26）
- 2025-12-31：全局 fallback 扫描：`core/`+`gameplay/`（不含 `core/tests/`）仍有约 221 处 `.get(..., default!=null)`/类型兜底；重点集中在 `core/rules/phase/dinnertime_settlement.gd`、`core/state/state_updater.gd`、`core/rules/marketing_range_calculator.gd`、`core/rules/phase/marketing_settlement.gd`、`core/map/road_graph.gd`、`core/rules/economy/bankruptcy_rules.gd`、`core/rules/phase/payday_settlement.gd` 与 `gameplay/actions/*`（待你确认整改范围后逐项清理）
- 2025-12-31：修复 `gameplay/actions/initiate_marketing_action.gd` 非 airplane 放置校验缩进/逻辑错误（blocked/road_segments/邻接道路）；`all_tests` headless（90s 超时）通过（26/26）
- 2025-12-31：清理 `gameplay/actions/advance_phase_action.gd` 的 `order_of_business` 访问方式（移除 `.get(..., null)`，改为 `has` + `[]`）；同时修复该段缩进导致的编译错误；`all_tests` headless（90s 超时）通过（26/26）
- 2025-12-31：收紧 `core/rules/phase/dinnertime_settlement.gd`：移除对 `owner/house_number/cells/distance` 等结构字段的默认值兜底与旧入口字段 fallback；距离计算改为 `Result` 驱动并严格输出 `int distance/steps`；`all_tests` headless（90s 超时）通过（26/26）
- 2025-12-31：收紧 `core/state/game_state_serialization.gd`：移除 `Array(..., TYPE_*)` 容错转换，改为逐项严格校验并构建 `Array[Dictionary]/Array[String]`；`round_state.mandatory_actions_completed` 不再通过 `Array(..., TYPE_STRING)` 强制转换；`all_tests` headless（90s 超时）通过（26/26）
- 2025-12-31：收紧 Marketing 结算与范围计算：`core/rules/phase/marketing_settlement.gd` 移除默认值兜底并严格要求营销实例字段（含 `axis/tile_index/created_round`）与 `marketing_placements` 一致；`core/rules/marketing_range_calculator.gd` 改为返回 `Result` 并移除推断/静默空结果兜底；新增 `core/tests/marketing_settlement_fail_fast_test.gd` 并修复 `core/tests/milestone_system_test.gd` 的营销实例注入；`all_tests` headless（90s 超时）通过（27/27）
- 2025-12-31：收紧 Payday/Bankruptcy：`core/rules/phase/payday_settlement.gd` 与 `core/rules/economy/bankruptcy_rules.gd` 移除 `.get(..., default)` 默认值兜底并对关键字段做严格类型校验（缺字段/类型错直接失败或 assert）；`all_tests` headless（90s 超时）通过（27/27）
- 2025-12-31：收紧 `core/state/state_updater.gd`：现金转账/数组操作/库存/员工池/里程碑/批量更新移除 `.get(..., default)` 与静默兜底；关键结构字段缺失直接失败或 assert；`all_tests` headless（90s 超时）通过（27/27）
- 2026-01-01：落盘模块系统 V2（严格模式 + 结算全模块化 + 路线B）方案与 ADR；更新 `docs/design.md` 与架构文档索引
- 2026-01-01：实现模块系统 V2 的 M1（模块包目录 + module.json 严格解析 + 加载器）并接入 headless 测试；`all_tests` 31/31 通过（60s 超时脚本）
- 2026-01-01：启动模块系统 V2 的 M2：新增 per-game `ContentCatalog` 与加载器（employees/milestones），并新增 headless 测试；`all_tests` 32/32 通过（60s 超时脚本）
- 2026-01-01：新增模块系统 V2 的 ModulePlanBuilder（依赖闭包/冲突检测/确定性拓扑排序）与 headless 测试；同时修复 `NightShiftManagersModuleTest` 对“当前回合玩家必为 0”的脆弱假设；`all_tests` 33/33 通过（60s 超时脚本）
- 2026-01-01：接入模块系统 V2 到 `GameEngine.initialize()`（可选启用，支持指定 modules base_dir），并新增集成测试 `core/tests/module_system_v2_bootstrap_test.gd`；`all_tests` 34/34 通过（60s 超时脚本）
- 2026-01-01：启动 V2 M3（路线B，1x 按玩家人数决定每种卡张数）：为 `modules/*/content/employees/*`（部分）与 `modules/*/content/milestones/*` 增加 `pool` 元数据，并收紧 `MilestoneDef` 强制要求 `pool.enabled`；`all_tests` 34/34 通过（60s 超时脚本）
- 2026-01-01：实现 V2 M3 的 PoolBuilder（从内容元数据推导 Pools）并接入 `GameStateFactory` 构建初始 `employee_pool/milestone_pool`（`one_x_employee_copies` 以整数写入 `state.rules` 以保持存档规则字段为 int）；`all_tests` 34/34 通过（60s 超时脚本）
- 2026-01-01：完成路线B 的 GameConfig 精简：移除 `employee_pool.base` / `one_x_employee_ids` / `milestones.pool`，并将 `one_x_employee_copies_by_player_count` 移入 `rules`（schema_version=2）；`all_tests` 34/34 通过（60s 超时脚本）
- 2026-01-01：新增 `core/tests/pool_builder_v2_test.gd` 并接入 `ui/scenes/tests/all_tests.gd`，覆盖 one_x=按人数张数与 `MilestoneDef.pool` 必需字段；`all_tests` 35/35 通过（60s 超时脚本）
- 2026-01-01：实现 V2 M4 SettlementRegistry：新增 `core/rules/settlement_registry.gd` 与 `core/modules/v2/ruleset*`（entry_script 注册 + 生命周期持有）；V2 初始化时强制校验必需 primary settlements（缺失/重复直接失败）；PhaseManager 在 V2 模式下通过注册表调用结算；落盘 `modules/base_rules/`；新增 `core/tests/settlement_registry_v2_test.gd`；`all_tests` 36/36 通过（60s 超时脚本）
- 2026-01-01：饮料采购里程碑效果从里程碑 JSON `effects.value` 读取：`first_cart_operator/distance_plus_one`（范围+1）与 `first_errand_boy/procure_plus_one=1`（每源+1）；接入 `DrinksProcurement`/`ProcureDrinksAction` 并扩展 `ProcureDrinksRouteRulesTest` 覆盖；`all_tests` 37/37 通过（60s 超时脚本）
- 2026-01-01：补回缺失的 `tools/check_compile.gd`（遍历 load 常用脚本目录，便于排查脚本语法错误导致的 preload 失败）；`all_tests` headless（60s 超时脚本）通过（35/35）
- 2026-01-01：Working 子阶段数据驱动修正：Train 次数按员工 JSON `train_capacity` 统计（trainer/coach/guru），PlaceHouses 判定改用员工 `usage_tags`（`use:place_house`/`use:add_garden`）；更新 `PlaceHouseRulesTest/AddGardenRulesTest`；`all_tests` headless（60s 超时脚本）通过（35/35）
- 2026-01-01：Recruit/Payday 数据驱动修正：新增员工字段 `recruit_capacity`（`use:recruit` 必填且 >0）；Recruit 次数按 `recruit_capacity` 汇总；Payday 薪资折扣次数由 effect handler 读取 `recruit_capacity`，且仅在岗员工计入（待命不计入）；更新 `PaydaySalaryTest` 覆盖；`all_tests` headless（60s 超时脚本）通过（35/35）
- 2026-01-01：M6：移除旧模块系统 V1（`data/modules/*`、`core/modules/*` 旧实现、V1 模块相关测试与入口）；`GameEngine.initialize()` 收敛为仅接收 V2 modules；`all_tests` 34/34 通过（60s 超时脚本）
- 2026-01-01：新增基础内容模块包 `modules/base_employees/` 与 `modules/base_milestones/`（module.json+README+content）；将员工/里程碑 JSON 迁移到模块 content
- 2026-01-01：完成 V2 M2（employees/milestones 运行时接管）：`EmployeeRegistry/MilestoneRegistry` 不再从 `data/` 懒加载，改为由 `ContentCatalog` 装配；`GameEngine.initialize()` 默认启用 `base_rules/base_employees/base_milestones`；`load_from_archive()` 按 `state.modules` 装配模块计划；`all_tests` 34/34 通过（60s 超时脚本）
- 2026-01-01：删除 `data/employees/` 与 `data/milestones/`（避免数据双源；以 `modules/*/content/*` 为唯一权威）
- 2026-01-01：完成 V2 M2（marketing 运行时接管）：新增 `modules/base_marketing/`；`ContentCatalog` 加载 `content/marketing`；`MarketingRegistry` 由 `ContentCatalog` 装配并删除 `data/marketing/`；`all_tests` 34/34 通过（60s 超时脚本）
- 2026-01-02：M7/E1：解雇规则从硬编码 `ceo` 迁移为员工数据字段 `can_be_fired`（`ceo.json=false`）；修复 `EmployeeDef.to_dict()` 缩进导致的脚本解析失败；`all_tests` 35/35 通过（60s 超时脚本）
- 2026-01-02：M7/E4：新增 `MilestoneEffectRegistry` + 严格 init 校验（缺 handler fail fast）；补齐 Recruit/PaySalaries/CashReached 触发点；实现 `ban_card/multi_trainer_on_one/ceo_get_cfo`；`first_have_100` CFO 能力下一回合生效；扩展 `MilestoneSystemTest` 覆盖；`all_tests` 35/35 通过（60s 超时脚本）
- 2026-01-02：M2：随机地图生成接入（规则驱动）：`content/maps/*.json` 改为 MapOption（主题/选项）；由 base_rules 注册 primary map generator 按 `docs/rules.md` 的玩家数规则生成网格尺寸，并从本局 `ContentCatalog.tiles`（按文件夹枚举）**不放回**抽取 tile，`random_rotation=true` 时随机旋转；修复 `RandomManager.shuffle()` 非确定性（内部错误调用全局随机）；补齐 `apartment/park` pieces 以支持 `tile_x/y/z`；新增 `RandomMapGenerationTest`；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 回归通过（37/37）
- 2026-01-03：模块10 大众营销员（Mass Marketeers）按 V2 模块包落盘：新增 `modules/mass_marketeers/`（Marketing enter extension 写入 `round_state.marketing_rounds`）；新增 `core/tests/mass_marketeers_v2_test.gd` 并接入 `all_tests`；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 回归通过（38/38）
- 2026-01-03：模块8 番茄酱机制（The Ketchup Mechanism）按 V2 模块包落盘：新增 `modules/ketchup_mechanism/`（Dinnertime enter extension 触发 `KetchupSoldDemand`）；`DinnertimeSettlement` 新增 `:dinnertime:distance_delta:` segment；`MilestoneDef.pool.count` 支持拷贝数；新增 `core/tests/ketchup_mechanism_v2_test.gd` 并接入 `all_tests`；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 回归通过（39/39）
- 2026-01-03：模块15 电影明星（Movie Stars）按 V2 模块包落盘：新增受控 `register_employee_patch`（跨模块培训链）；新增 `modules/movie_stars/`（patch `waitress.train_to += movie_star` + 注册 tiebreak effect）；OrderOfBusiness 排序加入 `movie_star` 优先逻辑；新增 `core/tests/movie_stars_v2_test.gd` 并接入 `all_tests`；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 回归通过（40/40）
- 2026-01-03：模块11 夜班经理（Night Shift Managers）按 V2 模块包落盘：新增 V2 phase/sub_phase hook 注册并接入 `PhaseManager`；Strict Mode 校验 `train_to` 引用必须存在；新增 `modules/night_shift_managers/`（Working BEFORE_ENTER 写入 `working_employee_multipliers`，不叠加，CEO 排除；员工池 fixed=6）；新增 `core/tests/night_shift_managers_v2_test.gd` 并接入 `all_tests`；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 回归通过（41/41）
- 2026-01-03：模块6/7（面条/寿司）占位落盘：新增 `modules/noodles/` 与 `modules/sushi/`（当前仅提供 `noodles_cook/sushi_cook` 员工定义，供培训链/依赖引用；规则细节后续实现）
- 2026-01-03：模块9 薯条厨师（Fry Chefs）按 V2 模块包落盘：`DinnertimeSettlement` 新增 `:dinnertime:sale_house_bonus:` segment 并写入 `round_state.dinnertime.income_sale_house_bonus`；新增 `modules/fry_chefs/`（员工 `fry_chef` pool fixed=8，salary=true；patch 多个厨师 `train_to += fry_chef`；注册 `fry_chefs:dinnertime:sale_house_bonus:fry_chef`：仅对“非饮品 food”房屋售卖每个 fry_chef +$10）；新增 `core/tests/fry_chefs_v2_test.gd` 并接入 `all_tests`；`tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 回归通过（42/42）
- 2026-01-03：为模块12（乡村营销员 / Rural Marketeers）的“大改 offramp（棋盘外放 tile）”铺路：新增 `state.map.external_cells/external_tile_placements` 与 RoadGraph 外部格子建图支持；`MapUtils.crosses_tile_boundary` 支持负坐标；Dinnertime 路网入口点支持“结构格自身为道路”；MapCanvas 支持负坐标/外部格子渲染；RulesetV2 支持模块注册自定义 ActionExecutor（供模块新增动作）；回滚误放入 core 的 `giant_billboard` type/range 分支（保持“模块内容/规则由模块注册”）；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（42/42）
- 2026-01-03：模块12（乡村营销员 / Rural Marketeers）框架落盘：新增 `modules/rural_marketeers/`（员工/里程碑/entry/actions + 飞机/出口互斥 validator）；`DinnertimeSettlement._append_sold_marketed_demand_events` 放宽 `house_number` 类型（允许 String，供模块注入“乡村地区”房屋）；新增 `core/tests/rural_marketeers_v2_test.gd` 并接入 `all_tests`；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（43/43），`tools/check_compile.gd` 通过（179 files）
- 2026-01-03：模块12（乡村营销员 / Rural Marketeers）完善边缘冲突映射：飞机在角落时视为“同时占用两条边”（返回双 edge keys），用于 offramp/airplane 互斥校验；并统一使用 `MapUtils.TILE_SIZE`；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（43/43），`tools/check_compile.gd` 通过（179 files）
- 2026-01-03：模块12（乡村营销员 / Rural Marketeers）继续收紧与补齐内容：`place_highway_offramp` 严格要求 `tile_id==highway_offramp`；模块包新增 `content/tiles/highway_offramp.json` 并在 `module.json` 声明 `tiles`；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（43/43），`tools/check_compile.gd` 通过（179 files）
- 2026-01-03：纠正模块12（乡村营销员 / Rural Marketeers）对 offramp 的建模：`highway_offramp` 实际为 **1x2 的 piece**（非 5x5 tile）。因此撤回上一轮的 TileRegistry/tile 方案（移除 `core/map/tile_registry.gd` 与 `modules/rural_marketeers/content/tiles/highway_offramp.json`），改为 `modules/rural_marketeers/content/pieces/highway_offramp.json`；`place_highway_offramp` 改为按 **边缘连接格 world_pos** 放置（严格要求连接格存在“朝外道路段”，且与 airplane 同格互斥），并在棋盘外写入 2 个 external road cells（确定性、冲突 fail）；距离计算起点由模块提供的“单个连接格”列表驱动。回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（43/43），`tools/check_compile.gd` 通过（179 files）
- 2026-01-03：模块12（乡村营销员 / Rural Marketeers）进一步收紧 offramp 放置：连接格必须为道路且除“朝外方向”外还至少连接一个内部方向（避免不连路的伪造 edge segment）；同时将 offramp placement 记录补齐 `owner/rotation/occupied`，并把外部格子的 `structure` 写入 `owner/rotation` 以便后续贴图与调试；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（43/43），`tools/check_compile.gd` 通过（179 files）
- 2026-01-03：为模块13（美食评论家 / Gourmet Food Critics）铺路：新增可由模块注册的 `MarketingTypeRegistry`（支持 `requires_edge` 与自定义 range handler）；`MarketingDef` 放开 `type` 限制；`InitiateMarketingAction` 基于 `requires_edge` 统一边缘放置规则；`MarketingRangeCalculator` 对未知 type 改为调用模块 handler（缺 handler → 失败）；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（43/43），`tools/check_compile.gd` 通过（180 files）
- 2026-01-03：模块13 美食评论家（Gourmet Food Critics）按 V2 模块包落盘：新增 `modules/gourmet_food_critics/`（员工 `gourmet_food_critic` salary=true pool fixed=6，`marketing_max_duration=3`，`range=air:-1`；营销板件 `gourmet_guide`（board_number=17–20）；注册 marketing type `gourmet_guide`：边缘放置且范围=所有带花园房屋；`initiate_marketing` 校验“全局最多 3 个同类 token”与“同格 offramp 冲突”；新增 `core/tests/gourmet_food_critics_v2_test.gd` 并接入 `all_tests`；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（44/44），`tools/check_compile.gd` 通过（182 files）
- 2026-01-03：为模块14（Reserve Prices）铺路：新增可由模块注册的 `BankruptcyRegistry`（目前支持 `first_break` handler），并在 `BankruptcyRules._break_the_bank_first_time` 优先调用模块 handler（Strict：handler 必须返回 `Result`）；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（44/44），`tools/check_compile.gd` 通过（185 files）
- 2026-01-03：模块14 储备价格（Reserve Prices）按 V2 模块包落盘：新增 `modules/reserve_prices/`（第 1 回合进入 Restructuring 时为每位玩家确定性发 3 张“替代储备卡”（18 张牌堆，类型 5/10/20 各 6 张）；第一次破产固定注资 `$200×人数`，不再修改 CEO 卡槽；统计玩家选择的储备卡类型决定 `state.rules.base_unit_price`（并列按 `20 > 5 > 10`）；新增 `core/tests/reserve_prices_v2_test.gd` 并接入 `all_tests`）；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（45/45），`tools/check_compile.gd` 通过（185 files）
- 2026-01-03：模块15 电影明星（Movie Stars）规则升级：将 `movie_star` 拆分为 `movie_star_b/c/d`（salary=true，unique=true，pool fixed=1/张），并通过 action validator 限制“每位玩家最多 1 张电影明星”；OrderOfBusiness 的“明星优先”从 `WorkingFlow` 中移除，改由模块在 `OrderOfBusiness:after_enter` hook 按 B>C>D 重排选择顺序（其余玩家再按空槽数排序；同级明星出现直接失败）；晚餐平局通过 `movie_stars:dinnertime:tiebreaker:movie_star_{b|c|d}` 实现并满足严格排序；更新 `core/tests/movie_stars_v2_test.gd`；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（45/45），`tools/check_compile.gd` 通过（185 files）
- 2026-01-03：为模块16（Hard Choices）铺路：新增 `RulesetV2.register_milestone_patch/apply_milestone_patches`（受控 patch：`set_expires_at`），并在 V2 初始化时应用到 `ContentCatalog.milestones`；将基础里程碑中“回合到期移除”的 `expires_at` 从 `base_milestones` 撤回为 `null`，避免变体规则常驻；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（45/45），`tools/check_compile.gd` 通过（187 files）
- 2026-01-03：模块16 艰难抉择（Hard Choices）按 V2 模块包落盘：新增 `modules/hard_choices/`，通过 milestone patch 将 `first_*` 起步里程碑设置为 `expires_at=2/3`；新增 `core/tests/hard_choices_v2_test.gd` 并接入 `all_tests`；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（46/46），`tools/check_compile.gd` 通过（187 files）
- 2026-01-03：模块1 新区域（New Districts）按 V2 模块包落盘：新增 `modules/new_districts/`，并将 `tile_u/v/w/x/y` 与 `apartment` piece 从 `base_tiles/base_pieces` 迁移至本模块（Strict：禁用即不存在）；新增 `MapBaker` 的 `printed_structures[].house_props` 透传能力；新增 `MarketingSettlement` 的 `houses[*].marketing_demand_multiplier`（支持公寓营销 *2）并复用 `no_demand_cap`；新增 `core/tests/new_districts_v2_test.gd` 并接入 `all_tests`；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（47/47），`tools/check_compile.gd` 通过（188 files）
- 2026-01-03：V2 工作阶段子阶段支持模块扩展（通用机制）：新增 `working_sub_phase_order`（字符串数组）并允许 Ruleset 以“插入点(after/before)”方式加入自定义子阶段名，同时支持按名注册 Working 子阶段 hooks；PhaseManager/Defs/Hooks/RulesetV2/RuesetBuilder 完成接线（Strict：顺序必须包含所有基础子阶段，缺失/重复直接失败）
- 2026-01-03：地图坐标与扩边通用支撑（为模块2“说客”的“立即拼接新地图板块”准备）：新增 `state.map.map_origin`（支持 world_pos 为负）；MapRuntime/RoadGraph/MapCanvas/PlacementValidator/RangeUtils/MarketingRangeCalculator/InitiateMarketingAction 适配 map_origin；新增 `MapRuntime.ensure_world_rect` 与 `MapRuntime.add_map_tile`（扩展 cells 矩形并在 void 区域默认 blocked=true，使用 `MapBaker.bake_tile_into_cells` 增量烘焙 tile）；并放开 airplane 的 `tile_index` 负值支持
- 2026-01-03：为模块2“说客 (Lobbyists)”继续铺路：新增 `TileRegistry/PieceRegistry`（Strict：由 ContentCatalog 装配并在 GameEngine 初始化阶段配置）；GameEngine 初始化写入 `state.map.tile_supply_remaining`（供模块实现“从剩余 tile 中选择并扩边”）；DinnertimeSettlement 支持 `distance_ctx.path/steps` 以及 `global_effect_ids`（模块可注册全局距离/奖金修正）；新增 `modules/lobbyists/`（员工/里程碑/道路 pieces/Tile Z/工作子阶段插入与动作骨架，待补齐测试与规则细节）
- 2026-01-03：为模块6/7（Noodles/Sushi）补齐“晚餐需求替代”通用扩展点：新增 `DinnertimeDemandRegistry`（模块可注册 demand variants），并在 `DinnertimeSettlement` 按 `rank` 选择可成交的替代方案；同时新增 `ProductDef.starting_inventory` 并由 `GameStateFactory` 以产品集合生成完整起始库存 key 集（允许启用模块扩展产品集合）；`initiate_marketing` 拒绝 `tags` 包含 `no_marketing` 的产品；新增 `modules/noodles`/`modules/sushi` 的产品与规则 entry（仍保留员工卡数据占位）；新增回归 `core/tests/noodles_sushi_v2_test.gd` 并接入 `all_tests`；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（49/49）
- 2026-01-03：实现“额外奢侈品经理卡”通用机制：新增 `EmployeePoolPatchRegistry`（模块可声明对 `state.employee_pool` 的受控增量 patch，并支持同 patch_id 去重以满足“多模块仍只加一次”）；在 `GameEngine.initialize` 中应用 patches；模块6/7（面条/寿司）补齐员工卡数据（`*_cook` fixed=12 产出3，`*_chef` unique 产出8，并通过 patch 将 `kitchen_trainee` 的 `train_to` 扩展为对应 cook）；新增回归覆盖“luxury_manager 只加一次”；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（49/49）
- 2026-01-03：模块5 泡菜（Kimchi）按 V2 模块包落盘：新增 `modules/kimchi/`（产品 `kimchi` 不可营销；员工 `kimchi_master` one_x）；通过 `DinnertimeDemandRegistry` 提供 `kimchi_plus_base`/`kimchi_plus_{noodles|sushi}` variants（优先选择可成交的“带 kimchi”餐厅）；Cleanup 结算以模块 extension 方式在丢弃后生产 kimchi，并以确定性规则强制“存 kimchi 则其他产品清空，kimchi clamp=10”；复用 `extra_luxury_manager` employee_pool patch（只加一次）；新增 `core/tests/kimchi_v2_test.gd` 并接入 `all_tests`；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（50/50）
- 2026-01-04：模块2 说客（Lobbyists）补齐回归：扩展 `core/tests/lobbyists_v2_test.gd` 覆盖 roadworks 距离惩罚与 park 单价翻倍的 `global_effect_ids` 调用路径；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（52/52）
- 2026-01-04：M5+（阶段/子阶段/结算进一步模块化）补齐“动作可用性”模块注册：新增 `core/actions/action_availability_registry.gd` 并在 ActionRegistry/GameEngine 接入；Ruleset 新增 `register_action_availability_override`；新增回归 `core/tests/action_availability_override_v2_test.gd` 与 `modules/action_availability_override_test/`；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（71/71）
- 2026-01-05：测试结构整理：新增 `modules_test/` 并将测试专用模块包迁移出 `modules/`；V2 模块加载支持多根目录（`res://modules;res://modules_test`）；将 `ui/scenes/tests/` 旧测试场景移动到 `ui/scenes/tests/legacy/`；回归 `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 60` 通过（71/71）
- 2026-01-05：启动 Repo 清洁与边界收敛（R0–R4）：新增 `.gitignore` 并落盘追踪清单
- 2026-01-05：迁移 legacy `.tres` seeds 到 `tools/migration/legacy_seeds/`，删除 `data/migration/`；迁移脚本输出改为 `tools/migration/out_legacy_json/`
- 2026-01-05：core 解耦 autoload：移除 `core/*` 对 `Globals` 的引用（`GameConstants` + 统一存档 schema/version 来源）
- 2026-01-05：收敛模块系统 V2 的默认值与多根目录解析：`GameDefaults` + `ModuleDirSpec`，并接入 `GameEngine/Globals/VisualCatalogLoader/TileEditor`；`all_tests` 71/71 通过
- 2026-01-05：`EventBus.emit_event` 增加 `Callable.is_valid()` 校验并清理失效订阅，避免释放后回调崩溃；`all_tests` 71/71 通过
- 2026-01-05：`GameLog` 文件写入改为明确 append 语义（避免潜在截断/覆盖）；`all_tests` 71/71 通过
- 2026-01-05：清理未使用 legacy API：删除 `GameData.load_from_dirs` 等旧入口（V2 仅通过 ContentCatalog 装配）；`all_tests` 71/71 通过
- 2026-01-05：`Globals` 常量对齐：`SCHEMA_VERSION/MIN/MAX_PLAYERS` 改为引用 core 常量来源，避免漂移；`all_tests` 71/71 通过
- 2026-01-05：收口 M7（硬编码迁移）：D0.4–D0.7 对应 E1–E4 已全部落地并回归通过
- 2026-01-05：`GameEngine._apply_modules_v2()` 去重：不再重复 reset 全局 Registry（统一由 `_reset_modules_v2()` 负责）；`all_tests` 71/71 通过
- 2026-01-05：抽取模块系统 V2 装配实现：新增 `core/engine/game_engine/modules_v2.gd` 并由 `GameEngine` 调用；`all_tests` 71/71 通过
- 2026-01-05：抽取 ActionRegistry 装配实现：新增 `core/engine/game_engine/action_wiring.gd` 并由 `GameEngine._setup_action_registry()` 调用；`all_tests` 71/71 通过
- 2026-01-05：R7 二次审计落地（低风险）：地图层常量去重（`MapUtils.TILE_SIZE/VALID_ROTATIONS`）并补齐 `tools/check_compile.gd` 默认 roots 包含 `res://modules_test`；`tools/check_compile.gd` 通过（247 files），`all_tests` 71/71 通过

> 每完成一个工作项，在这里追加一条记录，便于回溯。

- 2025-12-30：建立本重构整改计划文档（尚未开始代码整改）
