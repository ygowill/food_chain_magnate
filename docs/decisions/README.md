# Architecture Decision Records

ADR 记录长期有效的高影响决策、取舍和替代关系。ADR 的有效状态只以各文件 Frontmatter 为准；本索引不复制状态。

| ID | Decision | Related Feature |
|---|---|---|
| ADR-0001 | [数据格式采用 JSON](0001-data-format-json.md) | [F-001](../features/F-001-modules-v2.md) |
| ADR-0002 | [Modules V2 Strict Mode](0002-modules-v2-strict-mode.md) | [F-001](../features/F-001-modules-v2.md) |
| ADR-0003 | [Core 边界冻结与守卫测试](0003-core-boundary-guardrails.md) | [F-001](../features/F-001-modules-v2.md) |
| ADR-0004 | [联机恢复房单 full-engine 启动](0004-online-resume-single-full-engine-startup.md) | [F-002](../features/F-002-online-resume-bootstrap.md) |

新增 ADR 使用 [Decision 模板](../templates/decision.md)。accepted ADR 的原决策正文不应被改写；结论变化时创建新 ADR，并在 supersedes / superseded_by 中双向关联。详细规则见[文档治理规范](../governance/documentation-governance.md)。

