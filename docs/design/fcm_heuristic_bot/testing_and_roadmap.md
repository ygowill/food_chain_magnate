# 启发式人机对手：测试、路线图与验收

本文聚焦扩展契约、日志、测试计划、开发路线、失败模式、验收检查表和后续模块顺序。

## 12. 模块扩展契约

虽然首版只支持 base，AI 架构必须预留扩展点：

- 未识别 action：默认不主动生成，但可由 `RandomLegalBot` fallback 处理。
- 未识别产品：ObservationState 仍记录 inventory/demand，Evaluator 用通用商品价值。
- 未识别营销类型：只通过 registry reach 查询，不手写规则。
- 未识别 Dinnertime demand variant：DinnerPreview 以真实引擎结算为准。
- 模块新增里程碑：MilestoneRaceAnalyzer 用 trigger/effects 数据做弱评估，必要时配置覆盖。

每个扩展模块接入 AI 时，需要补：

- 候选生成器。
- feature extractor。
- golden tests。
- 难度配置权重。


## 13. 日志与调试

每次 Bot 决策记录 `DecisionTrace`：

- `round_number`
- `phase`
- `sub_phase`
- `player_id`
- `observation_hash`
- `candidate_count`
- `valid_candidate_count`
- `chosen_action_id`
- `chosen_params`
- `score`
- `top_candidates`
- `discarded_reasons`
- `belief_samples_summary`
- `time_ms`

解释文本只面向 UI/调试，不参与规则：

```text
选择培训 Burger Cook：下轮可服务 2 个 burger 需求，并竞争 first_burger_produced。
```


## 14. 测试计划

测试原则：

- 规则正确性复用现有 core/golden 测试作为 oracle；AI 测试只验证 Bot、Observation、candidate、simulation 是否调用同一套规则。
- smoke test 复用当前 headless 聚合入口和 deterministic replay 思路，不新建测试 runner。
- golden test 不复制结算规则，期望值来自同一前置状态下的真实 engine settlement/report。

### 14.1 规则回归测试

必须保留测试：

- Errand Boy 首次使用并获得 `first_errand_boy` 时，本次拿 2 瓶。
- 已有 `first_errand_boy` 时，后续 Errand Boy 拿 2 瓶。
- 路线型采购仍按每 source +1。

初始餐厅 pass 保留为未来规则工作；若实现 pass，也要补 Setup 双轮放置测试。

### 14.2 AI 观察测试

`core/tests/ai/observation_adapter_test.gd`：

- 对手未揭示 reserve card 不可见。
- `can_peek_all_reserve_cards` 后可见。
- Restructuring 未 finalized 时对手结构不可见。
- finalized 后结构可见。

可复用现有隐私覆盖作为 oracle：

- `core/tests/command_privacy_test.gd`
- `ui/scenes/tests/reserve_card_selection_modal_privacy_test.gd`
- `ui/scenes/tests/entity_tab_reserve_card_privacy_test.gd`
- `ui/scenes/tests/reserve_cards_full_screen_view_privacy_test.gd`
- `ui/scenes/tests/restructuring_privacy_test.gd`

### 14.3 候选生成测试

- 每个阶段至少能生成一个合法命令或合法 skip。
- 所有候选 validate 通过。
- 隐藏信息测试中候选生成不读取真实隐藏字段。
- 初始餐厅 pass 在当前引擎未支持前不会生成。

候选测试应尽量复用现有 action/state access 测试的 fixture；生产候选 helper 若参考 `tools/manual_test_saves/builders/*`，需要先抽到 `core/`，不能让 AI runtime 依赖 `tools/`。

### 14.4 Dinner golden 测试

复用并扩展现有测试：

- `core/tests/dinnertime_settlement_test.gd`
- `core/tests/dinnertime_distance_entry_boundary_test.gd`
- `core/tests/dinnertime_demand_registry_v2_test.gd`
- `core/tests/marketing_dinnertime_golden_replay_test.gd`
- `core/tests/confirm_dinnertime_availability_test.gd`
- `core/tests/online_dinnertime_confirm_enforced_test.gd`

新增 AI golden：同一状态下，`DinnerPreview` 与真实 Dinnertime settlement 的销售、收入、库存、bankruptcy 结果一致。

### 14.5 自对弈 smoke

复用当前 AllTests/headless 测试入口，新增 AI suite 或挂在现有 suite 附近：

