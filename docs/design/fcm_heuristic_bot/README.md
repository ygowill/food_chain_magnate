# 《快餐连锁大亨》启发式人机对手实施方案

本文档以当前 Godot 4.5 / GDScript 代码实现为准，用于在现有 `GameEngine`、`ActionRegistry`、`PhaseManager` 与 `RulesetV2` 基础上实现可落地的人机对手。


## 0. 当前结论

### 0.1 首版范围

首版 Bot 只要求完整支持默认 base 模块：

- `base_rules`
- `base_products`
- `base_pieces`
- `base_tiles`
- `base_maps`
- `base_employees`
- `base_milestones`
- `base_marketing`

这些模块由 `core/engine/game_defaults.gd` 的 `GameDefaults.build_default_enabled_modules_v2()` 默认启用。其他模块（咖啡、拉面、寿司、lobbyists、new_milestones 等）不进入首版强度验收，但架构必须为后续模块扩展留出边界。

### 0.2 规则差异与已对齐项

当前实现与规则书/早期文档有一个仍需保留的规则差异，以及一个已经在本地 `main` 对齐的规则项：

1. **初始餐厅 pass**

   规则设计中保留“第一轮可 pass，第二轮必须放”的初始餐厅逻辑；当前实现尚未实现该流程。现有代码在 `Setup/ReserveCards` 结束后，由 `place_restaurant` 放置起始餐厅，`skip` 要求玩家已经放过餐厅。

   Bot 文档与代码应保留 pass 规划接口，但在当前引擎未支持前，候选生成器不得产出 pass 命令。

2. **First Errand Boy Played 里程碑**

   规则书要求：

   > If a player has the “First Errand Boy Played” milestone, each source will provide an extra drink. Errand boys will also bring in two drinks of the same type, including the errand boy just played.

   本地 `main` 已在 `1670651b fix(core): apply errand boy milestone drink bonus` 中对齐：Errand Boy 分支会在 `apply_use_employee_event()` 后读取更新后 state 上的 `procure_plus_one` bonus；首次打出并获得 `first_errand_boy` 的 Errand Boy 本次也拿 2 瓶同类饮料。Bot 只需按该现有规则建模，并保留回归测试。

### 0.3 实施原则

- Bot 只能输出 `Command`，不能直接改 `GameState`。
- Bot 必须通过严格 `ObservationAdapter` 读取信息，不能直接把完整 `GameState` 传给决策逻辑。
- 所有候选命令最终必须通过当前 `ActionRegistry` / executor validator 校验。
- 晚餐模拟不得另写一套会长期漂移的规则。首版以 fork 引擎真实推进为正确性基线，再逐步抽取快速 preview。
- 所有 AI 逻辑应保持纯逻辑、可 headless 测试，不依赖 UI Node。

### 0.4 GreedyBot 定位

`GreedyBot` 不是目标人机对手，只作为流程探针和回归基线保留：

- 验证 `ObservationAdapter`、`CandidateGenerator`、`ForwardSimulator`、`Evaluator`、`DecisionTrace` 能串起来。
- 验证核心行动链路不会软锁，并能在短程 smoke 中跑过招聘、培训、营销、生产/采购、销售等关键流程。
- 保留对明显无效动作的正确性过滤，例如营销影响不到任何房屋时不能浪费候选/搜索预算。

不再把 GreedyBot 调成“会玩”的 Bot，不要求它完整打完 2p base 局，也不继续为长期经济规划、里程碑路线、对手反制等目标堆单步贪心补丁。真正的人机对手从 `StrategyBot` 起步，用长期计划和阶段策略驱动候选选择。

### 0.5 当前进度追踪

本节作为后续开发的进度账本。每完成一个阶段性步骤，先更新这里的状态、验证结果、已知问题和下一步计划，再提交代码。

最近快照：

