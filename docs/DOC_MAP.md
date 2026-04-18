# 文档地图（Doc Map）

本文档用于快速回答两个问题：

1. **某类信息应该去哪里找？**
2. **第一次进入项目，应该按什么顺序读？**

---

## 1. 快速导航

### 想看当前代码结构

- 总入口：`docs/architecture/README.md`
- 系统总览：`docs/architecture/00-system-overview.md`
- 引擎：`docs/architecture/30-core-engine.md`
- 模块系统：`docs/architecture/60-modules-v2.md`
- 联机平台：`docs/architecture/70-online-multiplayer.md`
- 平台后端：`docs/architecture/71-online-platform-backend-and-accounts.md`

### 想看当前工作状态

- 主进度快照：`docs/progress/current_development_progress_report.md`
- 当前问题单：`docs/progress/issue_tracker.md`
- 联机专题进度：`docs/refactors/multiplayer_progress.md`

### 想看设计方案

- 总体技术设计：`docs/design.md`
- 员工 `staff_id` / usage track / 动作面板统一：`docs/design/staff_id_usage_tracks_and_action_panel_unification_2026-04-18.md`
- UI 重构：`docs/design/ui_redesign.md`
- UI 视觉升级：`docs/design/ui_visual_upgrade_design.md`
- 游戏设置页：`docs/design/game_setup_page_redesign.md`
- 营销板件改造：`docs/design/marketing_board_refactor.md`

### 想看当前计划

- UI 整改主计划：`docs/plans/ui_remediation_plan.md`
- UI 开发计划：`docs/plans/ui_development_plan.md`
- 模块 UI 解耦：`docs/plans/module_ui_decoupling_plan_2026-02-10.md`
- 手工测试存档计划：`docs/plans/manual_test_saves_plan.md`

### 想看历史报告 / 审计

- Core / Modules：`docs/reports/core/`
- UI / UX：`docs/reports/ui/`
- 综合性报告：`docs/reports/general/`

### 想看联机专题

- 专题目录：`docs/online/`
- 自动恢复 / 断线：`docs/online/online_session_resume_redesign_2026-04-03.md`
- 游客账号：`docs/online/guest_account_identity_design.md`

### 想看测试与规则参考

- 测试规范：`docs/testing.md`
- 规则参考：`docs/rules.md`
- OCR / 资源清单：`docs/reference/`

---

## 2. 阅读顺序（推荐）

### 路线 A：第一次接手项目

1. `docs/README.md`
2. `docs/architecture/README.md`
3. `docs/design.md`
4. `docs/progress/current_development_progress_report.md`
5. `docs/progress/issue_tracker.md`
6. `docs/testing.md`

### 路线 B：准备改 UI

1. `docs/architecture/20-ui.md`
2. `docs/architecture/21-ui-game-scene.md`
3. `docs/architecture/23-ui-overlay-guidelines.md`
4. `docs/design/staff_id_usage_tracks_and_action_panel_unification_2026-04-18.md`
5. `docs/design/ui_redesign.md`
6. `docs/plans/ui_remediation_plan.md`
7. `docs/plans/ui_development_plan.md`
8. `docs/reports/ui/`

### 路线 C：准备改联机 / 平台

1. `docs/architecture/70-online-multiplayer.md`
2. `docs/architecture/71-online-platform-backend-and-accounts.md`
3. `docs/online/README.md`
4. `docs/refactors/multiplayer_progress.md`
5. `docs/refactors/multiplayer_implementation_guide.md`
6. `docs/refactors/multiplayer_public_deployment.md`

### 路线 D：准备改 core / modules

1. `docs/architecture/30-core-engine.md`
2. `docs/architecture/31-core-phase-manager.md`
3. `docs/architecture/32-core-actions-framework.md`
4. `docs/architecture/33-core-state-model.md`
5. `docs/design/staff_id_usage_tracks_and_action_panel_unification_2026-04-18.md`
6. `docs/architecture/60-modules-v2.md`
7. `docs/reports/core/`

---

## 3. 目录职责速查

- `docs/architecture/`：**当前实现事实**
- `docs/design/`：**当前仍有参考价值的设计方案**
- `docs/design/archive/`：**已落地/历史设计**
- `docs/plans/`：**当前仍有执行价值的计划**
- `docs/plans/archive/`：**历史总计划**
- `docs/progress/`：**当前状态**
- `docs/progress/archive/`：**旧状态快照**
- `docs/reports/`：**审计/评估/整改复盘**
- `docs/online/`：**联机与平台专题**
- `docs/refactors/`：**仍有参考价值的重构专题**
- `docs/refactors/archive/`：**历史重构方案**
- `docs/reference/`：**参考资料与资源清单**

---

## 4. 文件命名建议（后续新增文档）

建议尽量遵守：

- 当前实现说明：放 `architecture/`
- 未来方案：放 `design/` 或 `plans/`
- 进度快照：放 `progress/`
- 报告：放 `reports/`
- 若是阶段性文档，优先在文件名尾部保留日期：`_YYYY-MM-DD`
- 文件名尽量使用英文/下划线；标题可以继续使用中文