- 2p base 模块。
- 固定 seed。
- 两个 `RandomLegalBot` 能跑到至少第 3 轮或 GameOver。
- 无 softlock。
- replay hash deterministic。

可复用：

- `core/tests/replay_determinism_test.gd` 的 deterministic 校验思路。
- `tools/run_headless_test.sh` 与 `ui/scenes/tests/all_tests.tscn`。
- 现有 action panel “隐藏非 initiatable special actions”测试可作为 internal action 白名单的 UI 侧参考，但 Bot 白名单仍应在 `LegalActionService` 中独立约束。

运行方式仍使用：

```bash
tools/run_headless_test.sh res://ui/scenes/tests/all_tests.tscn AllTests
```

当前实现状态：

- `core/tests/ai/osla_search_test.gd`：验证 OSLASearch 不修改 source engine、返回合法命令、输出 OSLA 评分/response trace、对手回应 evaluated count 与 budget status、候选 command-signature dedupe、同 seed deterministic、growth route breadth，以及 3p OrderOfBusiness 的 2-step response chain；并验证 OSLABot 无 engine 时回退到 StrategyBot。
- `core/tests/ai/beam_search_test.gd`：验证 BeamSearch 不修改 source engine、返回合法命令、输出 beam path/eval trace、candidate dedupe 和 budget status、至少在 fixed seed smoke 中展开到 depth 2 并记录 selected depth / expanded nodes；并用可回放的招聘员场景确认 Beam 能选择同一玩家连续 `recruit` 的 depth 2 path。同 seed deterministic，并验证 BeamBot 无 engine 时回退到 OSLABot/StrategyBot 链路。
- `core/tests/ai/random_legal_bot_smoke_test.gd`：两个 `RandomLegalBot` 在 2p base、固定 seed 下跑到至少第 3 轮或 GameOver，并校验同 seed 行动 trace deterministic。
- `core/tests/ai/greedy_bot_smoke_test.gd`：保留 GreedyBot 短程 deterministic 校验，并新增单程跑到至少第 3 轮或 GameOver 的 smoke。GreedyBot 不再要求完整打完 2p base 局。
- `core/tests/ai/strategy_bot_test.gd`：两个 `StrategyBot` 在 2p base、固定 seed 下跑到至少第 3 轮或 GameOver，并校验同 seed 行动 trace deterministic、strategy trace 元数据、phase strategy 分类 trace、route planner 收入路线 readiness、employee planner 员工基础价值/placement route readiness、recruit planner 招聘目标/roster 饱和度、setup planner 储备卡/行动顺序 payload、supply/train planner 产量与训练增量估值、marketing planner 供给 readiness、structure planner 食品上岗/营销链激活价值、support planner 价格员工/waitress/调价 payload、cash planner 无需求现金安全/Payday 裁员 payload、dinner planner 食物生产真实销售预览 payload、board analyzer 餐厅选址 payload、profile 数据加载、营销空覆盖候选过滤、营销商品候选排序、营销可服务房屋/活跃供给评分、营销被对手餐厅完全占优时的候选生成过滤、MarketingPreview 零新增需求惩罚、招聘 roster 饱和度、结构阶段食品供给激活与训练保留豁免、房屋扩张路线招聘/培训评分、价格支持与 waitress 支持路线评分、收入缺口、pending marketing planning demand、生产补缺口/供给数量/路线饮料商品推断/过量库存惩罚、无需求现金安全在基础/成长 profile 下均压过首产里程碑、DinnerPreview 食物收入安全惩罚、PricingPipeline 价格动作评分、关键里程碑 race 评分、冰箱保留、餐厅位置/road graph 评分、房屋放置距离评分、Payday 解雇评分、PaydayPreview 未解决当前玩家薪资短缺惩罚、其他玩家仍欠薪不压低当前玩家已解决 shortfall 的裁员候选等特征。
- `core/tests/ai/strategy_bot_scenario_benchmark_test.gd`：StrategyBot 的路线级场景基准。它不替代 `StrategyBotTest` 的组件断言，而是把关键策略断点抽成可命名、可扩展的 deterministic benchmark，作为后续 StrategyBot 开发的主验收入口。当前已覆盖营销本回合发起、Marketing 结算生成需求、下轮结构补产能、对手餐厅完全占优时丢弃营销候选并保留己方可服务候选、`campaign_manager` billboard 营销影响己方可服务房屋并立即获得 `first_billboard`，同时让营销员工免薪，并验证后续真实营销在 `marketing_instances` / `marketing_placements` 中变为永久 `remaining_duration=-1`，随后结算生成需求并在下一轮生产销售、`brand_director` radio 营销影响己方可服务房屋并获得 `first_radio`，随后由 `extra_marketing` 生成 2 个需求并在下一轮生产销售、`brand_manager` airplane 营销贴边影响己方可服务房屋并获得 `first_airplane`，验证 `turnorder_empty_slots` 让 Order of Business 空槽数 +2，随后结算生成需求并在下一轮生产销售、饮料营销在真实 Marketing settlement 的 `DemandMarked` 后获得 `first_drink_marketed`，再由路线采购补足并在 Dinnertime 按 `PricingPipeline` 精确校验 sell_bonus 收入、披萨营销在真实 Marketing settlement 的 `DemandMarked` 后获得 `first_pizza_marketed`，随后补齐 `pizza_cook` 产能、生产披萨并在 Dinnertime 按 `PricingPipeline` 精确校验 sell_bonus 收入、同回合训练后发起 burger 营销、在真实 Marketing settlement 后获得 `first_burger_marketed`、下轮生产并按 `PricingPipeline` 精确校验 sell_bonus 收入的完整早期收入路线、训练补食品基础产能、真实 `first_train` 薪资总额 -$15 在 Payday report 中落地、训练升级食品产能、训练升级饮料路线产能、首次 Errand Boy 饮料产量、汉堡需求下生产汉堡并获得 `first_burger_produced` / `burger_cook` 后在 Dinnertime 销售、披萨需求下生产披萨并获得 `first_pizza_produced` / `pizza_cook` 后在 Dinnertime 销售、路线型饮料采购并在 Dinnertime 销售、生产并在 Dinnertime 销售的无冰箱常规收入链，Cleanup pending 中基于己方未结算营销需求的冰箱保留选择与执行，Payday shortfall 下真实裁员选择与结算，Payday 现金足够支付 20 薪水时不裁员并通过真实结算获得 `first_pay_20_salaries`，第三次真实 `recruit` 获得 `first_hire_3` 并发放 2 张 `management_trainee`，完整 base 员工池默认预算下的价格支持招聘/上岗/真实价格行动闭环，并验证 `first_lower_prices` 的本回合 modifier 与永久 `base_price_delta` 都已通过 `PricingPipeline` 生效，完整 base 员工池默认预算下的 waitress 招聘/上岗路线，active waitress 在真实生产销售链路中触发 `first_waitress` 并获得小费，DinnerPreview 对 `first_have_20`、`first_have_100`、销售员工等 Dinnertime 新增公开里程碑的评分，并通过真实生产销售落地 `first_have_20` / `first_have_100`、CFO 禁用和下一回合 CEO/CFO 收入加成起始标记，以及 base 支持型里程碑 effect 估值不退化。
- `core/tests/ai/candidate_generator_test.gd`：覆盖高级培训路线候选生成，包括 `burger_cook -> burger_chef`、`errand_boy -> cart_operator` 和 `management_trainee -> junior_vice_president`；同时保留 `campaign_manager -> brand_manager` 不阻塞当前营销员上岗的回归测试，验证路线饮料候选在 tight budget 下优先保留满足公开需求的饮料源，并验证 Recruit 在完整 base 员工池与默认预算下不会把稳定收入路线需要的 `pricing_manager` 截掉，也不会先生成非入门级招聘候选再依赖 validator 丢弃。
- `core/tests/ai/dinner_preview_golden_test.gd`：从同一前置状态分别跑真实 engine 与 `DinnerPreview`，校验基础销售、花园收入、drive-through 入口点、关键 Dinnertime report 字段、库存消耗、source 不变性和 registry 恢复。
- `core/tests/ai/marketing_preview_golden_test.gd`：从同一前置状态分别跑真实 engine 与 `MarketingPreview`，校验 Marketing report、最终状态、`DemandMarked` 里程碑、source 不变性和 registry 恢复。
- `core/tests/ai/payday_preview_golden_test.gd`：从同一前置状态分别跑真实 engine 与 `PaydayPreview`，校验 Payday report、最终状态、Payday 中先裁员再结算、source 不变性和 registry 恢复。
- `core/tests/ai/cleanup_preview_golden_test.gd`：从同一前置状态分别跑真实 engine 与 `CleanupPreview`，校验 Cleanup report、最终状态、Cleanup pending 中先选择冰箱保留再读取 report、source 不变性和 registry 恢复。
- `core/tests/ai/strategic_plan_test.gd`：现在额外覆盖 plan generator 的 route-history bias、runner 对 route history 的 rollout payload 透传，以及 evaluator 的 `route_transition_bonus`；同时补了 `StrategicBot` 的 route-history 写回 / cache invalidation 回归，以及 MCTS rollout 对外部 route history 的 trace 透传，保证非根路线展开会轻微偏向 `supply_capacity` / `price_recovery` 等补位路线，而不是继续重复同类 `marketing_income` 路线。2026-05-11 的 3-match `r8` / `base_revenue_growth_v1` `strategy,strategy` vs `strategy,strategic` smoke 显示 `strategy_vs_strategic` 的 `route_switch_avg` 仍为 `0.000`，但 route mix 已开始出现 `price_recovery` / `supply_capacity`；2s `play` 预算 smoke 则能产生非根展开，却减少早期营销/生产/招聘并拉低现金峰值。当前已补上回归：非饮料路线不再默认注入 `procure_drink` / `procure_drinks`，evaluator 会等现金站稳后才奖励从 `marketing_income` 切到 `price_recovery` / `supply_capacity`，并且 MCTS root 在 visit floor 达标后会按 visits/q 收尾，而不是被 `budget_guarded` 强制回退到 prior 排序。
- `core/tests/ai/strategic_plan_test.gd` 这轮又补了 stalled non-root branch 回归：`_select_best_child` 会跳过 `route_stalled` 的非根 child，`_select_leaf` 遇到 stalled non-root leaf 会直接收口，不再继续消耗 rollout / expand 预算。这个回归是后续继续压低 MCTS 搜索成本的结构性门槛。
- 验证补充：`CheckCompile` 已重新跑过并保持 `PASS files=1234`，`AllTests` 以 exit code `0` 完成。`strategy,strategic` / `base_revenue_growth_v1` / 1-match `r8` / seed `12345` / 2s `play` MCTS smoke 使用正确 `--script` 入口后完成，`success_rate=1.0`，`SEARCH` 里 `strategic_total=28`、`strategic_cached=1`、`time_ms_avg_per_decision=417.306`、`budget_expired_rate=0.058`；`MCTS_ROUTE` 为 `route_switch_avg=0.008`、`non_root_populated_avg=0.405`、`non_root_expanded_avg=0.545`、`non_root_candidate_avg=1.256`，route mix 为 `marketing_income=20`、`supply_capacity=9`。后续若要继续推进 `play` 档强度，还得继续收缩 MCTS 触发窗口或展开预算。
- `BotSelfplayMatrix` 这轮 1-match `r8` / seed 12345 / `base_revenue_growth_v1` / 2s smoke 记录了 plan-level MCTS 的当前实战基线：`strategic-play-mcts` 已出现 `route_switch_avg=0.025`、`non_root_populated_avg=1.292`、`non_root_expanded_avg=1.767`、`non_root_candidate_avg=2.592`，route mix 偏向 `marketing_income=56`、`price_recovery=5`、`supply_capacity=13`，但 `budget_expired_rate=0.225` 与 `time_ms_avg=815.200` 仍然偏高，后续调参要先控 search cost，再继续看更大样本的现金峰值与路线强度。
- `core/tests/ai/strategic_plan_test.gd` 现补充低现金 route-history gate：现金低于 15 时，最近的 `marketing_income` 历史不会把 plan generator / evaluator 直接推向 `supply_capacity` 或 `price_recovery`；现金明确站稳后，才重新允许从 `marketing_income` 切到补位路线。对应 `CheckCompile PASS files=1234` 与 `AllTests PASS 425/425` 已验证。
- 早期收入权重第一轮后的单边 strategic smoke：`strategy,strategy` vs `strategy,strategic`、1-match `r8`、seed 12345、`base_revenue_growth_v1`、2s `play` MCTS，二者 success `1.0` 且 `cash_min_after_first_positive=[10,10]`；`strategic` 侧 `MCTS_ROUTE` 为 `route_switch_avg=0.000`、`non_root_populated_avg=0.342`、`non_root_expanded_avg=0.417`、`non_root_candidate_avg=0.683`，route mix 为 `marketing_income=13`、`supply_capacity=2`。但 `cash_max_seen_delta=[-44.0,0.0]`，双 strategic 2s `play` smoke 仍会超过 5 分钟，说明下一轮必须先调 MCTS 预算/展开成本。
- MCTS 预算 profile 第一轮后，`CheckCompile PASS files=1234` 与 `AllTests PASS 425/425` 已验证。`strategy,strategy` vs `strategy,strategic`、1-match `r8`、seed 12345、`base_revenue_growth_v1`、2s `play` MCTS 已完成，`strategic-play_mcts_budget_r1` success `1.0`，`budget_expired_rate=0.078`、`time_ms_avg=643.797`，`MCTS_ROUTE route_switch_avg=0.047 non_root_populated_avg=1.055 non_root_expanded_avg=1.453 non_root_candidate_avg=2.117`，route mix 为 `marketing_income=50`、`price_recovery=12`、`supply_capacity=12`。相对 Strategy `tuning_score_delta=+47.375`、`cash_min_after_positive_delta=[0.0,0.0]`、`cash_max_seen_delta=[-11.0,10.0]`；成本问题缓解但仍要继续观察是否需要减少低价值窗口的重复搜索。
- 诊断补充：`BotSelfplaySummary` 现在会在 `SEARCH` 行里单独暴露 `strategic_total`、`strategic_cached`、`strategic_cached_rate` 和 `strategic_cached_share`。同一轮 1-match `r8` smoke 中，summary 里能看到 `strategic=48`、`strategic_cached=12`、`strategy=59`，说明 plan cache 的命中已经可见，但还不够高到只靠缓存就解释 `time_ms_avg=512.361` 级别的成本，后续如果要继续压耗时，需要把缓存命中率和展开策略一起看。
- 20 局 `strategy` vs `strategic` 对照（seed 12345-12354、双向座位互换）显示：16 局正常结束、3 局 600s timeout、1 局 `max_steps=1000`，正常结束局胜负为 8:8，平均 `round=14.125`、`steps=276.375`、`time_ms_avg_per_decision=277.635`、`budget_expired_rate=0.163`。4 个未完成局都停在 `Restructuring`，并且 `set_company_structure_direct` / `restructure_employee` 数量异常高；后续强度评估前必须先补 restructuring anti-cycle / submit 收口回归，否则长局结果会被结构编辑循环污染。
- 追踪补充：`StrategyBot` 的 Restructuring decision trace 现在会记录候选数量分桶、edit/submit best score 和 `restructuring_score_gap_to_submit`。结构评分第一轮已经落地：`StrategyStructurePlanner` 把泛员工分降权为 `structure_employee_weight=0.35`，并保留激活、价格路线、waitress 路线和扩张 readiness 的完整分值；下一轮复跑 timeout seeds 时，先看 `score_gap_to_submit` 是否明显回落，再判断是否还需要调 `plan_hints` 或候选生成。