- 日期：2026-05-11
- 提交：`pending`
- 当前状态：`StrategicBot` 已默认使用面向真实对局的 `play` 预算 profile；`tools/run_bot_tuning_matrix.gd` 在未显式传 `--strategic-budget-profile` 时会注入 `tuning` profile，用低预算窗口做 profile / 参数筛选。selfplay、matrix、tuning matrix 都已能透传 `strategic` 参数，并把 `bot_config` 按 `play/tuning` 与显式 config id 分桶，避免实战配置和调参配置混在同一个 summary bucket。
- 当前状态：`StrategicPlan` / `StrategicSearch` / `StrategicBot` 的 plan-level Beam/MCTS 入口已接通，结构仍是“`StrategyBot` 负责短期命令执行，`StrategicPlan` 负责 2-4 回合路线选择”。`StrategicPlanEvaluator` 的 `search_cost_penalty` 只作为 trace / breakdown 诊断保留，不再进入 objective score；`route_transition_bonus` 会根据 rollout 的 `route_history` 进入 objective score，让重复同类路线与切到价格恢复 / 供给补位在 leaf value 上可区分。MCTS/Strategic 的强度比较只看给定预算内的现金底线、收入形成、路线覆盖和行动分布。
- 当前状态：`StrategicMCTSSearch` 已推进到 plan-level MCTS：节点/路径都记录 `plan_id`、`route_type`、depth、visits/q，`evaluated_plans` 暴露 plan path，不直接选择 raw command；plan-state transposition 会按 `state_hash|phase|sub_phase|current_player_id|plan_id` 去重/剪枝，并通过 `mcts_plan_state_deduped_nodes` / `mcts_plan_transposition_pruned_nodes` 进入 trace / explanation。
- 当前状态：Plan MCTS 的 backprop 现在会为每个节点保留见过的 best leaf continuation path，最终 payload / `StrategicBot` trace 暴露 `mcts_selected_path`、`mcts_selected_leaf_depth`、`mcts_selected_leaf_value_score`，`evaluated_plans` 也包含 `best_path`，用于解释根 plan 被选中时实际依赖的后续路线，而不是只看到第一步 plan。
- 当前状态：Plan MCTS 的 plan-state identity 已显式进入 trace：最终 payload / `StrategicBot` trace 暴露 `mcts_selected_state_key`，`evaluated_plans` 暴露每个 plan 节点的 `state_key`；回归覆盖同一 engine state 下不同 `active_plan` 不会被 transposition 当成同一节点剪掉。
- 当前状态：Plan MCTS 继续往解释性补强：最终 payload / `StrategicBot` trace 现在还会暴露 `mcts_selected_route_types`、`mcts_route_switch_count` 以及 `mcts_non_root_populated_nodes` / `mcts_non_root_expanded_nodes` / `mcts_non_root_candidate_count`，`evaluated_plans` 也同步记录 `route_types` / `best_route_types`，方便区分“根节点选了什么”和“后续 plan 路线到底有没有真的展开”。
- 当前状态：`StrategicBot` 现在会保留短路由历史并跨决策传递给 plan cache / Beam / MCTS 输入；历史会在玩家切换、回合倒退或上下文 seed 回退时重置，避免缓存计划继续沿用过期路线上下文。对应回归会检查首个决策后的历史写回、同窗口缓存失效，以及 MCTS rollout trace 是否保留外部 route history。
- 当前状态：selfplay / matrix summary 已能聚合 Plan MCTS 的路线级诊断：`search_metrics` 记录 selected route type counts、route switch 总数和非根展开/候选计数，`BotSelfplaySummary` 会输出独立 `MCTS_ROUTE` 行，后续可以直接从矩阵 summary 看路线偏向，而不用人工翻每条 decision trace。
- 当前状态：`StrategicBot` 的 MCTS 分支已同步 `strategic_horizon_decisions`、`strategic_horizon_rounds`、`strategic_max_plans`、`strategic_rollout_step_budget_ms`、`strategic_min_plans_for_rollout` 到 plan search 使用的无前缀选项，避免 beam 可调而 MCTS 忽略战略层预算/宽度配置。
- 当前状态：旧命令层 MCTS 已从 active code、测试套件和 selfplay CLI 中移除；Plan MCTS 的公开调参入口统一为 `--strategic-mcts-*`，并只作用于 `StrategicBot` 的 plan search。
- 当前状态：Plan MCTS 的非根 plan 展开会携带 route history，`StrategicPlanGenerator` 会对连续重复的同类路线做轻微抑制，并对价格恢复 / 供给补位 / 路线切换给出小幅偏置；`StrategicPlanRunner` 会把 route history 保序带回 rollout payload，`StrategicPlanEvaluator` 再用 `route_transition_bonus` 把该偏置计入 plan-level value，避免搜索长期卡在同一类 `marketing_income` 计划上。对应的 generator / evaluator 回归已补。
- 验证：使用 `D:\tools\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe` 运行 `res://tools/check_compile.gd` 得到 `PASS files=1234`；运行 `res://ui/scenes/tests/all_tests.tscn -- --autorun` 得到 `425/425 PASS`、`StrategicPlanTest PASS (1757ms)`、`BotSelfplayToolTest PASS (912ms)`、`BotSelfplayMatrixTest PASS (1371ms)`、`total_ms=92568`。Godot headless 退出时仍会输出既有 RID/resource leak warning；以 AllTests summary 为准。
- 诊断：同一低样本 r8 / 2 matches / `play` profile / `mcts-d4-r1-p4-s20-b16-m1-mi6-md2-mk2` smoke 中，`MCTS_ROUTE` 为 `route_switch_avg=0.038`、`non_root_populated_avg=0.621`、`non_root_expanded_avg=0.858`、`non_root_candidate_avg=1.525`，selected route types 为 `marketing_income=109`、`price_recovery=19`、`product_switch_attack=8`、`supply_capacity=12`。这说明 route-history bias 已经产生少量路线切换，但 `marketing_income` 仍是主导路线。
- 诊断补充：本轮按相同的 `mcts-d4-r1-p4-s20-b16-m1-mi6-md2-mk2` 结构复跑 2 matches / `r8` / `play` profile，`MCTS_ROUTE` 为 `route_switch_avg=0.000`、`non_root_populated_avg=0.000`、`non_root_expanded_avg=0.000`、`non_root_candidate_avg=0.000`，selected route types 为 `marketing_income=79`、`price_recovery=20`、`product_switch_attack=4`、`supply_capacity=8`。这表示 route transition 评分已经接入，但在这个很窄的 smoke 里还没有显著抬高路线切换率；后续需要拉宽样本或预算再判断是 search 宽度不足还是分数项力度不够。
- 后续计划：继续用 route-switch 和非根展开指标定位 `strategic` 早期收入覆盖缺口；下一步优先检查 hints / evaluator 是否仍高估重复营销收入、低估价格恢复和早期现金保全。第二优先级是用 `tuning` profile 做低预算小矩阵筛方向，再用 `play` profile 和 2s/5s/10s 预算做少量真实对局 smoke，确认收益来自更深路线而不是偶然超时。

