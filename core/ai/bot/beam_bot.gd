class_name BeamBot
extends "res://core/ai/bot/fcm_bot.gd"

const BeamSearchClass = preload("res://core/ai/search/beam_search.gd")
const OSLABotClass = preload("res://core/ai/bot/osla_bot.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")

var search_options: Dictionary = {
	"beam_width": 4,
	"max_depth": 3,
	"top_k_per_node": 3,
}
var fallback_bot = OSLABotClass.new()

func configure_profile(profile_source: String) -> Result:
	var loaded = StrategyProfileClass.new()
	var load_read := loaded.configure(profile_source)
	if not load_read.ok:
		return load_read
	search_options["profile"] = loaded
	var fallback_read := fallback_bot.configure_profile(profile_source)
	if not fallback_read.ok:
		return fallback_read
	return Result.success()

func choose_command(
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable = Callable(),
	budget: TimeBudget = null
) -> BotDecision:
	return fallback_bot.choose_command(observation, context, legal_action_ids, validate_command, budget)

func choose_command_with_engine(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable = Callable(),
	budget: TimeBudget = null
) -> BotDecision:
	var search_read := BeamSearchClass.choose_command(
		engine,
		observation,
		context,
		legal_action_ids,
		validate_command,
		budget,
		search_options
	)
	if search_read.ok:
		return search_read.value

	var fallback_budget = null if budget != null and budget.expired() else budget
	var fallback := fallback_bot.choose_command_with_engine(engine, observation, context, legal_action_ids, validate_command, fallback_budget)
	if fallback != null and not fallback.is_failure():
		fallback.trace["beam_failure"] = search_read.error
		fallback.explanation["fallback"] = "osla"
		return fallback
	return BotDecision.failure("BeamBot failed: %s" % search_read.error)