## 15. 开发路线图

Phase -1 到 Phase 1 的可执行任务拆解与现有代码复用总表见：[phase0_phase1_breakdown.md](phase0_phase1_breakdown.md)。

### Phase -1：规则对齐

- 确认 Errand Boy + `first_errand_boy` 已按规则书对齐。
- 保留对应 core 回归测试。
- 保留初始餐厅 pass 为规则差异记录，不在当前 Bot 候选中启用。

### Phase 0：接口与观察层

- 新建 `core/ai/` 基础结构。
- 实现 `ObservationAdapter` 严格隐藏信息。
- 实现 `BotDecision`、`MacroAction`、`TimeBudget`。
- 实现 `RandomLegalBot` 的最小合法行动。

### Phase 1：Simulation 与 DinnerPreview

- 实现 `AiEngineFork`。
- 实现基于 fork engine 的 forward simulation。
- 实现 DinnerPreview 正确性基线。
- 补 golden tests。

### Phase 2：BoardAnalyzer 与候选生成

- BoardAnalyzer 复用当前地图/距离/range helper。
- 实现 base 模块候选生成：
  - reserve
  - initial restaurant
  - restructuring
  - turn order
  - recruit/train
  - marketing
  - production/drinks
  - expansion
  - salary/fire
  - cleanup

