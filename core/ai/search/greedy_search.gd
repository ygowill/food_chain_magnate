class_name GreedySearch
extends RefCounted

const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const ForwardSimulatorClass = preload("res://core/ai/simulation/forward_simulator.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const EvaluatorClass = preload("res://core/ai/evaluation/evaluator.gd")
const DecisionTraceClass = preload("res://core/ai/logging/decision_trace.gd")
const MarketingRangeCalculatorClass = preload("res://core/rules/marketing_range_calculator.gd")
const PaydayPreviewClass = preload("res://core/ai/analysis/payday_preview.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

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

	var generator_options := options.duplicate()
	generator_options["source_state"] = engine.get_state()
	var gen_read := CandidateGeneratorClass.generate(observation, context, legal_action_ids, validate_command, generator_options)
	if not gen_read.ok:
		return gen_read
	var gen_payload: Dictionary = gen_read.value
	var candidates_val = gen_payload.get("candidates", [])
	if not (candidates_val is Array):
		return Result.failure("GreedySearch.choose_command: CandidateGenerator returned invalid candidates")
	var candidates: Array = candidates_val
	if candidates.is_empty():
		return Result.failure("GreedySearch.choose_command: no candidates generated")
	_sort_candidates_for_search(candidates)
	var discarded := _copy_string_array(gen_payload.get("discarded_reasons", []))

	var best_macro: MacroAction = null
	var best_score := -INF
	var best_features := {}
	var evaluated := []
	var attempted_simulations := 0
	for macro_val in candidates:
		if budget != null and budget.expired() and attempted_simulations > 0:
			break
		if not (macro_val is MacroAction):
			discarded.append("candidate is not MacroAction")
			continue
		var macro: MacroAction = macro_val
		if macro.commands.is_empty():
			discarded.append("%s: empty command list" % macro.id)
			continue

		attempted_simulations += 1
		var sim_read := _simulate_macro_for_scoring(engine, observation, macro)
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
		var context_bonus := _macro_context_bonus(sim_engine, context.player_id, macro)
		var total_score := float(score_payload.get("score", 0.0)) + float(macro.prior_score) + context_bonus
		var features: Dictionary = Dictionary(score_payload.get("features", {})).duplicate(true)
		if not is_zero_approx(context_bonus):
			features["context_bonus"] = context_bonus
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

static func _sort_candidates_for_search(candidates: Array) -> void:
	candidates.sort_custom(func(a, b) -> bool:
		if not (a is MacroAction):
			return false
		if not (b is MacroAction):
			return true
		var ma: MacroAction = a
		var mb: MacroAction = b
		if not is_equal_approx(float(ma.prior_score), float(mb.prior_score)):
			return float(ma.prior_score) > float(mb.prior_score)
		return str(ma.id) < str(mb.id)
	)

static func _copy_string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in Array(value):
			out.append(str(item))
	return out

static func _simulate_macro_for_scoring(engine: GameEngine, observation: ObservationState, macro: MacroAction) -> Result:
	if observation != null and str(observation.phase) == DefsClass.PHASE_PAYDAY:
		var preview_read := PaydayPreviewClass.preview_after_commands(engine, macro.commands, {"max_steps": 16})
		if not preview_read.ok:
			return preview_read
		var preview_payload: Dictionary = preview_read.value
		var preview_engine: GameEngine = preview_payload.get("engine", null)
		if preview_engine == null:
			return Result.failure("Payday preview result missing engine")
		return Result.success({
			"engine": preview_engine,
			"state": preview_engine.get_state(),
			"commands_executed": preview_payload.get("commands_executed", []),
			"warnings": preview_payload.get("warnings", []),
			"failed_command_index": -1,
			"error": "",
		})
	return ForwardSimulatorClass.simulate_commands(engine, macro.commands, {"mode": "after_command"})

static func _macro_context_bonus(sim_engine: GameEngine, player_id: int, macro: MacroAction) -> float:
	if sim_engine == null or macro == null or macro.commands.is_empty():
		return 0.0
	var command: Command = macro.commands[0]
	if command == null:
		return 0.0
	match str(command.action_id):
		"initiate_marketing":
			return _marketing_context_bonus(sim_engine.get_state(), player_id, command)
		_:
			return 0.0

static func _marketing_context_bonus(state: GameState, player_id: int, command: Command) -> float:
	if state == null or command == null:
		return 0.0
	var board_number := int(command.params.get("board_number", -1))
	if board_number <= 0:
		return 0.0
	var instance := _find_marketing_instance(state, player_id, board_number)
	if instance.is_empty():
		return 0.0
	var calculator = MarketingRangeCalculatorClass.new()
	var affected_read: Result = calculator.get_affected_house_ids(state, instance)
	if not affected_read.ok:
		return 0.0
	var affected: Array = affected_read.value
	if affected.is_empty():
		return -12.0
	var bonus := float(affected.size()) * 4.0
	for house_id_val in affected:
		var distance := _min_house_distance_to_owned_restaurant(state, str(house_id_val), player_id)
		if distance >= 0:
			bonus += maxf(0.0, 10.0 - float(distance) * 0.5)
	return bonus

static func _find_marketing_instance(state: GameState, player_id: int, board_number: int) -> Dictionary:
	if state == null:
		return {}
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		if int(inst.get("owner", -1)) != player_id:
			continue
		if int(inst.get("board_number", -1)) != board_number:
			continue
		return inst
	return {}

static func _min_house_distance_to_owned_restaurant(state: GameState, house_id: String, player_id: int) -> int:
	if state == null or house_id.is_empty():
		return -1
	var houses_val = state.map.get("houses", {})
	if not (houses_val is Dictionary):
		return -1
	var houses: Dictionary = houses_val
	var house_val = houses.get(house_id, null)
	if not (house_val is Dictionary):
		return -1
	var house_anchor := _read_vector2i(Dictionary(house_val).get("anchor_pos", Vector2i.ZERO))
	var restaurants_val = state.map.get("restaurants", {})
	if not (restaurants_val is Dictionary):
		return -1
	var restaurants: Dictionary = restaurants_val
	var best := 2147483647
	for rest_val in restaurants.values():
		if not (rest_val is Dictionary):
			continue
		var rest: Dictionary = rest_val
		if int(rest.get("owner", -1)) != player_id:
			continue
		var rest_anchor := _read_vector2i(rest.get("anchor_pos", Vector2i.ZERO))
		var distance := absi(house_anchor.x - rest_anchor.x) + absi(house_anchor.y - rest_anchor.y)
		best = mini(best, distance)
	return best if best < 2147483647 else -1

static func _read_vector2i(value) -> Vector2i:
	if value is Vector2i:
		return Vector2i(value)
	if value is Vector2:
		var v2: Vector2 = value
		return Vector2i(int(v2.x), int(v2.y))
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO

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