- 日期：2026-05-09
- 提交：`6a937463 feat(ai): implement strategy bot planning`
- 远端分支：`origin/bot`
- 工作区进展：`StrategyBotScenarioBenchmarkTest` 已补三类结构性恢复 deterministic scenario：换客户/房屋、降价恢复需求、换产品卡对手产能缺口；开局餐厅选择新增 route-dominance 结构过滤，避免在存在更宽营销路线时保留单一薄弱开局。
- 验证：
  - `HOME="$PWD/.tmp_home" godot --headless --log-file "$PWD/.godot/CheckCompile.log" --path "$PWD" --script res://tools/check_compile.gd`
  - `tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests 240`
  - 结果：compile PASS（1237 files），`AllTests` 426/426 PASS，`StrategicPlanTest` PASS（1489ms），`total_ms=88110`（约 88s）。Godot headless 退出时仍会输出既有 RID/resource leak warning；以测试脚本 summary 为准。
  - selfplay：`base_revenue_growth_v1` / 2p / target round 12 / 60 seeds：success `1.0`，failures `0`，avg round `11.55`，avg steps `201.717`，opening players without positive cash avg `0.033`，cash_min_after_first_positive avg `[9.933, 9.661]`。
  - selfplay：`base_revenue_growth_v1` / 2p / target round 14 / 30 seeds：success `1.0`，failures `0`，avg round `12.333`，avg steps `226.433`，opening players without positive cash avg `0.033`，cash_min_after_first_positive avg `[9.933, 9.667]`。
  - tuning R1：6 个 profile 变体在 `r12` / 6 seeds 下完成 sweep，`sample_005` 以 `score=1152.596` 排第 1，baseline 为 `1118.072`；随后用同一组候选做 `r12` / 30 seeds 与 `r14` / 30 seeds 复核，`sample_005` 仍保持第 1，且两轮均为 `success=1.0`、`failures=0`。
  - tuning R1 复核：`r12` / 30 seeds 下 `sample_005` `score=1029.512`，baseline `1009.355`；`r14` / 30 seeds 下 `sample_005` `score=999.003`，baseline `953.793`。这组历史分数来自旧版 objective，当时仍包含搜索成本罚分；当前 objective 已改为只衡量局面/路线质量，搜索耗时与 budget expired 只作为 `SEARCH` 诊断。`cash_min_after_first_positive` 仍需在下一轮继续盯住，但没有出现失败或结构性退化。