### Phase 3：GreedyBot 流程基线

- 实现线性 Evaluator。
- GreedyBot 能作为候选/模拟/评分链路 smoke baseline。
- 记录 DecisionTrace。
- 明确不再要求 GreedyBot 成为实际可用的人机对手。

### Phase 4：StrategyBot MVP

- 实现 `StrategyProfile` 与 `StrategyScorer`。
- StrategyBot 复用候选生成器和 validator，不直接读隐藏状态。
- StrategyBot 固定 seed 自对弈能到第 3 轮或 GameOver。
- 将默认 profile 迁移到 `data/bots/*.json`。
- 以 scenario benchmark 作为主验收入口，先覆盖营销-供给、训练保留、pending marketing 供给、Payday 裁员、Cleanup 冰箱保留等路线级不变量。
- 已落地第一层 `StrategyPhasePlanner` / `StrategyRoutePlanner` / `StrategyEmployeePlanner` / `StrategyRecruitPlanner` / `StrategySetupPlanner` / `StrategySupplyPlanner` / `StrategyTrainPlanner` / `StrategyMarketingPlanner` / `StrategyStructurePlanner` / `StrategySupportPlanner` / `StrategyCashPlanner` / `StrategyDinnerPlanner` 和对应 targeted tests；后续继续把阶段策略器从 trace/readiness/员工基础价值与 route readiness/招聘目标/Setup 储备卡与行动顺序/供给估值/营销可兑现性/结构激活/价格与无薪支持/现金安全/真实销售预览挂点下钻到 Recruit/Train/Marketing/Supply/Payday/Cleanup 的候选约束与评分组件。新增 heuristic 前先补场景，再调 scorer/profile。

