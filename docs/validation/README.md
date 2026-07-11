# Validation 索引

Validation 报告把验证范围、Feature、commit、命令、退出码、结果和限制绑定在一起。报告的 pass 只证明文档中列出的范围，不自动把关联 Feature 标记为 done。

当前报告：

- [VAL-2026-001：2026-07-11 AllTests headless 基线](VAL-2026-001-all-tests-baseline.md)

新增报告使用 [Validation 模板](../templates/validation.md)，字段与证物要求见[文档治理规范](../governance/documentation-governance.md)。原始日志若位于被 Git 忽略的本地目录，必须在报告中明确标为临时证物；PR/CI 应上传持久 Artifact。

