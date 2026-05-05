class_name BotController
extends RefCounted

const ObservationAdapterClass = preload("res://core/ai/observation/observation_adapter.gd")
const AiDecisionPointClass = preload("res://core/ai/bot/ai_decision_point.gd")
const LegalActionServiceClass = preload("res://core/ai/bot/legal_action_service.gd")

var last_trace: Array[Dictionary] = []

func step(engine: GameEngine, player_id: int, bot, budget: TimeBudget = null) -> Result:
	if engine == null:
		return Result.failure("BotController.step: engine is null")
	if bot == null:
		return Result.failure("BotController.step: bot is null")
	if not _is_supported_bot(bot):
		return Result.failure("BotController.step: bot does not implement choose_command")

	var observation_read := ObservationAdapterClass.observe_for_player(engine, player_id)
	if not observation_read.ok:
		return observation_read
	var observation: ObservationState = observation_read.value

	var context_read := AiDecisionContext.from_observation(
		observation,
		_make_decision_seed(engine, player_id),
		_get_allowed_internal_actions(observation)
	)
	if not context_read.ok:
		return context_read
	var context: AiDecisionContext = context_read.value

	var ids_read := LegalActionServiceClass.get_action_ids_for_context(engine, context)
	if not ids_read.ok:
		return ids_read
	var legal_action_ids: Array[String] = ids_read.value

	var validate_fn := func(command: Command) -> Result:
		return LegalActionServiceClass.validate_command(engine, command, context)

	var phase_before := str(observation.phase)
	var sub_phase_before := str(observation.sub_phase)
	var decision := _choose_command(engine, bot, observation, context, legal_action_ids, validate_fn, budget)
	if decision == null:
		return Result.failure("BotController.step: bot returned null decision")
	if decision.is_failure():
		return Result.failure("BotController.step: bot decision failed for player %d: %s" % [player_id, decision.failure_reason])
	if decision.command == null:
		return Result.failure("BotController.step: bot returned empty command")

	var validated := LegalActionServiceClass.validate_command(engine, decision.command, context)
	if not validated.ok:
		return Result.failure("BotController.step: invalid bot command %s: %s" % [str(decision.command), validated.error])

	var executed := engine.execute_command(decision.command)
	if not executed.ok:
		return Result.failure("BotController.step: execute failed for %s: %s" % [str(decision.command), executed.error])

	var state_after := engine.get_state()
	var trace_item := {
		"player_id": player_id,
		"action_id": decision.command.action_id,
		"params": decision.command.params.duplicate(true),
		"phase_before": phase_before,
		"sub_phase_before": sub_phase_before,
		"phase_after": str(state_after.phase) if state_after != null else "",
		"sub_phase_after": str(state_after.sub_phase) if state_after != null else "",
		"macro_action_id": decision.macro_action_id,
		"score": decision.score,
		"explanation": decision.explanation.duplicate(true),
		"decision_trace": decision.trace.duplicate(true),
	}
	last_trace.append(trace_item)
	return Result.success(trace_item)

func run_until(
	engine: GameEngine,
	bots_by_player: Dictionary,
	stop_condition: Callable,
	max_steps: int,
	budget_ms: int = 50
) -> Result:
	last_trace = []
	if not stop_condition.is_valid():
		return Result.failure("BotController.run_until: stop_condition is invalid")
	for i in range(max_steps):
		if bool(stop_condition.call(engine)):
			return Result.success({
				"steps": i,
				"trace": last_trace.duplicate(true),
			})
		var player_id := resolve_next_player_id(engine)
		if player_id < 0:
			return Result.failure("BotController.run_until: cannot resolve next player")
		if not bots_by_player.has(player_id):
			return Result.failure("BotController.run_until: missing bot for player %d" % player_id)
		var bot = bots_by_player[player_id]
		if not _is_supported_bot(bot):
			return Result.failure("BotController.run_until: value for player %d is not a bot" % player_id)
		var step_result := step(engine, player_id, bot, TimeBudget.start(budget_ms))
		if not step_result.ok:
			return Result.failure("%s; last_trace=%s" % [step_result.error, str(_last_trace_slice(10))])

	if bool(stop_condition.call(engine)):
		return Result.success({
			"steps": max_steps,
			"trace": last_trace.duplicate(true),
		})
	return Result.failure("BotController.run_until: max_steps reached (%d); last_trace=%s" % [max_steps, str(_last_trace_slice(10))])

static func resolve_next_player_id(engine: GameEngine) -> int:
	if engine == null:
		return -1
	var state := engine.get_state()
	if state == null:
		return -1
	var pending_player := _first_pending_player_for_current_phase(state)
	if pending_player >= 0:
		return pending_player
	return state.get_current_player_id()

static func _first_pending_player_for_current_phase(state: GameState) -> int:
	if state == null or not (state.round_state is Dictionary):
		return -1
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return -1
	var phase_pending_val = Dictionary(ppa_val).get(str(state.phase), null)
	if not (phase_pending_val is Array):
		return -1
	for item in Array(phase_pending_val):
		var player_id := _read_pending_player_id(item)
		if player_id >= 0 and player_id < state.players.size():
			return player_id
	return -1

static func _read_pending_player_id(item) -> int:
	if item is int or item is float:
		return int(item)
	if item is Dictionary:
		var dict: Dictionary = item
		var pid_val = dict.get("player_id", null)
		if pid_val is int or pid_val is float:
			return int(pid_val)
	return -1

static func _get_allowed_internal_actions(observation: ObservationState) -> Array[String]:
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

static func _is_supported_bot(bot) -> bool:
	if bot == null:
		return false
	return bot.has_method("choose_command") or bot.has_method("choose_command_with_engine")

static func _choose_command(
	engine: GameEngine,
	bot,
	observation: ObservationState,
	context: AiDecisionContext,
	legal_action_ids: Array[String],
	validate_fn: Callable,
	budget: TimeBudget
) -> BotDecision:
	if bot != null and bot.has_method("choose_command_with_engine"):
		return bot.choose_command_with_engine(engine, observation, context, legal_action_ids, validate_fn, budget)
	if bot != null and bot.has_method("choose_command"):
		return bot.choose_command(observation, context, legal_action_ids, validate_fn, budget)
	return null

func _last_trace_slice(count: int) -> Array[Dictionary]:
	var start := maxi(0, last_trace.size() - count)
	var out: Array[Dictionary] = []
	for i in range(start, last_trace.size()):
		out.append(last_trace[i].duplicate(true))
	return out
