class_name StrategyBot
extends "res://core/ai/bot/fcm_bot.gd"

const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const RandomLegalBotClass = preload("res://core/ai/bot/random_legal_bot.gd")
const StrategyCandidateFilterClass = preload("res://core/ai/strategy/strategy_candidate_filter.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")

var profile = null
var fallback_bot = RandomLegalBotClass.new()

func _init() -> void:
	profile = StrategyProfileClass.new()
	profile.configure_base_revenue()

func configure_profile(profile_source: String) -> Result:
	var loaded = StrategyProfileClass.new()
	var load_read := loaded.configure(profile_source)
	if not load_read.ok:
		return load_read
	profile = loaded
	return Result.success()

func choose_command(
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable = Callable(),
	budget: TimeBudget = null
) -> BotDecision:
	return _choose_command_with_options(observation, context, legal_action_ids, validate_command, budget, {})

func choose_command_with_engine(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable = Callable(),
	budget: TimeBudget = null
) -> BotDecision:
	var options := {}
	if engine != null:
		options["source_state"] = engine.get_state()
	return _choose_command_with_options(observation, context, legal_action_ids, validate_command, budget, options)

func _choose_command_with_options(
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	budget: TimeBudget,
	generator_options: Dictionary
) -> BotDecision:
	if observation == null:
		return BotDecision.failure("StrategyBot: observation is null")
	if context == null:
		return BotDecision.failure("StrategyBot: context is null")
	if budget != null and budget.expired():
		return BotDecision.failure("StrategyBot: decision budget expired")

	var options := generator_options.duplicate()
	options["max_valid_per_action"] = maxi(1, int(profile.max_valid_per_action))
	var gen_read := CandidateGeneratorClass.generate(observation, context, legal_action_ids, validate_command, options)
	if not gen_read.ok:
		return _fallback(observation, context, legal_action_ids, validate_command, budget, gen_read.error)
	var payload: Dictionary = gen_read.value
	var candidates_val = payload.get("candidates", [])
	if not (candidates_val is Array):
		return _fallback(observation, context, legal_action_ids, validate_command, budget, "CandidateGenerator returned invalid candidates")
	var candidates: Array = candidates_val
	if candidates.is_empty():
		return _fallback(observation, context, legal_action_ids, validate_command, budget, "CandidateGenerator returned no candidates")
	var generated_candidate_count := candidates.size()
	var discarded_reasons := _copy_string_array(payload.get("discarded_reasons", []))
	var filter_payload: Dictionary = StrategyCandidateFilterClass.filter_candidates(observation, candidates, profile)
	var filtered_candidates_val = filter_payload.get("candidates", [])
	if not (filtered_candidates_val is Array):
		return _fallback(observation, context, legal_action_ids, validate_command, budget, "StrategyCandidateFilter returned invalid candidates")
	candidates = filtered_candidates_val
	discarded_reasons.append_array(_copy_string_array(filter_payload.get("discarded_reasons", [])))
	var filter_stats: Dictionary = Dictionary(filter_payload.get("stats", {})).duplicate(true)
	if candidates.is_empty():
		return _fallback(observation, context, legal_action_ids, validate_command, budget, "StrategyCandidateFilter discarded all candidates: %s" % "; ".join(discarded_reasons.slice(0, 8)))

	var best_macro: MacroAction = null
	var best_score := -INF
	var best_features := {}
	var ranked: Array[Dictionary] = []
	for macro_val in candidates:
		if not (macro_val is MacroAction):
			continue
		var macro: MacroAction = macro_val
		var score_payload := StrategyScorerClass.score_macro(observation, macro, profile, {
			"source_state": generator_options.get("source_state", null),
		})
		var score := float(score_payload.get("score", -INF))
		var features: Dictionary = Dictionary(score_payload.get("features", {})).duplicate(true)
		var first_command: Command = macro.commands[0] if not macro.commands.is_empty() else null
		ranked.append({
			"macro_action_id": macro.id,
			"action_id": str(first_command.action_id) if first_command != null else "",
			"params": first_command.params.duplicate(true) if first_command != null else {},
			"score": score,
			"features": features,
			"tags": macro.tags.duplicate(),
		})
		if best_macro == null or score > best_score or (is_equal_approx(score, best_score) and macro.id < best_macro.id):
			best_macro = macro
			best_score = score
			best_features = features

	if best_macro == null or best_macro.commands.is_empty():
		return _fallback(observation, context, legal_action_ids, validate_command, budget, "StrategyBot found no scored candidate")

	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ascore := float(a.get("score", 0.0))
		var bscore := float(b.get("score", 0.0))
		if not is_equal_approx(ascore, bscore):
			return ascore > bscore
		return str(a.get("macro_action_id", "")) < str(b.get("macro_action_id", ""))
	)

	var chosen_command: Command = best_macro.commands[0]
	return BotDecision.create(
		chosen_command,
		best_macro.id,
		best_score,
		{
			"strategy_profile": profile.id,
			"features": best_features,
			"candidate_count": candidates.size(),
			"generated_candidate_count": generated_candidate_count,
			"filter_stats": filter_stats,
		},
		{
			"bot": "StrategyBot",
			"strategy_profile": profile.id,
			"phase": str(observation.phase),
			"sub_phase": str(observation.sub_phase),
			"player_id": context.player_id,
			"candidate_count": candidates.size(),
			"generated_candidate_count": generated_candidate_count,
			"filter_stats": filter_stats,
			"top_candidates": ranked.slice(0, 5),
			"discarded_reasons": discarded_reasons.slice(0, 20),
		}
	)

func _fallback(
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	budget: TimeBudget,
	reason: String
) -> BotDecision:
	var fallback := fallback_bot.choose_command(observation, context, legal_action_ids, validate_command, budget)
	if fallback != null and not fallback.is_failure():
		fallback.trace["strategy_failure"] = reason
		fallback.explanation["fallback"] = "random_legal"
		return fallback
	return BotDecision.failure("StrategyBot failed: %s" % reason)

static func _copy_string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			out.append(str(item))
	return out
