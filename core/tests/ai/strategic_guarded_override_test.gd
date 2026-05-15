class_name StrategicGuardedOverrideTest
extends RefCounted

const StrategicPlanClass = preload("res://core/ai/planning/strategic_plan.gd")
const StrategicPlanHintsClass = preload("res://core/ai/planning/strategic_plan_hints.gd")
const StrategicPlanEvaluatorClass = preload("res://core/ai/planning/strategic_plan_evaluator.gd")
const StrategicSearchClass = preload("res://core/ai/planning/strategic_search.gd")
const StrategicBotClass = preload("res://core/ai/bot/strategic_bot.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")
const MacroActionClass = preload("res://core/ai/candidates/macro_action.gd")
const CommandClass = preload("res://core/types/command.gd")
const BotDecisionClass = preload("res://core/ai/bot/bot_decision.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var low_cash := _test_low_cash_blocks_non_marketing_override()
	if not low_cash.ok:
		return low_cash
	var stalled := _test_stalled_route_is_rejected()
	if not stalled.ok:
		return stalled
	var cash_floor := _test_cash_floor_regression_is_rejected()
	if not cash_floor.ok:
		return cash_floor
	var delta := _test_delta_threshold_keeps_weak_plan_below_override_bar()
	if not delta.ok:
		return delta
	var hints := _test_next_step_hints_are_phase_local()
	if not hints.ok:
		return hints
	var structure_hints := _test_restructuring_hints_are_phase_local_route_directives()
	if not structure_hints.ok:
		return structure_hints
	var structure_progress := _test_targeted_restructuring_counts_as_route_progress()
	if not structure_progress.ok:
		return structure_progress
	var positive_override := _test_positive_plan_clears_hard_gate_and_delta()
	if not positive_override.ok:
		return positive_override
	var route_progress_delta := _test_guarded_route_progress_can_clear_delta()
	if not route_progress_delta.ok:
		return route_progress_delta
	var child_budget := _test_compared_rollout_budget_uses_child_budget()
	if not child_budget.ok:
		return child_budget
	var precomputed_fallback := _test_compared_fallback_reuses_precomputed_strategy_decision()
	if not precomputed_fallback.ok:
		return precomputed_fallback
	var scorer := _test_directive_hint_bonus_is_local_and_capped()
	if not scorer.ok:
		return scorer
	return Result.success({"cases": 12})

static func _test_low_cash_blocks_non_marketing_override() -> Result:
	var plan = StrategicPlanClass.create(
		"price_recovery_burger",
		0,
		"price_recovery",
		0.0,
		["burger"],
		[],
		["pricing_manager"],
		{},
		[],
		2,
		8,
		["set_price"]
	)
	var baseline := _summary({"cash_before": 10, "cash_min_after_first_positive": 10})
	var summary := _summary({"cash_before": 10, "cash_min_after_first_positive": 10, "route_action_count": 1})
	var hard_gate: Dictionary = StrategicSearchClass._comparison_hard_gate(plan, summary, baseline, {"strategic_cash_footing": 15})
	var reasons := _string_array(hard_gate.get("reasons", []))
	if bool(hard_gate.get("passed", true)) or not reasons.has("low_cash_non_marketing_override"):
		return Result.failure("low cash should block non-marketing strategic override: %s" % str(hard_gate))
	return Result.success()

static func _test_stalled_route_is_rejected() -> Result:
	var plan = StrategicPlanClass.create(
		"marketing_income_burger",
		0,
		"marketing_income",
		0.0,
		["burger"],
		[],
		["campaign_manager"],
		{},
		[],
		2,
		8,
		["initiate_marketing"]
	)
	var baseline := _summary({"cash_before": 20, "cash_min_after_first_positive": 20})
	var summary := _summary({"cash_before": 20, "cash_min_after_first_positive": 20, "route_action_count": 1, "route_stalled": true})
	var hard_gate: Dictionary = StrategicSearchClass._comparison_hard_gate(plan, summary, baseline, {"strategic_cash_footing": 15})
	var reasons := _string_array(hard_gate.get("reasons", []))
	if bool(hard_gate.get("passed", true)) or not reasons.has("route_stalled"):
		return Result.failure("stalled strategic route should be rejected: %s" % str(hard_gate))
	return Result.success()

static func _test_cash_floor_regression_is_rejected() -> Result:
	var plan = StrategicPlanClass.create(
		"marketing_income_burger",
		0,
		"marketing_income",
		0.0,
		["burger"],
		[],
		["campaign_manager"],
		{},
		[],
		2,
		8,
		["initiate_marketing"]
	)
	var baseline := _summary({"cash_before": 20, "cash_min_after_first_positive": 14})
	var summary := _summary({"cash_before": 20, "cash_min_after_first_positive": 12, "route_action_count": 1})
	var hard_gate: Dictionary = StrategicSearchClass._comparison_hard_gate(plan, summary, baseline, {"strategic_cash_footing": 15})
	var reasons := _string_array(hard_gate.get("reasons", []))
	if bool(hard_gate.get("passed", true)) or not reasons.has("cash_min_after_first_positive_regressed"):
		return Result.failure("cash floor regression should reject strategic override: %s" % str(hard_gate))
	return Result.success()

static func _test_delta_threshold_keeps_weak_plan_below_override_bar() -> Result:
	var plan = StrategicPlanClass.create(
		"marketing_income_burger",
		0,
		"marketing_income",
		0.0,
		["burger"],
		[],
		["campaign_manager"],
		{},
		[],
		2,
		8,
		["initiate_marketing"]
	)
	var baseline := _summary({"cash_after": 20, "cash_max_seen": 20, "demand_sold": 1})
	var weak_summary := _summary({"cash_after": 24, "cash_max_seen": 20, "demand_sold": 1, "route_action_count": 1})
	var strong_summary := _summary({"cash_after": 27, "cash_max_seen": 20, "demand_sold": 1, "route_action_count": 1})
	var weak_delta := StrategicSearchClass._comparison_delta_score(plan, weak_summary, baseline)
	var strong_delta := StrategicSearchClass._comparison_delta_score(plan, strong_summary, baseline)
	if weak_delta >= 12.0:
		return Result.failure("weak strategic delta should stay below override threshold, got %f" % weak_delta)
	if strong_delta < 12.0:
		return Result.failure("cash-positive strategic delta should clear override threshold, got %f" % strong_delta)
	return Result.success()

static func _test_next_step_hints_are_phase_local() -> Result:
	var plan = StrategicPlanClass.create(
		"marketing_income_burger",
		0,
		"marketing_income",
		0.0,
		["burger"],
		[],
		["campaign_manager", "burger_cook"],
		{},
		[],
		2,
		8,
		["recruit", "train", "initiate_marketing", "produce_food"]
	)
	var hints = StrategicPlanHintsClass.from_plan_for_decision(plan, null, ["initiate_marketing", "produce_food"])
	var data: Dictionary = hints.to_dict()
	var next_actions := _string_array(data.get("next_action_ids", []))
	var preferred_actions := _string_array(data.get("preferred_actions", []))
	var next_employees := _string_array(data.get("next_target_employees", []))
	var route_actions := _string_array(data.get("route_preferred_actions", []))
	if next_actions != ["initiate_marketing"] or preferred_actions != ["initiate_marketing"]:
		return Result.failure("directive hints should expose only the next legal action: %s" % str(data))
	if next_employees != ["campaign_manager"]:
		return Result.failure("directive employees should be bounded to the next action role: %s" % str(data))
	if not route_actions.has("produce_food"):
		return Result.failure("route-wide trace should retain later route actions: %s" % str(data))
	return Result.success()

static func _test_restructuring_hints_are_phase_local_route_directives() -> Result:
	var plan = StrategicPlanClass.create(
		"supply_capacity_burger",
		0,
		"supply_capacity",
		0.0,
		["burger"],
		[],
		["burger_cook", "kitchen_trainee"],
		{},
		[],
		2,
		8,
		["train", "produce_food"]
	)
	var hints = StrategicPlanHintsClass.from_plan_for_decision(plan, null, ["set_company_structure_direct", "submit_restructuring"])
	var data: Dictionary = hints.to_dict()
	var next_actions := _string_array(data.get("next_action_ids", []))
	var preferred_actions := _string_array(data.get("preferred_actions", []))
	var next_employees := _string_array(data.get("next_target_employees", []))
	var route_actions := _string_array(data.get("route_preferred_actions", []))
	if next_actions != ["set_company_structure_direct"] or preferred_actions != ["set_company_structure_direct"]:
		return Result.failure("restructuring directive should expose only legal route structure edits: %s" % str(data))
	if next_employees != ["burger_cook", "kitchen_trainee"]:
		return Result.failure("restructuring directive should keep route target employees: %s" % str(data))
	if route_actions.has("set_company_structure_direct") or not route_actions.has("produce_food"):
		return Result.failure("route-wide trace should stay separate from restructuring directive: %s" % str(data))
	return Result.success()

static func _test_targeted_restructuring_counts_as_route_progress() -> Result:
	var plan = StrategicPlanClass.create(
		"supply_capacity_burger",
		0,
		"supply_capacity",
		0.0,
		["burger"],
		[],
		["burger_cook", "kitchen_trainee"],
		{},
		[],
		2,
		8,
		["train", "produce_food"]
	)
	var targeted_rollout := {
		"commands_executed": [
			{"actor": 0, "action_id": "set_company_structure_direct", "params": {"employee_id": "kitchen_trainee"}},
		],
	}
	var targeted_count := StrategicPlanEvaluatorClass._route_action_count(plan, targeted_rollout)
	if targeted_count != 1:
		return Result.failure("targeted structure edit should count as route progress, got %d" % targeted_count)
	var unrelated_rollout := {
		"commands_executed": [
			{"actor": 0, "action_id": "set_company_structure_direct", "params": {"employee_id": "waitress"}},
		],
	}
	var unrelated_count := StrategicPlanEvaluatorClass._route_action_count(plan, unrelated_rollout)
	if unrelated_count != 0:
		return Result.failure("unrelated structure edit should not count as route progress, got %d" % unrelated_count)
	return Result.success()

static func _test_positive_plan_clears_hard_gate_and_delta() -> Result:
	var plan = StrategicPlanClass.create(
		"marketing_income_burger",
		0,
		"marketing_income",
		0.0,
		["burger"],
		[],
		["campaign_manager"],
		{},
		[],
		2,
		8,
		["initiate_marketing", "produce_food"]
	)
	var baseline := _summary({"cash_before": 20, "cash_after": 20, "cash_max_seen": 20, "demand_sold": 1, "command_count": 4})
	var summary := _summary({"cash_before": 20, "cash_after": 28, "cash_max_seen": 28, "demand_sold": 2, "route_action_count": 1, "command_count": 4})
	var hard_gate: Dictionary = StrategicSearchClass._comparison_hard_gate(plan, summary, baseline, {"strategic_cash_footing": 15})
	var delta := StrategicSearchClass._comparison_delta_score(plan, summary, baseline)
	if not bool(hard_gate.get("passed", false)):
		return Result.failure("positive strategic plan should clear hard gates: %s" % str(hard_gate))
	if delta < 12.0:
		return Result.failure("positive strategic plan should clear delta threshold, got %f" % delta)
	var passed := StrategicSearchClass._passed_compared_evaluated([
		{"plan_id": "positive", "score": delta, "comparison_passed": true},
		{"plan_id": "weak", "score": 3.0, "comparison_passed": false},
	])
	if passed.size() != 1 or str(Dictionary(passed[0]).get("plan_id", "")) != "positive":
		return Result.failure("positive compared plan should be selectable: %s" % str(passed))
	return Result.success()

static func _test_guarded_route_progress_can_clear_delta() -> Result:
	var plan = StrategicPlanClass.create(
		"marketing_income_burger",
		0,
		"marketing_income",
		0.0,
		["burger"],
		[],
		["campaign_manager"],
		{},
		[],
		2,
		8,
		["initiate_marketing", "produce_food"]
	)
	var baseline := _summary({"cash_before": 0, "cash_after": 0, "cash_max_seen": 0, "command_count": 5})
	var summary := _summary({
		"cash_before": 0,
		"cash_after": 0,
		"cash_max_seen": 0,
		"demand_sold": 1,
		"route_action_count": 1,
		"route_progress_bonus": 7.2,
		"route_completion_bonus": 12.0,
		"command_count": 5,
	})
	var hard_gate: Dictionary = StrategicSearchClass._comparison_hard_gate(plan, summary, baseline, {"strategic_cash_footing": 15})
	var delta := StrategicSearchClass._comparison_delta_score(plan, summary, baseline)
	if not bool(hard_gate.get("passed", false)):
		return Result.failure("guarded route progress should clear hard gates: %s" % str(hard_gate))
	if delta < 12.0:
		return Result.failure("guarded route progress should clear delta threshold, got %f" % delta)
	var no_action_summary := _summary({
		"cash_before": 0,
		"cash_after": 0,
		"cash_max_seen": 0,
		"demand_sold": 1,
		"route_action_count": 0,
		"route_progress_bonus": 7.2,
		"route_completion_bonus": 12.0,
		"command_count": 5,
	})
	var no_action_delta := StrategicSearchClass._comparison_delta_score(plan, no_action_summary, baseline)
	if no_action_delta >= 12.0:
		return Result.failure("route progress credit should require route action progress, got %f" % no_action_delta)
	return Result.success()

static func _test_compared_rollout_budget_uses_child_budget() -> Result:
	var parent_budget := TimeBudget.start(360)
	var rollout_budget_ms := StrategicSearchClass._compared_rollout_budget_ms(parent_budget, {
		"step_budget_ms": 48,
		"horizon_decisions": 16,
		"min_plans_for_rollout": 1,
	}, 6)
	if rollout_budget_ms <= 0 or rollout_budget_ms > 130:
		return Result.failure("compared rollout budget should preserve room for baseline and candidates, got %d" % rollout_budget_ms)
	var child_budget := StrategicSearchClass._compared_child_rollout_budget(parent_budget, rollout_budget_ms)
	if child_budget == null:
		return Result.failure("compared rollout child budget should be created")
	if child_budget == parent_budget:
		return Result.failure("compared rollout should not reuse the parent TimeBudget instance")
	var child_remaining := int(child_budget.remaining_ms())
	if child_remaining <= 0 or child_remaining > rollout_budget_ms:
		return Result.failure("child budget remaining should be bounded by rollout budget, got %d of %d" % [child_remaining, rollout_budget_ms])
	return Result.success()

static func _test_compared_fallback_reuses_precomputed_strategy_decision() -> Result:
	var bot := StrategicBotClass.new()
	var command := CommandClass.create("produce_food", 0, {"food_type": "burger"})
	var fallback := BotDecisionClass.create(
		command,
		"produce_burger",
		42.0,
		{"search": "strategy"},
		{"search": "strategy", "bot": "StrategyBot"}
	)
	var payload := {
		"hard_gate_failures": {"delta_below_threshold": 1},
		"time_ms": 123,
	}
	var annotated := bot._annotate_precomputed_fallback(
		fallback,
		"StrategicSearch.choose_plan_compared: no plan beat baseline gates={ \"delta_below_threshold\": 1 }",
		payload
	)
	if annotated == null or annotated.is_failure():
		return Result.failure("precomputed StrategyBot fallback should remain usable")
	if annotated.command != command:
		return Result.failure("precomputed StrategyBot fallback should preserve the original command")
	if str(annotated.trace.get("search", "")) != "strategy":
		return Result.failure("precomputed StrategyBot fallback should remain counted as strategy search: %s" % str(annotated.trace))
	if str(annotated.trace.get("strategic_fallback_source", "")) != "precomputed_strategy":
		return Result.failure("precomputed StrategyBot fallback should expose its source: %s" % str(annotated.trace))
	if str(annotated.trace.get("strategic_failure", "")).find("choose_plan_compared") < 0:
		return Result.failure("precomputed StrategyBot fallback should preserve compared failure reason: %s" % str(annotated.trace))
	if not (annotated.trace.get("strategic_failure_payload", null) is Dictionary):
		return Result.failure("precomputed StrategyBot fallback should keep compared failure payload: %s" % str(annotated.trace))
	if str(annotated.explanation.get("fallback", "")) != "strategy":
		return Result.failure("precomputed StrategyBot fallback should explain fallback strategy: %s" % str(annotated.explanation))
	return Result.success()

static func _test_directive_hint_bonus_is_local_and_capped() -> Result:
	var produce_macro := MacroActionClass.create(
		"produce_burger",
		[Command.create("produce_food", 0, {"employee_type": "burger_cook", "food_type": "burger"})],
		0.0,
		["working", "produce_food"],
		{}
	)
	var marketing_macro := MacroActionClass.create(
		"market_burger",
		[Command.create("initiate_marketing", 0, {"employee_type": "campaign_manager", "product": "burger"})],
		0.0,
		["working", "initiate_marketing"],
		{}
	)
	var hints = StrategicPlanHintsClass.create(
		"produce_now",
		["burger"],
		["produce_food"],
		["burger_cook"],
		[],
		[],
		[],
		0.0,
		0,
		[],
		["produce_food"],
		["produce_food"],
		["produce_food"],
		["burger"],
		["burger_cook"],
		"working/produce_food",
		["burger"],
		["campaign_manager", "burger_cook"],
		["initiate_marketing", "produce_food"]
	)
	var produce_features: Dictionary = {}
	var produce_bonus := StrategyScorerClass._plan_hints_bonus(null, produce_macro, {"plan_hints": hints}, produce_features)
	var marketing_features: Dictionary = {}
	var marketing_bonus := StrategyScorerClass._plan_hints_bonus(null, marketing_macro, {"plan_hints": hints}, marketing_features)
	if produce_bonus <= 0.0 or produce_bonus > 12.0:
		return Result.failure("directive hint bonus should be positive but capped, got %f features=%s" % [produce_bonus, str(produce_features)])
	if marketing_bonus != 0.0:
		return Result.failure("directive hint bonus should not leak to non-next actions, got %f features=%s" % [marketing_bonus, str(marketing_features)])
	if str(produce_features.get("plan_hints_directive_phase", "")) != "working/produce_food":
		return Result.failure("directive hint bonus should expose phase-local trace: %s" % str(produce_features))
	return Result.success()

static func _summary(overrides: Dictionary = {}) -> Dictionary:
	var out := {
		"plan_id": "",
		"route_type": "",
		"eval_score": 0.0,
		"cash_before": 20,
		"cash_after": 20,
		"cash_max_seen": 20,
		"cash_min_after_first_positive": 20,
		"milestone_value": 0.0,
		"milestones_gained": [],
		"demand_created": 0,
		"demand_sold": 0,
		"lost_to_competitor": 0,
		"salary_due_estimate": 0,
		"unsold_demand": 0,
		"route_action_count": 0,
		"route_progress_bonus": 0.0,
		"route_completion_bonus": 0.0,
		"route_transition_bonus": 0.0,
		"route_stalled": false,
		"command_count": 0,
		"restructuring_edit_count": 0,
	}
	for key in overrides.keys():
		out[key] = overrides[key]
	return out

static func _string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item).strip_edges()
			if not text.is_empty() and not out.has(text):
				out.append(text)
	out.sort()
	return out