### Phase 5：OSLA 与 Beam

- 已实现 OSLA 最小搜索骨架：候选 topK、fork simulation、简单 opponent response、Evaluator 加权和 deterministic trace；trace 已能显示对手回应 action、score 和 evaluated count。
- 已实现 Beam 最小搜索骨架：小宽度、多深度、按下一决策玩家展开、根玩家视角评估和 deterministic trace；trace 已能显示 deepest/selected depth、expanded node count、candidate dedupe count、state dedupe count 和 transposition prune count，用于区分“未展开”“重复候选浪费预算”“重复状态浪费预算”“被更优同态状态剪枝”和“展开但未选择深层路径”。可回放的招聘员 targeted test 已确认 Beam 在同一玩家可连续行动时能选择 depth 2 recruit path。
- 已开始做 phase-adaptive search budget：`StrategyPhasePlanner` 会按当前 phase/sub_phase 生成 `search_hints`，OSLA / Beam wrapper 会把这些 hints 传给搜索器；当前先覆盖 setup、income route 与 growth route，后续再继续扩展 opponent policy、跨阶段 horizon 和更深层的 response 建模。
- 后续完善 opponent policy 的强度、预算分配和跨阶段 response horizon。
- 后续完善 Beam 的预算分配、候选裁剪和跨阶段 horizon。