- search R1：`BeamSearch` 增加了按 `GameState` + `next_player` 的 state dedupe 和 transposition pruning，去重/剪枝计数通过 `beam_deduped_nodes` / `beam_transposition_pruned_nodes` 进入 trace / explanation；`AllTests` 424/424 PASS，说明这一步没有破坏现有 AI smoke / deterministic test。
- search R2：`StrategyPhasePlanner` 现在会输出阶段自适应 `search_hints`，`OSLABot` / `BeamBot` 会按 `phase/sub_phase` 自动放宽 `Working` / `Train` / `PlaceHouses` 等阶段的 candidate coverage、beam width 和 topK；`AllTests` 424/424 PASS，说明这一步没有破坏现有 AI smoke / deterministic test。
- search R3：增长路线的 `max_depth` 已从 3 提升到 4，`StrategyPhasePlanner` 和 phase-planner tests 已同步覆盖更深 horizon；这一步仍只针对结构性的长期路线，不回退到单 seed 权重修补。
- search R4：增长路线的 OSLA 候选与对手回应 breadth 继续放宽到 `max_candidates=10`、`opponent_max_candidates=4`、`opponent_max_valid_per_action=4`，继续向更深的结构性探索推进，而不是靠权重微调追单 seed。
- search R5：OSLA / Beam 的 growth smoke 已切到“先到 Working，再直接定位 PlaceHouses，并注入 `new_business_developer` 以保证多候选增长分支”的稳定 setup；两条 smoke 都重新覆盖了 `trace.phase/sub_phase` 与 `candidate_count>1`，`AllTests` 424/424 PASS，说明当前搜索增强链路保持可运行。
- search R6：BeamSearch 现在会按 actor 切分分支预算：己方节点继续用 root `top_k_per_node` / `max_valid_per_action`，对手节点改用 `opponent_max_candidates` / `opponent_max_valid_per_action`；trace 同步暴露 `beam_root_max_valid_per_action`、`beam_opponent_max_valid_per_action`、`beam_opponent_top_k_per_node`，`AllTests` 424/424 PASS。
- search R7：OSLASearch 增加 `opponent_response_horizon` 与多步 response chain；`order_of_business_tempo` 先启用 2-step horizon，并用 3p OrderOfBusiness smoke 确认 trace 中能看到两步对手响应链。trace / explanation 现在暴露 `osla_opponent_response_chain_length`、`osla_opponent_response_chain`、`osla_opponent_response_chain_stop_reason`，`AllTests` 424/424 PASS。
- search R8：OSLA / Beam 增加 scored candidate command-signature dedupe：同一命令签名只保留最高 `strategy_score` 候选，平分按 `macro_action_id` 稳定 tie-break；trace / explanation 暴露 `candidate_deduped_count`，OSLA 额外暴露 root / opponent response 去重计数，Beam 汇总 root + expansion 的候选去重计数。`AllTests` 424/424 PASS。
- search R9-R15：历史命令层 MCTS 实验证明，短期命令选择继续由 `StrategyBot` 负责更稳定；MCTS 应上移到 `StrategicPlan` 路线层。相关旧 bot/search/test/CLI 已从 active code 中清理，后续不再维护命令层 MCTS 分支。
- strategic SP-008 R1：plan-level MCTS 已在 `StrategicMCTSSearch` 中落地首轮结构化版本。搜索对象是 `StrategicPlan`，root/final selection 暴露 visits/q、prior guard、path score、selected path 和 best continuation path；`StrategicBot` mcts 模式继续把选中 plan 转成 hints 交给 `StrategyBot` 产出当前合法命令。新增回归覆盖 plan-level trace、`strategic_*` 参数别名同步、plan-state transposition、best leaf path backprop 以及 cached mcts plan reuse。
- strategic SP-001..SP-006：已落地首版 data-only `StrategicPlan` / `StrategicPlanHints`、路线候选生成、hints 接入、fork rollout runner、plan evaluator 与 `StrategicBot` Plan Beam wrapper。`StrategicBot` 只在当前合法动作包含 recruit/train/restructuring/marketing/supply/price/growth placement 等可被战略路线影响的动作时运行 plan search；Payday、skip-only 等非战略决策直接回退 `StrategyBot`，避免把预算浪费在无法改变路线的阶段。
- strategic 验证快照：使用本机 Godot 4.6 console binary 运行 `tools/check_compile.gd` 得到 `PASS files=1236`；`AllTests` 得到 `426/426 PASS`、`StrategicPlanTest PASS (402ms)`。低预算 smoke：`strategy` vs `strategic`、`target-round=3`、`budget-ms=160`、`strategic-search=beam`、`horizon-decisions=4`、`max-plans=2`、`rollout-step-budget-ms=20`，结果 `success=1.0`、failures `0`、strategic search type count `strategic=5` / `strategy=21`、budget expired rate `0.115`、max decision time `973ms`。
- strategic 小矩阵：`strategy` vs `strategic`、`target-round=4`、3 seeds、`budget-ms=200`、`horizon-decisions=6`、`max-plans=3`、`rollout-step-budget-ms=20`，结果 `PASS configs=2 matches=6 failures=0`。这组旧版 objective 分数为 `strategy=920.647`、`strategic=737.364`，但该口径包含搜索成本罚分，不能作为 Plan Beam 低于 Strategy 的公平结论；仍然有效的问题是 `strategic` 正现金玩家均值 `1.333`、无正现金玩家均值 `0.667`，说明早期收入覆盖下降。首版 Plan Beam 只能称为“可运行的路线搜索入口”，还不能作为强度提升结论。
- strategic 缓存矩阵：`StrategicBot` 的 plan cache 保持 broad key `(player_id, round, phase)`，在 `cache_r8_d10p4s40` / r8/3 seeds / `1000ms` 矩阵中命中 `strategic_cached=137`，把平均决策时间压到 `197.392ms`，`budget_expired_rate=0.115`。缓存只负责降成本，不负责修强度；因为最终命令仍要过 `StrategyBot` validate/fallback，所以这里不需要把缓存收窄成更重的 state hash。
- tuning objective 口径修正：`TUNING` score 不再包含 `search_time_ms_avg_per_match` 或 `search_budget_expired_avg_per_match` 罚分；搜索耗时、预算耗尽率和搜索类型仍通过 `SEARCH`、`search_delta`、tuning matrix ranking 行输出。对 `cache_r8_d10p4s40` 的历史 summary 重新按无搜索成本口径估算，`strategic-cache_r8_d10p4s40@base_revenue_growth_v1` 为 `1343.360`，`strategy@base_revenue_growth_v1` 为 `1294.830`，说明旧分数低于 Strategy 主要由搜索成本罚分造成；但 r4 低预算小矩阵的早期正现金覆盖问题仍是真问题。

