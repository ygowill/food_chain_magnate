class_name GreedyBot
extends "res://core/ai/bot/fcm_bot.gd"

const GreedySearchClass = preload("res://core/ai/search/greedy_search.gd")
const RandomLegalBotClass = preload("res://core/ai/bot/random_legal_bot.gd")

var search_options: Dictionary = {
	"max_valid_per_action": 12,
}
var fallback_bot = RandomLegalBotClass.new()

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
	var search_read := GreedySearchClass.choose_command(
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

	var fallback := fallback_bot.choose_command(observation, context, legal_action_ids, validate_command, budget)
	if fallback != null and not fallback.is_failure():
		fallback.trace["greedy_failure"] = search_read.error
		fallback.explanation["fallback"] = "random_legal"
		return fallback
	return BotDecision.failure("GreedyBot failed: %s" % search_read.error)
