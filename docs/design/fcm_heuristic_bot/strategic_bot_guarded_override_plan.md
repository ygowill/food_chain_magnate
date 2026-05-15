# StrategicBot Guarded Override Plan

本文是 `StrategicBot` 重构的执行记录。目标不是做一个临时初版，而是把战略层固定成可长期维护的结构：`StrategyBot` 继续作为战术基线，`StrategicBot` 只有在相同预算、相同 horizon 下证明 plan rollout 优于 baseline 时，才允许覆盖当前命令。

## 设计主旨

- `StrategicBot` 不再默认相信 plan search；它必须先和无 hints 的 `StrategyBot` baseline 对照。
- plan 只负责路线选择，不直接输出命令；真实命令仍由 `StrategyBot` 生成并通过现有 validate。
- hints 只能作为当前阶段的下一步 directive，不能把整条路线一次性塞进 scorer。
- hints bonus 只能作为 tie-break，不能压过现金安全、真实 preview、可服务需求、薪资风险和候选合法性。
- MCTS 保留为实验工具，不作为默认强度路径；默认路径应是 deterministic baseline-compared planner。
- 开局和低现金阶段优先保护收入形成，现金未站稳前不得用 growth、price recovery 或 supply capacity 覆盖收入线。
- 每次实现改动都要检查是否仍满足上述主旨，再进入提交。

## 最终行为

`StrategicBot` 默认使用 `strategic_search="compared"`：

1. 生成无 hints 的 `StrategyBot` baseline rollout。
2. 生成 grounded strategic plans。
3. 用相同 horizon、相同 opponent policy rollout 每个 plan。
4. 每个 plan 必须通过 hard gates。
5. 只有 delta score 达到阈值时才执行 plan hints。
6. 否则直接 fallback 到 `StrategyBot` 的原始决策。

## Hard Gates

每个 plan 覆盖 baseline 前必须满足：

- `cash_min_after_first_positive >= baseline`
- `salary_shortfall <= baseline`
- `lost_to_competitor <= baseline`
- `route_stalled == false`
- owner 至少执行一个 route 相关 action，或产生/出售与 route 相关的需求
- 早期现金低于 15 时，只允许 `marketing_income` 覆盖 baseline
- 不能增加无法供应的 demand
- 不能显著增加 `Restructuring` edit loop 风险

## Delta Score

候选 plan 通过 hard gates 后再计算相对收益：

```text
score =
  2.0 * cash_after_delta
+ 1.5 * cash_max_seen_delta
+ 10.0 * demand_sold_delta
+ 5.0 * suppliable_demand_created_delta
+ milestone_delta
+ route_specific_delta
- 12.0 * salary_shortfall_delta
- 8.0 * unsold_demand_delta
- 8.0 * lost_to_competitor_delta
- 0.5 * extra_command_count
```

默认覆盖阈值：`+12.0`。低于阈值直接 fallback。

## Implementation Steps

1. **Document the design and progress source of truth.**
   - Add this document.
   - Commit only this document.
2. **Add compared search payload.**
   - Implement `StrategicSearch.choose_plan_compared()`.
   - Add baseline rollout and delta scoring helpers.
   - Keep existing Beam/MCTS paths available.
3. **Switch StrategicBot default to guarded compared mode.**
   - Default `strategic_search` becomes `compared`.
   - Fallback when compared search returns no improving plan.
   - Trace records baseline score, delta score, hard gate failures, and selected override reason.
4. **Convert hints to next-step directives.**
   - Extend `StrategyPlanHints` with current-phase directive fields.
   - Keep legacy fields for trace.
   - Scorer uses directive fields first and caps hint bonus.
5. **Add tests.**
   - Baseline better means fallback.
   - Low cash blocks non-marketing overrides.
   - Plan with stalled route is rejected.
   - Hints are bounded and phase-local.
6. **Run verification.**
   - Focused AI tests first.
   - Compile check.
   - Broader AllTests if focused checks are clean.

## Progress Log

### 2026-05-14 Step 1

- Status: ready for commit.
- Change: created this design/progress document as the single source of truth for the guarded override refactor.
- Design check: aligns with the main principle because no code behavior changes yet; it only freezes the implementation contract before edits.
- Verification: document-only change; no runtime test required.
- Commit: `docs(ai): record guarded strategic bot plan`.

### 2026-05-14 Step 2

- Status: ready for commit.
- Change: added `StrategicSearch.choose_plan_compared()` plus baseline rollout, hard gates, delta scoring, and comparison trace payload.
- Design check: aligned. This step does not enable the new path by default and does not let a plan override baseline unless it passes hard gates and the minimum delta threshold. Existing Beam and MCTS entry points remain available.
- Verification: `CheckCompile PASS files=1235`.
- Commit: `feat(ai): add baseline-compared strategic search`.

