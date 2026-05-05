class_name CandidateGeneratorTest
extends RefCounted

const CandidateGeneratorClass = preload("res://core/ai/candidates/candidate_generator.gd")
const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const AiDecisionPointClass = preload("res://core/ai/bot/ai_decision_point.gd")
const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")
const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const RandomLegalBotClass = preload("res://core/ai/bot/random_legal_bot.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var reserve := _test_reserve_candidates_are_valid(seed_val)
	if not reserve.ok:
		return reserve
	var initial := _test_initial_restaurant_candidates_are_valid_and_no_pass(seed_val)
	if not initial.ok:
		return initial
	var working := _test_working_recruit_candidates_are_valid_and_deterministic(seed_val)
	if not working.ok:
		return working
	var restructuring := _test_restructuring_direct_assignment_candidate(seed_val)
	if not restructuring.ok:
		return restructuring
	return Result.success({"cases": 4})

static func _test_reserve_candidates_are_valid(seed_val: int) -> Result:
	var engine_read := _build_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var payload_read := _generate_for_current_player(engine_read.value, seed_val, {"max_valid_per_action": 8})
	if not payload_read.ok:
		return payload_read
	var candidates := _read_candidates(payload_read.value)
	if candidates.is_empty():
		return Result.failure("reserve candidate list should not be empty")
	if not _all_macros_single_action(candidates, "select_reserve_card"):
		return Result.failure("reserve candidates should only contain select_reserve_card: %s" % str(_macro_debug(candidates)))
	var selected := {}
	for macro in candidates:
		var command: Command = macro.commands[0]
		selected[int(command.params.get("selected_index", -1))] = true
	if selected.size() != candidates.size():
		return Result.failure("reserve selected_index candidates should be unique: %s" % str(_macro_debug(candidates)))
	return Result.success()

static func _test_initial_restaurant_candidates_are_valid_and_no_pass(seed_val: int) -> Result:
	var engine_read := _build_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var setup_read := _finish_reserve_selection(engine)
	if not setup_read.ok:
		return setup_read

	var payload_read := _generate_for_current_player(engine, seed_val, {"max_valid_per_action": 5})
	if not payload_read.ok:
		return payload_read
	var candidates := _read_candidates(payload_read.value)
	if not _has_action(candidates, "place_restaurant"):
		return Result.failure("initial restaurant candidates should include place_restaurant: %s" % str(_macro_debug(candidates)))
	if _has_macro_id(candidates, "initial_restaurant_pass"):
		return Result.failure("initial restaurant pass must stay disabled while engine lacks setup pass support")
	if _count_action(candidates, "place_restaurant") > 5:
		return Result.failure("place_restaurant candidates exceeded max_valid_per_action")
	return Result.success()

static func _test_working_recruit_candidates_are_valid_and_deterministic(seed_val: int) -> Result:
	var engine_read := _build_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var run_read := _run_random_bots_to_working(engine)
	if not run_read.ok:
		return run_read
	var state := engine.get_state()
	if state == null or str(state.phase) != DefsClass.PHASE_WORKING or str(state.sub_phase) != DefsClass.SUB_PHASE_RECRUIT:
		return Result.failure("expected Working/Recruit, got %s/%s" % [str(state.phase), str(state.sub_phase)])

	var first_read := _generate_for_current_player(engine, seed_val, {"max_valid_per_action": 8})
	if not first_read.ok:
		return first_read
	var second_read := _generate_for_current_player(engine, seed_val, {"max_valid_per_action": 8})
	if not second_read.ok:
		return second_read
	var first_candidates := _read_candidates(first_read.value)
	var second_candidates := _read_candidates(second_read.value)
	if not _has_action(first_candidates, "skip_sub_phase"):
		return Result.failure("working candidates should include skip_sub_phase fallback: %s" % str(_macro_debug(first_candidates)))
	if not _has_action(first_candidates, "recruit"):
		return Result.failure("Working/Recruit candidates should include at least one recruit command: %s" % str(_macro_debug(first_candidates)))
	if str(_macro_debug(first_candidates)) != str(_macro_debug(second_candidates)):
		return Result.failure("candidate generation should be deterministic for same state and seed")
	return Result.success()

static func _test_restructuring_direct_assignment_candidate(seed_val: int) -> Result:
	var engine_read := _build_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var state := engine.get_state()
	if state == null:
		return Result.failure("engine state is null")
	state.phase = DefsClass.PHASE_RESTRUCTURING
	state.sub_phase = ""
	state.turn_order = [0, 1]
	state.selection_order = [0, 1]
	state.current_player_index = 0
	state.round_state["restructuring"] = {
		"finalized": false,
	}
	state.players[0]["reserve_employees"].append("kitchen_trainee")
	state.employee_pool["kitchen_trainee"] = int(state.employee_pool.get("kitchen_trainee", 0)) - 1

	var payload_read := _generate_for_current_player(engine, seed_val, {"max_valid_per_action": 8})
	if not payload_read.ok:
		return payload_read
	var candidates := _read_candidates(payload_read.value)
	if not _has_action(candidates, "set_company_structure_direct"):
		return Result.failure("restructuring should generate direct slot assignment: %s" % str(_macro_debug(candidates)))
	var command := _first_command_with_param(candidates, "set_company_structure_direct", "employee_id", "kitchen_trainee")
	if command == null:
		return Result.failure("missing set_company_structure_direct command for kitchen_trainee: %s" % str(_macro_debug(candidates)))
	var executed := engine.execute_command(command)
	if not executed.ok:
		return Result.failure("direct structure candidate failed on execute: %s" % executed.error)
	var player: Dictionary = engine.get_state().players[0]
	if not Array(player.get("employees", [])).has("kitchen_trainee"):
		return Result.failure("direct assignment should move reserve employee to active employees")
	return Result.success()

static func _build_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	return Result.success(engine)

static func _finish_reserve_selection(engine: GameEngine) -> Result:
	for _i in range(2):
		var state := engine.get_state()
		if state == null:
			return Result.failure("engine state is null")
		var pid := state.get_current_player_id()
		var command := Command.create("select_reserve_card", pid, {"selected_index": 0})
		var executed := engine.execute_command(command)
		if not executed.ok:
			return Result.failure("select reserve failed: %s" % executed.error)
	return Result.success()

static func _run_random_bots_to_working(engine: GameEngine) -> Result:
	var controller := BotControllerClass.new()
	var bots := {
		0: RandomLegalBotClass.new(),
		1: RandomLegalBotClass.new(),
	}
	var stop_condition := func(test_engine: GameEngine) -> bool:
		var state := test_engine.get_state()
		return state != null and str(state.phase) == DefsClass.PHASE_WORKING
	return controller.run_until(engine, bots, stop_condition, 80, 50)

static func _generate_for_current_player(engine: GameEngine, seed_val: int, options: Dictionary) -> Result:
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
	return CandidateGeneratorClass.generate(observation, context, legal_action_ids, validate_fn, options)

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

static func _read_candidates(payload: Dictionary) -> Array:
	var candidates_val = payload.get("candidates", [])
	if candidates_val is Array:
		return candidates_val
	return []

static func _all_macros_single_action(candidates: Array, action_id: String) -> bool:
	if candidates.is_empty():
		return false
	for macro_val in candidates:
		if not (macro_val is MacroAction):
			return false
		var macro: MacroAction = macro_val
		if macro.commands.size() != 1:
			return false
		if macro.commands[0] == null or macro.commands[0].action_id != action_id:
			return false
	return true

static func _has_action(candidates: Array, action_id: String) -> bool:
	return _count_action(candidates, action_id) > 0

static func _first_command_with_param(candidates: Array, action_id: String, param_key: String, param_value: Variant) -> Command:
	for macro_val in candidates:
		if not (macro_val is MacroAction):
			continue
		var macro: MacroAction = macro_val
		for command in macro.commands:
			if command == null or command.action_id != action_id:
				continue
			if command.params.get(param_key, null) == param_value:
				return command
	return null

static func _count_action(candidates: Array, action_id: String) -> int:
	var count := 0
	for macro_val in candidates:
		if not (macro_val is MacroAction):
			continue
		var macro: MacroAction = macro_val
		for command in macro.commands:
			if command != null and command.action_id == action_id:
				count += 1
	return count

static func _has_macro_id(candidates: Array, macro_id: String) -> bool:
	for macro_val in candidates:
		if macro_val is MacroAction and str((macro_val as MacroAction).id) == macro_id:
			return true
	return false

static func _macro_debug(candidates: Array) -> Array:
	var out := []
	for macro_val in candidates:
		if macro_val is MacroAction:
			out.append((macro_val as MacroAction).to_debug_dict())
	return out
