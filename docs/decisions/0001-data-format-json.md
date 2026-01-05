# ADR 0001：数据格式采用 JSON（而非 Godot Resource）

- 状态：已采纳
- 日期：2025-12-30

## 背景

早期 `docs/design.md` 中将员工/里程碑/地图等数据描述为 Godot Resource（`.tres`）。但当前代码与测试体系已经以 JSON 作为事实数据源（`res://data/**/*.json` + `res://modules/**/content/**/*.json`），并且需要在版本控制中稳定 diff/合并与回放确定性。

## 决策

- 统一以 JSON 作为**提交到仓库的唯一权威数据源**：
  - 员工：`modules/*/content/employees/*.json`
  - 里程碑：`modules/*/content/milestones/*.json`
  - 地图板块：`modules/*/content/tiles/*.json`
  - 地图：`modules/*/content/maps/*.json`
  - 建筑件：`modules/*/content/pieces/*.json`
  - 营销板件：`modules/*/content/marketing/*.json`
  - 游戏配置：`data/config/game_config.json`
- 如未来需要（编辑器体验/可视化工具），可以在工具链中生成/导出 Resource，但 Resource **不作为权威源**，也不建议提交到仓库。

## 影响

- 优点：更易 diff/审查；更易做迁移与脚本校验；跨引擎/跨工具复用更简单；降低“编辑器自动改动二进制资源”导致的冲突。
- 代价：需要补齐 JSON schema/迁移工具；编辑器工具若依赖 Resource，需要额外导入/导出层。
