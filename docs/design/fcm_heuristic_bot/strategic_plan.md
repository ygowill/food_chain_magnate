# 长程战略规划层（StrategicPlan）

本文聚焦把搜索从单步命令树上移到 2-4 回合路线树的设计与实施拆解。


目标：把搜索从“单步命令树”上移到“2-4 回合路线树”。`StrategyBot` 继续做短期命令执行，`StrategicPlanner` 只选择目标路线和约束 hints；Beam/MCTS 搜索的是 plan，而不是 `Command`。

## 分层职责

| 层级 | 职责 | 是否搜索 |
| --- | --- | --- |
| `StrategyBot` | 当前决策点的合法候选、过滤、评分、preview、fallback | 不做长程搜索 |
| `StrategyPlanHints` | 把长程 plan 转成局部偏好：目标产品、目标员工、目标营销房屋/板件、价格/扩张优先级 | 不搜索，只约束 |
| `StrategicPlanGenerator` | 从 observation/source state 生成少量路线候选 | 启发式生成 |
| `StrategicPlanRunner` | 在 fork engine 中按某个 plan 用 StrategyBot 执行若干决策，推进到阶段/回合边界 | rollout |
| `StrategicPlanEvaluator` | 评价 rollout 后的现金、需求兑现、里程碑、薪资风险、对手压力 | 长程价值 |
| `StrategicSearch` | 在 plan 候选上做 Beam 或 MCTS | 搜索 plan tree |

原则：

- 不复制规则：rollout 仍通过 `GameEngine.execute_command()` 和 phase hooks。
- 不让 plan 直接输出非法命令：plan 只给 hints，最终命令仍由 StrategyBot 生成并 validate。
- 不用 plan 修补单 seed：只有路线级候选缺失、评价缺口或 rollout 边界错误才改代码。
- 保持可关闭：没有可用 plan、预算不足、rollout 失败时直接回 StrategyBot。

## StrategicPlan 数据结构

建议新增：

```text
core/ai/planning/
  strategic_plan.gd
  strategic_plan_generator.gd
  strategic_plan_hints.gd
  strategic_plan_runner.gd
  strategic_plan_evaluator.gd
  strategic_search.gd
```

`StrategicPlan` 最小字段：

- `id`：稳定字符串，例如 `burger_marketing_income`、`price_recovery_burger`、`train_supply_burger`、`opening_growth_restaurant`。
- `owner_player_id`：计划归属玩家。
- `horizon_rounds` / `horizon_decisions`：最多向前看多少回合/决策。
- `target_products`：优先服务/生产/营销的产品。
- `target_houses`：可选，目标房屋或客户群。
- `target_employees`：优先招聘/训练/上岗的员工类型。
- `route_type`：`marketing_income` / `supply_capacity` / `price_recovery` / `product_switch_attack` / `cash_safety` / `growth`。
- `constraints`：现金下限、薪资安全、不可丢弃关键员工、不要重复营销无供给产品等硬约束。
- `prior_score`：由当前 Strategy 分析给出的路线先验。
- `tags`：用于 trace 和实验分桶。

`StrategyPlanHints` 最小字段：

- `preferred_products`
- `preferred_employee_roles`
- `preferred_employee_ids`
- `preferred_marketing_house_ids`
- `preferred_marketing_board_numbers`
- `preferred_price_actions`
- `growth_bias`
- `cash_floor`
- `avoid_actions`
- `plan_id`

这些 hints 不应绕过已有 scorer，而是在 `StrategyScorer` / route planner 中作为小范围结构偏置和过滤条件使用。例如：目标是 `price_recovery_burger` 时，Recruit 优先 pricing role，Restructuring 优先上岗 pricing manager，Marketing 不应抢走价格恢复所需的库存路线。

## 首批计划候选

先做 5 类低数量候选，保证每个决策点最多 4-8 个 plan：

1. **Burger/Pizza 营销收入线**
   - 条件：存在可服务房屋或当前可通过一轮招聘/训练补足产能。
   - hints：目标产品、目标 marketing employee、目标供给员工、目标 billboard/house。
   - 评价：Dinnertime 后现金、触发 `first_billboard` / `first_*_marketed` / `first_*_produced`、未销售需求惩罚。

2. **价格恢复线**
   - 条件：已有库存或短期可产，存在 price-recoverable demand。
   - hints：优先 pricing manager / lower price action / 保留库存。
   - 评价：真实 `set_price` mandatory completion、恢复后的可销售单元、现金底线。

