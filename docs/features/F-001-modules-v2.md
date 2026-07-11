---
id: F-001
doc_kind: feature
status: done
created: 2026-01-01
updated: 2026-07-11
owners: [gameplay-architecture]
requirement_ids: [REQ-001, REQ-002, NFR-001]
decision_refs: [docs/decisions/0001-data-format-json.md, docs/decisions/0002-modules-v2-strict-mode.md, docs/decisions/0003-core-boundary-guardrails.md]
validation_refs: [docs/validation/VAL-2026-001-all-tests-baseline.md]
review_after: 2027-01-11
---

# F-001：Modules V2

## 当前结论

Modules V2 是当前唯一模块装配体系。新局和读档都根据启用模块及依赖闭包装配 ContentCatalog、Ruleset 和 UI 扩展；V1 已移除。这里的 done 表示当前 V2 装配和 Strict Mode 合同已落地，不表示未来不再增加模块扩展点。

## 背景、目标与范围

目标是让“禁用模块”在运行期真正不存在，并把内容、动作、阶段结算和扩展规则从核心编排中解耦。初始化阶段必须拒绝缺失依赖、冲突、重复注册和无效引用。

范围包括模块包发现、依赖计划、JSON 内容目录、Ruleset 注册、结算装配、模块 UI 元数据和边界守卫。

Non-goals：

- 不提供运行中热卸载或热替换模块。
- 不恢复 V1 兼容路径。
- 不把 Godot Resource 重新设为提交到仓库的权威数据源。
- 不承诺任意第三方模块 ABI 的长期二进制兼容。

## Requirements 与验收标准

这些 Requirement ID 的规范性定义来自[项目级需求](../REQUIREMENTS.md)；本页只维护 F-001 的验收解释、判定与证物映射。

| ID | Requirement / AC | 判定 | 证物 |
|---|---|---|---|
| REQ-001 | 每局只从启用模块与依赖闭包装配内容和规则；禁用模块内容不可见，依赖、冲突和 manifest 错误在初始化期失败 | pass | [ModulePlanBuilder 测试](../../core/tests/module_plan_builder_v2_test.gd)、[PackageLoader 测试](../../core/tests/module_package_loader_v2_test.gd) |
| REQ-002 | 动作、阶段 hooks 与必需 primary settlements 通过 V2 Ruleset 注册；缺失或重复 primary settlement 必须 fail fast | pass | [V2 bootstrap 测试](../../core/tests/module_system_v2_bootstrap_test.gd)、[Ruleset loader](../../core/modules/v2/ruleset_loader.gd) |
| NFR-001 | 新局、读档和模块组合保持确定性；核心与模块/UI 边界由自动契约守卫 | pass | [Module boundary guard](../../core/tests/module_boundary_contract_test.gd)、[Core boundary guard](../../core/tests/core_architecture_boundary_contract_test.gd)、[基线验证](../validation/VAL-2026-001-all-tests-baseline.md) |

## Related Artifacts

### 原始需求与设计意图

- [项目级 Requirements](../REQUIREMENTS.md) 定义 REQ-001、REQ-002 与 NFR-001。
- [ADR 0002：严格模式与结算全模块化](../decisions/0002-modules-v2-strict-mode.md) 是 Strict Mode 的规范性来源。
- [ADR 0001：JSON 权威数据源](../decisions/0001-data-format-json.md) 定义模块内容的数据格式边界。

### Decisions

- [ADR-0001](../decisions/0001-data-format-json.md)
- [ADR-0002](../decisions/0002-modules-v2-strict-mode.md)
- [ADR-0003](../decisions/0003-core-boundary-guardrails.md) 提供防止 core/module/UI 边界回流的 Guardrail。

### Architecture

- [Modules V2 当前实现](../architecture/60-modules-v2.md)
- [Core 状态扩展契约](../architecture/33a-core-state-schema-contract.md)
- [测试架构](../architecture/52-testing.md)

### Plans

- [模块 UI 解耦落地方案](../plans/module_ui_decoupling_plan_2026-02-10.md) 是已完成过程材料，不承担当前 Feature 状态。
- [Architecture 模块审查计划](../plans/archive/architecture_module_review_plan_2026-04-30.md) 包含 Modules V2 的后续审查记录，不承担当前架构真相。

### Code

- [GameEngine 装配入口](../../core/engine/game_engine/modules_v2.gd)
- [Module manifest parser](../../core/modules/v2/module_manifest.gd)
- [Module plan builder](../../core/modules/v2/module_plan_builder.gd)
- [Content catalog loader](../../core/modules/v2/content_catalog_loader.gd)
- [Ruleset loader](../../core/modules/v2/ruleset_loader.gd)
- [Gameplay UI metadata bootstrap](../../gameplay/module_ui_metadata_bootstrap.gd)

### Tests and Validation

- [Module package loader tests](../../core/tests/module_package_loader_v2_test.gd)
- [Module plan builder tests](../../core/tests/module_plan_builder_v2_test.gd)
- [Content catalog tests](../../core/tests/content_catalog_v2_test.gd)
- [Module system bootstrap tests](../../core/tests/module_system_v2_bootstrap_test.gd)
- [Module boundary contract](../../core/tests/module_boundary_contract_test.gd)
- [2026-07-11 AllTests 基线](../validation/VAL-2026-001-all-tests-baseline.md)

## 已知限制与偏差

- ADR-0001 提到的独立 JSON Schema 与迁移工具仍不是完整的仓库级交付；当前主要依赖解析器和测试 fail fast。
- UI 扩展已经从规则 holder 分离，但仍由 module metadata 桥接到 gameplay/UI；扩大接口前应复核 ADR-0003。
- 本次 Validation 是本地 headless 全量基线，没有持久化 CI Artifact；原始日志不能跨工作区复核。
- Godot 退出时仍有资源泄漏警告，功能断言通过不等于这些警告已解决。

## Next Action

- gameplay-architecture：新增模块 schema 字段或扩展注册类型时同步更新 ADR/Architecture、边界测试与本页 Requirement/AC。
- quality-engineering：在新的 PR Quality Gate 首次成功运行后，把 commit/run 绑定的 Artifact 链接写入新的 Validation；当前本地基线不回填尚未发生的 CI 证物。
