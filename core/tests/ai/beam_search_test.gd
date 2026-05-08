class_name BeamSearchTest
extends RefCounted

const BeamSearchClass = preload("res://core/ai/search/beam_search.gd")
const BeamBotClass = preload("res://core/ai/bot/beam_bot.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const AiDecisionPointClass = preload("res://core/ai/bot/ai_decision_point.gd")
const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var direct := _test_choose_command_without_mutating_source(seed_val)
	if not direct.ok:
		return direct
	var deterministic := _test_beam_search_is_deterministic(seed_val)
	if not deterministic.ok:
		return deterministic
	var depth_two := _test_beam_search_selects_depth_two_same_actor_recruit_path(seed_val)
	if not depth_two.ok:
		return depth_two
	var wrapper := _test_beam_bot_without_engine_uses_fallback(seed_val)
	if not wrapper.ok:
		return wrapper
	return Result.success({"cases": 4})

static func _test_choose_command_without_mutating_source(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var source_hash_before := str(engine.get_state().compute_hash())
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var decision_read := BeamSearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(260),
		{
			"beam_width": 2,
			"max_depth": 2,
			"top_k_per_node": 2,
		}
	)
	if not decision_read.ok:
		return decision_read
	if str(engine.get_state().compute_hash()) != source_hash_before:
		return Result.failure("BeamSearch must not mutate source engine")
	var decision: BotDecision = decision_read.value
	if decision == null or decision.command == null:
		return Result.failure("BeamSearch returned empty decision")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("BeamSearch returned invalid command: %s" % valid.error)
	if str(decision.trace.get("bot", "")) != "BeamSearch":
		return Result.failure("BeamSearch trace should identify search: %s" % str(decision.trace))
	if int(decision.explanation.get("valid_candidate_count", 0)) <= 0:
		return Result.failure("BeamSearch explanation missing valid_candidate_count: %s" % str(decision.explanation))
	var features: Dictionary = Dictionary(decision.explanation.get("features", {}))
	if not features.has("beam_eval_score"):
		return Result.failure("BeamSearch should expose beam_eval_score: %s" % str(features))
	if int(features.get("beam_deepest_depth", 0)) < 2:
		return Result.failure("BeamSearch should expand beyond the root decision in this smoke setup: %s" % str(features))
	if int(features.get("beam_expanded_nodes", 0)) <= 0:
		return Result.failure("BeamSearch should expose expanded node count: %s" % str(features))
	if int(features.get("beam_selected_depth", 0)) <= 0:
		return Result.failure("BeamSearch should expose selected node depth: %s" % str(features))
	if not features.has("beam_budget_expired"):
		return Result.failure("BeamSearch should expose budget status in features: %s" % str(features))
	if not decision.explanation.has("budget_expired"):
		return Result.failure("BeamSearch should expose budget status in explanation: %s" % str(decision.explanation))
	var path_val = features.get("beam_path", [])
	if not (path_val is Array) or Array(path_val).is_empty():
		return Result.failure("BeamSearch should expose non-empty path: %s" % str(features))
	return Result.success()

static func _test_beam_search_is_deterministic(seed_val: int) -> Result:
	var first := _choose_once(seed_val)
	if not first.ok:
		return first
	var second := _choose_once(seed_val)
	if not second.ok:
		return second
	var first_decision: BotDecision = first.value
	var second_decision: BotDecision = second.value
	if first_decision.macro_action_id != second_decision.macro_action_id:
		return Result.failure("BeamSearch should choose deterministic macro: first=%s second=%s" % [first_decision.macro_action_id, second_decision.macro_action_id])
	if str(first_decision.command.to_dict()) != str(second_decision.command.to_dict()):
		return Result.failure("BeamSearch should choose deterministic command: first=%s second=%s" % [str(first_decision.command.to_dict()), str(second_decision.command.to_dict())])
	return Result.success()

static func _test_beam_search_selects_depth_two_same_actor_recruit_path(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var scenario := _prepare_replay_safe_recruiter_followup_state(engine)
	if not scenario.ok:
		return scenario
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var decision_read := BeamSearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		null,
		{
			"beam_width": 2,
			"max_depth": 2,
			"top_k_per_node": 3,
		}
	)
	if not decision_read.ok:
		return decision_read
	var decision: BotDecision = decision_read.value
	if decision == null or decision.command == null:
		return Result.failure("BeamSearch depth-two scenario returned empty decision")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("BeamSearch depth-two scenario returned invalid command: %s" % valid.error)
	var features: Dictionary = Dictionary(decision.explanation.get("features", {}))
	if int(features.get("beam_deepest_depth", 0)) < 2:
		return Result.failure("BeamSearch should expand to depth two with an active recruiter: %s" % str(features))
	if int(features.get("beam_selected_depth", 0)) < 2:
		return Result.failure("BeamSearch should be able to select a depth-two same-actor recruit path: %s" % str(features))
	if int(features.get("beam_expanded_nodes", 0)) <= 0:
		return Result.failure("BeamSearch depth-two scenario should expand child nodes: %s" % str(features))
	var path_val = features.get("beam_path", [])
	if not (path_val is Array):
		return Result.failure("BeamSearch depth-two scenario path should be an Array: %s" % str(features))
	var path: Array = path_val
	if path.size() < 2:
		return Result.failure("BeamSearch depth-two scenario path should include two decisions: %s" % str(path))
	var actor := int(data["context"].player_id)
	for i in range(2):
		if not (path[i] is Dictionary):
			return Result.failure("BeamSearch path[%d] should be Dictionary: %s" % [i, str(path)])
		var step: Dictionary = path[i]
		if int(step.get("actor", -1)) != actor:
			return Result.failure("BeamSearch path[%d] should stay on root actor %d: %s" % [i, actor, str(path)])
		if str(step.get("action_id", "")) != "recruit":
			return Result.failure("BeamSearch path[%d] should be recruit: %s" % [i, str(path)])
	return Result.success()

static func _test_beam_bot_without_engine_uses_fallback(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	var bot := BeamBotClass.new()
	var decision := bot.choose_command(
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(80)
	)
	if decision == null:
		return Result.failure("BeamBot returned null fallback decision")
	if decision.is_failure():
		return Result.failure("BeamBot fallback decision failed: %s" % decision.failure_reason)
	if decision.command == null:
		return Result.failure("BeamBot fallback returned empty command")
	var valid := LegalActionServiceClass.validate_command(engine, decision.command, data["context"])
	if not valid.ok:
		return Result.failure("BeamBot fallback returned invalid command: %s" % valid.error)
	return Result.success()

static func _choose_once(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var setup := _build_search_inputs(engine, seed_val)
	if not setup.ok:
		return setup
	var data: Dictionary = setup.value
	return BeamSearchClass.choose_command(
		engine,
		data["observation"],
		data["context"],
		data["legal_action_ids"],
		data["validate_fn"],
		TimeBudget.start(260),
		{
			"beam_width": 2,
			"max_depth": 2,
			"top_k_per_node": 2,
		}
	)

static func _prepare_replay_safe_recruiter_followup_state(engine: GameEngine) -> Result:
	var working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 30)
	if not working.ok:
		return working
	var first_actor := engine.get_state().get_current_player_id()
	var first_recruit := engine.execute_command(Command.create("recruit", first_actor, {"employee_type": "recruiting_girl"}))
	if not first_recruit.ok:
		return Result.failure("recruiting_girl setup recruit failed: %s" % first_recruit.error)
	var restructuring := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_RESTRUCTURING, 80)
	if not restructuring.ok:
		return restructuring
	var place := engine.execute_command(Command.create("set_company_structure_direct", first_actor, {
		"slot_index": 0,
		"employee_id": "recruiting_girl",
	}))
	if not place.ok:
		return Result.failure("recruiting_girl setup structure placement failed: %s" % place.error)
	var next_working := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_WORKING, 80)
	if not next_working.ok:
		return next_working
	var safety := 0
	while engine.get_state().get_current_player_id() != first_actor:
		safety += 1
		if safety > 20:
			return Result.failure("recruiting_girl setup failed to rotate back to original actor")
		var end_turn := TestPhaseUtilsClass.end_current_player_working_turn(engine, 50)
		if not end_turn.ok:
			return end_turn
		if engine.get_state().phase != DefsClass.PHASE_WORKING:
			return Result.failure("recruiting_girl setup left Working before original actor returned")
	if str(engine.get_state().sub_phase) != DefsClass.SUB_PHASE_RECRUIT:
		return Result.failure("recruiting_girl setup should end at Working/Recruit, got %s/%s" % [str(engine.get_state().phase), str(engine.get_state().sub_phase)])
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