当前阶段判断：

- Phase -1 到 Phase 5 已基本落地：规则对齐、观察层、候选生成、fork/preview、Greedy smoke、StrategyBot MVP、OSLA/Beam 最小搜索入口均已实现并有测试覆盖。
- Phase 6 已进入可运行状态：selfplay、matrix、profile sweep、profile variant 生成和 summary 工具已提交，可以开始更大规模实验。
- 当前 StrategyBot 是“可测试的 MVP”，不是最终强度版本。它已经能在固定场景和轻量自对弈中形成基础收入路线，但还没有达到“合格玩家级对手”的验收标准。
- StrategicPlan 层已经进入可运行实验状态，但还没有通过强度验收。当前优先级是修路线级结构缺口：候选是否缺收入线、hints 是否压制了短期收入动作、evaluator 是否高估远期扩张或低估第一轮正现金，而不是继续调单 seed 权重。

已完成的关键能力：

- `StrategyScorer` 已拆出阶段策略组件：`StrategyPhasePlanner`、`StrategyRoutePlanner`、`StrategyEmployeePlanner`、`StrategyRecruitPlanner`、`StrategySetupPlanner`、`StrategySupplyPlanner`、`StrategyTrainPlanner`、`StrategyMarketingPlanner`、`StrategyStructurePlanner`、`StrategySupportPlanner`、`StrategyCashPlanner`、`StrategyDinnerPlanner`。
- `MarketingPressureAnalyzer` / `StrategyRecoveryPlanner` 已把三类常见玩家响应建成显式结构：
  - 换客户群体/换房屋：寻找己方仍能服务且竞争可赢的房屋。
  - 降价：通过 `PricingPipeline` 和 lower-price pressure 识别可恢复需求。
  - 换产品卡对手：营销对手当前计划无法完整供应的产品，破坏其完整订单。