### 2026-05-14 Step 3

- Status: ready for commit.
- Change: wired `StrategicBot` default mode to `compared`, added compared-mode execution, and exposed baseline/comparison/hard-gate trace fields.
- Design check: aligned. Compared mode skips the old broad plan cache so every override must be freshly compared against baseline. Beam/MCTS remain explicit modes, and failed compared searches still fallback to `StrategyBot`.
- Verification: `CheckCompile PASS files=1235`.
- Commit: `feat(ai): gate strategic bot with baseline comparison`.

### 2026-05-14 Step 4

- Status: ready for commit.
- Change: added next-step directive fields to `StrategyPlanHints`, made `StrategicBot` and rollout use decision-local hints, and capped `StrategyScorer` hint bonuses.
- Design check: aligned. The active decision path now only gives hints for the current legal next action, while route-wide targets remain trace data. Hint bonus is bounded and cannot replace existing hard validation or Strategy preconditions.
- Verification: `CheckCompile PASS files=1235`.
- Commit: `feat(ai): constrain strategic hints to next step`.

### 2026-05-14 Step 5

- Status: ready for commit.
- Change: added focused guarded override tests, tightened directive employee hints so the current action only receives employees matching the next action role, and updated legacy Beam cache tests to opt into Beam explicitly.
- Design check: aligned. This closes a remaining leak where a current-action directive could still carry route-wide employee targets. It also keeps Beam/MCTS as explicit experimental paths while the default path stays baseline-compared with StrategyBot fallback.
- Verification: `CheckCompile PASS files=1236`; `AllTests PASS passed=426/426 failed=[]`.
- Commit: `test(ai): cover guarded strategic overrides`.

### 2026-05-15 Step 6

- Status: ready for commit.
- Change: brought selfplay/matrix/tuning tooling up to the new default by accepting explicit `strategic_search=compared`, updated CLI docs, and added summary diagnostics for guarded `strategic_failure` fallbacks.
- Design check: aligned. The tooling change only makes the guarded mode reproducible and observable; it does not weaken hard gates, does not make MCTS default, and does not tune around failed comparisons.
- Verification: `CheckCompile PASS files=1236`; `AllTests PASS passed=426/426 failed=[]`.
- Benchmark: `strategy` vs `strategy,strategic` with `--strategic-search=compared`, `base_revenue_growth_v1`, seeds `12345-12347`, `target_round=8`, `budget_ms=80` finished `6/6` with no failures/timeouts. Behavior deltas were zero; guarded strategic recorded `strategic_fallback=179`, with `insufficient_plan_search_budget=113` and `no_strategic_legal_actions=66`.
- Budget probe: same matchup with seed `12345`, `budget_ms=360`, `strategic_min_search_budget_ms=120` also finished without behavior deltas. It recorded `strategic_fallback=59`, with `no_plan_beat_baseline=32`, `no_plans_generated=5`, and `no_strategic_legal_actions=22`.
- Conclusion: the guarded design is no longer harmful in these smoke runs, but it is still mostly equivalent to `StrategyBot`. Next implementation should add targeted positive override scenarios and improve plan generation/evaluation until at least one route can beat the baseline without relaxing safety gates.
- Commit: `chore(ai): expose guarded strategic diagnostics` (`714e69bc`).

### 2026-05-15 Step 7

- Status: committed.
- Change: made Restructuring usable by guarded plans without leaking route-wide hints. If no route execution action is legal yet, `StrategyPlanHints` emits a current-phase directive for route-relevant structure edits only, while preserving the full route only as trace metadata. `StrategicPlanEvaluator` counts structure edits as route progress only when the edited employee id or role matches the plan route targets.
- Change: surfaced compared-search failure payloads through `StrategicBot` fallback trace/explanation, so a safe fallback now records candidate count, evaluated plans, hard-gate failures, baseline summary, and elapsed search time.
- Design check: aligned. This does not weaken hard gates, lower the delta threshold, or allow `submit_restructuring` to masquerade as route execution. Preparatory structure progress must still be produced by validated commands and must match the plan's target employees/roles.
- Verification: `AllTests PASS passed=426/426 failed=[] total_ms=161211`; `StrategicGuardedOverrideTest` now covers phase-local restructuring directives, targeted-only structure progress, and a positive compared-plan gate/delta case.
- Benchmark: `strategy` vs `strategy,strategic`, seed `12345`, `target_round=8`, `budget_ms=360`, `strategic_min_search_budget_ms=120` finished with no failures/timeouts but still zero behavior deltas. Guarded strategic recorded `strategic_fallback=59`, with `no_plan_beat_baseline=32`, `no_plans_generated=5`, and `no_strategic_legal_actions=22`.
- Diagnostic probe: decision-detail payloads showed compared search usually evaluated only one candidate, often with `budget_expired` and `commands=0..1`. A high-budget `target_round=4`, `budget_ms=1800` probe still produced no strategic decisions. Next implementation should fix compared-search rollout budget fairness before changing scoring thresholds.
- Commit: `feat(ai): guard strategic restructuring directives` (`fb7ccb81`).

