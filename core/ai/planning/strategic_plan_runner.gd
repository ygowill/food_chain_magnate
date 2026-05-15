class_name StrategicPlanRunner
extends RefCounted

const AiEngineForkClass = preload("res://core/ai/simulation/ai_engine_fork.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const AiDecisionPointClass = preload("res://core/ai/bot/ai_decision_point.gd")
const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")
const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyPlanHintsClass = preload("res://core/ai/planning/strategic_plan_hints.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func rollout(
	source_engine: GameEngine,
	plan,
	profile = null,
	options: Dictionary = {}
) -> Result:
	if source_engine == null:
		return Result.failure("StrategicPlanRunner.rollout: source_engine is null")
	if plan == null or not plan.has_method("is_valid"):
		return Result.failure("StrategicPlanRunner.rollout: plan is null")
	var fork_start_ms := Time.get_ticks_msec()
	var fork_read := AiEngineForkClass.fork_from_engine(source_engine)
	if not fork_read.ok:
		source_engine.activate_registry_bundles()
		return fork_read
	var engine: GameEngine = fork_read.value
	var fork_ms := Time.get_ticks_msec() - fork_start_ms
	var state := engine.get_state()
	if state == null:
		source_engine.activate_registry_bundles()
		return Result.failure("StrategicPlanRunner.rollout: fork state is null")
	var start_round := int(state.round_number)
	var cash_before := _player_cash(state, plan.owner_player_id)
	var min_after_positive := cash_before if cash_before > 0 else 2147483647
	var max_cash_seen := cash_before
	var horizon_decisions := maxi(1, int(options.get("horizon_decisions", plan.horizon_decisions)))
	var horizon_rounds := maxi(1, int(options.get("horizon_rounds", plan.horizon_rounds)))
	var budget_val = options.get("budget", null)
	var budget: TimeBudget = budget_val if budget_val is TimeBudget else null
	var root_bot: StrategyBot = StrategyBotClass.new()
	var opponent_bot: StrategyBot = StrategyBotClass.new()
	if profile != null:
		root_bot.profile = profile
		opponent_bot.profile = profile
	var commands_executed: Array[Dictionary] = []
	var rollout_metrics := {
		"milestones_gained": [],
		"demand_created": 0,
		"demand_sold": 0,
		"lost_to_competitor": 0,
		"salary_due_estimate": 0,
	}
	var stop_reason := "decision_limit"
	var start_ms := Time.get_ticks_msec()
	var step_budget_ms := maxi(1, int(options.get("step_budget_ms", 40)))
	for decision_index in range(horizon_decisions):
		state = engine.get_state()
		if state == null:
			stop_reason = "state_missing"
			break
		if str(state.phase) == DefsClass.PHASE_GAME_OVER:
			stop_reason = "game_over"
			break
		if int(state.round_number) - start_round >= horizon_rounds:
			stop_reason = "round_horizon"
			break
		if decision_index > 0 and _is_payday_or_cleanup_boundary(state):
			stop_reason = "phase_boundary"
			break
		if budget != null and budget.expired():
			stop_reason = "budget_expired"
			break
		var actor := BotControllerClass.resolve_next_player_id(engine)
		if actor < 0:
			stop_reason = "no_next_player"
			break
		var observation_read := ObservationAdapterClass.observe_for_player(engine, actor)
		if not observation_read.ok:
			stop_reason = "observation_failed"
			break
		var observation: ObservationState = observation_read.value
		var context_read := AiDecisionContext.from_observation(observation, _make_decision_seed(engine, actor), _allowed_internal_actions(observation))
		if not context_read.ok:
			stop_reason = "context_failed"
			break
		var context: AiDecisionContext = context_read.value
		var ids_read := LegalActionServiceClass.get_action_ids_for_context(engine, context)
		if not ids_read.ok:
			stop_reason = "legal_actions_failed"
			break
		var legal_ids: Array[String] = ids_read.value
		var validate_fn := func(command: Command) -> Result:
			return LegalActionServiceClass.validate_command(engine, command, context)
		var step_budget := _step_budget(budget, step_budget_ms)
		if budget != null and step_budget == null:
			stop_reason = "budget_expired"
			break
		var decision: BotDecision = null
		if actor == plan.owner_player_id:
			var hints = StrategyPlanHintsClass.from_plan_for_decision(plan, observation, legal_ids)
			decision = root_bot.choose_command_with_engine_and_plan_hints(engine, observation, context, legal_ids, hints, validate_fn, step_budget)
		else:
			decision = opponent_bot.choose_command_with_engine(engine, observation, context, legal_ids, validate_fn, step_budget)
		if decision == null or decision.is_failure() or decision.command == null:
			stop_reason = "bot_failed"
			break
		var old_phase := str(state.phase)
		var old_milestones := _player_milestones_snapshot(state, plan.owner_player_id)
		var old_marketing_processed = _marketing_processed_snapshot(state) if old_phase == DefsClass.PHASE_MARKETING else []
		var exec_read := engine.execute_command(decision.command)
		if not exec_read.ok:
			stop_reason = "execute_failed"
			break
		state = engine.get_state()
		_collect_step_metrics(old_phase, old_milestones, old_marketing_processed, state, plan.owner_player_id, rollout_metrics)
		var cash_after := _player_cash(state, plan.owner_player_id)
		if cash_after > 0:
			min_after_positive = mini(min_after_positive, cash_after)
		max_cash_seen = maxi(max_cash_seen, cash_after)
		commands_executed.append({
			"actor": actor,
			"action_id": str(decision.command.action_id),
			"params": decision.command.params.duplicate(true),
			"macro_action_id": decision.macro_action_id,
			"score": decision.score,
			"round": int(state.round_number) if state != null else -1,
			"phase": str(state.phase) if state != null else "",
			"sub_phase": str(state.sub_phase) if state != null else "",
		})
	if min_after_positive == 2147483647:
		min_after_positive = 0
	var final_metrics := _final_rollout_metrics(engine, plan.owner_player_id, profile)
	rollout_metrics["lost_to_competitor"] = int(final_metrics.get("lost_to_competitor", rollout_metrics.get("lost_to_competitor", 0)))
	rollout_metrics["salary_due_estimate"] = int(final_metrics.get("salary_due_estimate", rollout_metrics.get("salary_due_estimate", 0)))
	source_engine.activate_registry_bundles()
	return Result.success({
		"engine": engine,
		"commands_executed": commands_executed,
		"round_delta": int(engine.get_state().round_number) - start_round if engine.get_state() != null else 0,
		"phase_stop_reason": stop_reason,
		"cash_before": cash_before,
		"cash_after": _player_cash(engine.get_state(), plan.owner_player_id),
		"cash_max_seen": max_cash_seen,
		"cash_min_after_first_positive": min_after_positive,
		"milestones_gained": Array(rollout_metrics.get("milestones_gained", [])).duplicate(true),
		"demand_created": int(rollout_metrics.get("demand_created", 0)),
		"demand_sold": int(rollout_metrics.get("demand_sold", 0)),
		"lost_to_competitor": int(rollout_metrics.get("lost_to_competitor", 0)),
		"salary_due_estimate": int(rollout_metrics.get("salary_due_estimate", 0)),
		"route_history": _route_history_array(options.get("route_history", [])),
		"search_time_ms": Time.get_ticks_msec() - start_ms,
		"fork_ms": fork_ms,
	})

static func _collect_step_metrics(old_phase: String, old_milestones: Array[String], old_marketing_processed: Array, new_state: GameState, owner_player_id: int, metrics: Dictionary) -> void:
	if metrics == null or new_state == null:
		return
	_append_unique_strings(metrics, "milestones_gained", _player_milestones_gained(old_milestones, new_state, owner_player_id))
	if old_phase == DefsClass.PHASE_MARKETING and str(new_state.phase) != DefsClass.PHASE_MARKETING:
		metrics["demand_created"] = int(metrics.get("demand_created", 0)) + _marketing_demand_created(old_marketing_processed)
	if str(new_state.phase) == DefsClass.PHASE_DINNERTIME and old_phase != DefsClass.PHASE_DINNERTIME:
		metrics["demand_sold"] = int(metrics.get("demand_sold", 0)) + _dinnertime_demand_sold(new_state)

static func _final_rollout_metrics(engine: GameEngine, owner_player_id: int, profile) -> Dictionary:
	var out := {
		"lost_to_competitor": 0,
		"salary_due_estimate": 0,
	}
	if engine == null or owner_player_id < 0:
		return out
	var obs_read := ObservationAdapterClass.observe_for_player(engine, owner_player_id)
	if not obs_read.ok:
		return out
	var observation: ObservationState = obs_read.value
	var income := StrategyIncomeAnalyzerClass.analyze(observation, profile, engine.get_state())
	out["lost_to_competitor"] = int(income.get("total_lost_to_competitor_demand", 0))
	out["salary_due_estimate"] = _salary_due_estimate(engine.get_state(), owner_player_id)
	return out

static func _player_milestones_snapshot(state: GameState, player_id: int) -> Array[String]:
	var out: Array[String] = []
	if state == null:
		return out
	if not (state.players is Array):
		return out
	if player_id < 0 or player_id >= state.players.size():
		return out
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return out
	var ms_val = Dictionary(player_val).get("milestones", [])
	if not (ms_val is Array):
		return out
	for mid_val in Array(ms_val):
		var mid := str(mid_val).strip_edges()
		if not mid.is_empty():
			out.append(mid)
	out.sort()
	return out

static func _player_milestones_gained(old_milestones: Array[String], new_state: GameState, player_id: int) -> Array[String]:
	var out: Array[String] = []
	if new_state == null:
		return out
	var new_milestones := _player_milestones_snapshot(new_state, player_id)
	var old_set := {}
	for mid in old_milestones:
		var text := str(mid).strip_edges()
		if not text.is_empty():
			old_set[text] = true
	for mid2 in new_milestones:
		if mid2.is_empty() or old_set.has(mid2):
			continue
		out.append(mid2)
	out.sort()
	return out

static func _append_unique_strings(target: Dictionary, key: String, values: Array[String]) -> void:
	if target == null:
		return
	var merged: Array[String] = []
	var existing_val = target.get(key, [])
	if existing_val is Array:
		for item in Array(existing_val):
			var text := str(item).strip_edges()
			if not text.is_empty() and not merged.has(text):
				merged.append(text)
	for value in values:
		var text2 := str(value).strip_edges()
		if not text2.is_empty() and not merged.has(text2):
			merged.append(text2)
	merged.sort()
	target[key] = merged

static func _marketing_demand_created(processed: Array) -> int:
	if processed.is_empty():
		return 0
	var total := 0
	for p_val in processed:
		total += maxi(0, int(Dictionary(p_val).get("demands_added", 0)))
	return total

static func _dinnertime_demand_sold(dinnertime_state: GameState) -> int:
	if dinnertime_state == null or not (dinnertime_state.round_state is Dictionary):
		return 0
	var dinnertime_val = Dictionary(dinnertime_state.round_state).get("dinnertime", null)
	if not (dinnertime_val is Dictionary):
		return 0
	var sales_val = Dictionary(dinnertime_val).get("sales", null)
	if not (sales_val is Array):
		return 0
	var total := 0
	for sale_val in Array(sales_val):
		if not (sale_val is Dictionary):
			continue
		total += maxi(0, int(Dictionary(sale_val).get("quantity", 0)))
	return total

static func _route_history_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			var text := ""
			if item is Dictionary:
				text = str(Dictionary(item).get("route_type", ""))
			else:
				text = str(item)
			text = text.strip_edges()
			if not text.is_empty():
				out.append(text)
	return out

static func _marketing_processed_snapshot(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or not (state.round_state is Dictionary):
		return out
	var marketing_val = Dictionary(state.round_state).get("marketing", null)
	if not (marketing_val is Dictionary):
		return out
	var processed_val = Dictionary(marketing_val).get("processed", null)
	if not (processed_val is Array):
		return out
	for p_val in Array(processed_val):
		if p_val is Dictionary:
			out.append(Dictionary(p_val).duplicate(true))
	return out

static func _salary_due_estimate(state: GameState, player_id: int) -> int:
	if state == null or not (state.players is Array):
		return 0
	if player_id < 0 or player_id >= state.players.size():
		return 0
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return 0
	var player: Dictionary = player_val
	var salary_cost := state.get_rule_int("salary_cost")
	var override_val = player.get("salary_cost_override", null)
	if override_val is int and int(override_val) >= 0:
		salary_cost = int(override_val)
	var due := 0
	for key in ["employees", "reserve_employees", "busy_marketers"]:
		var employees_val = player.get(key, null)
		if not (employees_val is Array):
			continue
		for employee_id_val in Array(employees_val):
			var employee_id := str(employee_id_val).strip_edges()
			if employee_id.is_empty() or employee_id == "ceo":
				continue
			if EmployeeRulesClass.requires_salary(employee_id, player):
				due += salary_cost
	return maxi(0, due)

static func _step_budget(parent_budget: TimeBudget, default_step_ms: int) -> TimeBudget:
	if parent_budget == null:
		return null
	var remaining := int(parent_budget.remaining_ms())
	if remaining <= 0:
		return null
	return TimeBudget.start(mini(maxi(1, default_step_ms), remaining))

static func _is_payday_or_cleanup_boundary(state: GameState) -> bool:
	if state == null:
		return false
	return str(state.phase) == DefsClass.PHASE_PAYDAY or str(state.phase) == DefsClass.PHASE_CLEANUP

static func _player_cash(state: GameState, player_id: int) -> int:
	if state == null or player_id < 0 or player_id >= state.players.size():
		return 0
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return 0
	return int(Dictionary(player_val).get("cash", 0))

static func _allowed_internal_actions(observation: ObservationState) -> Array[String]:
	var decision_point := AiDecisionPointClass.from_observation(observation)
	match decision_point:
		AiDecisionPointClass.RESERVE_CARD:
			return ["select_reserve_card"]
		AiDecisionPointClass.RESTRUCTURING:
			return [
				"restructure_employee",
				"set_company_structure_direct",
				"set_company_structure_report",
				"submit_restructuring",
			]
		AiDecisionPointClass.CLEANUP_PENDING:
			return ["choose_fridge_keep"]
		_:
			return []

static func _make_decision_seed(engine: GameEngine, player_id: int) -> int:
	if engine == null:
		return player_id
	var state := engine.get_state()
	if state == null:
		return player_id
	return int(state.round_number) * 100000 + int(engine.command_history.size()) * 100 + player_id
