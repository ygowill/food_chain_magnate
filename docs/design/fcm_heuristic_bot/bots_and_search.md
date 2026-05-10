# 启发式人机对手：Bot 与搜索策略

本文由原搜索策略章节拆分为多个专题入口。

## 子文档

- [Bot 基线与实现顺序](bot_baselines.md)：实现顺序、RandomLegalBot、GreedyBot。
- [StrategyBot](strategy_bot.md)：StrategyBot 专题入口，含核心策略、自对弈工具与场景基准。
- [OSLA / Beam](search_osla_beam.md)：命令层搜索增强、trace、预算和当前结论。
- [长程战略规划层](strategic_plan.md)：StrategicPlan、plan hints、Plan Beam / Plan MCTS。

## 当前结论

- 短期命令层继续以 StrategyBot 为强基线。
- OSLA / Beam 仍用于命令层搜索诊断和 fixed-seed 对照，不作为默认强度路线。
- MCTS 只保留在长程 plan 层，由 `StrategicBot` 通过 `StrategicMCTSSearch` 搜索 `StrategicPlan`，不直接选择 raw command。
