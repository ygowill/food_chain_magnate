# StrategyBot strengthening plan

Last updated: 2026-05-15

## Decision

StrategicBot has not yet beaten StrategyBot under guarded, fair verification. The current StrategyBot line is therefore the practical main path for a stable playable bot. StrategicBot should remain a diagnostic and narrow override tool until a real StrategyBot blind spot is proven by complete rollout evidence.

This plan strengthens StrategyBot directly by adding:

- richer scenario classification;
- profile-controlled phase parameters;
- profile-controlled economic scoring weights;
- trace-visible explanations for every new adjustment;
- focused tests before broader selfplay checks.

The goal is not to pile up arbitrary rules. Every new rule must answer:

1. What game situation is being classified?
2. Which current StrategyBot decision becomes better?
3. Which economic feature proves the change?
4. Which trace fields and tests protect it from becoming a hidden magic number?

## Design Principles

1. StrategyBot stays the baseline decision maker.
   Failed or unproven strategic search must not be used to justify weakening StrategyBot.

2. Economic proof is preferred over route labels.
   Demand, actionable demand, inventory gap, cash runway, salary pressure, lost sales, recoverable sales, and preview income are stronger evidence than route progress.

3. Parameters live in `StrategyProfile`.
   New scoring constants should be configurable through profile data when they affect strength or style. Hard-coded constants are acceptable only for structural invariants or defensive clamps.

4. Trace must expose each adjustment.
   New phase/scenario/economic modifiers should appear in `decision_trace.features` or top-level StrategyBot trace metadata so failed probes can be diagnosed without guessing.

5. Small commits, guarded by tests.
   Each implementation point must update this document, state the design-alignment check, run the relevant headless validation, and commit only scoped files.

## Implementation Roadmap

### Step 1: Profile-backed economic and phase-weight foundation

Status: complete.

Intent:

- Add `economic_weights` and `phase_action_adjustments` to `StrategyProfile`.
- Keep defaults behavior-compatible unless explicitly configured.
- Replace selected hard-coded economic coefficients in shared product valuation with profile lookups.
- Add a lightweight phase/scenario action adjustment layer in `StrategyScorer` that is trace-visible and profile-controlled.

Why this first:

- It gives later scenario work a safe home instead of scattering magic numbers.
- It lets tuning and selfplay compare profiles without code edits.
- It turns phase judgment into observable data rather than implicit action-weight drift.

Initial constraints:

- Do not weaken existing cash safety gates.
- Do not change StrategicBot acceptance gates.
- Do not add broad search or rollout dependency.
- Prefer direct planner/scorer tests before larger selfplay matrices.

Design-alignment check before commit:

- New weights are in profile data and fallback defaults.
- Missing optional weight sections preserve old behavior.
- Trace shows the applied context and adjustment.
- Tests cover profile parsing and at least one scoring effect.

### Step 2: Opening income-chain scenario judgment

Status: complete.

Target:

- Detect whether the opening chain is missing restaurant, food supply, marketing, or sellable demand.
- Prefer the missing link rather than repeating a saturated link.
- Keep the existing no-demand/cash-safety guard stronger than milestone chasing.

Candidate evidence:

- own restaurant count;
- owns food supply;
- owns marketing;
- actionable food demand and inventory gap;
- cash runway relative to salary due.

### Step 3: Midgame capacity and recovery scenarios

Status: complete.

Target:

- Differentiate ordinary demand growth from actual capacity shortage, price recovery, competitor capture, and product-switch opportunities.
- Increase score only when current command can improve sellable units or protect future sellable units.

Candidate evidence:

- actionable inventory gap;
- lost-to-competitor demand;
- price-recoverable demand;
- own-sourced opponent-blocking demand;
- DinnerPreview/MarketingPreview fields when available.

### Step 4: Growth readiness and risk control

Status: complete.

Target:

- Make house/garden/restaurant expansion more stage-aware.
- Allow growth when income chain and cash runway are stable.
- Penalize growth when it competes with immediate supply/cash recovery.

Candidate evidence:

- `StrategyRoutePlanner.house_growth_ready`;
- cash >= salary runway threshold;
- serviceable demand scale;
- remaining house/garden space.

### Step 5: Verification loop

Status: implementation in progress.

For each step:

- update this document with the exact change and design-alignment result;
- run compile and focused AI tests;
- run small Strategy-only selfplay smoke when scoring behavior changes;
- compare against `base_revenue_growth_v1` and do not accept changes that only improve one metric while hiding cash or failure regressions.

Current implementation focus:

