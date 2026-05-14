class_name StrategicSearch
extends RefCounted

const StrategicPlanGeneratorClass = preload("res://core/ai/planning/strategic_plan_generator.gd")
const StrategicPlanRunnerClass = preload("res://core/ai/planning/strategic_plan_runner.gd")
const StrategicPlanEvaluatorClass = preload("res://core/ai/planning/strategic_plan_evaluator.gd")
const StrategicMCTSSearchClass = preload("res://core/ai/planning/strategic_mcts_search.gd")
const StrategicPlanClass = preload("res://core/ai/planning/strategic_plan.gd")

const DEFAULT_COMPARED_MIN_DELTA_SCORE := 12.0
const DEFAULT_CASH_FOOTING := 15
const DEFAULT_RESTRUCTURING_EDIT_MARGIN := 2

static func choose_plan_beam(
	engine: GameEngine,
	observation: ObservationState,
	profile = null,
	budget: TimeBudget = null,
	options: Dictionary = {}
) -> Result:
	if engine == null:
		return Result.failure("StrategicSearch.choose_plan_beam: engine is null")
	if observation == null:
		return Result.failure("StrategicSearch.choose_plan_beam: observation is null")
	if budget != null and budget.expired():
		return Result.failure("StrategicSearch.choose_plan_beam: budget expired before search")
	var start_ms := Time.get_ticks_msec()
	var generator_options := options.duplicate()
	generator_options["source_state"] = engine.get_state()
	var plans_read := StrategicPlanGeneratorClass.generate(observation, profile, generator_options)
	if not plans_read.ok:
		return plans_read
	var plans: Array = plans_read.value
	if plans.is_empty():
		return Result.failure("StrategicSearch.choose_plan_beam: no plans generated")
	var min_plans_for_rollout := maxi(1, int(options.get("min_plans_for_rollout", 1)))
	if plans.size() < min_plans_for_rollout:
		return Result.failure("StrategicSearch.choose_plan_beam: insufficient route alternatives (%d < %d)" % [plans.size(), min_plans_for_rollout])
	var evaluated: Array[Dictionary] = []
	var successful_evaluations := 0
	var max_plans := maxi(1, int(options.get("max_plans", plans.size())))
	var limit := mini(max_plans, plans.size())
	for i in range(limit):
		if budget != null and budget.expired() and not evaluated.is_empty():
			break
		var plan_val = plans[i]
		if plan_val == null or not plan_val.has_method("is_valid"):
			continue
		var plan = plan_val
		var plan_horizon_decisions := _bounded_plan_horizon(int(options.get("horizon_decisions", plan.horizon_decisions)), int(plan.horizon_decisions))
		var plan_horizon_rounds := _bounded_plan_horizon(int(options.get("horizon_rounds", plan.horizon_rounds)), int(plan.horizon_rounds))
		var rollout_options := {
			"horizon_decisions": plan_horizon_decisions,
			"horizon_rounds": plan_horizon_rounds,
			"step_budget_ms": int(options.get("step_budget_ms", 40)),
			"budget": budget,
		}
		var rollout_read := StrategicPlanRunnerClass.rollout(engine, plan, profile, rollout_options)
		if not rollout_read.ok:
			evaluated.append({
				"plan": plan,
				"plan_id": plan.id,
				"route_type": plan.route_type,
				"prior_score": plan.prior_score,
				"score": -INF,
				"error": rollout_read.error,
			})
			continue
		var eval_read := StrategicPlanEvaluatorClass.evaluate_rollout(plan, rollout_read.value, profile)
		if not eval_read.ok:
			evaluated.append({
				"plan": plan,
				"plan_id": plan.id,
				"route_type": plan.route_type,
				"prior_score": plan.prior_score,
				"score": -INF,
				"error": eval_read.error,
			})
			continue
		var eval_payload: Dictionary = eval_read.value
		successful_evaluations += 1
		evaluated.append({
			"plan": plan,
			"plan_id": plan.id,
			"route_type": plan.route_type,
			"prior_score": plan.prior_score,
			"score": float(eval_payload.get("score", 0.0)) + plan.prior_score * 0.2,
			"eval_score": float(eval_payload.get("score", 0.0)),
			"breakdown": Dictionary(eval_payload.get("breakdown", {})).duplicate(true),
			"telemetry": Dictionary(eval_payload.get("telemetry", {})).duplicate(true),
			"rollout": _rollout_trace_payload(Dictionary(rollout_read.value)),
		})
	if evaluated.is_empty():
		return Result.failure("StrategicSearch.choose_plan_beam: no plans evaluated")
	if successful_evaluations < min_plans_for_rollout:
		return Result.failure("StrategicSearch.choose_plan_beam: insufficient evaluated route alternatives (%d < %d)" % [successful_evaluations, min_plans_for_rollout])
	var actionable_evaluated := _actionable_evaluated(evaluated)
	if actionable_evaluated.is_empty():
		return Result.failure("StrategicSearch.choose_plan_beam: no plans made route progress")
	evaluated = actionable_evaluated
	_sort_evaluated(evaluated)
	var best: Dictionary = evaluated[0]
	var best_plan_val = best.get("plan", null)
	if best_plan_val == null or not best_plan_val.has_method("to_trace_dict") or float(best.get("score", -INF)) <= -INF:
		return Result.failure("StrategicSearch.choose_plan_beam: no plan evaluated successfully")
	var best_plan = best_plan_val
	var trace := _trace_evaluated(evaluated, 5)
	return Result.success({
		"plan": best_plan,
		"score": float(best.get("score", 0.0)),
		"evaluated_plans": trace,
		"telemetry": Dictionary(best.get("telemetry", {})).duplicate(true),
		"candidate_count": plans.size(),
		"evaluated_count": evaluated.size(),
		"time_ms": Time.get_ticks_msec() - start_ms,
	})

