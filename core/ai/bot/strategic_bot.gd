class_name StrategicBot
extends "res://core/ai/bot/fcm_bot.gd"

const StrategicSearchClass = preload("res://core/ai/planning/strategic_search.gd")
const StrategyPlanHintsClass = preload("res://core/ai/planning/strategic_plan_hints.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")

const FINAL_DECISION_RESERVE_MS := 32
const MIN_PLAN_SEARCH_MS := 16
const DEFAULT_MIN_PLAN_SEARCH_MS := 240
const DEFAULT_MIN_PLANS_FOR_ROLLOUT := 1
const DEFAULT_BUDGET_PROFILE := "play"
const MAX_ROUTE_HISTORY := 6
const STRATEGIC_ACTION_IDS := [
	"recruit",
	"train",
	"restructure_employee",
	"set_company_structure_direct",
	"set_company_structure_report",
	"initiate_marketing",
	"produce_food",
	"procure_drinks",
	"set_price",
	"set_discount",
	"set_luxury_price",
	"place_house",
	"add_garden",
	"place_restaurant",
	"move_restaurant",
]

var search_options: Dictionary = {
	"strategic_search": "compared",
	"strategic_budget_profile": DEFAULT_BUDGET_PROFILE,
	"strategic_horizon_decisions": 16,
	"strategic_horizon_rounds": 2,
	"strategic_max_plans": 6,
	"strategic_rollout_step_budget_ms": 40,
	"strategic_min_search_budget_ms": DEFAULT_MIN_PLAN_SEARCH_MS,
	"strategic_min_plans_for_rollout": DEFAULT_MIN_PLANS_FOR_ROLLOUT,
	"strategic_min_delta_score": 12.0,
	"strategic_config_id": "guarded_compared_v1",
}
var explicit_search_options: Dictionary = {}
var profile = null
var fallback_bot = StrategyBotClass.new()
var _cached_plan = null
var _cached_plan_key: String = ""
var _cached_search_payload: Dictionary = {}
var _recent_route_history: Array[String] = []
var _recent_route_history_player_id: int = -1
var _recent_route_history_round_number: int = -1
var _recent_route_history_decision_seed: int = -1

func _init() -> void:
	profile = StrategyProfileClass.new()
	profile.configure_base_revenue()

func configure_profile(profile_source: String) -> Result:
	var loaded = StrategyProfileClass.new()
	var load_read := loaded.configure(profile_source)
	if not load_read.ok:
		return load_read
	profile = loaded
	var fallback_read := fallback_bot.configure_profile(profile_source)
	if not fallback_read.ok:
		return fallback_read
	_clear_plan_cache()
	_clear_route_history()
	return Result.success()

func configure_search_options(options: Dictionary) -> Result:
	if options == null:
		return Result.success()
	for key in options.keys():
		explicit_search_options[str(key)] = options.get(key, null)
	_clear_plan_cache()
	return Result.success()

func choose_command(
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable = Callable(),
	budget: TimeBudget = null
) -> BotDecision:
	var fallback := fallback_bot.choose_command(observation, context, legal_action_ids, validate_command, budget)
	if fallback != null and not fallback.is_failure():
		fallback.trace["strategic_skipped"] = "no_engine"
		fallback.explanation["fallback"] = "strategy"
		fallback.explanation["strategic_skipped"] = "no_engine"
		return fallback
	return fallback

