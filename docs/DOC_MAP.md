# 文档地图

本页提供按任务进入项目的阅读路线，不复制 Feature 状态或测试结果。正式文档的完整机器索引见 [document-index.json](_generated/document-index.json)。

## 第一次接手项目

1. [项目愿景](VISION.md)
2. [稳定需求](REQUIREMENTS.md)
3. [系统总览](architecture/00-system-overview.md)
4. [Feature 索引](features/README.md)
5. [当前开发状态](progress/current_development_progress_report.md)
6. [测试规范](testing.md)
7. [文档治理规范](governance/documentation-governance.md)

## 按能力进入

| 能力 | 聚合入口 | 当前架构 | 关键决策 | 验证入口 |
|---|---|---|---|---|
| Modules V2 | [F-001](features/F-001-modules-v2.md) | [Modules V2](architecture/60-modules-v2.md) | [ADR-0001～0003](decisions/README.md) | [Validation](validation/README.md) |
| Online Resume / Bootstrap | [F-002](features/F-002-online-resume-bootstrap.md) | [Online Multiplayer](architecture/70-online-multiplayer.md) | [ADR-0004](decisions/0004-online-resume-single-full-engine-startup.md) | [联机手测清单](online/online_match_bootstrap_manual_checklist.md) |
| Tutorial Campaign | [F-003](features/F-003-tutorial-campaign.md) | [Onboarding / Tutorials](architecture/22-ui-onboarding-tutorials.md) | [ADR 索引](decisions/README.md) | [Validation](validation/README.md) |

## 按改动类型进入

### 修改 core / modules

1. [Core Engine](architecture/30-core-engine.md)
2. [State Model](architecture/33-core-state-model.md)
3. [State Extension Contract](architecture/33a-core-state-schema-contract.md)
4. [Modules V2](architecture/60-modules-v2.md)
5. [Module Development Guide](architecture/62-module-development-guide.md)
6. [F-001](features/F-001-modules-v2.md)

### 修改 UI / 教学

1. [UI Architecture](architecture/20-ui.md)
2. [Game Scene](architecture/21-ui-game-scene.md)
3. [Onboarding / Tutorials](architecture/22-ui-onboarding-tutorials.md)
4. [Overlay Guidelines](architecture/23-ui-overlay-guidelines.md)
5. [F-003](features/F-003-tutorial-campaign.md)
6. [UI / UX 报告](reports/ui/)

### 修改联机 / 平台

1. [Online Multiplayer](architecture/70-online-multiplayer.md)
2. [Platform Backend and Accounts](architecture/71-online-platform-backend-and-accounts.md)
3. [F-002](features/F-002-online-resume-bootstrap.md)
4. [ADR-0004](decisions/0004-online-resume-single-full-engine-startup.md)
5. [联机专题导航](online/README.md)
6. [活跃性能计划](plans/PLAN-2026-001-online-live-command-ui-log-performance.md)

### 修 Bug

1. 从 [BACKLOG](BACKLOG.md) 或外部 Issue 获取稳定 ID；
2. 找到所属 [Feature](features/README.md) 与 Architecture；
3. 保存失败复现证物并增加回归测试；
4. 运行 [测试规范](testing.md)中的目标测试与严格 AllTests；
5. 在 PR 中把 Requirement/AC 映射到证物；需要长期结论时新增 [Validation](validation/README.md)。

### 只改文档

1. 确认文档 Owner 与信息来源；
2. 判断是否改变 Requirement、Feature、Architecture、ADR 或流程语义；
3. 按 [治理规范](governance/documentation-governance.md)更新相关真相源；
4. 重建 [正式文档索引](_generated/document-index.json)并运行治理检查；
5. 由熟悉主题的人 Review。

## 当前工作与历史

- [当前 Backlog](BACKLOG.md)只放已确认继续推进且有 Owner 的事项；
- [待人工验收队列](progress/acceptance_queue.md)保存历史已实施但尚无独立验收的事项；
- [当前状态页](progress/current_development_progress_report.md)只导航，不复制 Feature 或 CI 状态；
- [历史进度](progress/archive/README.md)、[历史计划](plans/archive/README.md)和[联机历史方案](online/archive/README.md)只用于追溯。

若历史文档与当前 Feature、ADR 或 Architecture 冲突，以当前真相源为准，并修复会误导读者的入口。