static func choose_plan_compared(
	engine: GameEngine,
	observation: ObservationState,
	profile = null,
	budget: TimeBudget = null,
	options: Dictionary = {}
) -> Result:
	if engine == null:
		return Result.failure("StrategicSearch.choose_plan_compared: engine is null")
	if observation == null:
		return Result.failure("StrategicSearch.choose_plan_compared: observation is null")
	if budget != null and budget.expired():
		return Result.failure("StrategicSearch.choose_plan_compared: budget expired before search")
	var start_ms := Time.get_ticks_msec()
	var owner_player_id := int(observation.viewer_player_id)
	var generator_options := options.duplicate()
	generator_options["source_state"] = engine.get_state()
	var plans_read := StrategicPlanGeneratorClass.generate(observation, profile, generator_options)
	if not plans_read.ok:
		return plans_read
	var plans: Array = plans_read.value
	if plans.is_empty():
		return Result.failure("StrategicSearch.choose_plan_compared: no plans generated").with_value({
			"candidate_count": 0,
			"evaluated_count": 0,
			"successful_evaluations": 0,
			"evaluated_plans": [],
			"hard_gate_failures": {},
			"time_ms": Time.get_ticks_msec() - start_ms,
		})

	var baseline_plan = _baseline_plan(owner_player_id, options)
	var baseline_rollout_options := _rollout_options_for_plan(baseline_plan, budget, options)
	var baseline_rollout_read := StrategicPlanRunnerClass.rollout(engine, baseline_plan, profile, baseline_rollout_options)
	if not baseline_rollout_read.ok:
		return baseline_rollout_read
	var baseline_eval_read := StrategicPlanEvaluatorClass.evaluate_rollout(baseline_plan, Dictionary(baseline_rollout_read.value), profile)
	if not baseline_eval_read.ok:
		return baseline_eval_read
	var baseline_summary := _comparison_summary(baseline_plan, Dictionary(baseline_rollout_read.value), Dictionary(baseline_eval_read.value))

	var evaluated: Array[Dictionary] = []
	var successful_evaluations := 0
	var max_plans := maxi(1, int(options.get("max_plans", plans.size())))
	var limit := mini(max_plans, plans.size())
	var min_delta_score := float(options.get("strategic_min_delta_score", options.get("min_delta_score", DEFAULT_COMPARED_MIN_DELTA_SCORE)))
	var hard_gate_failures := {}
	for i in range(limit):
		if budget != null and budget.expired() and not evaluated.is_empty():
			break
		var plan_val = plans[i]
		if plan_val == null or not plan_val.has_method("is_valid"):
			continue
		var plan = plan_val
		var rollout_options := _rollout_options_for_plan(plan, budget, options)
		var rollout_read := StrategicPlanRunnerClass.rollout(engine, plan, profile, rollout_options)
		if not rollout_read.ok:
			evaluated.append({
				"plan": plan,
				"plan_id": plan.id,
				"route_type": plan.route_type,
				"prior_score": plan.prior_score,
				"score": -INF,
				"error": rollout_read.error,
				"comparison_passed": false,
			})
			continue
		var rollout_payload: Dictionary = Dictionary(rollout_read.value)
		var eval_read := StrategicPlanEvaluatorClass.evaluate_rollout(plan, rollout_payload, profile)
		if not eval_read.ok:
			evaluated.append({
				"plan": plan,
				"plan_id": plan.id,
				"route_type": plan.route_type,
				"prior_score": plan.prior_score,
				"score": -INF,
				"error": eval_read.error,
				"comparison_passed": false,
			})
			continue
		var eval_payload: Dictionary = Dictionary(eval_read.value)
		var summary := _comparison_summary(plan, rollout_payload, eval_payload)
		var hard_gate := _comparison_hard_gate(plan, summary, baseline_summary, options)
		var delta_score := _comparison_delta_score(plan, summary, baseline_summary)
		var passed := bool(hard_gate.get("passed", false)) and delta_score >= min_delta_score
		if not passed:
			_count_hard_gate_failures(hard_gate_failures, hard_gate, delta_score, min_delta_score)
		successful_evaluations += 1
		evaluated.append({
			"plan": plan,
			"plan_id": plan.id,
			"route_type": plan.route_type,
			"prior_score": plan.prior_score,
			"score": delta_score,
			"eval_score": float(eval_payload.get("score", 0.0)),
			"breakdown": Dictionary(eval_payload.get("breakdown", {})).duplicate(true),
			"telemetry": Dictionary(eval_payload.get("telemetry", {})).duplicate(true),
			"rollout": _rollout_trace_payload(rollout_payload),
			"comparison": summary,
			"baseline": baseline_summary,
			"hard_gate": hard_gate,
			"comparison_passed": passed,
			"min_delta_score": min_delta_score,
		})
	if evaluated.is_empty():
		return Result.failure("StrategicSearch.choose_plan_compared: no plans evaluated").with_value(_compared_failure_payload(evaluated, baseline_summary, plans.size(), successful_evaluations, hard_gate_failures, min_delta_score, start_ms))
	if successful_evaluations <= 0:
		return Result.failure("StrategicSearch.choose_plan_compared: no plans evaluated successfully").with_value(_compared_failure_payload(evaluated, baseline_summary, plans.size(), successful_evaluations, hard_gate_failures, min_delta_score, start_ms))
	var passed_evaluated := _passed_compared_evaluated(evaluated)
	if passed_evaluated.is_empty():
		return Result.failure("StrategicSearch.choose_plan_compared: no plan beat baseline gates=%s" % str(hard_gate_failures)).with_value(_compared_failure_payload(evaluated, baseline_summary, plans.size(), successful_evaluations, hard_gate_failures, min_delta_score, start_ms))
	evaluated = passed_evaluated
	_sort_evaluated(evaluated)
	var best: Dictionary = evaluated[0]
	var best_plan_val = best.get("plan", null)
	if best_plan_val == null or not best_plan_val.has_method("to_trace_dict") or float(best.get("score", -INF)) <= -INF:
		return Result.failure("StrategicSearch.choose_plan_compared: no plan evaluated successfully").with_value(_compared_failure_payload(evaluated, baseline_summary, plans.size(), successful_evaluations, hard_gate_failures, min_delta_score, start_ms))
	var best_plan = best_plan_val
	return Result.success({
		"plan": best_plan,
		"score": float(best.get("score", 0.0)),
		"evaluated_plans": _trace_evaluated(evaluated, 5),
		"telemetry": Dictionary(best.get("telemetry", {})).duplicate(true),
		"candidate_count": plans.size(),
		"evaluated_count": evaluated.size(),
		"time_ms": Time.get_ticks_msec() - start_ms,
		"baseline": baseline_summary,
		"comparison": Dictionary(best.get("comparison", {})).duplicate(true),
		"hard_gate": Dictionary(best.get("hard_gate", {})).duplicate(true),
		"min_delta_score": min_delta_score,
	})