func choose_command_with_engine(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable = Callable(),
	budget: TimeBudget = null
) -> BotDecision:
	var start_ms := Time.get_ticks_msec()
	if engine == null:
		return choose_command(observation, context, legal_action_ids, validate_command, budget)
	if _should_reset_route_history(context):
		_clear_route_history()
	var options := _effective_options()
	var search_mode := str(options.get("strategic_search", "beam")).strip_edges()
	var budget_profile := str(options.get("strategic_budget_profile", DEFAULT_BUDGET_PROFILE)).strip_edges()
	var route_history := _route_history_for_search()
	if search_mode == "none":
		return _fallback_with_reason(engine, observation, context, legal_action_ids, validate_command, budget, "disabled")
	if not _has_strategic_action(legal_action_ids):
		return _fallback_with_reason(engine, observation, context, legal_action_ids, validate_command, budget, "no_strategic_legal_actions")
	if budget != null and budget.expired():
		return _fallback_with_reason(engine, observation, context, legal_action_ids, validate_command, null, "budget_expired")
	var cached_plan = null if search_mode == "compared" else _cached_plan_for_current_window(observation, context, legal_action_ids, route_history)
	if cached_plan != null:
		return _choose_with_plan(
			engine,
			observation,
			context,
			legal_action_ids,
			validate_command,
			budget,
			cached_plan,
			_cached_search_payload,
			options,
			route_history,
			search_mode,
			start_ms,
			true,
			budget_profile
		)
	if search_mode == "compared":
		return _choose_with_compared(
			engine,
			observation,
			context,
			legal_action_ids,
			validate_command,
			budget,
			options,
			route_history,
			start_ms
		)
	if search_mode == "mcts":
		return _choose_with_mcts(
			engine,
			observation,
			context,
			legal_action_ids,
			validate_command,
			budget,
			options,
			route_history,
			start_ms
		)
	var search_budget := _plan_search_budget(budget, int(options.get("strategic_min_search_budget_ms", DEFAULT_MIN_PLAN_SEARCH_MS)))
	if budget != null and search_budget == null:
		return _fallback_with_reason(engine, observation, context, legal_action_ids, validate_command, budget, "insufficient_plan_search_budget")
	var max_plans := maxi(1, int(options.get("strategic_max_plans", 6)))
	var min_plans_for_rollout := mini(max_plans, maxi(1, int(options.get("strategic_min_plans_for_rollout", DEFAULT_MIN_PLANS_FOR_ROLLOUT))))
	var search_read := StrategicSearchClass.choose_plan_beam(
		engine,
		observation,
		profile,
		search_budget,
		{
			"max_plans": max_plans,
			"min_plans_for_rollout": min_plans_for_rollout,
			"horizon_decisions": int(options.get("strategic_horizon_decisions", 16)),
			"horizon_rounds": int(options.get("strategic_horizon_rounds", 2)),
			"step_budget_ms": int(options.get("strategic_rollout_step_budget_ms", 40)),
			"route_history": route_history.duplicate(true),
		}
	)
	if not search_read.ok:
		var failure_payload: Dictionary = Dictionary(search_read.value) if search_read.value is Dictionary else {}
		return _fallback_with_reason(engine, observation, context, legal_action_ids, validate_command, _final_decision_budget(budget), search_read.error, failure_payload)
	var search_payload: Dictionary = search_read.value
	var plan_val = search_payload.get("plan", null)
	if plan_val == null or not plan_val.has_method("to_trace_dict"):
		return _fallback_with_reason(engine, observation, context, legal_action_ids, validate_command, _final_decision_budget(budget), "selected plan is null")
	var plan = plan_val
	_store_plan_cache(observation, context, plan, search_payload, legal_action_ids, route_history)
	return _choose_with_plan(
		engine,
		observation,
		context,
		legal_action_ids,
		validate_command,
		budget,
		plan,
		search_payload,
		options,
		route_history,
		search_mode,
		start_ms,
		false,
		budget_profile
	)