3. **训练补产能线**
   - 条件：已有 trainee 或 trainer，目标产品有需求缺口。
   - hints：优先上岗 trainer、训练目标员工、后续 supply。
   - 评价：产能提升、`first_train`、未来一轮可服务需求、薪资风险。

4. **产品切换/对手产能缺口攻击**
   - 条件：`MarketingPressureAnalyzer` 发现对手无法完整供应某产品。
   - hints：优先营销该产品、同步补己方 supply。
   - 评价：对手 lost demand、己方新增销售、避免只给对手创造需求。

5. **扩张线**
   - 条件：有 `new_business_developer` / 合法 house 或 restaurant placement，或当前地图局面显示增长有收益。
   - hints：目标区域、目标 house/restaurant placement。
   - 评价：未来可服务房屋数、营销路线宽度、现金安全。当前仍低优先级，只在候选明确时启用。

## Rollout 边界

Plan rollout 不应无限跑整局。首版建议边界：

- 从当前决策点开始，最多执行 `horizon_decisions=16` 个 bot 决策。
- 或最多推进到下一个 `Cleanup` / `Payday` 后。
- 或最多推进 `horizon_rounds=2`。
- 如果遇到 mandatory action，继续让 engine auto/现有 controller 处理，不手写 mandatory 规则。
- 对手默认使用 StrategyBot；后续可让对手使用当前 best known plan policy，但首版不要引入循环依赖。

rollout 输出：

- `commands_executed`
- `round_delta`
- `phase_stop_reason`
- `cash_before/after/max/min_after_positive`
- `milestones_gained`
- `demand_created`
- `demand_sold`
- `lost_to_competitor`
- `salary_due_estimate`
- `search_time_ms`

## Plan evaluator

评价函数只用于比较 plan，不直接替代 StrategyScorer。建议首版特征：

- `cash_delta`
- `cash_min_after_first_positive`
- `cash_max_seen`
- `milestone_value`
- `sold_units`
- `unsold_demand_penalty`
- `inventory_overstock_penalty`
- `salary_shortfall_penalty`
- `employee_capability_delta`
- `route_completion_bonus`
- `opponent_denial_value`
- `search_cost_penalty`

验收时不要只看总分，必须在 trace 中暴露上述分项，避免 plan search 变成不可解释的权重黑箱。

## 搜索策略

分三步接入：

1. **Plan Beam**
   - 对当前状态生成 plan 候选。
   - 每个 plan rollout 一次到边界。
   - 选择 evaluator 最好的 plan，并把 plan hints 交给 StrategyBot 执行当前真实命令。
   - 目的：验证 plan 表示、rollout 和 evaluator。

2. **Rolling Plan**
   - 每个玩家每个关键阶段重选一次 plan。
   - 可以把上一轮 plan id 放进 trace，但不强制长期锁定，避免错误 plan 拖死。

3. **Plan MCTS**
   - 节点是 `(state, active_plan, round/phase)`，边是“选择/切换 plan”。
   - rollout policy 仍用 StrategyBot + plan hints。
   - visit/q/backprop 在 plan 层进行，不再直接比较单个 `Command` 的 visits。

### 当前实现

`StrategicMCTSSearch` 已经落到 plan-level trace，而不是单步命令搜索：

- `evaluated_plans` 记录 `path`、`best_path`、`route_types`、`best_route_types` 和 `route_switch_count`。
- 最终 payload / `StrategicBot` trace 记录 `mcts_selected_route_types`、`mcts_route_switch_count`、`mcts_non_root_populated_nodes`、`mcts_non_root_expanded_nodes`、`mcts_non_root_candidate_count`。
- 非根节点展开会把当前 route history 传回 `StrategicPlanGenerator`，让后续候选轻微偏向价格恢复 / 供给补位 / 路线切换，并抑制连续重复同类路线。
- `StrategicPlanRunner` 会把 route history 原样带回 rollout payload，`StrategicPlanEvaluator` 则通过 `route_transition_bonus` 把“切换路线”或“重复同类路线”的差异计入 plan value，避免 route bias 只停留在候选排序层。
- 这些指标用于区分根 plan 选择和后续 plan 展开，不再回到 raw command 级 visits/q 比较。
- `StrategicBot` 现在会保留短 route history，并把它写进 plan cache identity、Beam / MCTS search 输入和 trace；历史会在玩家切换、回合倒退或 decision seed 回退时清掉，确保缓存计划不会跨过期路线上下文复用。

