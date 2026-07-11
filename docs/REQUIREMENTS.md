---
id: REQUIREMENTS-001
doc_kind: requirement
status: accepted
created: 2026-07-11
updated: 2026-07-11
owners: [product-owner, engineering]
review_after: 2027-01-11
---

# 项目级需求

本文件是稳定 Requirement ID 与规范性定义的唯一仓库内真相源。Feature 聚合页维护范围、Non-goals、验收判定与证物映射，但不得重新定义同一个 Requirement。

## Modules V2

关联聚合页：[F-001 Modules V2](features/F-001-modules-v2.md)。

### REQ-001 模块严格装配

每局游戏必须仅装配显式启用模块及其依赖闭包；未启用模块的内容、动作和规则不得进入运行期。

### REQ-002 模块化规则扩展

模块必须通过受控的 Catalog、Ruleset、Registry、Provider 或 UI 扩展接口接入，不得要求 core 硬编码具体可选模块。

### NFR-001 确定性与 Fail-fast

缺失依赖、冲突、重复注册、无效引用和损坏 Schema 必须在装配或加载边界明确失败；相同输入必须保持可回放和可验证。

## Online Resume / Bootstrap

关联聚合页：[F-002 Online Resume / Bootstrap](features/F-002-online-resume-bootstrap.md)。

### REQ-003 权威状态恢复

断线、刷新或冷启动后的客户端必须从服务端权威资料恢复同一场对局，不得从不完整历史静默继续。

### REQ-004 单一历史真相

恢复房的 live、日志、时间线和 replay 必须基于同一完整历史坐标；历史查看保持只读，不能在客户端分叉权威状态。

### NFR-002 可观察与可失败

Bootstrap、snapshot、archive 回放和 cache 构建必须提供可读进度；失败必须显式上报、清理 loading 并进入安全状态。

## Tutorial Campaign

关联聚合页：[F-003 Tutorial Campaign](features/F-003-tutorial-campaign.md)。

### REQ-005 基础规则教学

教学必须覆盖 Setup、储备卡、公司结构、距离、营销、晚餐结算、收入和银行破产等核心规则链路。

### REQ-006 上下文教学

教学提示应在玩家实际执行对应操作时出现，并指向当前真实可见的 UI 与规则状态。

### REQ-007 扩展规则隔离

扩展模块教学必须与基础规则分层，明确哪些行为来自当前启用模块，避免玩家把扩展效果误认为基础规则。

### REQ-008 可操作教学战役

教学战役必须把课程结构落实为可操作、可判定目标、可复盘的关卡流程；静态参考章节和素材预览不能单独视为完整战役交付。

### NFR-005 教学运行时隔离

教学预设、提示和约束只能在显式教学运行时启用，不得进入 core 对局真相，不得因历史设置污染普通局、回放或读档。

## 文档与交付

关联规范：[文档治理规范](governance/documentation-governance.md)。

### NFR-003 可追溯交付

正式 Feature 必须有唯一聚合页，并关联 Requirement、ADR、Plan/实现、测试、Validation、已知限制和 Owner。

### NFR-004 持久证物

完成结论必须绑定 Commit 和可复核证物。被忽略的本地日志只能作为临时材料，不能单独证明 Feature 完成。