func _choose_with_plan(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	budget: TimeBudget,
	plan,
	search_payload: Dictionary,
	options: Dictionary,
	route_history: Array[String],
	search_mode: String,
	start_ms: int,
	used_cached_plan: bool,
	budget_profile: String
) -> BotDecision:
	var hints = StrategyPlanHintsClass.from_plan_for_decision(plan, observation, legal_action_ids)
	var final_budget := _final_decision_budget(budget)
	var decision := fallback_bot.choose_command_with_engine_and_plan_hints(
		engine,
		observation,
		context,
		legal_action_ids,
		hints,
		validate_command,
		final_budget
	)
	if decision != null and not decision.is_failure():
		var strategy_time_ms := int(decision.trace.get("time_ms", decision.explanation.get("time_ms", 0)))
		var plan_search_time_ms := 0 if used_cached_plan else int(search_payload.get("time_ms", 0))
		var elapsed_ms := maxi(strategy_time_ms + plan_search_time_ms, Time.get_ticks_msec() - start_ms)
		var plan_budget_expired := false if used_cached_plan else bool(search_payload.get("budget_expired", false))
		var final_budget_expired := final_budget != null and final_budget.expired()
		var decision_budget_expired := (budget != null and budget.expired()) or final_budget_expired
		decision.trace["search"] = "strategic_cached" if used_cached_plan else "strategic"
		decision.trace["bot"] = "StrategicBot"
		decision.trace["strategic_search"] = search_mode
		decision.trace["strategic_budget_profile"] = budget_profile
		decision.trace["strategic_config_id"] = str(options.get("strategic_config_id", ""))
		decision.trace["strategic_plan_cached"] = used_cached_plan
		decision.trace["strategic_route_history"] = Array(route_history).duplicate(true)
		decision.trace["plan_id"] = plan.id
		decision.trace["route_type"] = plan.route_type
		decision.trace["plan_prior_score"] = plan.prior_score
		decision.trace["plan_eval_score"] = float(search_payload.get("score", 0.0))
		decision.trace["plan_eval_breakdown"] = _best_breakdown(search_payload)
		decision.trace["plan_eval_telemetry"] = Dictionary(search_payload.get("telemetry", {})).duplicate(true)
		decision.trace["strategic_baseline"] = Dictionary(search_payload.get("baseline", {})).duplicate(true)
		decision.trace["strategic_comparison"] = Dictionary(search_payload.get("comparison", {})).duplicate(true)
		decision.trace["strategic_hard_gate"] = Dictionary(search_payload.get("hard_gate", {})).duplicate(true)
		decision.trace["strategic_min_delta_score"] = float(search_payload.get("min_delta_score", 0.0))
		decision.trace["plan_rollout_stop_reason"] = _best_stop_reason(search_payload)
		decision.trace["plan_search_time_ms"] = plan_search_time_ms
		decision.trace["strategy_time_ms"] = strategy_time_ms
		decision.trace["time_ms"] = elapsed_ms
		decision.trace["plan_search_budget_expired"] = plan_budget_expired
		decision.trace["final_decision_budget_expired"] = final_budget_expired
		decision.trace["budget_expired"] = decision_budget_expired
		decision.trace["evaluated_plans"] = Array(search_payload.get("evaluated_plans", [])).duplicate(true)
		decision.trace["mcts_iterations"] = int(search_payload.get("mcts_iterations", 0))
		decision.trace["mcts_root_visits"] = int(search_payload.get("mcts_root_visits", 0))
		decision.trace["mcts_root_q"] = float(search_payload.get("mcts_root_q", 0.0))
		decision.trace["mcts_selected_q"] = float(search_payload.get("mcts_selected_q", 0.0))
		decision.trace["mcts_selected_value_score"] = float(search_payload.get("mcts_selected_value_score", search_payload.get("score", 0.0)))
		decision.trace["mcts_root_child_count"] = int(search_payload.get("mcts_root_child_count", 0))
		decision.trace["mcts_root_raw_child_count"] = int(search_payload.get("mcts_root_raw_child_count", decision.trace.get("mcts_root_child_count", 0)))
		decision.trace["mcts_root_selection_mode"] = str(search_payload.get("mcts_root_selection_mode", ""))
		decision.trace["mcts_selected_path"] = Array(search_payload.get("mcts_selected_path", [])).duplicate(true)
		decision.trace["mcts_selected_leaf_depth"] = int(search_payload.get("mcts_selected_leaf_depth", 0))
		decision.trace["mcts_selected_leaf_value_score"] = float(search_payload.get("mcts_selected_leaf_value_score", search_payload.get("score", 0.0)))
		decision.trace["mcts_selected_state_key"] = str(search_payload.get("mcts_selected_state_key", ""))
		decision.trace["mcts_selected_route_types"] = Array(search_payload.get("mcts_selected_route_types", [])).duplicate()
		decision.trace["mcts_route_switch_count"] = int(search_payload.get("mcts_route_switch_count", 0))
		decision.trace["mcts_plan_state_deduped_nodes"] = int(search_payload.get("mcts_plan_state_deduped_nodes", 0))
		decision.trace["mcts_plan_transposition_pruned_nodes"] = int(search_payload.get("mcts_plan_transposition_pruned_nodes", 0))
		decision.trace["mcts_non_root_populated_nodes"] = int(search_payload.get("mcts_non_root_populated_nodes", 0))
		decision.trace["mcts_non_root_expanded_nodes"] = int(search_payload.get("mcts_non_root_expanded_nodes", 0))
		decision.trace["mcts_non_root_candidate_count"] = int(search_payload.get("mcts_non_root_candidate_count", 0))
		decision.explanation["search"] = "strategic_cached" if used_cached_plan else "strategic"
		decision.explanation["strategic_budget_profile"] = budget_profile
		decision.explanation["strategic_route_history"] = Array(route_history).duplicate(true)
		decision.explanation["plan_id"] = plan.id
		decision.explanation["route_type"] = plan.route_type
		decision.explanation["plan_eval_score"] = float(search_payload.get("score", 0.0))
		decision.explanation["plan_eval_telemetry"] = Dictionary(search_payload.get("telemetry", {})).duplicate(true)
		decision.explanation["strategic_baseline"] = Dictionary(search_payload.get("baseline", {})).duplicate(true)
		decision.explanation["strategic_comparison"] = Dictionary(search_payload.get("comparison", {})).duplicate(true)
		decision.explanation["strategic_hard_gate"] = Dictionary(search_payload.get("hard_gate", {})).duplicate(true)
		decision.explanation["strategic_min_delta_score"] = float(search_payload.get("min_delta_score", 0.0))
		decision.explanation["strategic_plan_cached"] = used_cached_plan
		decision.explanation["plan_search_time_ms"] = plan_search_time_ms
		decision.explanation["strategy_time_ms"] = strategy_time_ms
		decision.explanation["time_ms"] = elapsed_ms
		decision.explanation["plan_search_budget_expired"] = plan_budget_expired
		decision.explanation["final_decision_budget_expired"] = final_budget_expired
		decision.explanation["budget_expired"] = decision_budget_expired
		decision.explanation["evaluated_plans"] = Array(search_payload.get("evaluated_plans", [])).duplicate(true)
		decision.explanation["mcts_iterations"] = int(search_payload.get("mcts_iterations", 0))
		decision.explanation["mcts_root_visits"] = int(search_payload.get("mcts_root_visits", 0))
		decision.explanation["mcts_root_q"] = float(search_payload.get("mcts_root_q", 0.0))
		decision.explanation["mcts_selected_q"] = float(search_payload.get("mcts_selected_q", 0.0))
		decision.explanation["mcts_selected_value_score"] = float(search_payload.get("mcts_selected_value_score", search_payload.get("score", 0.0)))
		decision.explanation["mcts_root_child_count"] = int(search_payload.get("mcts_root_child_count", 0))
		decision.explanation["mcts_root_raw_child_count"] = int(search_payload.get("mcts_root_raw_child_count", decision.explanation.get("mcts_root_child_count", 0)))
		decision.explanation["mcts_root_selection_mode"] = str(search_payload.get("mcts_root_selection_mode", ""))
		decision.explanation["mcts_selected_path"] = Array(search_payload.get("mcts_selected_path", [])).duplicate(true)
		decision.explanation["mcts_selected_leaf_depth"] = int(search_payload.get("mcts_selected_leaf_depth", 0))
		decision.explanation["mcts_selected_leaf_value_score"] = float(search_payload.get("mcts_selected_leaf_value_score", search_payload.get("score", 0.0)))
		decision.explanation["mcts_selected_state_key"] = str(search_payload.get("mcts_selected_state_key", ""))
		decision.explanation["mcts_selected_route_types"] = Array(search_payload.get("mcts_selected_route_types", [])).duplicate()
		decision.explanation["mcts_route_switch_count"] = int(search_payload.get("mcts_route_switch_count", 0))
		decision.explanation["mcts_plan_state_deduped_nodes"] = int(search_payload.get("mcts_plan_state_deduped_nodes", 0))
		decision.explanation["mcts_plan_transposition_pruned_nodes"] = int(search_payload.get("mcts_plan_transposition_pruned_nodes", 0))
		decision.explanation["mcts_non_root_populated_nodes"] = int(search_payload.get("mcts_non_root_populated_nodes", 0))
		decision.explanation["mcts_non_root_expanded_nodes"] = int(search_payload.get("mcts_non_root_expanded_nodes", 0))
		decision.explanation["mcts_non_root_candidate_count"] = int(search_payload.get("mcts_non_root_candidate_count", 0))
		_record_route_type(str(plan.route_type), context)
		return decision
	return _fallback_with_reason(engine, observation, context, legal_action_ids, validate_command, _final_decision_budget(budget), "hinted strategy failed")