## 测试与验收

新增测试建议：

- `StrategicPlanGeneratorTest`
  - 有公开 burger demand 时生成 burger marketing/supply plan。
  - 有 price-recoverable demand 时生成 price recovery plan。
  - 对手有产能缺口时生成 product switch attack plan。
  - 非根 route history 会把后续计划轻微推向 supply / price recovery 等补位路线，而不是无限重复同类 marketing plan。

- `StrategicPlanHintsTest`
  - plan hints 能影响 StrategyBot 的目标员工/产品选择。
  - hints 不会让 StrategyBot 产生非法命令。

- `StrategicPlanRunnerTest`
  - rollout 不污染 source engine hash。
  - 同 seed 同 plan deterministic。
  - 到达 Payday/Cleanup 边界后记录现金和里程碑变化。

- `StrategicSearchTest`
  - 在构造场景中，price recovery plan 优于无目标 skip/recruit。
  - 在构造场景中，训练补产能 plan 优于重复招聘无关员工。
  - 预算耗尽时能回退 StrategyBot。

自对弈验收：

- 第一阶段只跑 `strategy` vs `strategic`，`base_revenue_growth_v1`，r8/6 seeds。
- 通过条件不是立刻显著超过 Strategy，而是：
  - success `1.0`
  - `players_without_positive_cash_avg_per_match` 不高于 Strategy
  - `cash_min_after_first_positive` 不低于 Strategy
  - search time 不超过 Strategy 的 2 倍
  - 至少一个路线指标改善，例如 `first_lower_prices`、`first_train`、`first_drink_marketed` 或现金峰值。

## 不做的事

- 不在命令层恢复 MCTS；Recruit/Train/Restructuring/Payday 等短期动作继续由 `StrategyBot` 处理。
- 不把 StrategyBot 的 preview/rescore 整体复制进 MCTS 来制造“搜索版 StrategyBot”。
- 不为单个 seed 调整 profile 权重。
- 不实现纯随机 rollout；FCM 的有效路线太稀疏，随机 rollout 预算会被浪费。

## 实施任务拆解

这部分是下一阶段的直接执行计划。每个任务都应先补小测试，再接入 selfplay；如果任一阶段证明没有聚合收益，只回到该阶段的结构假设，不回退到短期动作权重修补。

| 任务 | 目标 | 主要文件 | 测试 | 验收 |
| --- | --- | --- | --- | --- |
| SP-001 | 建立 data-only plan/hints 类型 | `core/ai/planning/strategic_plan.gd`、`strategic_plan_hints.gd` | `StrategicPlanTest` | 字段复制、序列化、trace 字典稳定；不依赖 UI/Node |
| SP-002 | 生成首批路线候选 | `strategic_plan_generator.gd` | `StrategicPlanGeneratorTest` | 当前状态可生成 4-8 个稳定排序 plan；无条件时返回空而非伪造路线 |
| SP-003 | 把 plan hints 接入 StrategyBot | `strategy_bot.gd`、`candidate_generator.gd`、相关 planner/scorer | `StrategicPlanHintsTest` | hints 能改变目标偏好，但所有命令仍走 validate；无 hints 时 Strategy 行为不变 |
| SP-004 | 实现 fork rollout runner | `strategic_plan_runner.gd` | `StrategicPlanRunnerTest` | source hash 不变；同 seed 同 plan deterministic；能停在 Cleanup/Payday/decision 上限 |
| SP-005 | 实现 plan evaluator 与 trace | `strategic_plan_evaluator.gd` | `StrategicPlanEvaluatorTest` | trace 暴露现金、需求、里程碑、薪资风险和搜索成本分项 |
| SP-006 | 接入 Plan Beam bot | `strategic_search.gd`、`strategic_bot.gd`、selfplay CLI | `StrategicSearchTest`、selfplay smoke | `--bot=strategic` 可跑通；预算耗尽回退 StrategyBot |
| SP-007 | 做小规模同 seed 对照 | selfplay matrix / summary | 现有 matrix smoke | r8/6 seeds 上 success `1.0`，现金底线不低于 Strategy，至少一个路线指标改善 |
| SP-008 | 只有在 Beam 有信号后接 Plan MCTS | `strategic_search.gd`、`strategic_mcts_search.gd` | `StrategicPlanTest` | plan-level visits/q 可解释；不直接选择 raw command |