### 2026-05-15 Step 8

- Status: committed.
- Change: made compared search budget-fair. Baseline and each candidate plan now receive a fresh child rollout budget capped by the remaining parent search budget, instead of sharing one absolute `TimeBudget` instance where the baseline can consume the whole deadline before candidates are evaluated. Failure/success payloads now include `compared_rollout_budget_ms`.
- Design check: aligned. This preserves the same hard gates and delta threshold, keeps total search bounded by the parent budget, and makes the baseline comparison meaningful before any scoring changes are considered.
- Verification: `CheckCompile PASS files=1236`; `AllTests PASS passed=426/426 failed=[] total_ms=151420`; `StrategicGuardedOverrideTest` now includes a child-budget regression case.
- Probe: low-budget `target_round=4`, `budget_ms=360`, `strategic_min_search_budget_ms=120` still fell back safely, but compared rollouts now used about `103-104ms` child budgets. Marketing evaluated `2/2` candidates; later route points still evaluated only `1/4` candidates because the total parent budget remained tight, but those candidate rollouts executed `1-2` commands instead of starving at `0`.
- Probe: high-budget `target_round=4`, `budget_ms=1800` evaluated all compared candidates at the strategic decision points: Marketing `2/2`, Restructuring/Recruit/GetFood `4/4`, with `compared_rollout_budget_ms=288` and `5-8` commands in the leading rollout. It still selected no strategic override (`no_plan_beat_baseline=5`), so the next point should inspect plan quality/comparison scoring with full candidate evidence rather than changing safety gates.
- Commit: `fix(ai): give compared strategic rollouts fair budgets` (`b497733f`).

### 2026-05-15 Step 9

- Status: committed.
- Change: let compared delta scoring recognize guarded route proof. Compared summaries now carry `route_progress_bonus`, `route_completion_bonus`, and `route_transition_bonus`; delta scoring adds a bounded route-progress credit only when route action count improves over baseline and at least one of those evaluator proof signals is positive.
- Design check: aligned. This is not a hard-gate relaxation: cash, salary, opponent-loss, route-stall, unsupplied-demand, and restructuring-risk gates still block unsafe plans. The first test run caught an over-broad version where bare `route_action_count` could lift a weak cash plan; the final version requires both route action progress and positive route proof.
- Verification: `CheckCompile PASS files=1236`; `AllTests PASS passed=426/426 failed=[] total_ms=152862`; `StrategicGuardedOverrideTest` now covers both sides of the scoring boundary: weak cash plus bare route action stays below threshold, while guarded route action plus positive progress/completion can clear it.
- Probe: low-budget `target_round=4`, `budget_ms=360`, `strategic_min_search_budget_ms=120` finished without failures/timeouts and recorded `search_type_counts={"strategic":2,"strategy":38}`. Both strategic decisions were `marketing_income_burger` with hard gate passed and route proof present (`progress=7.2/completion=12` for `initiate_marketing`; `progress=12.6/completion=14` for `produce_food`).
- Probe: high-budget `target_round=4`, `budget_ms=1800` finished without failures/timeouts and produced 4 guarded strategic decisions before the final tightening; the remaining low-budget retest after tightening confirms the credit still works without bare-action false positives.
- Commit: `feat(ai): score guarded strategic route progress` (`cabaff65`).

### 2026-05-15 Step 10

- Status: committed.
- Change target: normalize this progress document so committed work and future plan are unambiguous. Add the next execution sequence before changing runtime behavior.
- Design check: aligned. This is a documentation-only correction and planning step; it prevents implementation drift by making the next checks explicit.
- Verification: document-only change; no runtime test required. Diff review confirmed only this progress document changed for Step 10.
- Commit: `docs(ai): plan strategic bot validation follow-up` (`d92bf22d`).

### 2026-05-15 Step 11

