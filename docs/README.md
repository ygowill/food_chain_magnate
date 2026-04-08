# 文档总览

`docs/` 现按“稳定参考 / 设计方案 / 计划 / 进度 / 专项报告 / 联机专题”分层，避免所有草案与报告都堆在根目录。

## 目录约定

- `docs/architecture/`：当前代码架构与实现对照文档
- `docs/decisions/`：架构决策记录（ADR）
- `docs/design/`：功能/界面/交互设计方案（旧方案在 `docs/design/archive/`）
- `docs/plans/`：开发计划、重构计划、专项落地计划（历史总计划在 `docs/plans/archive/`）
- `docs/progress/`：当前进度、状态追踪、issue 清单（旧快照在 `docs/progress/archive/`）
- `docs/reports/`：审计、评估、整改报告、阶段性复盘（再细分为 `core/`、`ui/`、`general/`）
- `docs/online/`：联机/账号/恢复/平台化专题文档
- `docs/refactors/`：专题重构文档（历史方案在 `docs/refactors/archive/`）
- `docs/reference/`：规则 OCR、资源清单等参考资料
- `docs/demo_image/`：示意图、演示素材
- `docs/DOC_MAP.md`：完整文档地图与推荐阅读路径

## 建议阅读顺序

### 1. 先了解当前系统

- `docs/architecture/README.md`
- `docs/design.md`
- `docs/testing.md`
- `docs/rules.md`

### 2. 跟进当前工作状态

- `docs/progress/current_development_progress_report.md`
- `docs/progress/issue_tracker.md`
- `docs/refactors/`

### 3. 查看专题文档

- UI / 交互：`docs/design/`
- 联机 / 平台：`docs/online/`
- 历史审计与整改：`docs/reports/`

## 维护约定

- **当前实现说明** 放进 `architecture/`
- **未来方案** 放进 `design/` 或 `plans/`
- **阶段性状态** 放进 `progress/`
- **一次性审计/复盘/问题报告** 放进 `reports/`
- 文件名保留原有时间戳，方便追踪上下文


## 命名建议

- 文件名优先使用英文 + 下划线；标题可保留中文。
- 当前实现放 `architecture/`，方案放 `design/` / `plans/`，快照放 `progress/`，报告放 `reports/`。
- 阶段性文档建议在文件名中保留日期后缀，如 `_2026-04-09`。
