class_name GreedySearch
extends RefCounted

const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const ForwardSimulatorClass = preload("res://core/ai/simulation/forward_simulator.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const EvaluatorClass = preload("res://core/ai/evaluation/evaluator.gd")
const DecisionTraceClass = preload("res://core/ai/logging/decision_trace.gd")

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
		return Result.failure("GreedySearch.choose_command: engine is null")
	if observation == null:
		return Result.failure("GreedySearch.choose_command: observation is null")
	if context == null:
		return Result.failure("GreedySearch.choose_command: context is null")
	if budget != null and budget.expired():
		return Result.failure("GreedySearch.choose_command: budget expired before search")
	var start_ms := Time.get_ticks_msec()

	var gen_read := CandidateGeneratorClass.generate(observation, context, legal_action_ids, validate_command, options)
	if not gen_read.ok:
		return gen_read
	var gen_payload: Dictionary = gen_read.value
	var candidates_val = gen_payload.get("candidates", [])
	if not (candidates_val is Array):
		return Result.failure("GreedySearch.choose_command: CandidateGenerator returned invalid candidates")
	var candidates: Array = candidates_val
	if candidates.is_empty():
		return Result.failure("GreedySearch.choose_command: no candidates generated")
	var discarded := _copy_string_array(gen_payload.get("discarded_reasons", []))

	var best_macro: MacroAction = null
	var best_score := -INF
	var best_features := {}
	var evaluated := []
	for macro_val in candidates:
		if budget != null and budget.expired():
			break
		if not (macro_val is MacroAction):
			discarded.append("candidate is not MacroAction")
			continue
		var macro: MacroAction = macro_val
		if macro.commands.is_empty():
			discarded.append("%s: empty command list" % macro.id)
			continue

		var sim_read := ForwardSimulatorClass.simulate_commands(engine, macro.commands, {"mode": "after_command"})
		if not sim_read.ok:
			discarded.append("%s: simulation failed: %s" % [macro.id, sim_read.error])
			continue
		var sim_payload: Dictionary = sim_read.value
		var sim_engine: GameEngine = sim_payload.get("engine", null)
		if sim_engine == null:
			discarded.append("%s: simulation result missing engine" % macro.id)
			continue
		var sim_observation_read := ObservationAdapterClass.observe_for_player(sim_engine, context.player_id)
		if not sim_observation_read.ok:
			discarded.append("%s: simulation observation failed: %s" % [macro.id, sim_observation_read.error])
			continue
		var score_read := EvaluatorClass.score_observation(sim_observation_read.value, context.player_id)
		if not score_read.ok:
			discarded.append("%s: evaluator failed: %s" % [macro.id, score_read.error])
			continue
		var score_payload: Dictionary = score_read.value
		var total_score := float(score_payload.get("score", 0.0)) + float(macro.prior_score)
		var features: Dictionary = Dictionary(score_payload.get("features", {})).duplicate(true)
		var first_command: Command = macro.commands[0]
		evaluated.append({
			"macro_action_id": macro.id,
			"action_id": str(first_command.action_id),
			"params": first_command.params.duplicate(true),
			"score": total_score,
			"prior_score": float(macro.prior_score),
			"features": features,
			"tags": macro.tags.duplicate(),
		})
		if best_macro == null or total_score > best_score or (is_equal_approx(total_score, best_score) and macro.id < best_macro.id):
			best_macro = macro
			best_score = total_score
			best_features = features

	if best_macro == null:
		return Result.failure("GreedySearch.choose_command: no candidate simulated successfully: %s" % "; ".join(discarded.slice(0, 8)))
	evaluated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ascore := float(a.get("score", 0.0))
		var bscore := float(b.get("score", 0.0))
		if not is_equal_approx(ascore, bscore):
			return ascore > bscore
		return str(a.get("macro_action_id", "")) < str(b.get("macro_action_id", ""))
	)
	var chosen_command: Command = best_macro.commands[0]
	var trace := _build_decision_trace(
		observation,
		context.player_id,
		chosen_command,
		best_score,
		candidates.size(),
		evaluated.size(),
		evaluated.slice(0, 5),
		discarded.slice(0, 20),
		Time.get_ticks_msec() - start_ms
	)

	return Result.success(BotDecision.create(
		chosen_command,
		best_macro.id,
		best_score,
		{
			"features": best_features,
			"candidate_count": candidates.size(),
			"valid_candidate_count": evaluated.size(),
		},
		trace.to_dict()
	))

static func _copy_string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			out.append(str(item))
	return out

static func _build_decision_trace(
	observation: ObservationState,
	player_id: int,
	chosen_command: Command,
	score: float,
	candidate_count: int,
	valid_candidate_count: int,
	top_candidates: Array,
	discarded_reasons: Array,
	time_ms: int
) -> DecisionTrace:
	var trace := DecisionTraceClass.new()
	trace.round_number = int(observation.round_number) if observation != null else 0
	trace.phase = str(observation.phase) if observation != null else ""
	trace.sub_phase = str(observation.sub_phase) if observation != null else ""
	trace.player_id = int(player_id)
	trace.observation_hash = DecisionTraceClass.compute_observation_hash(observation)
	trace.candidate_count = int(candidate_count)
	trace.valid_candidate_count = int(valid_candidate_count)
	trace.chosen_action_id = str(chosen_command.action_id) if chosen_command != null else ""
	trace.chosen_params = chosen_command.params.duplicate(true) if chosen_command != null else {}
	trace.score = float(score)
	trace.time_ms = maxi(0, int(time_ms))
	for candidate_val in top_candidates:
		if candidate_val is Dictionary:
			trace.add_top_candidate(candidate_val)
	for reason_val in discarded_reasons:
		trace.add_discarded_reason(str(reason_val))
	return trace