- Status: committed.
- Change target: run guarded StrategicBot against StrategyBot on longer smoke matrices after Step 9. Use the same guarded compared path, compare `strategy` vs `strategy,strategic`, and record whether strategic decisions remain safe beyond the r4 probe.
- Required checks: target at least r8 and r12 probes with fixed seed ranges; capture `search_type_counts`, `strategic_failure_counts`, cash/first-cash/food-delay metrics, failures, timeouts, and whether guarded strategic improves or regresses the baseline.
- Command r8: `./tools/run_bot_selfplay_matrix.sh --config=strategy --config=strategy,strategic --profile=base_revenue_growth_v1 --players=2 --seed=12345 --matches=3 --target-round=8 --max-steps=1600 --budget-ms=360 --match-timeout-ms=240000 --trace-tail=60 --strategic-search=compared --strategic-min-search-budget-ms=120 --strategic-max-plans=6 --strategic-horizon-decisions=16 --strategic-rollout-step-budget-ms=48 --strategic-config-id=guarded_compared_step11_r8 --output-jsonl=res://.godot/guarded_compared_step11_r8.jsonl --output-json=res://.godot/guarded_compared_step11_r8_summary.json`.
- Command r12: `./tools/run_bot_selfplay_matrix.sh --config=strategy --config=strategy,strategic --profile=base_revenue_growth_v1 --players=2 --seed=12345 --matches=3 --target-round=12 --max-steps=2600 --budget-ms=360 --match-timeout-ms=300000 --trace-tail=60 --strategic-search=compared --strategic-min-search-budget-ms=120 --strategic-max-plans=6 --strategic-horizon-decisions=16 --strategic-rollout-step-budget-ms=48 --strategic-config-id=guarded_compared_step11_r12 --output-jsonl=res://.godot/guarded_compared_step11_r12.jsonl --output-json=res://.godot/guarded_compared_step11_r12_summary.json`.
- Result r8: `total_matches=6`, `failures=0`, `timeouts=0`. Baseline score `1296.669`; guarded mixed score `1298.418`; `tuning_score_delta=+1.749`. Guarded mixed search: `search_type_counts={"strategic":28,"strategy":331}`, `strategic_failure_counts={"no_plan_beat_baseline":70,"no_plans_generated":15,"no_strategic_legal_actions":66}`, `strategic_fallback_rate=0.421`. Opening metrics stayed equal: first positive cash round delta `0.0`, food recruit-to-produce round delay delta `0.0`. Cash average shifted `[+10.334,-9.333]`; cash max seen shifted `[+10.333,-7.666]`.
- Result r12: `total_matches=6`, `failures=0`, `timeouts=0`. Baseline score `1629.470`; guarded mixed score `1612.252`; `tuning_score_delta=-17.218`. Guarded mixed search: `search_type_counts={"strategic":36,"strategy":570}`, `strategic_failure_counts={"no_plan_beat_baseline":142,"no_plans_generated":15,"no_strategic_legal_actions":102}`, `strategic_fallback_rate=0.427`. Opening metrics stayed equal: first positive cash round delta `0.0`, food recruit-to-produce round delay delta `0.0`. Cash average shifted `[+43.333,-61.334]`; cash max seen shifted `[+43.333,-59.666]`.
- Design check: aligned. The longer probes did not justify threshold tuning or broader route hints. Guarded strategic decisions are stable enough to run without failures/timeouts, but r12 regresses the mixed configuration despite stronger player-0 cash, so the next step must diagnose fallback buckets and negative outcome distribution before any code expansion.
- Commit gate: satisfied for Step 11; exact commands and results are recorded here before commit.
- Commit: `docs(ai): record strategic bot longer smoke results` (`bc7ad7eb`).

### 2026-05-15 Step 12

