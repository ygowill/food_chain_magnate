# 联机与平台专题

本页按文档职责导航，不维护 Feature 状态。Online Resume / Bootstrap 的范围、验收和限制只以 [F-002](../features/F-002-online-resume-bootstrap.md) 为准。

## 当前事实

- [Online Multiplayer Architecture](../architecture/70-online-multiplayer.md)
- [Platform Backend and Accounts](../architecture/71-online-platform-backend-and-accounts.md)
- [F-002 Online Resume / Bootstrap](../features/F-002-online-resume-bootstrap.md)

## 规范决策与实施设计

- [ADR-0004：恢复房单 full-engine 启动](../decisions/0004-online-resume-single-full-engine-startup.md)是规范决策源；
- [单 full-engine 启动实施设计](online_resume_single_full_engine_startup_2026-04-17.md)记录实现细节与性能补充，不复制 ADR 状态。

## 活跃计划

- [PLAN-2026-001：live command 日志与 UI 热路径优化](../plans/PLAN-2026-001-online-live-command-ui-log-performance.md)

## 验证、Runbook 与审计

- [联机开局统一 Loading 手测清单](online_match_bootstrap_manual_checklist.md)
- [本地联机人工验证 Runbook](online_local_manual_validation_2026-04-04.md)
- [账号表面一致性审计](account_surface_consistency_audit.md)

人工记录只能证明其明确列出的提交、环境与范围。正式提交级结论应进入 [Validation](../validation/README.md)。

## 参考设计

- [游客账号身份设计](guest_account_identity_design.md)
- [早期恢复路线图](online_recovery_roadmap_2026-03-30.md)

参考设计可能同时包含已落地和未落地目标；不得据其阶段文字判断当前状态，应回到 F-002 与 Architecture。

## 历史资料

[archive/](archive/README.md)保存 dual-engine、早期断线重连和 Bootstrap 改造过程材料。它们全部只读；其中字段、阶段和“待提交”文字不能用于判断当前实现。
