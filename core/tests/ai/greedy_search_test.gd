class_name GreedySearchTest
extends RefCounted

const GreedySearchClass = preload("res://core/ai/search/greedy_search.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const AiDecisionPointClass = preload("res://core/ai/bot/ai_decision_point.gd")
const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var reserve := _test_choose_reserve_without_mutating_source(seed_val)
	if not reserve.ok:
		return reserve
	return Result.success({"cases": 1})

static func _test_choose_reserve_without_mutating_source(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var source_hash_before := str(engine.get_state().compute_hash())
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var decision_read := GreedySearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(50),
		{"max_valid_per_action": 8}
	)
	if not decision_read.ok:
		return decision_read
	if str(engine.get_state().compute_hash()) != source_hash_before:
		return Result.failure("GreedySearch must not mutate source engine")
	var decision: BotDecision = decision_read.value
	if decision == null or decision.command == null:
		return Result.failure("GreedySearch returned empty decision")
	if decision.command.action_id != "select_reserve_card":
		return Result.failure("expected select_reserve_card, got %s" % decision.command.action_id)
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("GreedySearch returned invalid command: %s" % valid.error)
	if int(decision.explanation.get("candidate_count", 0)) <= 0:
		return Result.failure("GreedySearch explanation missing candidate_count")
	if int(decision.explanation.get("valid_candidate_count", 0)) <= 0:
		return Result.failure("GreedySearch explanation missing valid_candidate_count")
	var trace_check := _assert_decision_trace(decision)
	if not trace_check.ok:
		return trace_check
	return Result.success()

static func _build_search_inputs(engine: GameEngine, seed_val: int) -> Result:
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	var player_id := state.get_current_player_id()
	var observation_read := ObservationAdapterClass.observe_for_player(engine, player_id)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value
	var context_read := AiDecisionContext.from_observation(observation, seed_val, _allowed_internal_actions(observation))
	if not context_read.ok:
		return context_read
	var context: AiDecisionContext = context_read.value
	var ids_read := LegalActionServiceClass.get_action_ids_for_context(engine, context)
	if not ids_read.ok:
		return ids_read
	var legal_action_ids: Array[String] = ids_read.value
	var validate_fn := func(command: Command) -> Result:
		return LegalActionServiceClass.validate_command(engine, command, context)
	return Result.success({
		"observation": observation,
		"context": context,
		"legal_action_ids": legal_action_ids,
		"validate_fn": validate_fn,
	})

static func _assert_decision_trace(decision: BotDecision) -> Result:
	if decision == null:
		return Result.failure("decision is null")
	var trace := decision.trace
	if trace.is_empty():
		return Result.failure("GreedySearch decision trace is empty")
	if int(trace.get("candidate_count", 0)) != int(decision.explanation.get("candidate_count", -1)):
		return Result.failure("trace candidate_count does not match explanation")
	if int(trace.get("valid_candidate_count", 0)) != int(decision.explanation.get("valid_candidate_count", -1)):
		return Result.failure("trace valid_candidate_count does not match explanation")
	if str(trace.get("observation_hash", "")).is_empty():
		return Result.failure("trace observation_hash is empty")
	if str(trace.get("chosen_action_id", "")) != str(decision.command.action_id):
		return Result.failure("trace chosen_action_id mismatch: %s" % str(trace))
	if Dictionary(trace.get("chosen_params", {})) != decision.command.params:
		return Result.failure("trace chosen_params mismatch: %s" % str(trace))
	if not is_equal_approx(float(trace.get("score", 0.0)), float(decision.score)):
		return Result.failure("trace score mismatch: %s vs %s" % [str(trace.get("score", null)), str(decision.score)])
	var top_val = trace.get("top_candidates", [])
	if not (top_val is Array) or Array(top_val).is_empty():
		return Result.failure("trace top_candidates is empty")
	var top: Dictionary = Dictionary(Array(top_val)[0])
	if str(top.get("macro_action_id", "")) != str(decision.macro_action_id):
		return Result.failure("top candidate should explain chosen macro: %s" % str(top))
	if str(top.get("action_id", "")) != str(decision.command.action_id):
		return Result.failure("top candidate action_id mismatch: %s" % str(top))
	if not (top.get("features", null) is Dictionary):
		return Result.failure("top candidate missing features: %s" % str(top))
	if int(trace.get("time_ms", -1)) < 0:
		return Result.failure("trace time_ms is invalid: %s" % str(trace.get("time_ms", null)))
	return Result.success()

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