- Status: committed.
- Change target: analyze remaining fallback reasons after the longer matrices. Separate `no_strategic_legal_actions`, `no_plans_generated`, `no_plan_beat_baseline`, hard-gate blocks, and delta-below-threshold cases.
- Required checks: inspect decision-detail payloads for at least one representative failing point per bucket; classify whether the root cause is missing plan generation, phase-local hinting, route proof, baseline equivalence, or genuinely unsafe strategy.
- Diagnosis command: reran seed `12346` mixed as `./tools/run_bot_selfplay.sh --bots=strategy,strategic --profile=base_revenue_growth_v1 --players=2 --seed=12346 --matches=1 --target-round=12 --max-steps=2600 --budget-ms=360 --match-timeout-ms=300000 --trace-tail=2600 --trace-detail=decision --strategic-search=compared --strategic-min-search-budget-ms=120 --strategic-max-plans=6 --strategic-horizon-decisions=16 --strategic-rollout-step-budget-ms=48 --strategic-config-id=guarded_compared_step12_seed12346 --output-jsonl=res://.godot/guarded_compared_step12_seed12346_decision.jsonl`.
- Baseline comparison command: reran seed `12346` pure baseline as `./tools/run_bot_selfplay.sh --bots=strategy,strategy --profile=base_revenue_growth_v1 --players=2 --seed=12346 --matches=1 --target-round=12 --max-steps=2600 --budget-ms=360 --match-timeout-ms=300000 --trace-tail=2600 --trace-detail=compact --output-jsonl=res://.godot/strategy_step12_seed12346_compact.jsonl`.
- Bucket result: representative mixed seed `12346` ended `final_cash=[331,30]` versus pure baseline `final_cash=[201,214]`. The mixed decision trace had `no_strategic_legal_actions=34`, `no_plans_generated=5`, `no_route_progress_over_baseline=24`, `delta_below_threshold=19`, `no_route_progress_over_baseline+unsupplied_demand_regressed=1`, and `route_stalled+no_route_progress_over_baseline=1`.
- Bucket classification: `no_strategic_legal_actions` in Setup/ReserveCards is expected fallback, not a plan bug. `no_plans_generated` in Setup restaurant placement has `candidate_count=0` and no evaluated plan, so it is not the r12 regression source. `no_route_progress_over_baseline` and `delta_below_threshold` are mostly correct guard behavior: examples had `route_action_count=0` or score `6.75 < min_delta=12`.
- Regression source: seed `12346` diverges after StrategicBot approves route-progress marketing while the compared payload still has no economic proof. At round 4 player 1 chooses `marketing_marketing_trainee_11_burger_13_2_90` with `cash_after=10`, `demand_sold=0`, `demand_created=0`, `lost_to_competitor=1`, `unsold_demand=1`; the pass is driven by `route_completion_bonus=12` and `route_progress_bonus=6.2`. At round 7 it repeats the pattern with `marketing_campaign_manager_7_burger_13_5_0`, `cash_after=30`, `demand_sold=0`, and no actual cash improvement. After round 5 the mixed trace gives player 1 no further income while player 0 earns every dinner.
- Chosen Step 13 target: scoring/acceptance of already-validated evidence. Keep hard gates intact, but prevent route-only credit from clearing a compared strategic override for marketing once the player already has positive cash unless the compared rollout shows economic proof over baseline: cash/max-cash improvement, sold demand improvement, reduced lost-to-competitor demand, or reduced unsold demand. Opening cash-zero route setup and legal supply/restructuring progress should remain available when they still satisfy the existing guarded proof checks.
- Design check: aligned. This targets the diagnosed over-trust in route proof; it does not broaden route hints, bypass action validation, lower `min_delta_score`, or relax hard gates.
- Commit gate: satisfied for Step 12; diagnosis and the chosen implementation target are recorded here before code changes.
- Commit: `docs(ai): diagnose guarded strategic r12 regression` (`be3b4ad7`).

### 2026-05-15 Step 13