- Treat the StrategyBot line as the product path, not a temporary bridge to StrategicBot.
- Continue the stable-income expansion chain only when it can be explained by economic evidence.
- Add direct economic scoring for expansion actions that currently rely too much on generic action weights, especially `add_garden`.
- Prefer trace-visible features such as garden revenue delta, demand-cap unlock, sale-unit estimate, and owned-restaurant service distance over hidden constants.

## Current Progress

- 2026-05-15: Pivoted main plan from StrategicBot strengthening to StrategyBot strengthening because guarded StrategicBot results are behavior-equivalent to StrategyBot, not stronger.
- 2026-05-15: Started Step 1. First implementation target is a profile-backed economic/phase-weight foundation with trace-visible scoring adjustments.
- 2026-05-15: Implemented Step 1 draft:
  - `StrategyProfile` now parses `economic_weights` and nested `phase_action_adjustments`.
  - `StrategyIncomeAnalyzer` uses profile-backed weights for shared product economic value.
  - `StrategyScorer` records `strategy_context_id` and applies profile-backed `phase_action_adjustment` when configured.
  - Default `base_revenue_v1` and `base_revenue_growth_v1` preserve existing economic coefficients and use empty phase adjustments.
  - Added targeted StrategyBot tests for profile parsing, economic-weight effect, and phase-action adjustment trace/score delta.
  - Design-alignment check before verification: this does not weaken cash safety, does not touch StrategicBot override gates, keeps defaults compatible, and makes the new mechanism profile/trace visible.
- 2026-05-15: Verified and closed Step 1:
  - `CheckCompile PASS files=1236`.
  - `AllTests PASS passed=426/426 failed=[] total_ms=155482`.
  - Strategy-only smoke: `base_revenue_growth_v1`, 2 players, seeds `12345-12347`, target round 8, `configs=1`, `matches=3`, `failures=0`, `timeouts=0`.
- Smoke summary: success `1.000`, avg round `8.000`, `cash_min_after_first_positive_avg=[10.0, 10.0]`, search types `strategy=358`.
- Design-alignment result: Step 1 stayed within the StrategyBot mainline, made scoring knobs profile-backed and trace-visible, and preserved default behavior compatibility.
- 2026-05-15: Implemented Step 2 draft for `base_revenue_growth_v1`:
  - Added profile-backed `phase_action_adjustments` for `cash_shortfall`, `opening_needs_restaurant`, `opening_needs_food_supply`, and `opening_needs_marketing`.
  - Kept `base_revenue_v1` phase adjustments empty as a conservative baseline profile.
  - Added targeted StrategyBot tests that assert the growth profile exposes the configured opening-chain context and adjustment for missing food supply, missing marketing, and missing restaurant cases.
  - Design-alignment check before verification: adjustments are modest, profile-scoped, trace-visible through `strategy_context_id` / `phase_action_adjustment`, and do not override existing cash safety or legal validation.
- 2026-05-15: Verified and closed Step 2:
  - `CheckCompile PASS files=1236`.
  - `AllTests PASS passed=426/426 failed=[] total_ms=152600`.
  - Strategy-only smoke: `base_revenue_growth_v1`, 2 players, seeds `12345-12347`, target round 8, `configs=1`, `matches=3`, `failures=0`, `timeouts=0`.
  - Smoke summary: success `1.000`, avg round `8.000`, `cash_min_after_first_positive_avg=[10.0, 10.0]`, opening positive cash avg `2.000`, no-positive-cash avg `0.000`, search types `strategy=358`.
  - Design-alignment result: opening-chain adjustments stayed profile-scoped and trace-visible; small smoke did not show strength movement, but it preserved safety and gives the next tuning pass a controlled stage-parameter surface.
- 2026-05-15: Implemented Step 3 draft for `base_revenue_growth_v1`:
  - Added `income_supply_gap` adjustments that prefer `produce_food`, `procure_drinks`, training, structure activation, and limited recruiting when actionable inventory gap exists.
  - Added `income_recovery` adjustments that prefer price actions plus structure/recruit/marketing support when lost or price-recoverable demand is present.
  - Added targeted StrategyBot tests for the configured `income_supply_gap` and `income_recovery` contexts and score adjustments.
  - Design-alignment check before verification: adjustments are tied to economic context (`actionable_inventory_gap`, lost demand, price-recoverable demand), remain profile-scoped, and stay below hard planner gates and preview evidence.