static func choose_plan_mcts(
	engine: GameEngine,
	observation: ObservationState,
	profile = null,
	budget: TimeBudget = null,
	options: Dictionary = {}
) -> Result:
	return StrategicMCTSSearchClass.choose_plan_mcts(engine, observation, profile, budget, options)

static func _bounded_plan_horizon(requested: int, plan_value: int) -> int:
	var request_limit := maxi(1, int(requested))
	var plan_limit := maxi(1, int(plan_value))
	return mini(request_limit, plan_limit)

static func _sort_evaluated(evaluated: Array[Dictionary]) -> void:
	evaluated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ascore := float(a.get("score", -INF))
		var bscore := float(b.get("score", -INF))
		if not is_equal_approx(ascore, bscore):
			return ascore > bscore
		var aprior := float(a.get("prior_score", 0.0))
		var bprior := float(b.get("prior_score", 0.0))
		if not is_equal_approx(aprior, bprior):
			return aprior > bprior
		return str(a.get("plan_id", "")) < str(b.get("plan_id", ""))
	)

static func _passed_compared_evaluated(evaluated: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item_val in evaluated:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if float(item.get("score", -INF)) <= -INF:
			continue
		if not bool(item.get("comparison_passed", false)):
			continue
		out.append(item)
	return out

static func _actionable_evaluated(evaluated: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item_val in evaluated:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if float(item.get("score", -INF)) <= -INF:
			continue
		var telemetry: Dictionary = Dictionary(item.get("telemetry", {}))
		if bool(telemetry.get("route_stalled", false)):
			continue
		out.append(item)
	return out

static func _trace_evaluated(evaluated: Array[Dictionary], limit: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(mini(maxi(0, limit), evaluated.size())):
		var item: Dictionary = evaluated[i]
		var rollout: Dictionary = Dictionary(item.get("rollout", {}))
		out.append({
			"plan_id": str(item.get("plan_id", "")),
			"route_type": str(item.get("route_type", "")),
			"prior_score": float(item.get("prior_score", 0.0)),
			"score": float(item.get("score", -INF)),
			"eval_score": float(item.get("eval_score", 0.0)),
			"breakdown": Dictionary(item.get("breakdown", {})).duplicate(true),
			"telemetry": Dictionary(item.get("telemetry", {})).duplicate(true),
			"comparison": Dictionary(item.get("comparison", {})).duplicate(true),
			"hard_gate": Dictionary(item.get("hard_gate", {})).duplicate(true),
			"comparison_passed": bool(item.get("comparison_passed", false)),
			"stop_reason": str(rollout.get("phase_stop_reason", item.get("error", ""))),
			"commands": Array(rollout.get("commands_executed", [])).size(),
			"error": str(item.get("error", "")),
		})
	return out

static func _rollout_trace_payload(rollout: Dictionary) -> Dictionary:
	return {
		"commands_executed": Array(rollout.get("commands_executed", [])).duplicate(true),
		"round_delta": int(rollout.get("round_delta", 0)),
		"phase_stop_reason": str(rollout.get("phase_stop_reason", "")),
		"cash_before": int(rollout.get("cash_before", 0)),
		"cash_after": int(rollout.get("cash_after", 0)),
		"cash_max_seen": int(rollout.get("cash_max_seen", 0)),
		"cash_min_after_first_positive": int(rollout.get("cash_min_after_first_positive", 0)),
		"search_time_ms": int(rollout.get("search_time_ms", 0)),
		"fork_ms": int(rollout.get("fork_ms", 0)),
	}

static func _compared_failure_payload(
	evaluated: Array[Dictionary],
	baseline_summary: Dictionary,
	candidate_count: int,
	successful_evaluations: int,
	hard_gate_failures: Dictionary,
	min_delta_score: float,
	start_ms: int
) -> Dictionary:
	return {
		"candidate_count": maxi(0, int(candidate_count)),
		"evaluated_count": evaluated.size(),
		"successful_evaluations": maxi(0, int(successful_evaluations)),
		"baseline": baseline_summary.duplicate(true),
		"evaluated_plans": _trace_evaluated(evaluated, 5),
		"hard_gate_failures": hard_gate_failures.duplicate(true),
		"min_delta_score": min_delta_score,
		"time_ms": Time.get_ticks_msec() - start_ms,
	}

static func _baseline_plan(owner_player_id: int, options: Dictionary):
	return StrategicPlanClass.create(
		"baseline_strategy",
		owner_player_id,
		"baseline_strategy",
		0.0,
		[],
		[],
		[],
		{},
		["baseline"],
		maxi(1, int(options.get("horizon_rounds", 2))),
		maxi(1, int(options.get("horizon_decisions", 16))),
		[]
	)

static func _rollout_options_for_plan(plan, budget: TimeBudget, options: Dictionary) -> Dictionary:
	var plan_horizon_decisions := _bounded_plan_horizon(int(options.get("horizon_decisions", plan.horizon_decisions)), int(plan.horizon_decisions))
	var plan_horizon_rounds := _bounded_plan_horizon(int(options.get("horizon_rounds", plan.horizon_rounds)), int(plan.horizon_rounds))
	return {
		"horizon_decisions": plan_horizon_decisions,
		"horizon_rounds": plan_horizon_rounds,
		"step_budget_ms": int(options.get("step_budget_ms", 40)),
		"budget": budget,
		"route_history": Array(options.get("route_history", [])).duplicate(true),
	}

static func _comparison_summary(plan, rollout: Dictionary, eval_payload: Dictionary) -> Dictionary:
	var breakdown: Dictionary = Dictionary(eval_payload.get("breakdown", {}))
	var telemetry: Dictionary = Dictionary(eval_payload.get("telemetry", {}))
	var commands := Array(rollout.get("commands_executed", []))
	return {
		"plan_id": str(plan.id),
		"route_type": str(plan.route_type),
		"eval_score": float(eval_payload.get("score", 0.0)),
		"cash_before": int(rollout.get("cash_before", 0)),
		"cash_after": int(rollout.get("cash_after", 0)),
		"cash_max_seen": int(rollout.get("cash_max_seen", 0)),
		"cash_min_after_first_positive": int(rollout.get("cash_min_after_first_positive", 0)),
		"milestone_value": float(breakdown.get("milestone_value", 0.0)),
		"milestones_gained": Array(telemetry.get("milestones_gained", [])).duplicate(true),
		"demand_created": int(telemetry.get("demand_created", 0)),
		"demand_sold": int(telemetry.get("demand_sold", 0)),
		"lost_to_competitor": int(telemetry.get("lost_to_competitor", 0)),
		"salary_due_estimate": int(telemetry.get("salary_due_estimate", 0)),
		"unsold_demand": _unsold_demand_from_breakdown(breakdown),
		"route_action_count": int(telemetry.get("route_action_count", 0)),
		"route_stalled": bool(telemetry.get("route_stalled", false)),
		"command_count": commands.size(),
		"restructuring_edit_count": _count_actions(commands, ["restructure_employee", "set_company_structure_direct", "set_company_structure_report"]),
	}

static func _comparison_hard_gate(plan, summary: Dictionary, baseline: Dictionary, options: Dictionary) -> Dictionary:
	var reasons: Array[String] = []
	if int(summary.get("cash_min_after_first_positive", 0)) < int(baseline.get("cash_min_after_first_positive", 0)):
		reasons.append("cash_min_after_first_positive_regressed")
	if int(summary.get("salary_due_estimate", 0)) > int(baseline.get("salary_due_estimate", 0)):
		reasons.append("salary_risk_regressed")
	if int(summary.get("lost_to_competitor", 0)) > int(baseline.get("lost_to_competitor", 0)):
		reasons.append("opponent_loss_regressed")
	if bool(summary.get("route_stalled", false)):
		reasons.append("route_stalled")
	var cash_footing := maxi(1, int(options.get("strategic_cash_footing", DEFAULT_CASH_FOOTING)))
	if int(baseline.get("cash_before", 0)) < cash_footing and str(plan.route_type) != "marketing_income":
		reasons.append("low_cash_non_marketing_override")
	if int(summary.get("route_action_count", 0)) <= 0 \
			and int(summary.get("demand_created", 0)) <= int(baseline.get("demand_created", 0)) \
			and int(summary.get("demand_sold", 0)) <= int(baseline.get("demand_sold", 0)):
		reasons.append("no_route_progress_over_baseline")
	if int(summary.get("unsold_demand", 0)) > int(baseline.get("unsold_demand", 0)) \
			and int(summary.get("demand_sold", 0)) <= int(baseline.get("demand_sold", 0)):
		reasons.append("unsupplied_demand_regressed")
	var restructuring_margin := maxi(0, int(options.get("strategic_restructuring_edit_margin", DEFAULT_RESTRUCTURING_EDIT_MARGIN)))
	if int(summary.get("restructuring_edit_count", 0)) > int(baseline.get("restructuring_edit_count", 0)) + restructuring_margin:
		reasons.append("restructuring_edit_risk")
	return {
		"passed": reasons.is_empty(),
		"reasons": reasons,
	}

static func _comparison_delta_score(plan, summary: Dictionary, baseline: Dictionary) -> float:
	var score := 0.0
	score += float(int(summary.get("cash_after", 0)) - int(baseline.get("cash_after", 0))) * 2.0
	score += float(int(summary.get("cash_max_seen", 0)) - int(baseline.get("cash_max_seen", 0))) * 1.5
	score += float(int(summary.get("demand_sold", 0)) - int(baseline.get("demand_sold", 0))) * 10.0
	var demand_created_delta := int(summary.get("demand_created", 0)) - int(baseline.get("demand_created", 0))
	if demand_created_delta > 0 and int(summary.get("unsold_demand", 0)) <= int(baseline.get("unsold_demand", 0)):
		score += float(demand_created_delta) * 5.0
	score += float(summary.get("milestone_value", 0.0)) - float(baseline.get("milestone_value", 0.0))
	score += _route_specific_delta(plan, summary, baseline)
	score -= float(maxi(0, int(summary.get("salary_due_estimate", 0)) - int(baseline.get("salary_due_estimate", 0)))) * 12.0
	score -= float(maxi(0, int(summary.get("unsold_demand", 0)) - int(baseline.get("unsold_demand", 0)))) * 8.0
	score -= float(maxi(0, int(summary.get("lost_to_competitor", 0)) - int(baseline.get("lost_to_competitor", 0)))) * 8.0
	score -= float(maxi(0, int(summary.get("command_count", 0)) - int(baseline.get("command_count", 0)))) * 0.5
	return score

static func _route_specific_delta(plan, summary: Dictionary, baseline: Dictionary) -> float:
	var gained := _string_array(summary.get("milestones_gained", []))
	var baseline_gained := _string_array(baseline.get("milestones_gained", []))
	match str(plan.route_type):
		"price_recovery":
			return 10.0 if gained.has("first_lower_prices") and not baseline_gained.has("first_lower_prices") else 0.0
		"supply_capacity":
			return 10.0 if gained.has("first_train") and not baseline_gained.has("first_train") else 0.0
		"marketing_income":
			for milestone_id in gained:
				if baseline_gained.has(milestone_id):
					continue
				if milestone_id.ends_with("_marketed") or milestone_id == "first_billboard" or milestone_id == "first_radio" or milestone_id == "first_airplane":
					return 8.0
	return 0.0

static func _count_hard_gate_failures(out: Dictionary, hard_gate: Dictionary, delta_score: float, min_delta_score: float) -> void:
	var reasons := _string_array(hard_gate.get("reasons", []))
	if reasons.is_empty() and delta_score < min_delta_score:
		reasons.append("delta_below_threshold")
	for reason in reasons:
		out[reason] = int(out.get(reason, 0)) + 1

static func _unsold_demand_from_breakdown(breakdown: Dictionary) -> int:
	var penalty := float(breakdown.get("unsold_demand_penalty", 0.0))
	if penalty >= 0.0:
		return 0
	return maxi(0, int(round(absf(penalty) / 6.0)))

static func _count_actions(commands: Array, action_ids: Array[String]) -> int:
	var count := 0
	for item_val in commands:
		if not (item_val is Dictionary):
			continue
		var action_id := str(Dictionary(item_val).get("action_id", ""))
		if action_ids.has(action_id):
			count += 1
	return count

static func _string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := str(item).strip_edges()
			if not text.is_empty() and not out.has(text):
				out.append(text)
	return out
