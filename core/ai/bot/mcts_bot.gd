class_name MCTSBot
extends "res://core/ai/bot/fcm_bot.gd"

const MCTSSearchClass = preload("res://core/ai/search/mcts_search.gd")
const BeamBotClass = preload("res://core/ai/bot/beam_bot.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const StrategyPhasePlannerClass = preload("res://core/ai/strategy/strategy_phase_planner.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")

const DEFAULT_ENABLED_STRATEGY_IDS := [
	"working_place_houses_growth",
	"working_place_restaurants_growth",
]

var search_options: Dictionary = {
	"mcts_iterations": 24,
	"mcts_max_depth": 3,
	"mcts_top_k_per_node": 4,
	"mcts_exploration": 1.25,
	"mcts_min_simulation_budget_ms": 24,
	"mcts_enabled_strategy_ids": DEFAULT_ENABLED_STRATEGY_IDS,
}
var explicit_search_options: Dictionary = {}
var fallback_bot = BeamBotClass.new()
var phase_fallback_bot = StrategyBotClass.new()

func configure_profile(profile_source: String) -> Result:
	var loaded = StrategyProfileClass.new()
	var load_read := loaded.configure(profile_source)
	if not load_read.ok:
		return load_read
	search_options["profile"] = loaded
	var phase_fallback_read := phase_fallback_bot.configure_profile(profile_source)
	if not phase_fallback_read.ok:
		return phase_fallback_read
	var fallback_read := fallback_bot.configure_profile(profile_source)
	if not fallback_read.ok:
		return fallback_read
	return Result.success()

func configure_search_options(options: Dictionary) -> Result:
	if options == null:
		return Result.success()
	for key in options.keys():
		explicit_search_options[str(key)] = options.get(key, null)
	return Result.success()

func choose_command(
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable = Callable(),
	budget: TimeBudget = null
) -> BotDecision:
	var fallback := phase_fallback_bot.choose_command(observation, context, legal_action_ids, validate_command, budget)
	if fallback != null and not fallback.is_failure():
		fallback.trace["mcts_skipped"] = "no_engine"
		fallback.explanation["fallback"] = "strategy"
		fallback.explanation["mcts_skipped"] = "no_engine"
		return fallback
	return fallback_bot.choose_command(observation, context, legal_action_ids, validate_command, budget)

func choose_command_with_engine(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable = Callable(),
	budget: TimeBudget = null
) -> BotDecision:
	var phase_plan := StrategyPhasePlannerClass.plan(
		observation,
		context,
		search_options.get("profile", null)
	)
	var strategy_id := str(phase_plan.get("id", ""))
	if not _mcts_enabled_for_strategy(strategy_id):
		return _choose_phase_fallback(
			engine,
			observation,
			context,
			legal_action_ids,
			validate_command,
			budget,
			strategy_id
		)
	if not _has_constructive_mcts_action(strategy_id, legal_action_ids):
		return _choose_phase_fallback(
			engine,
			observation,
			context,
			legal_action_ids,
			validate_command,
			budget,
			strategy_id,
			"no_constructive_legal_actions"
		)

	var phase_search_options := StrategyPhasePlannerClass.build_search_options(
		observation,
		context,
		search_options.get("profile", null),
		search_options
	)
	_apply_explicit_search_options(phase_search_options)
	phase_search_options["mcts_phase_strategy"] = strategy_id
	var search_read := MCTSSearchClass.choose_command(
		engine,
		observation,
		context,
		legal_action_ids,
		validate_command,
		budget,
		phase_search_options
	)
	if search_read.ok:
		return search_read.value

	var fallback: BotDecision = null
	if budget != null and budget.expired():
		fallback = fallback_bot.choose_command(observation, context, legal_action_ids, validate_command, null)
	else:
		fallback = fallback_bot.choose_command_with_engine(engine, observation, context, legal_action_ids, validate_command, budget)
	if fallback != null and not fallback.is_failure():
		fallback.trace["mcts_failure"] = search_read.error
		if budget != null and budget.expired():
			fallback.trace["fallback_after_budget_expired"] = true
		fallback.explanation["fallback"] = "beam"
		return fallback
	return BotDecision.failure("MCTSBot failed: %s" % search_read.error)

func _choose_phase_fallback(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	budget: TimeBudget,
	strategy_id: String,
	reason: String = "strategy_disabled"
) -> BotDecision:
	var fallback := phase_fallback_bot.choose_command_with_engine(
		engine,
		observation,
		context,
		legal_action_ids,
		validate_command,
		budget
	)
	if fallback != null and not fallback.is_failure():
		fallback.trace["mcts_skipped"] = reason
		fallback.trace["mcts_phase_strategy"] = strategy_id
		fallback.explanation["fallback"] = "strategy"
		fallback.explanation["mcts_skipped"] = reason
		fallback.explanation["mcts_phase_strategy"] = strategy_id
		return fallback
	return fallback

func _has_constructive_mcts_action(strategy_id: String, legal_action_ids: Array[String]) -> bool:
	var constructive_ids := _constructive_action_ids_for_strategy(strategy_id)
	if constructive_ids.is_empty():
		return true
	for action_id in constructive_ids:
		if legal_action_ids.has(action_id):
			return true
	return false

func _constructive_action_ids_for_strategy(strategy_id: String) -> Array[String]:
	match strategy_id:
		"working_place_houses_growth":
			return ["place_house", "add_garden"]
		"working_place_restaurants_growth":
			return ["place_restaurant", "move_restaurant"]
		_:
			return []

func _mcts_enabled_for_strategy(strategy_id: String) -> bool:
	var enabled_ids := _string_list(_option_value("mcts_enabled_strategy_ids", DEFAULT_ENABLED_STRATEGY_IDS))
	if enabled_ids.has("*") or enabled_ids.has("all"):
		return true
	if strategy_id.strip_edges().is_empty():
		return false
	return enabled_ids.has(strategy_id)

func _option_value(key: String, default_value):
	if explicit_search_options.has(key):
		return explicit_search_options.get(key)
	return search_options.get(key, default_value)

func _apply_explicit_search_options(options: Dictionary) -> void:
	for key in explicit_search_options.keys():
		options[str(key)] = explicit_search_options.get(key, null)

func _string_list(value) -> Array[String]:
	var out: Array[String] = []
	if value is String:
		var text := str(value).strip_edges()
		if text.is_empty():
			return out
		for part in text.split(",", false):
			var item := str(part).strip_edges()
			if not item.is_empty():
				out.append(item)
		return out
	if value is Array:
		for item_val in Array(value):
			var item := str(item_val).strip_edges()
			if not item.is_empty():
				out.append(item)
	return out
