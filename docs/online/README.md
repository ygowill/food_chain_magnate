# 联机与平台专题

这里收纳联机、账号、掉线恢复、平台后端等专题文档。

建议配合阅读：

- `docs/architecture/70-online-multiplayer.md`
- `docs/architecture/71-online-platform-backend-and-accounts.md`

补充文档：

- `docs/online/online_resume_single_full_engine_startup_2026-04-17.md`：当前已采纳方案。恢复房改为“单 full-engine 启动 + 完整 archive 本地回放 + 预构建 timeline/log cache”
- `docs/online/online_resume_fastload_full_history_design_2026-04-14.md`：历史设计文档，记录双轨方案背景与权衡（现已被 2026-04-17 方案取代）
- `docs/online/online_resume_hot_path_rebuild_plan_2026-04-16.md`：恢复房热路径重构结论；其中“双轨收敛”的最终落点已更新为单 full-engine 启动