- 营销候选不再只看覆盖范围；它会检查是否影响战略上有用的房屋、己方是否能当前或未来供应、是否会只给对手创造销售机会，以及真实 MarketingPreview 是否实际新增需求。
- 开局餐厅评分已加入竞争安全、road graph 距离、营销路线可达性和独立 billboard 板件数，降低“只靠一个容易被抢占的板件”的开局。
- 供给逻辑区分当前可销售缺口、price recovery 缺口、product switch 缺口、pending marketing 规划缺口和无冰箱时不能提前兑现的未来需求。
- Scenario benchmark 已成为 StrategyBot 开发主闸门，覆盖营销结算、训练补产能、饮料路线、价格路线、waitress、Payday 裁员、Cleanup 冰箱保留、关键里程碑预览等路线级断点；本轮补齐结构性恢复 gate：换客户/房屋、降价恢复需求、换产品卡对手产能缺口。
- 自对弈工具已能输出 JSONL、summary、mandatory completion、search metrics、玩家现金/员工/库存/里程碑统计和 tuning objective；objective 只衡量局面/路线质量，搜索成本只作为预算诊断。
- BeamSearch 当前已加入 state dedupe 与 transposition pruning，后续搜索增强应继续从更强的 horizon、候选裁剪和对手响应建模推进，而不是回到 profile 权重微调。

