class_name LegalActionService
extends RefCounted

const DecisionPointClass = preload("res://core/ai/bot/ai_decision_point.gd")

const INTERNAL_ACTION_DECISION_POINTS := {
	# Setup/ReserveCards: the UI action is internal because selection is secret.
	"select_reserve_card": "RESERVE_CARD",
	# Restructuring: internal drag/drop edits plus explicit submit.
	"restructure_employee": "RESTRUCTURING",
	"set_company_structure_direct": "RESTRUCTURING",
	"set_company_structure_report": "RESTRUCTURING",
	"submit_restructuring": "RESTRUCTURING",
	# Cleanup: pending fridge choices are modal/internal, not normal turn actions.
	"choose_fridge_keep": "CLEANUP_PENDING",
}

static func get_action_ids_for_context(engine: GameEngine, context: AiDecisionContext) -> Result:
	var preflight := _require_engine_context(engine, context)
	if not preflight.ok:
		return preflight
	var state: GameState = preflight.value
	var ids: Array[String] = engine.action_registry.get_player_initiatable_actions(state, context.player_id)
	var decision_point := DecisionPointClass.from_context(context)

	for action_id in context.allowed_internal_actions:
		if ids.has(action_id):
			continue
		if not _is_internal_action_allowed_for_decision(action_id, decision_point):
			continue
		if not _can_initiate_action(engine, state, context.player_id, action_id):
			continue
		ids.append(action_id)
	ids.sort()
	return Result.success(ids)

static func validate_command(engine: GameEngine, command: Command, context: AiDecisionContext = null) -> Result:
	if engine == null:
		return Result.failure("LegalActionService.validate_command: engine is null")
	if command == null:
		return Result.failure("LegalActionService.validate_command: command is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("LegalActionService.validate_command: engine state is null")
	if engine.action_registry == null:
		return Result.failure("LegalActionService.validate_command: action_registry is null")
	var executor := engine.action_registry.get_executor(command.action_id)
	if executor == null:
		return Result.failure("LegalActionService.validate_command: unknown action_id: %s" % command.action_id)
	if executor.is_internal and not _context_allows_internal_action(context, command.action_id):
		return Result.failure("LegalActionService.validate_command: internal action not allowed: %s" % command.action_id)

	var test_command := _copy_command_with_phase(command, state)
	var gate := engine.action_registry.run_validators(state, test_command)
	if not gate.ok:
		return gate
	return executor.validate(state, test_command)

static func is_internal_action_whitelisted(action_id: String) -> bool:
	return INTERNAL_ACTION_DECISION_POINTS.has(action_id)

static func get_internal_action_decision_point(action_id: String) -> String:
	return str(INTERNAL_ACTION_DECISION_POINTS.get(action_id, DecisionPointClass.NO_DECISION))

static func _require_engine_context(engine: GameEngine, context: AiDecisionContext) -> Result:
	if engine == null:
		return Result.failure("LegalActionService: engine is null")
	if context == null:
		return Result.failure("LegalActionService: context is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("LegalActionService: engine state is null")
	if engine.action_registry == null:
		return Result.failure("LegalActionService: action_registry is null")
	if context.player_id < 0 or context.player_id >= state.players.size():
		return Result.failure("LegalActionService: player_id out of range: %d" % context.player_id)
	return Result.success(state)

static func _context_allows_internal_action(context: AiDecisionContext, action_id: String) -> bool:
	if context == null:
		return false
	if not context.allowed_internal_actions.has(action_id):
		return false
	var decision_point := DecisionPointClass.from_context(context)
	return _is_internal_action_allowed_for_decision(action_id, decision_point)

static func _is_internal_action_allowed_for_decision(action_id: String, decision_point: String) -> bool:
	if not INTERNAL_ACTION_DECISION_POINTS.has(action_id):
		return false
	return str(INTERNAL_ACTION_DECISION_POINTS[action_id]) == decision_point

static func _can_initiate_action(engine: GameEngine, state: GameState, player_id: int, action_id: String) -> bool:
	if not engine.action_registry.has_executor(action_id):
		return false
	var executor := engine.action_registry.get_executor(action_id)
	if executor == null:
		return false
	if executor.has_method("can_initiate"):
		var can_value = executor.can_initiate(state, player_id)
		if can_value is bool and not bool(can_value):
			return false
	var command := Command.create(action_id, player_id, {})
	command.phase = state.phase
	command.sub_phase = state.sub_phase
	var gate := engine.action_registry.run_validators(state, command)
	if not gate.ok:
		return false
	var validate := executor.validate(state, command)
	return validate.ok or _is_missing_params_error(validate)

static func _copy_command_with_phase(command: Command, state: GameState) -> Command:
	var out := Command.create(command.action_id, command.actor, command.params.duplicate(true))
	out.index = command.index
	out.phase = command.phase if not command.phase.is_empty() else state.phase
	out.sub_phase = command.sub_phase if not command.sub_phase.is_empty() else state.sub_phase
	out.timestamp = command.timestamp
	out.metadata = command.metadata.duplicate(true)
	return out

static func _is_missing_params_error(result: Result) -> bool:
	if result == null or result.ok:
		return false
	return int(result.error_code) == Result.ErrorCode.MISSING_PARAMS
