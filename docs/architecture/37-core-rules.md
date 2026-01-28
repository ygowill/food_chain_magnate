# 模块：core/rules（规则系统与 registries）

`core/rules` 是“领域规则与结算”的主要落点。它与 `gameplay/actions` 的分工通常是：

- actions：把玩家输入转换成“状态写入”，并触发必要的校验与缓存失效
- rules：提供跨动作复用的领域规则、结算、以及可插拔的 registry/provider

## 结算框架（SettlementRegistry）

- 注册表：`core/rules/settlement_registry.gd`
- 结算实现：例如 `core/rules/phase/dinnertime_settlement.gd`（内部再拆到子目录）

关键约束（Strict Mode）：

- 每个 `(phase, point)` 必须且只能有 1 个 **primary settlement**（缺失直接失败）
- **extension settlements** 可选，按 `priority` 排序
  - `<100`：primary 前
  - `>=100`：primary 后

`PhaseManager` 通过 settlement triggers 在 enter/exit 边界调用 registry（触发点可被模块覆盖）。

## EffectRegistry（可插拔效果）

`EffectRegistry` 用于把“员工/里程碑/全局效果”从硬编码迁移为可注册 handler：

- registry：`core/rules/effect_registry.gd`
- milestone effects：`core/rules/milestone_effect_registry.gd` + `core/rules/milestone_effect_queries.gd`

模块系统 V2 会对 content 引用的 effect handler 做严格校验（缺失即初始化失败），避免运行期 silent fallback。

## 其它关键 registries（按需扩展）

模块系统 V2 会把模块提供的规则注册到一组 core-owned registries，典型包括：

- 晚餐需求：`core/rules/dinnertime_demand_registry.gd`
- 路上购买（晚餐扩展点）：`core/rules/dinnertime_route_purchase_registry.gd`
- 破产处理：`core/rules/bankruptcy_registry.gd`
- 营销类型与范围：`core/rules/marketing_type_registry.gd`、`core/rules/marketing_range_calculator.gd`
- 营销发起：`core/rules/marketing_initiation_registry.gd`
- 放置冲突查询：`core/rules/placement_conflict_registry.gd`（避免模块互相窥探 state）
- 员工池 patch：`core/rules/employee_pool_patch_registry.gd`
- 地图生成：`core/rules/map_generation_registry.gd`

这些 registries 的共同目标是：**跨模块协作通过 registry/provider，而不是通过直接读取别的模块私有 state 字段**。

## 与模块系统 V2 的关系

RulesetV2（`core/modules/v2/ruleset.gd`）是“模块注册规则的聚合容器”，装配时（`core/engine/game_engine/modules_v2.gd`）会：

- 构建 `ruleset_v2`
- 把其 settlement/effect registry 注入 `PhaseManager`
- 用其 providers 配置上述各类 core registries

因此：在 Strict Mode 下，规则与内容的存在性由“启用模块集合”决定，缺失应尽量在初始化阶段 fail-fast。

