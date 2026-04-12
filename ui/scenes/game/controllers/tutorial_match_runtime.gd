# Game scene：教学局脚本运行时
# 负责：
# - 教学局首轮关键步骤的强约束
# - 在玩家试图过早跳过时给出清晰提示
# - 保持逻辑独立，避免把教学流程硬编码进 Game / Panel 主控制器
class_name GameTutorialMatchRuntime
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

const _STEP_SCOPE_GLOBAL_ONCE := "global_once"
const _STEP_SCOPE_PER_PLAYER := "per_player"

const _ENFORCED_STEPS := [
	{
		"id": "match_setup_place_restaurant",
		"round": 0,
		"phase": DefsClass.PHASE_SETUP,
		"sub_phase": "",
		"required_action": "place_restaurant",
		"completion_scope": _STEP_SCOPE_PER_PLAYER,
		"blocked_actions": [ActionIdsClass.SKIP, ActionIdsClass.ADVANCE_PHASE],
		"message": "教学说明：请先为当前玩家放置起始餐厅，并确认朝向。",
	},
	{
		"id": "match_round1_order_of_business",
		"round": 1,
		"phase": DefsClass.PHASE_ORDER_OF_BUSINESS,
		"sub_phase": "",
		"required_action": "choose_turn_order",
		"completion_scope": _STEP_SCOPE_PER_PLAYER,
		"blocked_actions": [ActionIdsClass.SKIP, ActionIdsClass.ADVANCE_PHASE],
		"message": "教学说明：请先为当前玩家选定一个回合顺位。",
	},
	{
		"id": "match_round1_working_recruit",
		"round": 1,
		"phase": DefsClass.PHASE_WORKING,
		"sub_phase": DefsClass.SUB_PHASE_RECRUIT,
		"required_action": "recruit",
		"completion_scope": _STEP_SCOPE_GLOBAL_ONCE,
		"blocked_actions": [ActionIdsClass.SKIP_SUB_PHASE, ActionIdsClass.SKIP, ActionIdsClass.ADVANCE_PHASE],
		"message": "教学说明：请先实际完成一次招聘，再结束招聘子阶段。",
	},
	{
		"id": "match_round1_working_train",
		"round": 1,
		"phase": DefsClass.PHASE_WORKING,
		"sub_phase": DefsClass.SUB_PHASE_TRAIN,
		"required_action": "train",
		"completion_scope": _STEP_SCOPE_GLOBAL_ONCE,
		"blocked_actions": [ActionIdsClass.SKIP_SUB_PHASE, ActionIdsClass.SKIP, ActionIdsClass.ADVANCE_PHASE],
		"message": "教学说明：请先实际完成一次培训，再结束培训子阶段。",
	},
	{
		"id": "match_round1_working_marketing",
		"round": 1,
		"phase": DefsClass.PHASE_WORKING,
		"sub_phase": DefsClass.SUB_PHASE_MARKETING,
		"required_action": "initiate_marketing",
		"completion_scope": _STEP_SCOPE_GLOBAL_ONCE,
		"blocked_actions": [ActionIdsClass.SKIP_SUB_PHASE, ActionIdsClass.SKIP, ActionIdsClass.ADVANCE_PHASE],
		"message": "教学说明：请先实际发起一次营销，再结束营销子阶段。",
	},
	{
		"id": "match_round1_working_get_food",
		"round": 1,
		"phase": DefsClass.PHASE_WORKING,
		"sub_phase": DefsClass.SUB_PHASE_GET_FOOD,
		"required_action": "produce_food",
		"completion_scope": _STEP_SCOPE_GLOBAL_ONCE,
		"blocked_actions": [ActionIdsClass.SKIP_SUB_PHASE, ActionIdsClass.SKIP, ActionIdsClass.ADVANCE_PHASE],
		"message": "教学说明：请先实际生产一次食物，再结束生产子阶段。",
	},
	{
		"id": "match_round1_working_get_drinks",
		"round": 1,
		"phase": DefsClass.PHASE_WORKING,
		"sub_phase": DefsClass.SUB_PHASE_GET_DRINKS,
		"required_action": "procure_drinks",
		"completion_scope": _STEP_SCOPE_GLOBAL_ONCE,
		"blocked_actions": [ActionIdsClass.SKIP_SUB_PHASE, ActionIdsClass.SKIP, ActionIdsClass.ADVANCE_PHASE],
		"message": "教学说明：请先实际采购一次饮料，再结束采购子阶段。",
	},
	{
		"id": "match_round1_working_place_houses",
		"round": 1,
		"phase": DefsClass.PHASE_WORKING,
		"sub_phase": DefsClass.SUB_PHASE_PLACE_HOUSES,
		"required_action": "place_house",
		"completion_scope": _STEP_SCOPE_GLOBAL_ONCE,
		"blocked_actions": [ActionIdsClass.SKIP_SUB_PHASE, ActionIdsClass.SKIP, ActionIdsClass.ADVANCE_PHASE],
		"message": "教学说明：请先实际放置一栋房屋，再结束放置房屋子阶段。",
	},
	{
		"id": "match_round1_working_place_restaurants",
		"round": 1,
		"phase": DefsClass.PHASE_WORKING,
		"sub_phase": DefsClass.SUB_PHASE_PLACE_RESTAURANTS,
		"required_action": "place_restaurant",
		"completion_scope": _STEP_SCOPE_GLOBAL_ONCE,
		"blocked_actions": [ActionIdsClass.SKIP_SUB_PHASE, ActionIdsClass.SKIP, ActionIdsClass.ADVANCE_PHASE],
		"message": "教学说明：请先实际放置一次餐厅，再结束放置餐厅子阶段。",
	},
]