func _choose_with_compared(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	budget: TimeBudget,
	options: Dictionary,
	route_history: Array[String],
	start_ms: int
) -> BotDecision:
	var precomputed_fallback := fallback_bot.choose_command_with_engine(engine, observation, context, legal_action_ids, validate_command, budget)
	var search_budget := _plan_search_budget(budget, int(options.get("strategic_min_search_budget_ms", DEFAULT_MIN_PLAN_SEARCH_MS)))
	if budget != null and search_budget == null:
		return _fallback_from_precomputed_or_reason(precomputed_fallback, engine, observation, context, legal_action_ids, validate_command, budget, "insufficient_plan_search_budget")
	var compared_options := options.duplicate(true)
	compared_options["route_history"] = route_history.duplicate(true)
	var search_read := StrategicSearchClass.choose_plan_compared(
		engine,
		observation,
		profile,
		search_budget,
		compared_options
	)
	if not search_read.ok:
		var failure_payload: Dictionary = Dictionary(search_read.value) if search_read.value is Dictionary else {}
		return _fallback_from_precomputed_or_reason(precomputed_fallback, engine, observation, context, legal_action_ids, validate_command, _final_decision_budget(budget), search_read.error, failure_payload)
	var search_payload: Dictionary = search_read.value
	var budget_profile := str(options.get("strategic_budget_profile", DEFAULT_BUDGET_PROFILE)).strip_edges()
	var plan_val = search_payload.get("plan", null)
	if plan_val == null or not plan_val.has_method("to_trace_dict"):
		return _fallback_with_reason(engine, observation, context, legal_action_ids, validate_command, _final_decision_budget(budget), "selected compared plan is null")
	var plan = plan_val
	return _choose_with_plan(
		engine,
		observation,
		context,
		legal_action_ids,
		validate_command,
		budget,
		plan,
		search_payload,
		compared_options,
		route_history,
		"compared",
		start_ms,
		false,
		budget_profile
	)