### Phase 6：自对弈调参

- `tools/run_bot_selfplay.gd` / `tools/run_bot_selfplay.sh`
- `tools/run_bot_selfplay_matrix.gd` / `tools/run_bot_selfplay_matrix.sh`
- `tools/run_bot_tuning_matrix.gd` / `tools/run_bot_tuning_matrix.sh`：重复 `--profile=`、`--profile-dir=` 或 `--profile-list=` profile sweep，输出 bot/profile 行级 `RANK` 与 profile 聚合 `PROFILE_RANK`；同样会透传 `StrategicBot` 的 plan-level MCTS 参数选项，便于在固定 profile sweep 里复用某个 `StrategicMCTSSearch` 配置。
- `tools/generate_bot_profile_variants.gd` / `tools/generate_bot_profile_variants.sh`：按 `--scale=` 生成候选 profile，可写 `--manifest=` 供 tuning matrix 复用。
- 输出 JSONL match logs。
- `tools/summarize_bot_selfplay.gd` / `tools/summarize_bot_selfplay.sh`
- 汇总固定 seed 矩阵的成功率、行动分布、回合/步数/命令数和每玩家资源趋势。
- 支持固定 bot config 对战：`--bot=` 用同一 bot 填满所有玩家，`--bots=` 按玩家指定 matchup。
- 支持 `--profile=<id|path>` 固定 profile 对照；当前已有 `base_revenue_v1` 与 `base_revenue_growth_v1` 两个数据配置。
- selfplay JSONL 已包含每位玩家的 `player_milestone_ids`；summary 会输出 `MILESTONES` 覆盖频次，可用于后续分析 StrategyBot、OSLA、Beam 和 `StrategicBot` 在关键里程碑规划上的差异。JSONL 也会区分 bot 主动命令 `action_counts` 与自动强制动作 completion 统计，避免 `pricing_manager` 已经触发自动 `set_price` 但行动分布里看不到 `set_price` 时误判价格路线没有闭环。OSLA/Beam/Strategic 调参还应同时查看 `search_metrics` / `SEARCH` / comparison `search_delta`，并结合 `TUNING` / `tuning_score_delta` 判断新增搜索是否带来行动或路线质量变化，而不是只增加 attempted simulations、expanded nodes、耗时或 budget expired。Plan MCTS 还会在 summary 输出 `MCTS_ROUTE` 行，聚合 selected route type counts、route switch 均值和非根展开/候选均值，用于直接诊断路线偏向与后续节点是否真正展开。
- 对于像 `strategy` vs `strategic` 这种 1s/decision 的长局对照，建议额外加 `--match-timeout-ms` 做单局墙钟上限；超时 row 会显式标记 `match_timed_out=true`，summary 里会分开统计 `timeouts`，这样更容易区分“局真的没结束”与“只是很慢但最终结束”。
- `BotSelfplayMatrixTest` 现包含一个搜索 bot 流程 smoke：`strategy/osla/beam` 使用同一 `base_revenue_growth_v1` profile、seed 12345、target round 4、1 局，断言三类 bot 都能到达第 4 回合并完成放餐厅、招聘和发起营销等基础动作，同时验证 summary bucket 成功率为 1.0。这条测试只作为 OSLA/Beam wrapper 与 matrix 汇总的流程 gate，不把三者早期行动分布相同视为强度通过。
- `BotSelfplayMatrixTest` 现包含一个 Strategy-only `base_revenue_growth_v1` 轻量质量门：seed 12345、target round 8、1 局，断言到达第 8 回合、两名玩家现金形成后不跌破 10、现金峰值至少 20，并在真实自对弈中覆盖 `initiate_marketing`、`produce_food`、`procure_drinks`、`recruit`、真实 `set_price` mandatory completion，以及 `first_billboard`、`first_burger_marketed`、`first_burger_produced`、`first_errand_boy`、`first_lower_prices`。这条测试只作为核心收入与关键路线监控，不把 `first_throw_away` 当作主动策略目标。
- 先用 scenario benchmark 固定策略行为闸门，再做简单网格/随机搜索；若权重空间和指标稳定，再考虑 SPSA。
- 当前 StrategyBot、OSLABot、BeamBot 已在 seed 12345-12347、target round 4 的 smoke matrix 中全部成功到达第 4 回合，其中 seed 12345、target round 4 的三 bot 流程 smoke 已固化进 `BotSelfplayMatrixTest`；当前这组三者早期 action counts 基本相同，说明它只适合作为 wrapper/流程可比性 gate，不是 OSLA/Beam 强度指标。在 PaydayPreview 欠薪归因修正后，StrategyBot 使用 `base_revenue_growth_v1` 已在 seed 12345-12347、target round 5 与 target round 7 的 Strategy-only smoke 中全部成功，并在 Payday shortfall 中执行真实 `fire`。后续 seed 12345 target round 8 probe 已确认价格路线能在完整自对弈中招募并上岗 `pricing_manager`，由 auto mandatory `set_price` 触发 `first_lower_prices`，且 JSONL 会记录 `untraced_mandatory_completion_counts.set_price`。seed 12345 target round 3 decision probe 已确认现金为 0、无公开/可服务需求、无库存缺口时，`base_revenue_growth_v1` 会跳过 GetFood 而不是为了首产里程碑生产汉堡。餐厅竞争和营销可服务性修正后，StrategyBot 使用 `base_revenue_growth_v1` 已在 seed 12345-12347、target round 9 的 Strategy-only smoke 中全部成功，`failures=0`，平均现金约 `[37.667, 41.0]`，`cash_min_after_first_positive` 的 avg/min/max 均为 `[10, 10]`，并稳定触发 `first_lower_prices`；其中 `cash_min_seen=0` 仍会包含开局/早期现金为 0 的状态，不能单独视为后期现金安全失败，后续应优先参考 `cash_min_after_first_positive` 来定位收入形成后的现金回撤。上述结果只证明流程稳定和部分关键路线可观测，不代表强度已经足够；下一步应把收入质量、关键里程碑覆盖和对手反制拆成更小的场景闸门。

