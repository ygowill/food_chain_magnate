class_name StrategyBot
extends "res://core/ai/bot/fcm_bot.gd"

const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const RandomLegalBotClass = preload("res://core/ai/bot/random_legal_bot.gd")
const BoardAnalyzerClass = preload("res://core/ai/analysis/board_analyzer.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const StrategyCandidateFilterClass = preload("res://core/ai/strategy/strategy_candidate_filter.gd")
const StrategyIncomeAnalyzerClass = preload("res://core/ai/strategy/strategy_income_analyzer.gd")
const StrategyPhasePlannerClass = preload("res://core/ai/strategy/strategy_phase_planner.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")

const TRACE_TOP_CANDIDATE_LIMIT := 12
const PREVIEW_MIN_REMAINING_MS := 32

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
		options["source_engine"] = engine
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
	var start_ms := Time.get_ticks_msec()

	var options := generator_options.duplicate()
	options["budget"] = budget
	var source_state = generator_options.get("source_state", null)
	var source_analysis := _source_board_analysis(source_state) if _should_precompute_board_analysis(observation, legal_action_ids) else {}
	if not source_analysis.is_empty():
		options["source_analysis"] = source_analysis
	var phase_plan := StrategyPhasePlannerClass.plan(observation, context, profile)
	options["max_valid_per_action"] = maxi(1, int(phase_plan.get("max_valid_per_action", profile.max_valid_per_action)))
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
	var income_analysis := StrategyIncomeAnalyzerClass.analyze(observation, profile, source_state, source_analysis)
	var filter_options := {
		"source_state": source_state,
		"source_analysis": source_analysis,
		"income_analysis": income_analysis,
	}
	var filter_payload: Dictionary = StrategyCandidateFilterClass.filter_candidates(observation, candidates, profile, filter_options)
	var filtered_candidates_val = filter_payload.get("candidates", [])
	if not (filtered_candidates_val is Array):
		return _fallback(observation, context, legal_action_ids, validate_command, budget, "StrategyCandidateFilter returned invalid candidates")
	candidates = filtered_candidates_val
	discarded_reasons.append_array(_copy_string_array(filter_payload.get("discarded_reasons", [])))
	var filter_stats: Dictionary = Dictionary(filter_payload.get("stats", {})).duplicate(true)
	if candidates.is_empty():
		return _fallback(observation, context, legal_action_ids, validate_command, budget, "StrategyCandidateFilter discarded all candidates: %s" % "; ".join(discarded_reasons.slice(0, 8)))

	var source_engine = generator_options.get("source_engine", null)
	var base_score_options := {
		"source_state": source_state,
		"source_analysis": source_analysis,
		"income_analysis": income_analysis,
	}
	var base_ranked := _score_candidates(observation, candidates, profile, base_score_options, "base")
	if base_ranked.is_empty():
		return _fallback(observation, context, legal_action_ids, validate_command, budget, "StrategyBot found no scored candidate")
	var opening_filter := _filter_unsafe_opening_restaurant_entries(observation, base_ranked)
	base_ranked = Array(opening_filter.get("ranked", base_ranked))
	var opening_filter_discarded := int(opening_filter.get("discarded_count", 0))
	if opening_filter_discarded > 0:
		discarded_reasons.append_array(_copy_string_array(opening_filter.get("discarded_reasons", [])))
		filter_stats["discarded_opening_unviable_restaurant"] = opening_filter_discarded
		filter_stats["discarded_count"] = int(filter_stats.get("discarded_count", 0)) + opening_filter_discarded
		filter_stats["kept_count"] = base_ranked.size()
	base_ranked.sort_custom(_compare_scored_entries)

	var ranked := base_ranked
	var preview_rescore_count := 0
	var preview_enabled := source_engine is GameEngine
	if preview_enabled:
		var preview_score_options := base_score_options.duplicate()
		preview_score_options["source_engine"] = source_engine
		preview_score_options["budget"] = budget
		var preview_payload := _finalize_ranked_candidates(observation, base_ranked, profile, preview_score_options)
		ranked = Array(preview_payload.get("ranked", []))
		preview_rescore_count = int(preview_payload.get("preview_rescore_count", 0))
		if ranked.is_empty():
			return _fallback(observation, context, legal_action_ids, validate_command, budget, "StrategyBot preview verification produced no scored candidate")

	var best_entry: Dictionary = ranked[0]
	var best_macro_val = best_entry.get("_macro", null)
	if not (best_macro_val is MacroAction):
		return _fallback(observation, context, legal_action_ids, validate_command, budget, "StrategyBot best candidate missing macro")
	var best_macro: MacroAction = best_macro_val
	var best_score := float(best_entry.get("score", -INF))
	var best_features := Dictionary(best_entry.get("features", {})).duplicate(true)

	if best_macro.commands.is_empty():
		return _fallback(observation, context, legal_action_ids, validate_command, budget, "StrategyBot found no scored candidate")

	var trace_top_candidates := _trace_candidates(ranked, TRACE_TOP_CANDIDATE_LIMIT)

	var chosen_command: Command = best_macro.commands[0]
	var elapsed_ms := maxi(0, Time.get_ticks_msec() - start_ms)
	var budget_expired := budget != null and budget.expired()
	return BotDecision.create(
		chosen_command,
		best_macro.id,
		best_score,
		{
			"search": "strategy",
			"strategy_profile": profile.id,
			"phase_strategy": str(phase_plan.get("id", "")),
			"phase_strategy_goal": str(phase_plan.get("goal", "")),
			"phase_strategy_version": str(phase_plan.get("version", "")),
			"features": best_features,
			"candidate_count": ranked.size(),
			"generated_candidate_count": generated_candidate_count,
			"filter_stats": filter_stats,
			"preview_enabled": preview_enabled,
			"preview_rescore_count": preview_rescore_count,
			"attempted_simulations": preview_rescore_count,
			"expanded_nodes": ranked.size(),
			"budget_expired": budget_expired,
			"time_ms": elapsed_ms,
		},
		{
			"search": "strategy",
			"bot": "StrategyBot",
			"strategy_profile": profile.id,
			"phase_strategy": str(phase_plan.get("id", "")),
			"phase_strategy_goal": str(phase_plan.get("goal", "")),
			"phase_strategy_version": str(phase_plan.get("version", "")),
			"phase": str(observation.phase),
			"sub_phase": str(observation.sub_phase),
			"player_id": context.player_id,
			"candidate_count": ranked.size(),
			"generated_candidate_count": generated_candidate_count,
			"filter_stats": filter_stats,
			"preview_enabled": preview_enabled,
			"preview_rescore_count": preview_rescore_count,
			"attempted_simulations": preview_rescore_count,
			"expanded_nodes": ranked.size(),
			"budget_expired": budget_expired,
			"time_ms": elapsed_ms,
			"top_candidates": trace_top_candidates,
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

static func _score_candidates(
	observation: ObservationState,
	candidates: Array,
	profile,
	score_options: Dictionary,
	score_pass: String
) -> Array[Dictionary]:
	var ranked: Array[Dictionary] = []
	for macro_val in candidates:
		if not (macro_val is MacroAction):
			continue
		var macro: MacroAction = macro_val
		ranked.append(_score_candidate(observation, macro, profile, score_options, score_pass))
	return ranked

static func _filter_unsafe_opening_restaurant_entries(observation: ObservationState, ranked: Array[Dictionary]) -> Dictionary:
	if not _is_first_setup_restaurant_decision(observation):
		return {
			"ranked": ranked,
			"discarded_count": 0,
			"discarded_reasons": [],
		}
	var has_viable_opening := false
	var viable_opening_entries: Array[Dictionary] = []
	for entry in ranked:
		if not _is_restaurant_entry(entry):
			continue
		if _is_viable_opening_restaurant_entry(entry):
			has_viable_opening = true
			viable_opening_entries.append(entry)
	if not has_viable_opening:
		return {
			"ranked": ranked,
			"discarded_count": 0,
			"discarded_reasons": [],
		}

	var kept: Array[Dictionary] = []
	var discarded_reasons: Array[String] = []
	for entry in ranked:
		if _is_restaurant_entry(entry) and not _is_viable_opening_restaurant_entry(entry):
			var macro_id := str(entry.get("macro_action_id", ""))
			var features: Dictionary = Dictionary(entry.get("features", {}))
			var dominated := int(features.get("restaurant_competitor_dominated_houses", 0))
			var servable := int(features.get("restaurant_competitive_houses", 0)) + int(features.get("restaurant_contested_houses", 0))
			if servable <= 0:
				discarded_reasons.append("%s: opening restaurant has no serviceable opening houses" % macro_id)
			else:
				discarded_reasons.append("%s: opening restaurant dominated houses %d > servable houses %d" % [macro_id, dominated, servable])
			continue
		if _is_restaurant_entry(entry) and _is_viable_opening_restaurant_entry(entry) and _is_dominated_opening_restaurant_entry(entry, viable_opening_entries):
			var macro_id2 := str(entry.get("macro_action_id", ""))
			discarded_reasons.append("%s: opening restaurant is dominated by a broader marketing route" % macro_id2)
			continue
		kept.append(entry)
	return {
		"ranked": kept,
		"discarded_count": discarded_reasons.size(),
		"discarded_reasons": discarded_reasons,
	}

static func _is_first_setup_restaurant_decision(observation: ObservationState) -> bool:
	if observation == null:
		return false
	if str(observation.phase) != DefsClass.PHASE_SETUP:
		return false
	var restaurants_val = observation.own_player.get("restaurants", [])
	return restaurants_val is Array and Array(restaurants_val).is_empty()

static func _is_restaurant_entry(entry: Dictionary) -> bool:
	return str(entry.get("action_id", "")) == "place_restaurant"

static func _is_viable_opening_restaurant_entry(entry: Dictionary) -> bool:
	var features: Dictionary = Dictionary(entry.get("features", {}))
	var dominated := int(features.get("restaurant_competitor_dominated_houses", 0))
	var servable := int(features.get("restaurant_competitive_houses", 0)) + int(features.get("restaurant_contested_houses", 0))
	return servable > 0 and dominated <= servable

static func _is_dominated_opening_restaurant_entry(entry: Dictionary, viable_opening_entries: Array[Dictionary]) -> bool:
	if not _is_restaurant_entry(entry):
		return false
	for other_entry in viable_opening_entries:
		if _opening_route_dominates(other_entry, entry):
			return true
	return false

static func _opening_route_dominates(a_entry: Dictionary, b_entry: Dictionary) -> bool:
	var a_features: Dictionary = Dictionary(a_entry.get("features", {}))
	var b_features: Dictionary = Dictionary(b_entry.get("features", {}))
	var a_houses := int(a_features.get("restaurant_opening_marketing_route_houses", 0))
	var a_boards := int(a_features.get("restaurant_opening_marketing_route_board_count", 0))
	var a_options := int(a_features.get("restaurant_opening_marketing_route_options", 0))
	var b_houses := int(b_features.get("restaurant_opening_marketing_route_houses", 0))
	var b_boards := int(b_features.get("restaurant_opening_marketing_route_board_count", 0))
	var b_options := int(b_features.get("restaurant_opening_marketing_route_options", 0))
	var dominates := a_houses >= b_houses and a_boards >= b_boards and a_options >= b_options
	if not dominates:
		return false
	return a_houses > b_houses or a_boards > b_boards or a_options > b_options

static func _finalize_ranked_candidates(
	observation: ObservationState,
	base_ranked: Array[Dictionary],
	profile,
	score_options: Dictionary
) -> Dictionary:
	var ranked: Array[Dictionary] = []
	var preview_rescore_count := 0
	var best_score := -INF
	var verified_count := 0
	var budget_val = score_options.get("budget", null)
	var budget: TimeBudget = budget_val if budget_val is TimeBudget else null
	for i in range(base_ranked.size()):
		var base_entry: Dictionary = base_ranked[i]
		var entry := base_entry
		if _entry_needs_preview(base_entry) and _can_preview_candidate(budget, preview_rescore_count):
			var macro_val = base_entry.get("_macro", null)
			if not (macro_val is MacroAction):
				continue
			var macro: MacroAction = macro_val
			entry = _score_candidate(observation, macro, profile, score_options, "preview")
			entry["base_score"] = float(base_entry.get("score", -INF))
			preview_rescore_count += 1
		ranked.append(entry)
		verified_count = i + 1
		var score := float(entry.get("score", -INF))
		if score > best_score:
			best_score = score
		if i >= base_ranked.size() - 1:
			break
		var next_base_score := float(base_ranked[i + 1].get("score", -INF))
		if best_score >= next_base_score:
			break
	ranked.sort_custom(_compare_scored_entries)
	for i in range(verified_count, base_ranked.size()):
		var pending := base_ranked[i].duplicate(true)
		pending["score_pass"] = "base_unverified"
		ranked.append(pending)
	return {
		"ranked": ranked,
		"preview_rescore_count": preview_rescore_count,
	}

static func _score_candidate(
	observation: ObservationState,
	macro: MacroAction,
	profile,
	score_options: Dictionary,
	score_pass: String
) -> Dictionary:
	var score_payload := StrategyScorerClass.score_macro(observation, macro, profile, score_options)
	var score := float(score_payload.get("score", -INF))
	var features: Dictionary = Dictionary(score_payload.get("features", {})).duplicate(true)
	var first_command: Command = macro.commands[0] if not macro.commands.is_empty() else null
	return {
		"_macro": macro,
		"macro_action_id": macro.id,
		"action_id": str(first_command.action_id) if first_command != null else "",
		"params": first_command.params.duplicate(true) if first_command != null else {},
		"score": score,
		"features": features,
		"tags": macro.tags.duplicate(),
		"score_pass": score_pass,
}

static func _compare_scored_entries(a: Dictionary, b: Dictionary) -> bool:
	var ascore := float(a.get("score", 0.0))
	var bscore := float(b.get("score", 0.0))
	if not is_equal_approx(ascore, bscore):
		return ascore > bscore
	return str(a.get("macro_action_id", "")) < str(b.get("macro_action_id", ""))

static func _trace_candidates(ranked: Array[Dictionary], limit: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(mini(ranked.size(), maxi(0, limit))):
		out.append(_trace_candidate(ranked[i]))
	return out

static func _trace_candidate(entry: Dictionary) -> Dictionary:
	var out := {
		"macro_action_id": str(entry.get("macro_action_id", "")),
		"action_id": str(entry.get("action_id", "")),
		"params": Dictionary(entry.get("params", {})).duplicate(true),
		"score": float(entry.get("score", -INF)),
		"features": Dictionary(entry.get("features", {})).duplicate(true),
		"tags": Array(entry.get("tags", [])).duplicate(),
		"score_pass": str(entry.get("score_pass", "")),
	}
	if entry.has("base_score"):
		out["base_score"] = float(entry.get("base_score", -INF))
	return out

static func _entry_needs_preview(entry: Dictionary) -> bool:
	var action_id := str(entry.get("action_id", ""))
	var features: Dictionary = Dictionary(entry.get("features", {}))
	match action_id:
		"initiate_marketing":
			return int(features.get("affected_houses", 0)) > 0 or int(features.get("marketing_serviceable_houses", 0)) > 0
		"produce_food", "procure_drinks":
			return int(features.get("product_public_demand", 0)) > 0
		"fire":
			return int(features.get("fire_payday_shortfall", 0)) > 0 or int(features.get("fire_effective_salary_relief", 0)) > 0
		_:
			return false

static func _has_preview_budget(budget: TimeBudget) -> bool:
	if budget == null:
		return true
	return budget.remaining_ms() >= PREVIEW_MIN_REMAINING_MS

static func _can_preview_candidate(budget: TimeBudget, preview_rescore_count: int) -> bool:
	if _has_preview_budget(budget):
		return true
	if preview_rescore_count > 0:
		return false
	return budget == null or not budget.expired()

static func _source_board_analysis(source_state) -> Dictionary:
	if not (source_state is GameState):
		return {}
	var analysis_read := BoardAnalyzerClass.analyze_state(source_state)
	if not analysis_read.ok or not (analysis_read.value is Dictionary):
		return {}
	return Dictionary(analysis_read.value).duplicate(true)

static func _should_precompute_board_analysis(observation: ObservationState, legal_action_ids: Array[String]) -> bool:
	if observation != null and str(observation.phase) == DefsClass.PHASE_SETUP and legal_action_ids.has("place_restaurant"):
		return true
	if legal_action_ids.has("initiate_marketing"):
		return true
	return _observation_has_public_demand(observation)

static func _observation_has_public_demand(observation: ObservationState) -> bool:
	if observation == null:
		return false
	var houses_val = observation.map_public.get("houses", {})
	if not (houses_val is Dictionary):
		return false
	for house_val in Dictionary(houses_val).values():
		if not (house_val is Dictionary):
			continue
		var demands_val = Dictionary(house_val).get("demands", [])
		if demands_val is Array and not Array(demands_val).is_empty():
			return true
	return false