当前已知问题与风险：

- 大规模自对弈仍是 smoke 和诊断工具，不应直接当作强度指标。当前 60 局 target round 12 与 30 局 target round 14 均稳定通过，但仍有约 `0.033` players/match 的开局无正现金现象；这类问题后续按聚合异常与确定结构缺口处理，不围绕单个 seed 调权重。
- 目前 profile 权重仍是人工构造的基线。单参数 sweep 不足以说明问题，因为一个合理参数可能被其他不合理权重拖累；后续调参必须使用多参数候选、至少 3 个以上 seed，并结合对局日志人工检查异常。
- 自对弈指标不能使用“双方动作分化”这类只对 bot-vs-bot 有意义、对真实对局无直接价值的指标。优先看收入形成速度、收入形成后现金底线、可销售需求兑现率、关键路线覆盖、异常对局存档。
- OSLA/Beam 当前主要用于验证 fork simulation、trace、预算和多步接口；默认强度路线仍由 `StrategyBot` 承担。
- Plan MCTS 已进入 `StrategicBot` 的路线搜索入口，但它还没有通过强度验收。后续只比较给定预算内的现金底线、收入形成、路线覆盖和行动分布，不把搜索耗时混入 objective score。
- MCTS 的搜索层级已上移到长程路线规划；后续不再让 MCTS 和 StrategyBot 竞争单步命令排序。
- 长程规划的核心假设：`StrategyBot` 继续负责短期战术动作；新的 planner 负责选择 2-4 回合尺度的收入路线、产能路线、价格/恢复路线、营销目标和扩张目标，并把这些路线作为 hints 约束 StrategyBot 执行。MCTS/Beam 应搜索这些 plan，而不是搜索每个 `Command`。
- Plan Beam 当前的聚合弱点是早期收入覆盖下降：小矩阵中 `strategic` 少做营销和生产、少招 0.667 名员工/局，导致 3 seed 中平均 0.667 个玩家到 r4 仍未形成正现金。下一步只在 trace 证明有路线级原因时改代码，例如 plan 候选过早偏向 growth、hints 抑制 marketing/supply，或 evaluator 给未完成路线过高分。
- 真实对局预算与调参预算必须分离：`StrategicBot` 面向玩家默认使用 `play` 预算 profile，可以把单回合思考预算提高到最高 `10s`，用于更长 horizon 和更多 plan rollout；profile tuning matrix 默认注入 `tuning` 预算 profile，常规 selfplay/matrix/profile tuning 应继续使用 `160-300ms` 级 `--budget-ms` 与 `20-40ms` 级 `--strategic-rollout-step-budget-ms`，通过低预算窗口筛选结构方向，再用少量高预算 smoke 检查实战质量，不能把 10s 预算作为常规调参成本。预算达标由配置和 smoke 验证负责，不通过 tuning objective 给搜索型 bot 加额外罚分。
- 新房/新餐厅扩张路线仍按低优先级处理。实际游戏中建造新房屋较少，当前阶段优先保证初始餐厅、营销、产能、价格和现金安全路线。
- 严格隐藏信息接口已有基础要求，但后续产品接入、在线配置和调试 UI 仍需继续确认不会暴露对手隐藏信息。
- Godot 会生成大量 `.import` / `.uid` sidecar；这些不是本阶段 AI 逻辑源码，后续不应纳入策略提交。

下一步计划：

