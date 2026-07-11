---
id: BACKLOG
doc_kind: backlog
status: active
created: 2026-07-11
updated: 2026-07-11
owners: [product-owner]
review_after: 2026-07-18
---

# 当前工作项

本文件是**活跃产品/工程工作项的唯一仓库内入口**。只记录已经确认要继续推进、且有 Owner 的事项；完成项、详细诊断和验收历史不得长期堆积在这里。

## 活跃项

| ID | Owner | 当前目标 | 完成条件 |
|---|---|---|---|
| [F-002](features/F-002-online-resume-bootstrap.md) | online-systems | 完成 [PLAN-2026-001](plans/PLAN-2026-001-online-live-command-ui-log-performance.md)，并补真实平台多客户端恢复 E2E | 长历史 live hot path 达到已批准性能基线；创建/加入/断线/冷恢复/resync 有同 commit 的持久 Validation，Owner 决定是否由 validation 进入 done |
| [F-003](features/F-003-tutorial-campaign.md) | player-experience | 先建立 REQ-005～REQ-008 的实施 Plan，再交付基础学院最小可操作闭环 | 关键操作有上下文提示；关卡目标可判定；基础/扩展边界清晰；自动 E2E 与独立人工验收形成持久 Validation |

旧 Tracker 顶部状态与后续详细记录发生冲突，因此其中所有有实施记录但缺少独立验收的事项已迁移到[待人工验收队列](progress/acceptance_queue.md)，没有凭猜测重新标记为开发中。

## 新工作项准入

新增活跃项必须包含：

- 稳定 ID；
- Owner；
- 原始意图和 Non-goals；
- 风险级别；
- 对应 Feature 或明确说明为何走 Small Change Lane；
- 可验证的完成条件。

正式 Feature 使用 [Feature 聚合页](features/README.md)；低风险小改动也必须在 PR 中链接 Issue/Feature 和验证证物。