- 2026-05-15: Verified and closed Step 3:
  - `CheckCompile PASS files=1236`.
  - `AllTests` first run hit a `BeamSearchTest` fixed-budget edge (`beam_budget_expired=true`, 260ms budget / 267ms elapsed); immediate rerun passed.
  - `AllTests PASS passed=426/426 failed=[] total_ms=159109`.
  - Strategy-only smoke: `base_revenue_growth_v1`, 2 players, seeds `12345-12347`, target round 8, `configs=1`, `matches=3`, `failures=0`, `timeouts=0`.
  - Smoke summary: success `1.000`, avg round `8.000`, avg cash `[68.333, 63.667]`, `cash_min_after_first_positive_avg=[10.0, 10.0]`, opening positive cash avg `2.000`, no-positive-cash avg `0.000`, `produce_food=35`, `set_price` mandatory completions `8`, search types `strategy=375`.
  - Design-alignment result: Step 3 keeps StrategyBot as the mainline and adds economic context scoring only through profile-scoped, trace-visible phase adjustments; it improves midgame supply/recovery judgment without changing hard validation, cash safety gates, or StrategicBot override behavior.
- 2026-05-15: Implemented Step 4 draft for `base_revenue_growth_v1`:
  - Added `growth_ready` adjustments that prefer `place_house`, `add_garden`, restaurant positioning, and modest recruit/train/marketing support only after `StrategyRoutePlanner.house_growth_ready`.
  - Added `income_recovery` expansion penalties for `place_house`, `add_garden`, `place_restaurant`, and `move_restaurant` so price/competition recovery beats new growth.
  - Added targeted StrategyBot tests proving stable income exposes `growth_ready` and recovery demand takes priority over growth-ready expansion.
  - Design-alignment check before verification: Step 4 reuses existing route-readiness evidence rather than adding speculative logic; the new behavior is profile-scoped, trace-visible, and ordered below cash/supply/recovery safety contexts.
- 2026-05-15: Verified and closed Step 4:
  - `CheckCompile PASS files=1236`.
  - `AllTests PASS passed=426/426 failed=[] total_ms=159349`.
  - Strategy-only smoke: `base_revenue_growth_v1`, 2 players, seeds `12345-12347`, target round 8, `configs=1`, `matches=3`, `failures=0`, `timeouts=0`.
  - Smoke summary: success `1.000`, avg round `8.000`, avg cash `[68.333, 63.667]`, `cash_min_after_first_positive_avg=[10.0, 10.0]`, opening positive cash avg `2.000`, no-positive-cash avg `0.000`, `produce_food=35`, search types `strategy=375`.
  - Residual watchpoint: action mix was unchanged in the small smoke and budget-expired rate rose slightly from Step 3's `0.048` to `0.059`; keep larger matrices focused on whether `growth_ready` actually converts stable income into useful expansion without search-cost drift.
  - Design-alignment result: Step 4 stayed within the StrategyBot profile/scoring layer and preserved opening/cash/supply behavior; growth bonuses only apply after existing economic readiness evidence, while recovery penalties keep immediate revenue repair ahead of expansion.
- 2026-05-15: Step 5 longer verification found a growth-chain blocker:
  - 10-seed round-12 strategy-only smoke passed stability (`matches=10`, `failures=0`, `timeouts=0`) and kept high average cash, but produced no `place_house` / `add_garden` actions.
  - Root cause: `strategy_context_id` treated every actionable inventory gap as `income_supply_gap`, even when `StrategyRoutePlanner.house_growth_ready` said demand was supply-ready and cash/runway were sufficient.
  - Implemented a correction so `income_supply_gap` means real shortage (`supply_blocked_actionable_demand > 0` or growth route not ready), while supply-ready high-cash states can enter `growth_ready`.
  - Added a targeted StrategyBot test for supply-ready growth with current inventory gap so this does not regress.
  - Design-alignment check before verification: the change narrows an over-broad context rather than weakening cash safety; recovery still outranks growth, and blocked demand still stays in `income_supply_gap`.
- 2026-05-15: Step 5 follow-up found a second growth-chain blocker:
  - After the context fix, the same 10-seed round-12 smoke still produced no `place_house` / `add_garden`, while traces showed the management/NBD chain could appear in reserve.
  - Root cause: `StrategyStructurePlanner` intentionally damped generic employee value to avoid restructuring loops, but that also damped `placement_route_value`; this made reserve `new_business_developer` too easy to lose against ordinary structure upkeep once the bot had stable revenue.
  - Implemented a narrower structure scoring correction: keep generic employee value damped, but move `placement_route_value` into full `structure_route_support_value` and expose `structure_placement_route_support_value`.
  - Added a targeted StrategyBot test asserting ready reserve NBD keeps placement value as full route support.
  - Design-alignment check before verification: this preserves the anti-cycle generic employee damping, applies only when the existing placement route already says economy/growth is ready, and keeps cash/supply/recovery gates ahead of expansion.