- Status: ready for commit.
- Change target: implement the smallest diagnosed improvement from Step 12. Candidate areas are route-specific plan generation, route proof extraction, or scoring of already-validated evidence. Hard-gate relaxation is explicitly out of scope unless a later document section proves a gate is logically wrong.
- Required checks: add or update focused `StrategicGuardedOverrideTest` coverage for the new boundary, run `CheckCompile`, run `AllTests`, and rerun the same matrix/probe that exposed the issue.
- Design check before implementation: every new strategic override must still be baseline-compared, phase-local, legal-command-backed, and explainable in trace payloads.
- In-progress diagnosis: the first implementation only required economic proof for positive-cash `marketing_income` route credit. The r12 seed `12346` trace improved player 1 from the Step 12 `30` cash outcome to about `71-86`, but still lagged the pure StrategyBot baseline because a later `price_recovery` override at cash `15` cleared on route progress/training proof alone: cash, max cash, sold demand, lost-to-competitor demand, and unsold demand were all equal to baseline.
- Adjusted implementation target: route-progress credit is available only when the compared rollout has economic proof over baseline, regardless of route type or current cash level. Cash-zero opening setup can still override only if the rollout already proves improved cash/max cash, sold demand, reduced lost demand, or reduced unsold demand.
- Design check for adjustment: aligned. This narrows StrategicBot authority; it does not relax gates, does not lower the delta threshold, and does not let route-local proof override StrategyBot unless the rollout also shows a concrete economic advantage.
- Additional diagnosis: even after narrowing route credit, seed `12346` still showed a large r12 gap with only one remaining strategic override. The underlying design flaw was fallback timing: compared search spent most of the parent budget before calling `StrategyBot` fallback, so a rejected plan could still degrade play by forcing the fallback decision to run with a starved final budget.
- Fallback implementation target: precompute the current `StrategyBot` decision before compared search. If no plan proves itself, return that precomputed baseline decision with the compared failure payload attached, instead of recomputing fallback after search. This makes "fallback to StrategyBot" literal rather than just nominal.
- Design check for fallback target: aligned. This preserves the tactical baseline, keeps plan search as an optional override only, and prevents failed strategic search from changing behavior through budget side effects.
- Follow-up diagnosis: the `strategic,strategy` r12 seat-swap exposed seed `12347` as the remaining regression. Full trace showed cash-zero `marketing_income` overrides clearing on `first_billboard` and `first_burger_produced` route proof while cash, sold demand, lost demand, and unsold demand were unchanged. That invalidates the earlier cash-zero exception.
- Follow-up target: remove the cash-zero exception entirely. Route proof is now a tie-break only after the compared rollout proves economic movement; opening marketing must reach concrete economic proof inside the rollout horizon before it can override `StrategyBot`.
- Design check for follow-up: aligned. This directly enforces the design principle that the strategic layer may choose routes, but cannot spend the opening on route-shaped intent that has not yet beaten the tactical baseline.
- Change: `StrategicBot` now precomputes the current `StrategyBot` decision before compared search and returns that decision on failed compared search, preserving the true tactical baseline. `StrategicSearch` route-progress delta credit now requires economic proof at every cash level. Compared summaries include `command_action_ids` for trace/debugging. Focused tests cover precomputed fallback preservation and the economic-proof route-credit boundary.
- Verification: `CheckCompile PASS files=1236`; `AllTests PASS passed=426/426 failed=[] total_ms=154068`.
- Matrix command: `./tools/run_bot_selfplay_matrix.sh --config=strategy --config=strategy,strategic --config=strategic,strategy --profile=base_revenue_growth_v1 --players=2 --seed=12345 --matches=3 --target-round=12 --max-steps=2600 --budget-ms=360 --match-timeout-ms=300000 --trace-tail=60 --strategic-search=compared --strategic-min-search-budget-ms=120 --strategic-max-plans=6 --strategic-horizon-decisions=16 --strategic-rollout-step-budget-ms=48 --strategic-config-id=guarded_compared_step13e_r12 --output-jsonl=res://.godot/guarded_compared_step13e_r12_allseats.jsonl --output-json=res://.godot/guarded_compared_step13e_r12_allseats_summary.json`.
- Matrix result: `configs=3`, `matches=9`, `failures=0`, `timeouts=0`. Both mixed seat configurations were behavior-identical to pure `strategy`: `tuning_score_delta=0.000`, cash averages `[248.0,123.667]`, opening deltas all `0.000`, and `types=strategy=608` with `strategic_decision_count_avg_per_match=0.000`.
- Design check before commit: aligned. Step 13 intentionally restores a no-harm baseline: failed strategic search cannot perturb the fallback, and route-shaped progress cannot override without economic proof. This is not the final strength improvement; it is the corrected guardrail required before adding positive StrategicBot-only plans.
- Commit gate: satisfied for Step 13; verification and matrix result are recorded here before commit.
- Commit: `fix(ai): preserve strategic baseline fallback` (`7b01b5dc`).

### 2026-05-15 Step 14

- Status: in progress.
- Change target: add true positive StrategicBot strength without relaxing Step 13 guardrails. The next work must generate/evaluate plans that can show economic proof inside the compared rollout horizon, rather than relying on route milestones.
- Implementation plan:
  - First checkpoint: run a decision-detail probe on the guarded Step 13 baseline and classify why candidate plans fail to produce economic proof. The implementation point must be chosen from this evidence, not from threshold tuning.
  - Extend plan generation/evaluation for only one narrow opening route first: marketing plus immediate supply/sale proof, with commands that can reach `cash_after`, `cash_max_seen`, `demand_sold`, `lost_to_competitor`, or `unsold_demand` improvement before the horizon ends.
  - Add a deterministic fixture where StrategicBot beats baseline through economic proof, and a paired negative fixture where route proof without economic proof still falls back.
  - Keep `strategic_min_delta_score`, hard gates, legal command validation, phase-local hints, and precomputed fallback unchanged.
  - Rerun the same three-config r12 matrix and require StrategicBot's own seat cash to be non-negative versus same-seat pure StrategyBot before commit.