阶段顺序：

1. **类型与候选先行**：先实现 SP-001/SP-002，只证明 planner 能提出合理路线，不碰 StrategyBot 决策链。
2. **hints 小范围接入**：SP-003 只允许 hints 调整产品/员工/营销/价格目标；禁止绕过 `CandidateGenerator`、`StrategyCandidateFilter` 和 action validate。
3. **rollout 可验证后再搜索**：SP-004/SP-005 完成前，不接 bot wrapper；否则 plan score 会缺少可信 oracle。
4. **Plan Beam 作为第一强度实验**：SP-006/SP-007 用 deterministic beam 验证“路线搜索”是否有收益；这一步比直接上 MCTS 更容易定位问题。
5. **Plan MCTS 延后**：只有 Plan Beam 已能改变路线指标且不破坏现金底线时，才做 SP-008；否则先修候选、hints 或 evaluator。

首批实现优先级：

1. `marketing_income`：最直接影响收入形成和现金峰值。
2. `price_recovery`：当前 StrategyBot 已能走价格路线，适合作为 hints/rollout 正确性基准。
3. `supply_capacity`：训练/产能路线是长程价值最明显的候选。
4. `product_switch_attack`：依赖对手产能分析，等前三类稳定后接入。
5. `growth`：扩张路线成本高、收益慢，继续低优先级。

关键设计约束：

- `StrategicPlan` 只描述路线，不持有 `Command`；命令必须由 StrategyBot 当前状态生成。
- `StrategyPlanHints` 默认是软约束；只有明显非法或会破坏计划的动作才进入 `avoid_actions`。
- rollout 对手首版固定使用 StrategyBot，避免战略搜索和自身策略递归耦合。
- `StrategicBot` 的 fallback 顺序应是 `StrategyBot`，不是其他搜索 bot，因为当前强基线是 Strategy。
- trace 必须记录 `plan_id`、`route_type`、`route_types` / `best_route_types`、`mcts_selected_route_types`、`mcts_route_switch_count`、`mcts_non_root_populated_nodes`、`mcts_non_root_expanded_nodes`、`mcts_non_root_candidate_count`、`plan_prior_score`、`plan_eval_score`、`plan_eval_breakdown`、`plan_rollout_stop_reason`、`plan_search_time_ms`。

最小 CLI 接入：

- `--bot=strategic`
- `--strategic-search=none|beam|mcts`
- `--strategic-budget-profile=tuning|play`
- `--strategic-horizon-decisions=<n>`
- `--strategic-horizon-rounds=<n>`
- `--strategic-max-plans=<n>`
- `--strategic-rollout-step-budget-ms=<n>`
- `--strategic-min-search-budget-ms=<n>`
- `--strategic-min-plans-for-rollout=<n>`
- `--strategic-mcts-iterations=<n>`
- `--strategic-mcts-max-depth=<n>`
- `--strategic-mcts-top-k-per-node=<n>`
- `--strategic-mcts-exploration=<n>`
- `--strategic-mcts-prior-weight=<n>`
- `--strategic-mcts-root-prior-min-visits-per-child=<n>`
- `--strategic-config-id=<id>`

首轮推荐参数：

- `--strategic-search=beam`
- `--strategic-budget-profile=tuning`
- `--strategic-horizon-decisions=16`
- `--strategic-horizon-rounds=2`
- `--strategic-max-plans=6`
- `--strategic-min-plans-for-rollout=1`

首轮自对弈命令目标：

```bash
tools/run_bot_selfplay_matrix.sh \
  --profile=base_revenue_growth_v1 \
  --target-round=8 \
  --matches=6 \
  --seed=12345 \
  --config=strategy \
  --config=strategic \
  --strategic-search=beam \
  --strategic-budget-profile=tuning \
  --strategic-config-id=plan_beam_v0
```

如果 `strategic` 的行动分布与 Strategy 完全一致但搜索时间上升，优先检查 hints 是否真正进入 scorer/planner；如果行动分布改变但现金底线下降，优先检查 evaluator 是否高估了远期里程碑或低估了薪资/库存风险；如果 rollout 不稳定，优先修 `StrategicPlanRunner` 的边界和 source isolation。常规矩阵与调参使用 `tuning` profile 控制成本；面向真实玩家的少量 smoke 再使用默认 `play` profile 和更高 `--budget-ms`，只检查是否在给定预算内完成，不把搜索耗时加入 objective score。
