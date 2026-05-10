class_name StrategicSearch
extends RefCounted

const StrategicPlanGeneratorClass = preload("res://core/ai/planning/strategic_plan_generator.gd")
const StrategicPlanRunnerClass = preload("res://core/ai/planning/strategic_plan_runner.gd")
const StrategicPlanEvaluatorClass = preload("res://core/ai/planning/strategic_plan_evaluator.gd")
const StrategicMCTSSearchClass = preload("res://core/ai/planning/strategic_mcts_search.gd")

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