- Design check before implementation: Step 14 may increase strategic decisions only when they produce measured economic proof. If it merely restores route-proof overrides or depends on starving the opponent through aggregate-score artifacts, it violates the design.
- First checkpoint command: `./tools/run_bot_selfplay.sh --bots=strategic,strategy --profile=base_revenue_growth_v1 --players=2 --seed=12345 --matches=1 --target-round=8 --max-steps=1800 --budget-ms=360 --match-timeout-ms=240000 --trace-tail=1800 --trace-detail=decision --strategic-search=compared --strategic-min-search-budget-ms=120 --strategic-max-plans=6 --strategic-horizon-decisions=16 --strategic-rollout-step-budget-ms=48 --strategic-config-id=guarded_compared_step14_probe_p0_seed12345 --output-jsonl=res://.godot/guarded_compared_step14_probe_p0_seed12345.jsonl`.
- First checkpoint result: `search_type_counts={"strategic":1,"strategy":118}`, `strategic_failure_counts={"insufficient_plan_search_budget":1,"no_plan_beat_baseline":32,"no_plans_generated":4,"no_strategic_legal_actions":22}`, final cash `[95,15]`.
- First checkpoint finding: the only accepted strategic decision was not a true behavior improvement. It selected `produce_food`, the same immediate action as the precomputed StrategyBot baseline, while the compared candidate rollout reached `cash_after=25` only because it executed an additional `skip_sub_phase` before stopping with `budget_expired`; the baseline rollout stopped with only `produce_food` under the same constrained child budget. Most rejected candidates also stopped with `budget_expired` and no cash/sold-demand/unsold-demand improvement.
- Point 14A target: compared search must not accept budget-expired rollout evidence. Add the rollout stop reason to compared summaries and reject candidate or baseline comparisons whose rollout stopped on `budget_expired`.
- Design check for 14A: aligned. This narrows StrategicBot authority and prevents budget artifacts from counting as economic proof; it does not relax thresholds, hard gates, legal validation, phase-local hints, or precomputed fallback.
- Point 14A change: compared summaries now include `phase_stop_reason`; hard gates reject `candidate_rollout_budget_expired` and `baseline_rollout_budget_expired`. Focused guarded tests cover both cases even when the candidate otherwise shows positive cash proof.
- Point 14A verification: `CheckCompile PASS files=1236`; `AllTests PASS passed=426/426 failed=[] total_ms=153893`.
- Point 14A post-fix probe: reran the same seed/config as `guarded_compared_step14a_postfix_p0_seed12345`. Result: `search_type_counts={"strategy":119}`, `strategic_failure_counts={"insufficient_plan_search_budget":1,"no_plan_beat_baseline":33,"no_plans_generated":4,"no_strategic_legal_actions":22}`, final cash `[95,15]`, and hard-gate failure totals included `candidate_rollout_budget_expired=33` and `baseline_rollout_budget_expired=33`. The previous budget-expired pseudo-strategic decision no longer passes.
- Design check before 14A commit: aligned. This is a guardrail fix required before adding positive strength; it reduces false positives and keeps Step 14's true-positive work pending.
- Point 14A commit: `fix(ai): reject budget-expired strategic rollouts` (`c3f81dc8`).
- Point 14B target: add the first true-positive StrategicBot route only after the compared baseline and candidate can both complete a comparable rollout boundary. The next implementation must focus on making one narrow marketing/supply/sale proof path finish inside the rollout budget or on constructing a deterministic fixture with complete non-budget-expired rollouts; it must not restore budget-expired proof or route-only proof.
- Point 14B diagnosis: high-budget probe `guarded_compared_step14b_highbudget_p0_seed12345` still produced no strategic decisions (`search_type_counts={"strategy":81}`) even with `budget_ms=1800`, because compared rollouts still used `compared_rollout_budget_ms=288` and many otherwise promising candidates stopped as `budget_expired`. A representative round-4 Recruit candidate reached `cash_after=25` vs baseline `10` after `["recruit","initiate_marketing","produce_food","produce_food","skip_sub_phase"]`, but both candidate and baseline were rejected as budget-expired. The runner checks budget before recognizing an already-reached Payday/Cleanup boundary, so complete-at-boundary rollouts can be mislabeled as budget failures.
- Point 14B implementation target: reorder `StrategicPlanRunner.rollout` loop checks so an already reached `phase_boundary`, `round_horizon`, or `game_over` state is classified before budget expiration. This does not allow budget-expired evidence; it prevents completed boundary evidence from being mislabeled as budget-expired.
- Design check for 14B: aligned. The hard gate from 14A remains intact; only the stop reason for an already-complete rollout boundary changes.
- Point 14B change: `StrategicPlanRunner.rollout` now classifies current terminal/boundary state before checking whether the rollout budget has expired.
- Point 14B verification: `CheckCompile PASS files=1236`; `AllTests PASS passed=426/426 failed=[] total_ms=154550`.
- Point 14B probes:
  - Low-budget replay `guarded_compared_step14b_lowbudget_p0_seed12345`: `search_type_counts={"strategy":119}`, `strategic_failure_counts={"insufficient_plan_search_budget":1,"no_plan_beat_baseline":33,"no_plans_generated":4,"no_strategic_legal_actions":22}`, final cash `[95,15]`. The 14A pseudo-strategic decision stayed blocked.
  - High-budget boundary replay `guarded_compared_step14b_boundary_p0_seed12345`: `search_type_counts={"strategy":81}`, `strategic_failure_counts={"no_plan_beat_baseline":20,"no_plans_generated":5,"no_strategic_legal_actions":16}`, final cash `[41,15]`. Completed boundary candidates mostly became baseline-equivalent (`delta_below_threshold`), confirming the previous `cash_after` advantage was not a true strategic edge.
  - Wider step-budget probe `guarded_compared_step14b_widestep_p0_seed12345`: still `search_type_counts={"strategy":81}`. Wider rollout step budget did not create a safe positive decision; economic-delta candidates were blocked by opponent-loss, cash-floor, unsupplied-demand, or budget gates.
