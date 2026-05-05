class_name OSLASearch
extends RefCounted

const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const StrategyCandidateFilterClass = preload("res://core/ai/strategy/strategy_candidate_filter.gd")
const StrategyProfileClass = preload("res://core/ai/strategy/strategy_profile.gd")
const StrategyScorerClass = preload("res://core/ai/strategy/strategy_scorer.gd")
const ForwardSimulatorClass = preload("res://core/ai/simulation/forward_simulator.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const EvaluatorClass = preload("res://core/ai/evaluation/evaluator.gd")
const AiDecisionPointClass = preload("res://core/ai/bot/ai_decision_point.gd")
const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const DEFAULT_MAX_CANDIDATES := 6
const DEFAULT_OPPONENT_MAX_CANDIDATES := 3
const DEFAULT_EVALUATOR_WEIGHT := 0.35

static func choose_command(
	engine: GameEngine,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_command: Callable,
	budget: TimeBudget = null,
	options: Dictionary = {}
) -> Result:
	if engine == null:
		return Result.failure("OSLASearch.choose_command: engine is null")
	if observation == null:
		return Result.failure("OSLASearch.choose_command: observation is null")
	if context == null:
		return Result.failure("OSLASearch.choose_command: context is null")
	if budget != null and budget.expired():
		return Result.failure("OSLASearch.choose_command: budget expired before search")

	var start_ms := Time.get_ticks_msec()
	var profile = options.get("profile", null)
	if profile == null:
		profile = StrategyProfileClass.new()
		profile.configure_base_revenue()

	var gen_options := options.duplicate()
	gen_options["source_state"] = engine.get_state()
	gen_options["max_valid_per_action"] = maxi(1, int(profile.max_valid_per_action))
	var gen_read := CandidateGeneratorClass.generate(observation, context, legal_action_ids, validate_command, gen_options)
	if not gen_read.ok:
		return gen_read
	var gen_payload: Dictionary = Dictionary(gen_read.value)
	var candidates_val = gen_payload.get("candidates", [])
	if not (candidates_val is Array):
		return Result.failure("OSLASearch.choose_command: CandidateGenerator returned invalid candidates")
	var candidates: Array = candidates_val
	if candidates.is_empty():
		return Result.failure("OSLASearch.choose_command: no candidates generated")

	var discarded := _copy_string_array(gen_payload.get("discarded_reasons", []))
	var filter_payload: Dictionary = StrategyCandidateFilterClass.filter_candidates(observation, candidates, profile)
	var filtered_val = filter_payload.get("candidates", [])
	if not (filtered_val is Array):
		return Result.failure("OSLASearch.choose_command: StrategyCandidateFilter returned invalid candidates")
	candidates = filtered_val
	discarded.append_array(_copy_string_array(filter_payload.get("discarded_reasons", [])))
	var filter_stats: Dictionary = Dictionary(filter_payload.get("stats", {})).duplicate(true)
	if candidates.is_empty():
		return Result.failure("OSLASearch.choose_command: StrategyCandidateFilter discarded all candidates: %s" % "; ".join(discarded.slice(0, 8)))

	var scored_candidates := _score_candidates(observation, candidates, profile, engine.get_state(), discarded)
	if scored_candidates.is_empty():
		return Result.failure("OSLASearch.choose_command: no candidates scored: %s" % "; ".join(discarded.slice(0, 8)))
	_sort_scored_candidates(scored_candidates)

	var max_candidates := maxi(1, int(options.get("max_candidates", DEFAULT_MAX_CANDIDATES)))
	var evaluator_weight := float(options.get("evaluator_weight", DEFAULT_EVALUATOR_WEIGHT))
	var best_macro: MacroAction = null
	var best_score := -INF
	var best_features := {}
	var evaluated: Array[Dictionary] = []
	var attempted := 0
	var limit := mini(max_candidates, scored_candidates.size())
	for i in range(limit):
		if budget != null and budget.expired() and attempted > 0:
			break
		var entry: Dictionary = scored_candidates[i]
		var macro: MacroAction = entry.get("macro", null)
		if macro == null or macro.commands.is_empty():
			continue

		attempted += 1
		var sim_read := ForwardSimulatorClass.simulate_commands(engine, macro.commands, {"mode": "after_command"})
		if not sim_read.ok:
			discarded.append("%s: simulation failed: %s" % [macro.id, sim_read.error])
			continue
		var sim_payload: Dictionary = Dictionary(sim_read.value)
		var eval_engine: GameEngine = sim_payload.get("engine", null)
		if eval_engine == null:
			discarded.append("%s: simulation result missing engine" % macro.id)
			continue

		var response_payload := _simulate_opponent_response(eval_engine, context.player_id, profile, budget, options)
		if response_payload.ok:
			var response_data: Dictionary = Dictionary(response_payload.value)
			var response_engine: GameEngine = response_data.get("engine", null)
			if response_engine != null:
				eval_engine = response_engine
			entry["opponent_response"] = response_data
		else:
			discarded.append("%s: opponent response skipped after error: %s" % [macro.id, response_payload.error])
			entry["opponent_response"] = {
				"response_skipped_reason": response_payload.error,
			}

		var obs_read := ObservationAdapterClass.observe_for_player(eval_engine, context.player_id)
		if not obs_read.ok:
			discarded.append("%s: final observation failed: %s" % [macro.id, obs_read.error])
			continue
		var eval_read := EvaluatorClass.score_observation(obs_read.value, context.player_id)
		if not eval_read.ok:
			discarded.append("%s: evaluator failed: %s" % [macro.id, eval_read.error])
			continue

		var eval_payload: Dictionary = Dictionary(eval_read.value)
		var strategy_score := float(entry.get("strategy_score", 0.0))
		var eval_score := float(eval_payload.get("score", 0.0))
		var total_score := strategy_score + eval_score * evaluator_weight
		var features: Dictionary = Dictionary(entry.get("strategy_features", {})).duplicate(true)
		features["osla_strategy_score"] = strategy_score
		features["osla_eval_score"] = eval_score
		features["osla_evaluator_weight"] = evaluator_weight
		features["osla_final_features"] = Dictionary(eval_payload.get("features", {})).duplicate(true)
		var response: Dictionary = Dictionary(entry.get("opponent_response", {}))
		features["osla_opponent_response_macro_id"] = str(response.get("response_macro_id", ""))
		features["osla_opponent_response_action_id"] = str(response.get("response_action_id", ""))
		features["osla_opponent_response_score"] = float(response.get("response_score", 0.0))
		features["osla_opponent_response_skipped_reason"] = str(response.get("response_skipped_reason", ""))

		var first_command: Command = macro.commands[0]
		evaluated.append({
			"macro_action_id": macro.id,
			"action_id": str(first_command.action_id),
			"params": first_command.params.duplicate(true),
			"score": total_score,
			"strategy_score": strategy_score,
			"eval_score": eval_score,
			"features": features,
			"tags": macro.tags.duplicate(),
		})
		if best_macro == null or total_score > best_score or (is_equal_approx(total_score, best_score) and macro.id < best_macro.id):
			best_macro = macro
			best_score = total_score
			best_features = features

	if best_macro == null:
		return Result.failure("OSLASearch.choose_command: no candidate simulated successfully: %s" % "; ".join(discarded.slice(0, 8)))
	_sort_evaluated(evaluated)

	var chosen_command: Command = best_macro.commands[0]
	return Result.success(BotDecision.create(
		chosen_command,
		best_macro.id,
		best_score,
		{
			"features": best_features,
			"candidate_count": candidates.size(),
			"valid_candidate_count": evaluated.size(),
			"attempted_simulations": attempted,
			"filter_stats": filter_stats,
		},
		{
			"bot": "OSLASearch",
			"search": "osla",
			"strategy_profile": str(profile.id),
			"phase": str(observation.phase),
			"sub_phase": str(observation.sub_phase),
			"player_id": context.player_id,
			"candidate_count": candidates.size(),
			"valid_candidate_count": evaluated.size(),
			"attempted_simulations": attempted,
			"filter_stats": filter_stats,
			"top_candidates": evaluated.slice(0, 5),
			"discarded_reasons": discarded.slice(0, 20),
			"time_ms": Time.get_ticks_msec() - start_ms,
		}
	))

static func _score_candidates(
	observation: ObservationState,
	candidates: Array,
	profile,
	source_state: GameState,
	discarded: Array[String]
) -> Array[Dictionary]:
	var scored: Array[Dictionary] = []
	for macro_val in candidates:
		if not (macro_val is MacroAction):
			discarded.append("candidate is not MacroAction")
			continue
		var macro: MacroAction = macro_val
		if macro.commands.is_empty():
			discarded.append("%s: empty command list" % macro.id)
			continue
		var score_payload := StrategyScorerClass.score_macro(observation, macro, profile, {"source_state": source_state})
		var strategy_score := float(score_payload.get("score", -INF))
		var first_command: Command = macro.commands[0]
		scored.append({
			"macro": macro,
			"macro_action_id": macro.id,
			"action_id": str(first_command.action_id),
			"strategy_score": strategy_score,
			"strategy_features": Dictionary(score_payload.get("features", {})).duplicate(true),
			"tags": macro.tags.duplicate(),
		})
	return scored

static func _simulate_opponent_response(
	engine: GameEngine,
	root_player_id: int,
	profile,
	budget: TimeBudget,
	options: Dictionary
) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	if budget != null and budget.expired():
		return Result.success(_opponent_response_payload(engine, "budget expired", null, 0.0, 0))
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")
	if str(state.phase) == DefsClass.PHASE_GAME_OVER:
		return Result.success(_opponent_response_payload(engine, "game over", null, 0.0, 0))
	var response_player_id := BotControllerClass.resolve_next_player_id(engine)
	if response_player_id < 0:
		return Result.success(_opponent_response_payload(engine, "no next player", null, 0.0, 0))
	if response_player_id == root_player_id:
		return Result.success(_opponent_response_payload(engine, "next decision is root player", null, 0.0, 0))

	var observation_read := ObservationAdapterClass.observe_for_player(engine, response_player_id)
	if not observation_read.ok:
		return Result.failure(observation_read.error)
	var response_observation: ObservationState = observation_read.value
	var context_read := AiDecisionContext.from_observation(
		response_observation,
		_make_decision_seed(engine, response_player_id),
		_allowed_internal_actions(response_observation)
	)
	if not context_read.ok:
		return context_read
	var response_context: AiDecisionContext = context_read.value
	var ids_read := LegalActionServiceClass.get_action_ids_for_context(engine, response_context)
	if not ids_read.ok:
		return ids_read
	var legal_ids: Array[String] = ids_read.value
	if legal_ids.is_empty():
		return Result.success(_opponent_response_payload(engine, "no legal actions", null, 0.0, 0))
	var validate_fn := func(command: Command) -> Result:
		return LegalActionServiceClass.validate_command(engine, command, response_context)
	var gen_options := options.duplicate()
	gen_options["source_state"] = engine.get_state()
	gen_options["max_valid_per_action"] = maxi(1, int(options.get("opponent_max_valid_per_action", DEFAULT_OPPONENT_MAX_CANDIDATES)))
	var gen_read := CandidateGeneratorClass.generate(response_observation, response_context, legal_ids, validate_fn, gen_options)
	if not gen_read.ok:
		return Result.success(_opponent_response_payload(engine, "candidate generation failed: %s" % gen_read.error, null, 0.0, 0))
	var gen_payload: Dictionary = Dictionary(gen_read.value)
	var candidates_val = gen_payload.get("candidates", [])
	if not (candidates_val is Array):
		return Result.success(_opponent_response_payload(engine, "candidate generation returned invalid candidates", null, 0.0, 0))
	var candidates: Array = candidates_val
	if candidates.is_empty():
		return Result.success(_opponent_response_payload(engine, "no response candidates", null, 0.0, 0))
	var filter_payload: Dictionary = StrategyCandidateFilterClass.filter_candidates(response_observation, candidates, profile)
	var filtered_val = filter_payload.get("candidates", [])
	if not (filtered_val is Array):
		return Result.success(_opponent_response_payload(engine, "filter returned invalid candidates", null, 0.0, 0))
	candidates = filtered_val
	if candidates.is_empty():
		return Result.success(_opponent_response_payload(engine, "filter discarded all candidates", null, 0.0, 0))

	var discarded: Array[String] = []
	var scored := _score_candidates(response_observation, candidates, profile, engine.get_state(), discarded)
	if scored.is_empty():
		return Result.success(_opponent_response_payload(engine, "no scored response candidates", null, 0.0, 0))
	_sort_scored_candidates(scored)
	var max_candidates := maxi(1, int(options.get("opponent_max_candidates", DEFAULT_OPPONENT_MAX_CANDIDATES)))
	var limit := mini(max_candidates, scored.size())
	var best_macro: MacroAction = null
	var best_score := -INF
	for i in range(limit):
		var entry: Dictionary = scored[i]
		var macro: MacroAction = entry.get("macro", null)
		if macro == null or macro.commands.is_empty():
			continue
		var score := float(entry.get("strategy_score", -INF))
		if best_macro == null or score > best_score or (is_equal_approx(score, best_score) and macro.id < best_macro.id):
			best_macro = macro
			best_score = score
	if best_macro == null:
		return Result.success(_opponent_response_payload(engine, "no response macro selected", null, 0.0, limit))

	var sim_read := ForwardSimulatorClass.simulate_commands(engine, best_macro.commands, {"mode": "after_command"})
	if not sim_read.ok:
		return Result.success(_opponent_response_payload(engine, "response simulation failed: %s" % sim_read.error, null, 0.0, limit))
	var sim_payload: Dictionary = Dictionary(sim_read.value)
	var response_engine: GameEngine = sim_payload.get("engine", null)
	if response_engine == null:
		return Result.success(_opponent_response_payload(engine, "response simulation missing engine", null, 0.0, limit))
	return Result.success(_opponent_response_payload(response_engine, "", best_macro, best_score, limit))

static func _opponent_response_payload(
	engine: GameEngine,
	skipped_reason: String,
	macro: MacroAction,
	score: float,
	evaluated_count: int
) -> Dictionary:
	var first_command: Command = macro.commands[0] if macro != null and not macro.commands.is_empty() else null
	return {
		"engine": engine,
		"response_macro_id": str(macro.id) if macro != null else "",
		"response_action_id": str(first_command.action_id) if first_command != null else "",
		"response_params": first_command.params.duplicate(true) if first_command != null else {},
		"response_score": float(score),
		"response_evaluated_count": int(evaluated_count),
		"response_skipped_reason": str(skipped_reason),
	}

static func _sort_scored_candidates(scored: Array[Dictionary]) -> void:
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ascore := float(a.get("strategy_score", 0.0))
		var bscore := float(b.get("strategy_score", 0.0))
		if not is_equal_approx(ascore, bscore):
			return ascore > bscore
		return str(a.get("macro_action_id", "")) < str(b.get("macro_action_id", ""))
	)

static func _sort_evaluated(evaluated: Array[Dictionary]) -> void:
	evaluated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ascore := float(a.get("score", 0.0))
		var bscore := float(b.get("score", 0.0))
		if not is_equal_approx(ascore, bscore):
			return ascore > bscore
		return str(a.get("macro_action_id", "")) < str(b.get("macro_action_id", ""))
	)

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

static func _copy_string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			out.append(str(item))
	return out
