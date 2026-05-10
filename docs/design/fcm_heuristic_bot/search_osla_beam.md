# 启发式人机对手：OSLA / Beam

本文聚焦命令层 OSLA 与 Beam 的已落地骨架、trace、预算边界和当前结论。长程 Plan Beam / Plan MCTS 搜索见 [长程战略规划层](strategic_plan.md)。

### 11.5 OSLA / Beam

OSLA 用一层自己的候选 + 对手简单策略 response。

Beam Search 用 `MacroAction` 而不是裸 action 枚举，并设置：

- 最大宽度。
- 最大深度。
- 每阶段 topK。
- 每个候选最大模拟时间。

所有搜索都必须支持固定 seed 与 deterministic 排序。

当前已落地 OSLA 的最小搜索骨架：

- `core/ai/search/osla_search.gd` 复用 `CandidateGenerator`、`StrategyCandidateFilter`、`StrategyScorer`、`ForwardSimulator` 与 `Evaluator`。流程是先用 StrategyScorer 对当前候选排序，只模拟 topK；每个候选在 fork engine 上执行后，按 `opponent_response_horizon` 生成一到多步 response chain，再从己方视角观察最终 fork state 并用 Evaluator 加权。
- `core/ai/bot/osla_bot.gd` 是薄包装；有 engine 时走 `OSLASearch`，没有 engine 或搜索失败时回退到 `StrategyBot`。因此 OSLA 目前不会替代默认 `StrategyBot`；`tools/run_bot_selfplay.gd` 默认仍跑 StrategyBot，但可显式传入 `--bot=osla` 或 `--bot=beam` 做对照。
- `OSLASearch` 的 trace 暴露 `osla_strategy_score`、`osla_eval_score`、`osla_opponent_response_*`、对手回应候选评估数、response chain、candidate dedupe count、top candidates、discarded reasons、预算是否耗尽与耗时，用于后续比较 StrategyBot 单步评分、OSLA 与 Beam 的差异。targeted test 会确认如果 OSLA 实际模拟了对手回应，则 trace 里必须能看到回应 action、evaluated count 和 chain length，并且 explanation/trace 始终暴露 budget status，避免搜索退化成不可解释的单步 scorer wrapper。
- 这一层仍不是 MCTS：没有 rollout、tree policy、visit count 或 backpropagation。它的作用是验证 fork simulation、response policy、隐藏信息观察和 deterministic 排序能在同一接口里稳定工作。

当前已落地 Beam 的最小搜索骨架：

- `core/ai/search/beam_search.gd` 在根节点按 `StrategyScorer` 排序并只模拟 topK `MacroAction`。后续每一层从当前 fork engine 中解析下一位需要决策的玩家，继续复用 `ObservationAdapter`、`LegalActionService`、`CandidateGenerator`、`StrategyCandidateFilter`、`StrategyScorer` 与 `ForwardSimulator` 展开候选。
- Beam 节点用根玩家视角的 `Evaluator` 评估最终 fork state；己方行动的策略分正向进入路径分，对手行动的策略分按 `opponent_weight` 负向进入路径分。当前默认配置是小宽度/浅深度，用于验证流程和 trace，不用于最终强度。
- `core/ai/bot/beam_bot.gd` 是薄包装；有 engine 时走 `BeamSearch`，没有 engine 或搜索失败时回退到 `OSLABot`。`tools/run_bot_selfplay.gd` 支持 `--bot=beam` 做固定 seed 对照。
- `BeamSearch` 的 trace 暴露 `beam_width`、`max_depth`、`deepest_depth`、`selected_depth`、`attempted_simulations`、`expanded_nodes`、`candidate_deduped_count`、`beam_path`、`beam_eval_score`、预算是否耗尽与 top nodes。Beam 子节点展开复用同一个 `TimeBudget`，预算耗尽后不会继续在同一节点内追加模拟。targeted test 已确认初始 fixed seed smoke 至少能展开到 depth 2 并记录 expanded node count；另一个可回放场景用真实命令完成上一轮招聘 `recruiting_girl`、下一轮重组上岗，再在 Working/Recruit 中确认 Beam 可以选择同一玩家连续两次 `recruit` 的 depth 2 路径。这样 trace 既能区分“没有展开”和“展开了但深层节点没有超过根节点”，也能证明深层路径在己方连续行动时确实会进入最终选择。后续调参会优先比较 StrategyBot、OSLA、Beam 在同 seed JSONL 中的行动分布、库存/现金/里程碑趋势。