func _fallback_from_precomputed_or_reason(
	precomputed_fallback: BotDecision,
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	budget: TimeBudget,
	reason: String,
	failure_payload: Dictionary = {}
) -> BotDecision:
	var annotated := _annotate_precomputed_fallback(precomputed_fallback, reason, failure_payload)
	if annotated != null and not annotated.is_failure():
		return annotated
	return _fallback_with_reason(engine, observation, context, legal_action_ids, validate_command, budget, reason, failure_payload)

func _annotate_precomputed_fallback(
	fallback: BotDecision,
	reason: String,
	failure_payload: Dictionary = {}
) -> BotDecision:
	if fallback == null or fallback.is_failure():
		return fallback
	fallback.trace["strategic_failure"] = reason
	fallback.trace["strategic_fallback_source"] = "precomputed_strategy"
	fallback.explanation["fallback"] = "strategy"
	fallback.explanation["strategic_failure"] = reason
	fallback.explanation["strategic_fallback_source"] = "precomputed_strategy"
	if not failure_payload.is_empty():
		fallback.trace["strategic_failure_payload"] = failure_payload.duplicate(true)
		fallback.explanation["strategic_failure_payload"] = failure_payload.duplicate(true)
	return fallback

func _choose_with_mcts(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	budget: TimeBudget,
	options: Dictionary,
	route_history: Array[String],
	start_ms: int
) -> BotDecision:
	var search_budget := _plan_search_budget(budget, int(options.get("strategic_min_search_budget_ms", DEFAULT_MIN_PLAN_SEARCH_MS)))
	if budget != null and search_budget == null:
		return _fallback_with_reason(engine, observation, context, legal_action_ids, validate_command, budget, "insufficient_plan_search_budget")
	var mcts_options := options.duplicate(true)
	mcts_options["route_history"] = route_history.duplicate(true)
	var search_read := StrategicSearchClass.choose_plan_mcts(
		engine,
		observation,
		profile,
		search_budget,
		mcts_options
	)
	if not search_read.ok:
		return _fallback_with_reason(engine, observation, context, legal_action_ids, validate_command, _final_decision_budget(budget), search_read.error)
	var search_payload: Dictionary = search_read.value
	var budget_profile := str(options.get("strategic_budget_profile", DEFAULT_BUDGET_PROFILE)).strip_edges()
	var plan_val = search_payload.get("plan", null)
	if plan_val == null or not plan_val.has_method("to_trace_dict"):
		return _fallback_with_reason(engine, observation, context, legal_action_ids, validate_command, _final_decision_budget(budget), "selected plan is null")
	var plan = plan_val
	_store_plan_cache(observation, context, plan, search_payload, legal_action_ids, route_history)
	return _choose_with_plan(
		engine,
		observation,
		context,
		legal_action_ids,
		validate_command,
		budget,
		plan,
		search_payload,
		mcts_options,
		route_history,
		"mcts",
		start_ms,
		false,
		budget_profile
	)

