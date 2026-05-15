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

Status: pending.

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

Status: pending.

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

Status: pending.

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

Status: pending.

For each step:

- update this document with the exact change and design-alignment result;
- run compile and focused AI tests;
- run small Strategy-only selfplay smoke when scoring behavior changes;
- compare against `base_revenue_growth_v1` and do not accept changes that only improve one metric while hiding cash or failure regressions.

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