- 2026-05-15: Step 5 follow-up found the structure fix alone was not enough:
  - Repeat 10-seed round-12 smoke stayed stable (`matches=10`, `failures=0`, `timeouts=0`) but still produced no `place_house` / `add_garden`.
  - Trace read: NBD appears only rarely and late; most games either stop at `management_trainee` in reserve or never enter the expansion employee chain before target round/game over.
  - Root cause: the design waited until full `house_growth_ready` before valuing management trainee, but management trainee is only a preparation card and still needs a later train/structure cycle to become active NBD.
  - Implemented `growth_setup`: when income is stable and growth space exists, StrategyBot can start the management-trainee prep chain before full expansion readiness; actual NBD training and board expansion still require the existing stronger readiness gates.
  - Updated `base_revenue_growth_v1` with `growth_setup` stage adjustments and added targeted tests for management prep value, desired recruit count, and the new `growth_setup` context.
  - Design-alignment check before verification: this does not raise `place_house` early; it only moves the long-lead expansion employee setup earlier after stable income, while keeping supply/recovery contexts ahead of growth.
- 2026-05-15: Step 5 verification after `growth_setup` improved the chain but still exposed a board-scoring gap:
  - `CheckCompile PASS files=1236`.
  - `AllTests PASS passed=426/426 failed=[] total_ms=158420`.
  - 10-seed round-12 strategy-only smoke stayed stable (`matches=10`, `failures=0`, `timeouts=0`) and produced `place_house=4`, but still produced `add_garden=0`.
  - Trace read: NBD can now appear, but expansion actions are still sparse; `add_garden` has no direct StrategyBoardAnalyzer economic value, so it mostly relies on generic action weights and phase adjustment.
  - Next implementation target: add trace-visible garden economic scoring based on current house demand, estimated sale units, unit-price revenue delta, demand-cap unlock, and owned-restaurant service distance.
  - Design-alignment check before implementation: this keeps StrategyBot as the mainline and strengthens expansion through economic proof rather than arbitrary growth bonuses.
- 2026-05-15: Implemented the next Step 5 draft:
  - Added `StrategyBoardAnalyzer.evaluate_garden_action()` and wired `add_garden` into `StrategyScorer`.
  - Garden scoring now exposes `garden_revenue_delta_estimate`, `garden_cap_unlock_units`, `garden_estimated_sale_units`, `garden_unit_price`, and `garden_nearest_restaurant_distance`.
  - Added targeted StrategyBot coverage proving a serviceable, demand-heavy, no-garden house receives positive garden economic value.
  - 10-seed round-12 smoke after garden scoring stayed stable but did not change action distribution (`place_house=4`, `add_garden=0`), proving the remaining bottleneck is upstream of garden action scoring.
  - Trace/result read: management trainee is often held or trained into `luxury_manager`; actual `new_business_developer` appears too rarely before the round-12 target.
  - Added a trace-visible management-trainee reserve adjustment in `StrategyTrainPlanner`: stable-income states with remaining house/garden space reserve management trainee for NBD instead of spending it on non-expansion training; explicit price-recovery demand can still allow price training.
  - Design-alignment check before verification: this protects a long-lead expansion setup card after economic stability is proven, while preserving recovery-before-growth and avoiding early `place_house` / `add_garden` bonuses.
- 2026-05-15: Follow-up on management-trainee protection:
  - The first reserve adjustment reduced non-NBD training score but did not prevent `management_trainee -> luxury_manager`; the action still beat skipping in late-game traces.
  - Tightened the rule into a StrategyScorer precondition: when `train_expansion_reserved_for_nbd` is true, non-NBD management-trainee training is ineligible (`strategy_precondition_failed=management_trainee_reserved_for_nbd`).
  - Design-alignment check before verification: this is a structural route-preservation guard, not a broad score boost; price-recovery exceptions remain allowed.
- 2026-05-15: Verified Step 5 train/garden draft:
  - `AllTests PASS passed=426/426 failed=[] total_ms=159514`.
  - Round-12 10-seed strategy-only smoke stayed stable: `matches=10`, `failures=0`, `timeouts=0`, `success=1.000`; action distribution remained `place_house=4`, `add_garden=0`.
  - Trace confirmed the guard changed at least one late branch from `management_trainee -> luxury_manager` to `management_trainee -> new_business_developer`.
  - Round-14 10-seed strategy-only smoke stayed stable: `matches=10`, `failures=0`, `timeouts=0`, `success=1.000`; `place_house` increased to `6`, while `add_garden` remained `0`.
  - Safety metrics stayed acceptable: round-14 `cash_min_after_first_positive_avg=[10.3, 9.5]`, search `expired_rate=0.036`, avg cash `[222.0, 190.7]`.
  - Design-alignment result: the change strengthens StrategyBot through stage-aware economic scoring and route-preservation guards, not StrategicBot rollouts; residual watchpoint is that `add_garden` now has scoring support but still needs real candidate opportunities to appear in selfplay.