var _get_game_engine: Callable = Callable()

func _init(get_game_engine: Callable) -> void:
	_get_game_engine = get_game_engine

func dispose() -> void:
	_get_game_engine = Callable()

func is_enabled() -> bool:
	if Globals == null:
		return false
	var runtime_enabled := bool(Globals.tutorial_enabled)
	if Globals.has_method("is_tutorial_runtime_enabled"):
		runtime_enabled = bool(Globals.is_tutorial_runtime_enabled())
	if not runtime_enabled:
		return false
	if not bool(Globals.tutorial_match_enabled):
		return false
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
		return false
	return true

func get_current_step_id(state: GameState = null, current_player_id: int = -1) -> String:
	var live_state := state
	if live_state == null:
		var engine := _get_engine()
		if engine == null:
			return ""
		live_state = engine.get_state()
	if live_state == null:
		return ""
	var pid := current_player_id if current_player_id >= 0 else int(live_state.get_current_player_id())
	var step := _get_active_enforced_step(live_state, pid, _get_engine())
	return str(step.get("id", "")).strip_edges()

func get_action_block_reason(action_id: String, state: GameState, current_player_id: int = -1) -> String:
	return _get_action_block_reason_internal(action_id, state, current_player_id, _get_engine())

func validate_command(command: Command, state: GameState, game_engine) -> Result:
	if command == null or state == null:
		return Result.success()
	var actor_id := _resolve_actor_id(command, state)
	var reason := _get_action_block_reason_internal(str(command.action_id), state, actor_id, game_engine)
	if reason.is_empty():
		return Result.success()
	return Result.failure(reason)

func on_command_executed(_command: Command, _state: GameState, _exec_result: Result) -> void:
	pass

func _get_engine() -> GameEngine:
	if not _get_game_engine.is_valid():
		return null
	var engine_val = _get_game_engine.call()
	return engine_val if engine_val is GameEngine else null

func _resolve_actor_id(command: Command, state: GameState) -> int:
	if command != null and int(command.actor) >= 0:
		return int(command.actor)
	if state == null:
		return -1
	return int(state.get_current_player_id())

func _get_action_block_reason_internal(action_id: String, state: GameState, current_player_id: int, game_engine) -> String:
	if not is_enabled():
		return ""
	if state == null:
		return ""
	if _should_release_strict_tutorial(state):
		return ""

	var aid := str(action_id).strip_edges()
	if aid.is_empty():
		return ""

	var player_id := current_player_id if current_player_id >= 0 else int(state.get_current_player_id())
	var step := _get_active_enforced_step(state, player_id, game_engine)
	if step.is_empty():
		return ""

	var required_action := str(step.get("required_action", "")).strip_edges()
	if aid == required_action:
		return ""
	if _is_step_completed_for_scope(step, state, player_id, game_engine):
		return ""
	if not _is_action_initiatable(required_action, state, player_id, game_engine):
		return ""

	for blocked_action in Array(step.get("blocked_actions", [])):
		if aid == str(blocked_action).strip_edges():
			return str(step.get("message", "教学说明：请先完成当前步骤。")).strip_edges()

	return ""

func _should_release_strict_tutorial(state: GameState) -> bool:
	if state == null:
		return true
	return int(state.round_number) >= 2

