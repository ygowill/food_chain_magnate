# 启发式人机对手：StrategyBot

本文由原 StrategyBot 章节拆分为多个专题入口。

## 子文档

- [StrategyBot 核心策略](strategy_bot_core.md)：阶段策略、profile、planner 组件与已落地能力。
- [自对弈与调参工具](strategy_bot_selfplay_tools.md)：selfplay、matrix、tuning matrix、profile variants 和 summary。
- [开发流程与场景基准](strategy_bot_development_benchmarks.md)：结构性开发流程和 deterministic scenario benchmark。

## 当前结论

- StrategyBot 仍是短期命令层的强基线。
- 自对弈用于 smoke、回归监控和聚合指标，不用于追单 seed 调权重。
- 新策略路线应先写 deterministic scenario，再做 candidate/filter/scorer/profile 的局部实现。