1. **不恢复命令层 MCTS**：短期命令继续由 StrategyBot 决策；MCTS 只用于 `StrategicPlan` 路线搜索。
2. **诊断 StrategicPlan 早期收入缺口**：优先检查小矩阵中 strategic 未形成正现金的 seed/player trace，确认是候选缺失、hints 偏置、rollout 边界还是 evaluator 分项错误。
3. **修结构，不修单局**：只有当问题能归因为路线候选、hints 或 evaluator 的通用缺口时才改代码，并补 deterministic test；不为 seed 12347 这类单例直接调权重。
4. **保留 StrategyBot 作为战术执行器**：Recruit/Train/Restructuring/Payday/单候选 pass 等短期动作继续由 StrategyBot 决策；planner 只通过 hints 改变目标产品、目标员工、营销优先级、价格/扩张优先级。
5. **Plan Beam 先过现金底线，再考虑 Plan MCTS**：只有 deterministic beam 已能在聚合指标上不低于 Strategy 的早期收入底线，并至少改善一个路线指标，才进入 plan-level MCTS。
6. **分层预算验证**：调参与自对弈常用低预算筛方向；面向真实玩家的候选配置再用 2s/5s/10s 三档预算做少量 smoke，观察收益是否来自更深路线而非偶然超时。
7. **继续看聚合指标**：优先看 `cash_min_after_first_positive`、`milestone_counts`、`opening_first_positive_cash_step_avg`；同时把 `search_time_ms_avg_per_decision` 和 `budget_expired_rate` 作为预算诊断单独检查，不要被单个 seed 或单局 trace 带偏。
8. **先补回归，再调强度**：在可用 Godot CLI 的环境里补跑 `StrategicPlanTest`、`BotSelfplayToolTest`、`BotSelfplayMatrixTest` 和一小组 `strategy` vs `strategic` 对照；只有在预算分层、配置分桶和 trace 都稳定后，才继续扩大 `StrategicPlan` 候选和 plan-level MCTS 的搜索宽度。

### 0.6 Profile tuning 实验协议

当前阶段 profile tuning 的目标是筛选方向，不是把 `base_revenue_growth_v1` 调成最终强度版本。实验必须满足：

- **固定基线**：每轮 tuning matrix 都包含 `base_revenue_growth_v1`，并把同一组 seed、玩家数、target round、max steps、budget 应用于所有候选。
- **多参数候选**：候选 profile 应一次调整一组相关路径，例如开局收入节奏、营销/生产节奏、早期训练/招聘节奏；不再用单 seed、单权重微调解释问题。
- **先小后大**：第一轮使用 5-8 个候选、每个候选 5-10 局；只有候选在聚合指标上稳定优于基线，才进入 30+ seeds 的 r12/r14 复核。
- **主指标优先级**：先看 success/failures、`opening.players_without_positive_cash_avg_per_match`、`cash_min_after_first_positive`、`opening.first_positive_cash_round/step`、`cash_max_seen`、milestones，再看 tuning objective 总分。
- **异常处理**：只有异常在多个 seed 或多个 profile 中重复出现，且能归因为候选缺失、规则建模、阶段策略或搜索预算问题时，才补 deterministic scenario 或结构修复。
- **不提交生成物**：`.godot/bot_profile_variants*`、`.godot/bot_tuning_matrix*`、selfplay JSONL/summary 仍是实验输出，不作为源码提交对象。


## 专题文档索引

- [架构与接口契约](architecture.md)：代码基线、目录结构、Bot 接口、隐藏信息与状态模型。
- [模拟、地图与晚餐预览](simulation_board_dinner.md)：forward simulation、BoardAnalyzer、DinnerPreview。
- [候选生成与评价函数](candidates_and_evaluation.md)：候选生成规则、评价函数边界。
- [Bot 与搜索策略](bots_and_search.md)：Bot/search 专题入口，含 StrategyBot、自对弈工具、OSLA/Beam 与 Plan MCTS。
- [长程战略规划层](strategic_plan.md)：StrategicPlan、plan hints、Plan Beam / Plan MCTS 实施拆解。
- [测试、路线图与验收](testing_and_roadmap.md)：扩展契约、日志、测试计划、开发路线、失败模式与验收表。
- [Phase 0/1 任务拆解](phase0_phase1_breakdown.md)：早期接口、观察层、fork simulation 与 DinnerPreview 的执行拆解。
