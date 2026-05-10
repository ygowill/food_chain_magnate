# 启发式人机对手：Bot 与搜索策略

本文由原搜索策略章节拆分为多个专题入口。

## 子文档

- [Bot 基线与实现顺序](bot_baselines.md)：实现顺序、RandomLegalBot、GreedyBot。
- [StrategyBot](strategy_bot.md)：StrategyBot 专题入口，含核心策略、自对弈工具与场景基准。
- [OSLA / Beam / MCTS](search_osla_beam_mcts.md)：action-level 搜索增强、trace、预算和当前结论。
- [长程战略规划层](strategic_plan.md)：StrategicPlan、plan hints、Plan Beam / Plan MCTS。

## 当前结论

- 短期命令层继续以 StrategyBot 为强基线。
- action-level MCTS 保留为实验分支和诊断工具，不继续扩大到所有阶段。
- 后续搜索收益应来自长程 plan 层，而不是单步命令树调权重。