### Phase 7：产品接入

- UI/本地游戏可选择 Bot 玩家。
- 在线/房间配置中 Bot 不泄露隐藏信息。
- 调试面板显示 DecisionTrace。
- 长时间思考有超时 fallback。


## 16. 最小可用实现顺序

最小切片建议：

1. 确认 Errand Boy 回归测试通过。
2. `ObservationAdapter`。
3. `RandomLegalBot` 能从 Setup 跑到 Working。
4. `AiEngineFork`。
5. Greedy 初始餐厅 + reserve。
6. Greedy restructuring + recruit/train。
7. DinnerPreview golden。
8. Greedy 生产/饮料/营销。
9. Payday fire 策略。
10. GreedyBot smoke baseline 收口。
11. StrategyBot 框架与 smoke。
12. 自对弈工具。
13. OSLA / Beam 搜索骨架与对照 smoke。


## 17. 常见失败模式

- Bot 直接读取 `GameState`，导致隐藏信息作弊。
- 价格只看员工，不看 `round_state.price_modifiers`。
- 晚餐模拟漏掉需求变体或 route purchases。
- drive-through 自己算四角入口，和 `Structures.get_restaurant_entrance_points()` 漂移。
- Errand Boy 回归测试未纳入就开始训练权重。
- `submit_restructuring` 候选被 executor prune 后，与评分时结构不一致。
- Local Manager opening soon 被当成本轮可营业餐厅。
- Cleanup 前就把同回合里程碑从 pool 移除。
- 搜索并行切换全局 registry，导致模拟串局。
- 候选生成不 deterministic，replay 难以复现。


