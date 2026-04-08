# 报告与审计

`docs/reports/` 现在按主题再分层，减少所有审计/复盘堆在同一层级：

- `docs/reports/core/`：core / modules / engine 架构与代码审计
- `docs/reports/ui/`：UI / UX / 交互 / 日志 / 视觉相关报告
- `docs/reports/general/`：跨模块、跨系统、全局性报告

## 使用建议

- 查 **core 架构/代码问题**：先看 `docs/reports/core/`
- 查 **UI 问题与整改历史**：先看 `docs/reports/ui/`
- 查 **全局审计/设计评审/开发进度审计**：看 `docs/reports/general/`

提醒：这些报告大多是阶段性结论，不应替代 `docs/architecture/` 中的当前实现说明。