- Design check before 14B commit: aligned. 14B improves evidence classification without expanding StrategicBot authority. True-positive work remains open.
- Point 14C target: create a deterministic narrow fixture that forces a real StrategyBot-vs-plan decision difference under complete non-budget-expired rollouts, then implement only the missing route generation/hinting needed for that fixture. If no such fixture exists without weakening gates, the correct next result is to document that StrategyBot already dominates this opening route and move to a different narrow route.
- Point 14B commit: `fix(ai): classify completed strategic rollout boundaries` (`f150e505`).
- Point 14C natural high-budget diagnostic: ran a three-config r6 matrix (`strategy`, `strategic,strategy`, `strategy,strategic`) with `budget_ms=1800`, `strategic_min_search_budget_ms=120`, `strategic_max_plans=6`, horizon `16`, and rollout step budget `48` under config id `guarded_compared_step14c_highbudget_matrix_r6`.
- Point 14C natural high-budget result: `configs=3`, `matches=9`, `failures=0`, `timeouts=0`; both mixed configurations were behavior-identical to pure `strategy`; `strategic_decision_count_avg_per_match=0.000`; mixed search counts were `strategy=242`, `strategic_fallback=121`; mixed failure counts were `no_plan_beat_baseline=58`, `no_plans_generated=15`, `no_strategic_legal_actions=48`; `tuning_score_delta=0.000`.
- Point 14C design check from natural diagnostic: aligned. The absence of true-positive decisions at high budget confirms Step 14 should not tune score thresholds or weaken gates. The next work must either prove a deterministic fixture where the current command differs from StrategyBot and complete rollouts show economic advantage, or close the current marketing opening route as StrategyBot-dominated and move to a different narrow route.
- Point 14C.1 implementation target: enforce the deterministic-fixture requirement in runtime. If compared search selects a plan but the final hinted command is identical to the precomputed `StrategyBot` command, `StrategicBot` must return the precomputed baseline and trace `strategic_plan_same_command_as_baseline`. This prevents same-command pseudo-overrides from being counted as strategic progress.
- Point 14C.1 design check: aligned. This narrows StrategicBot authority and makes "current command differs from StrategyBot" a code constraint. It does not relax hard gates, lower the delta threshold, change route scoring, or allow route proof without economic proof.
- Point 14C.1 change: added the same-command fallback guard in `StrategicBot` and a focused `StrategicGuardedOverrideTest` case that verifies a high-scoring compared plan with the same command remains a `strategy` fallback and preserves the selected rejected plan in the failure payload.
- Point 14C.1 verification: `CheckCompile PASS files=1236`; `AllTests PASS passed=426/426 failed=[] total_ms=154590`. Post-change r6 matrix `guarded_compared_step14c1_same_command_guard_r6` finished `configs=3`, `matches=9`, `failures=0`, `timeouts=0`; both mixed seat configurations remained behavior-identical to pure `strategy` with `tuning_score_delta=0.000`, `strategic_decision_count_avg_per_match=0.000`, mixed search counts `strategy=242`, `strategic_fallback=121`, and failure counts `no_plan_beat_baseline=58`, `no_plans_generated=15`, `no_strategic_legal_actions=48`.
- Point 14C.1 design check before commit: aligned. The guard adds no strength by itself; it prevents future false positives and preserves the Step 14 requirement that the first accepted true-positive must both differ from StrategyBot's current command and prove complete-rollout economic advantage. The marketing opening route remains StrategyBot-dominated in natural r6 probes, so the next 14C point must move to a deterministic different-command fixture or close this route and select another narrow route.
- Commit: pending for 14C.
