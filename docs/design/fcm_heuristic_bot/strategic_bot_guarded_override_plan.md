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