func _fallback_with_reason(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	budget: TimeBudget,
	reason: String,
	failure_payload: Dictionary = {}
) -> BotDecision:
	var fallback := fallback_bot.choose_command_with_engine(engine, observation, context, legal_action_ids, validate_command, budget)
	if fallback != null and not fallback.is_failure():
		fallback.trace["strategic_failure"] = reason
		fallback.explanation["fallback"] = "strategy"
		fallback.explanation["strategic_failure"] = reason
		if not failure_payload.is_empty():
			fallback.trace["strategic_failure_payload"] = failure_payload.duplicate(true)
			fallback.explanation["strategic_failure_payload"] = failure_payload.duplicate(true)
		return fallback
	return fallback

func _effective_options() -> Dictionary:
	var out := search_options.duplicate(true)
	var budget_profile := _strategic_budget_profile_name(str(explicit_search_options.get("strategic_budget_profile", out.get("strategic_budget_profile", DEFAULT_BUDGET_PROFILE))))
	var profile_options := _strategic_budget_profile_options(budget_profile)
	for key in profile_options.keys():
		out[str(key)] = profile_options.get(key, null)
	for key in explicit_search_options.keys():
		out[str(key)] = explicit_search_options.get(key, null)
	out["strategic_budget_profile"] = budget_profile
	_apply_plan_search_aliases(out)
	return out

static func _apply_plan_search_aliases(options: Dictionary) -> void:
	if options.has("strategic_horizon_decisions"):
		options["horizon_decisions"] = int(options.get("strategic_horizon_decisions", options.get("horizon_decisions", 16)))
	if options.has("strategic_horizon_rounds"):
		options["horizon_rounds"] = int(options.get("strategic_horizon_rounds", options.get("horizon_rounds", 2)))
	if options.has("strategic_max_plans"):
		options["max_plans"] = int(options.get("strategic_max_plans", options.get("max_plans", 6)))
	if options.has("strategic_rollout_step_budget_ms"):
		options["step_budget_ms"] = int(options.get("strategic_rollout_step_budget_ms", options.get("step_budget_ms", 40)))
	if options.has("strategic_min_plans_for_rollout"):
		options["min_plans_for_rollout"] = int(options.get("strategic_min_plans_for_rollout", options.get("min_plans_for_rollout", 1)))

static func _strategic_budget_profile_name(raw_profile: String) -> String:
	var profile := raw_profile.strip_edges()
	if profile == "play":
		return "play"
	if profile == "tuning":
		return "tuning"
	return DEFAULT_BUDGET_PROFILE