## 18. 验收检查表

### 架构

- [x] AI 核心在 `core/ai/`，不依赖 UI Node。
- [x] Bot 只输出 `Command`。
- [x] 所有候选命令经当前 validator 校验。
- [x] ObservationAdapter 是 Bot 决策的真实状态入口。
- [x] Simulation 复用当前 `GameEngine` 和 settlement hooks。

### 规则

- [x] Errand Boy 规则已按规则书修复并测试。
- [x] 初始餐厅 pass 当前禁用但接口保留。
- [x] DinnerPreview 与真实 settlement 有 golden test。
- [x] MarketingPreview 与真实 Marketing settlement 有 golden test。
- [x] PaydayPreview 与真实 Payday settlement 有 golden test。
- [x] CleanupPreview 与真实 Cleanup settlement 有 golden test。
- [x] Pricing 使用 `PricingPipeline` / `round_state.price_modifiers`。
- [x] Drive-through 使用 `Structures.get_restaurant_entrance_points()`。

### 强度

- [x] RandomLegalBot 无 round 3 smoke softlock（完整局仍待自对弈工具覆盖）。
- [x] GreedyBot 作为流程 smoke baseline 能到第 3 轮或 GameOver。
- [x] StrategyBot 最小骨架能到第 3 轮或 GameOver。
- [x] OSLA / Beam 最小搜索骨架能通过 fixed seed smoke。
- [x] StrategyBot 在固定场景基准与轻量 selfplay 中能形成基础收入路线。
- [ ] StrategyBot 能形成稳定收入路线并完成 base 关键里程碑规划。
- [x] 决策 trace 可解释最高分候选。
- [x] 固定 seed 下 RandomLegalBot、GreedyBot、StrategyBot selfplay deterministic；OSLA / Beam 已有 targeted deterministic test。
- [x] 搜索超时有合法 fallback。


## 19. 后续模块支持顺序建议

base MVP 之后，按影响面从小到大支持：

1. `new_milestones`
2. `fry_chefs`
3. `coffee`
4. `noodles` / `sushi`
5. `rural_marketeers`
6. `lobbyists`

每支持一个模块，都要先补 AI golden tests，再纳入难度配置与自对弈验收。
