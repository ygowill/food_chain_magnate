# 启发式人机对手：OSLA / Beam / MCTS

本文聚焦 action-level OSLA、Beam 和 MCTS 的已落地骨架、trace、预算边界和当前结论。长程 plan 搜索见 [长程战略规划层](strategic_plan.md)。

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
- `OSLASearch` 的 trace 暴露 `osla_strategy_score`、`osla_eval_score`、`osla_opponent_response_*`、对手回应候选评估数、response chain、candidate dedupe count、top candidates、discarded reasons、预算是否耗尽与耗时，用于后续比较 StrategyBot 单步评分、OSLA、Beam 和 MCTS 的差异。targeted test 会确认如果 OSLA 实际模拟了对手回应，则 trace 里必须能看到回应 action、evaluated count 和 chain length，并且 explanation/trace 始终暴露 budget status，避免搜索退化成不可解释的单步 scorer wrapper。
- 这一层仍不是 MCTS：没有 rollout、tree policy、visit count 或 backpropagation。它的作用是验证 fork simulation、response policy、隐藏信息观察和 deterministic 排序能在同一接口里稳定工作。

当前已落地 Beam 的最小搜索骨架：

- `core/ai/search/beam_search.gd` 在根节点按 `StrategyScorer` 排序并只模拟 topK `MacroAction`。后续每一层从当前 fork engine 中解析下一位需要决策的玩家，继续复用 `ObservationAdapter`、`LegalActionService`、`CandidateGenerator`、`StrategyCandidateFilter`、`StrategyScorer` 与 `ForwardSimulator` 展开候选。
- Beam 节点用根玩家视角的 `Evaluator` 评估最终 fork state；己方行动的策略分正向进入路径分，对手行动的策略分按 `opponent_weight` 负向进入路径分。当前默认配置是小宽度/浅深度，用于验证流程和 trace，不用于最终强度。
- `core/ai/bot/beam_bot.gd` 是薄包装；有 engine 时走 `BeamSearch`，没有 engine 或搜索失败时回退到 `OSLABot`。`tools/run_bot_selfplay.gd` 支持 `--bot=beam` 做固定 seed 对照。
- `BeamSearch` 的 trace 暴露 `beam_width`、`max_depth`、`deepest_depth`、`selected_depth`、`attempted_simulations`、`expanded_nodes`、`candidate_deduped_count`、`beam_path`、`beam_eval_score`、预算是否耗尽与 top nodes。Beam 子节点展开复用同一个 `TimeBudget`，预算耗尽后不会继续在同一节点内追加模拟。targeted test 已确认初始 fixed seed smoke 至少能展开到 depth 2 并记录 expanded node count；另一个可回放场景用真实命令完成上一轮招聘 `recruiting_girl`、下一轮重组上岗，再在 Working/Recruit 中确认 Beam 可以选择同一玩家连续两次 `recruit` 的 depth 2 路径。这样 trace 既能区分“没有展开”和“展开了但深层节点没有超过根节点”，也能证明深层路径在己方连续行动时确实会进入最终选择。后续调参会优先比较 StrategyBot、OSLA、Beam 在同 seed JSONL 中的行动分布、库存/现金/里程碑趋势。

当前已落地 MCTS 的最小搜索骨架：

- `core/ai/search/mcts_search.gd` 复用同一组候选、过滤、评分、forward simulation 与 evaluator 组件，按 `mcts_iterations` / `mcts_max_depth` / `mcts_top_k_per_node` 做启发式宏动作树搜索，不做纯随机 rollout。
- `core/ai/bot/mcts_bot.gd` 是薄包装；有 engine 且当前 phase strategy 在 `mcts_enabled_strategy_ids` 中时走 `MCTSSearch`，否则走 `StrategyBot` fallback；预算过期或搜索失败时仍回退到 `BeamBot`，保证不会因为实验性 MCTS 阻塞 bot 决策链路。当前默认只启用 `working_place_houses_growth` / `working_place_restaurants_growth`，避免 MCTS 破坏已稳定的招聘、价格和训练收入路线。
- `MCTSSearch` 会在内部 fork source engine，并用 fork engine 绑定根节点 validation，避免搜索候选生成或模拟污染调用方 engine；返回前恢复调用方 registry bundle，确保 hash / serialization 不受 fork search 影响。
- `MCTSSearchTest` 覆盖 source isolation、同 seed deterministic、trace/explanation 中的 visit/q/prior/eval/预算字段，以及 budget-expired fallback 到 Beam。
- MCTS 现在会把 `TimeBudget` 传入 `ForwardSimulator`，并在每次扩展前检查 `mcts_min_simulation_budget_ms`。trace / explanation 额外记录 `mcts_simulation_ms`、`mcts_max_simulation_ms`、`mcts_simulation_budget_skips` 和 `mcts_budget_guarded`，用于区分“候选生成慢”“单次模拟慢”和“预算不足主动停扩展”。单条 engine command 仍不可中断，因此长尾集中在 settlement/skip/Restructuring 类命令时，应按 phase strategy 限制 MCTS 或改用更便宜的 fallback。`mcts_candidate_attempt_multiplier` 用于在 topK 中存在 simulation 失败候选时保留备选尝试，不改变评分权重。
- action-level MCTS 已补 root prior guard，避免低样本时用浅层 visits 覆盖 Strategy 先验；但这只能保证安全性，不能提供长程规划能力。短期命令层的 Recruit/Train/价格/供给选择已经由 StrategyBot 的手工结构、preview 和阶段 planner 覆盖；继续把 MCTS 打开到所有短期阶段会增加预算耗尽和路线破坏风险。因此下一阶段搜索应上移到 route/plan 层。