func _get_active_enforced_step(state: GameState, current_player_id: int, game_engine) -> Dictionary:
	if state == null:
		return {}

	for step_val in _ENFORCED_STEPS:
		if not (step_val is Dictionary):
			continue
		var step: Dictionary = step_val
		if int(step.get("round", -1)) != int(state.round_number):
			continue
		if str(step.get("phase", "")).strip_edges() != str(state.phase).strip_edges():
			continue
		if str(step.get("sub_phase", "")).strip_edges() != str(state.sub_phase).strip_edges():
			continue
		if _is_step_completed_for_scope(step, state, current_player_id, game_engine):
			continue
		return step

	return {}

func _is_step_completed_for_scope(step: Dictionary, state: GameState, current_player_id: int, game_engine) -> bool:
	if step.is_empty():
		return false
	if _is_state_requirement_already_satisfied(step, state, current_player_id):
		return true

	var scope := str(step.get("completion_scope", _STEP_SCOPE_GLOBAL_ONCE)).strip_edges()
	match scope:
		_STEP_SCOPE_PER_PLAYER:
			if current_player_id < 0:
				return false
			return _history_has_matching_completion(step, game_engine, current_player_id)
		_STEP_SCOPE_GLOBAL_ONCE:
			return _history_has_matching_completion(step, game_engine, -1)
		_:
			return false

func _is_state_requirement_already_satisfied(step: Dictionary, state: GameState, current_player_id: int) -> bool:
	if state == null:
		return false
	var step_id := str(step.get("id", "")).strip_edges()
	match step_id:
		"match_setup_place_restaurant":
			if current_player_id < 0:
				return false
			var player := state.get_player(current_player_id)
			var restaurants_val = player.get("restaurants", null)
			return restaurants_val is Array and not Array(restaurants_val).is_empty()
		"match_round1_order_of_business":
			if current_player_id < 0:
				return false
			if not (state.round_state is Dictionary):
				return false
			var oob_val = state.round_state.get("order_of_business", null)
			if not (oob_val is Dictionary):
				return false
			var picks_val = Dictionary(oob_val).get("picks", null)
			if not (picks_val is Array):
				return false
			return Array(picks_val).has(current_player_id)
		_:
			return false

func _history_has_matching_completion(step: Dictionary, game_engine, actor_filter: int) -> bool:
	if game_engine == null:
		return false

	var history: Array = game_engine.command_history
	if history.is_empty():
		return false

	var completion_action := str(step.get("required_action", "")).strip_edges()
	if completion_action.is_empty():
		return false

	var target_round := int(step.get("round", -1))
	var target_phase := str(step.get("phase", "")).strip_edges()
	var target_sub_phase := str(step.get("sub_phase", "")).strip_edges()
	var upper_bound := mini(int(game_engine.current_command_index), history.size() - 1)
	if upper_bound < 0:
		return false

	for idx in range(upper_bound + 1):
		var cmd_val = history[idx]
		if not (cmd_val is Command):
			continue
		var cmd: Command = cmd_val
		if str(cmd.action_id).strip_edges() != completion_action:
			continue
		if actor_filter >= 0 and int(cmd.actor) != actor_filter:
			continue
		if target_round >= 0 and _get_command_round(cmd) != target_round:
			continue
		if str(cmd.phase).strip_edges() != target_phase:
			continue
		if str(cmd.sub_phase).strip_edges() != target_sub_phase:
			continue
		return true

	return false

func _get_command_round(command: Command) -> int:
	if command == null:
		return -1
	if int(command.timestamp) >= 0:
		return int(int(command.timestamp) / 1000)
	if command.metadata is Dictionary:
		var round_val = command.metadata.get("round", null)
		if round_val is int or round_val is float:
			return int(round_val)
	return -1

func _is_action_initiatable(action_id: String, state: GameState, player_id: int, game_engine) -> bool:
	if action_id.is_empty():
		return false
	if state == null:
		return false
	if player_id < 0:
		return false
	if game_engine == null:
		return false

	var registry = game_engine.get_action_registry() if game_engine.has_method("get_action_registry") else game_engine.action_registry
	if registry == null or not registry.has_method("get_executor"):
		return false

	var executor = registry.get_executor(action_id)
	if executor == null or not executor.has_method("validate"):
		return false

	var test_command := Command.create(action_id, player_id)
	test_command.phase = state.phase
	test_command.sub_phase = state.sub_phase

	var validate_result = executor.validate(state, test_command)
	if validate_result is Result and validate_result.ok:
		return true
	if not (validate_result is Result):
		return false
	if int(validate_result.error_code) != Result.ErrorCode.MISSING_PARAMS:
		return false

	if executor.has_method("can_initiate"):
		var can_initiate_val = executor.can_initiate(state, player_id)
		if can_initiate_val is bool:
			return bool(can_initiate_val)

	return true