static func _strategic_budget_profile_options(profile_name: String) -> Dictionary:
	match _strategic_budget_profile_name(profile_name):
		"play":
			return {
				"strategic_horizon_decisions": 16,
				"strategic_horizon_rounds": 2,
				"strategic_max_plans": 6,
				"strategic_rollout_step_budget_ms": 48,
				"strategic_min_search_budget_ms": 640,
				"strategic_min_plans_for_rollout": 1,
				"mcts_iterations": 12,
				"mcts_max_depth": 2,
				"mcts_top_k_per_node": 4,
				"mcts_exploration": 1.05,
				"mcts_prior_weight": 0.3,
				"mcts_root_prior_min_visits_per_child": 1,
				"step_budget_ms": 48,
				"horizon_decisions": 16,
				"horizon_rounds": 2,
				"max_plans": 6,
			}
		"tuning":
			return {
				"strategic_horizon_decisions": 12,
				"strategic_horizon_rounds": 2,
				"strategic_max_plans": 4,
				"strategic_rollout_step_budget_ms": 24,
				"strategic_min_search_budget_ms": 160,
				"strategic_min_plans_for_rollout": 1,
				"mcts_iterations": 8,
				"mcts_max_depth": 2,
				"mcts_top_k_per_node": 3,
				"mcts_exploration": 1.05,
				"mcts_prior_weight": 0.3,
				"mcts_root_prior_min_visits_per_child": 1,
				"step_budget_ms": 24,
				"horizon_decisions": 12,
				"horizon_rounds": 2,
				"max_plans": 4,
			}
		_:
			return {
				"strategic_horizon_decisions": 16,
				"strategic_horizon_rounds": 2,
				"strategic_max_plans": 6,
				"strategic_rollout_step_budget_ms": 48,
				"strategic_min_search_budget_ms": 640,
				"strategic_min_plans_for_rollout": 1,
				"mcts_iterations": 12,
				"mcts_max_depth": 2,
				"mcts_top_k_per_node": 4,
				"mcts_exploration": 1.05,
				"mcts_prior_weight": 0.3,
				"mcts_root_prior_min_visits_per_child": 1,
				"step_budget_ms": 48,
				"horizon_decisions": 16,
				"horizon_rounds": 2,
				"max_plans": 6,
			}

func _clear_route_history() -> void:
	_recent_route_history.clear()
	_recent_route_history_player_id = -1
	_recent_route_history_round_number = -1
	_recent_route_history_decision_seed = -1

func _should_reset_route_history(context: AiDecisionContext) -> bool:
	if _recent_route_history.is_empty():
		return false
	if context == null:
		return true
	var player_id := int(context.player_id)
	if _recent_route_history_player_id >= 0 and player_id != _recent_route_history_player_id:
		return true
	var decision_seed := int(context.decision_seed)
	if _recent_route_history_decision_seed >= 0 and decision_seed < _recent_route_history_decision_seed:
		return true
	var round_number := int(context.round_number)
	if _recent_route_history_round_number >= 0 and round_number < _recent_route_history_round_number:
		return true
	return false

func _route_history_for_search() -> Array[String]:
	var out: Array[String] = []
	var start := maxi(0, _recent_route_history.size() - MAX_ROUTE_HISTORY)
	for i in range(start, _recent_route_history.size()):
		var route_type := str(_recent_route_history[i]).strip_edges()
		if not route_type.is_empty():
			out.append(route_type)
	return out

func _record_route_type(route_type: String, context: AiDecisionContext = null) -> void:
	var normalized := str(route_type).strip_edges()
	if normalized.is_empty():
		return
	if context != null and _should_reset_route_history(context):
		_clear_route_history()
	if context != null:
		_recent_route_history_player_id = int(context.player_id)
		_recent_route_history_round_number = int(context.round_number)
		_recent_route_history_decision_seed = int(context.decision_seed)
	_recent_route_history.append(normalized)
	while _recent_route_history.size() > MAX_ROUTE_HISTORY:
		_recent_route_history.remove_at(0)

func _cached_plan_for_current_window(observation: ObservationState, context: AiDecisionContext, legal_action_ids: Array[String], route_history = null):
	if _cached_plan == null:
		return null
	if observation == null or context == null:
		return null
	var key := _plan_cache_key(observation, context, legal_action_ids, route_history)
	if key.is_empty() or key != _cached_plan_key:
		return null
	return _cached_plan

func _store_plan_cache(observation: ObservationState, context: AiDecisionContext, plan, search_payload: Dictionary, legal_action_ids: Array[String], route_history = null) -> void:
	if plan == null or not plan.has_method("is_valid") or observation == null or context == null:
		_clear_plan_cache()
		return
	var key := _plan_cache_key(observation, context, legal_action_ids, route_history)
	if key.is_empty():
		_clear_plan_cache()
		return
	_cached_plan_key = key
	_cached_plan = plan.duplicate_plan() if plan.has_method("duplicate_plan") else plan
	_cached_search_payload = search_payload.duplicate(true)

func _clear_plan_cache() -> void:
	_cached_plan = null
	_cached_plan_key = ""
	_cached_search_payload = {}

func _plan_cache_key(observation: ObservationState, context: AiDecisionContext, legal_action_ids: Array[String], route_history = null) -> String:
	if observation == null or context == null:
		return ""
	var history := _route_history_for_cache_key(route_history)
	return "%d:%d:%s:%s:%s:%s" % [
		int(context.player_id),
		int(observation.round_number),
		str(observation.phase).strip_edges(),
		str(observation.sub_phase).strip_edges(),
		_strategic_legal_action_signature(legal_action_ids),
		_route_history_signature(history),
	]

func _route_history_for_cache_key(route_history) -> Array[String]:
	if route_history == null:
		return _route_history_for_search()
	return _route_history_array(route_history)

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
	if out.size() <= MAX_ROUTE_HISTORY:
		return out
	return out.slice(out.size() - MAX_ROUTE_HISTORY, out.size())

static func _route_history_signature(route_history: Array[String]) -> String:
	if route_history.is_empty():
		return ""
	var normalized: Array[String] = []
	for route_val in route_history:
		var route := str(route_val).strip_edges()
		if not route.is_empty():
			normalized.append(route)
	return "|".join(normalized)

static func _plan_search_budget(budget: TimeBudget, min_search_ms: int = MIN_PLAN_SEARCH_MS) -> TimeBudget:
	if budget == null:
		return null
	var remaining := int(budget.remaining_ms())
	var search_ms := remaining - FINAL_DECISION_RESERVE_MS
	var required_ms := maxi(MIN_PLAN_SEARCH_MS, int(min_search_ms))
	if search_ms < required_ms:
		return null
	return TimeBudget.start(search_ms)

static func _final_decision_budget(budget: TimeBudget) -> TimeBudget:
	if budget == null:
		return null
	var remaining := int(budget.remaining_ms())
	return TimeBudget.start(maxi(FINAL_DECISION_RESERVE_MS, remaining))

static func _has_strategic_action(legal_action_ids: Array[String]) -> bool:
	for action_id in STRATEGIC_ACTION_IDS:
		if legal_action_ids.has(action_id):
			return true
	return false

static func _strategic_legal_action_signature(legal_action_ids: Array[String]) -> String:
	var ids: Array[String] = []
	for action_id_val in legal_action_ids:
		var action_id := str(action_id_val).strip_edges()
		if action_id.is_empty() or not STRATEGIC_ACTION_IDS.has(action_id) or ids.has(action_id):
			continue
		ids.append(action_id)
	ids.sort()
	return ",".join(ids)

static func _best_breakdown(search_payload: Dictionary) -> Dictionary:
	var evaluated: Array = Array(search_payload.get("evaluated_plans", []))
	if evaluated.is_empty() or not (evaluated[0] is Dictionary):
		return {}
	return Dictionary(Dictionary(evaluated[0]).get("breakdown", {})).duplicate(true)

static func _best_stop_reason(search_payload: Dictionary) -> String:
	var evaluated: Array = Array(search_payload.get("evaluated_plans", []))
	if evaluated.is_empty() or not (evaluated[0] is Dictionary):
		return ""
	return str(Dictionary(evaluated[0]).get("stop_reason", ""))
