class_name TutorialMatchRuntimeTest
extends RefCounted

const GameTutorialMatchRuntimeClass = preload("res://ui/scenes/game/controllers/tutorial_match_runtime.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

class _FakeExecutor:
	extends RefCounted

	var _can_initiate: bool = true

	func _init(can_initiate: bool = true) -> void:
		_can_initiate = can_initiate

	func validate(state: GameState, command: Command) -> Result:
		if state == null:
			return Result.failure("state 为空")
		if command == null:
			return Result.failure("command 为空")
		if int(command.actor) != int(state.get_current_player_id()):
			return Result.failure("不是你的回合")
		return Result.failure("缺少参数", Result.ErrorCode.MISSING_PARAMS)

	func can_initiate(_state: GameState, _player_id: int) -> bool:
		return _can_initiate

class _FakeActionRegistry:
	extends RefCounted

	var _executors: Dictionary = {}

	func set_executor(action_id: String, executor) -> void:
		_executors[str(action_id).strip_edges()] = executor

	func get_executor(action_id: String):
		return _executors.get(str(action_id).strip_edges(), null)

class _FakeGameEngine:
	extends RefCounted

	var action_registry = _FakeActionRegistry.new()
	var command_history: Array[Command] = []
	var current_command_index: int = -1

	func get_action_registry():
		return action_registry

class _EngineHolder:
	extends RefCounted

	var engine = null

	func get_engine():
		return engine

static func run() -> Result:
	if Globals == null:
		return Result.failure("Globals 不可用")

	var snapshot := {
		"tutorial_enabled": bool(Globals.tutorial_enabled),
		"tutorial_match_enabled": bool(Globals.tutorial_match_enabled),
	}

	Globals.tutorial_enabled = true
	Globals.tutorial_match_enabled = true

	var holder := _EngineHolder.new()
	var engine := _FakeGameEngine.new()
	holder.engine = engine
	var runtime = GameTutorialMatchRuntimeClass.new(Callable(holder, "get_engine"))

	var recruit_state := _build_state(1, DefsClass.PHASE_WORKING, DefsClass.SUB_PHASE_RECRUIT, 0)
	engine.action_registry.set_executor("recruit", _FakeExecutor.new(true))

	var skip_sub_phase_cmd := Command.create(ActionIdsClass.SKIP_SUB_PHASE, 0, {})
	var gate_recruit := runtime.validate_command(skip_sub_phase_cmd, recruit_state, engine)
	if gate_recruit.ok:
		_restore_globals(snapshot)
		return Result.failure("教学局应阻止在首次招聘前跳过招聘子阶段")
	if str(gate_recruit.error).find("招聘") == -1:
		_restore_globals(snapshot)
		return Result.failure("招聘阻止提示不清晰: %s" % gate_recruit.error)

	var recruit_cmd := Command.create("recruit", 0, {"employee_type": "waitress"})
	var recruit_gate := runtime.validate_command(recruit_cmd, recruit_state, engine)
	if not recruit_gate.ok:
		_restore_globals(snapshot)
		return Result.failure("教学局不应阻止实际招聘: %s" % recruit_gate.error)

	engine.command_history = [_make_history_command("recruit", 0, 1, DefsClass.PHASE_WORKING, DefsClass.SUB_PHASE_RECRUIT)]
	engine.current_command_index = 0
	var gate_after_recruit := runtime.validate_command(skip_sub_phase_cmd, recruit_state, engine)
	if not gate_after_recruit.ok:
		_restore_globals(snapshot)
		return Result.failure("完成首次招聘后应允许跳过子阶段: %s" % gate_after_recruit.error)

	engine.command_history = [_make_history_command("choose_turn_order", 0, 1, DefsClass.PHASE_ORDER_OF_BUSINESS, "")]
	engine.current_command_index = 0
	engine.action_registry.set_executor("choose_turn_order", _FakeExecutor.new(true))
	var order_state := _build_state(1, DefsClass.PHASE_ORDER_OF_BUSINESS, "", 1)
	var skip_cmd := Command.create(ActionIdsClass.SKIP, 1, {})
	var order_gate := runtime.validate_command(skip_cmd, order_state, engine)
	if order_gate.ok:
		_restore_globals(snapshot)
		return Result.failure("顺位选择应按玩家分别约束，当前玩家尚未选择时不应允许跳过")

	var round_two_state := _build_state(2, DefsClass.PHASE_RESTRUCTURING, "", 0)
	var round_two_gate := runtime.validate_command(skip_cmd, round_two_state, engine)
	if not round_two_gate.ok:
		_restore_globals(snapshot)
		return Result.failure("第二回合开始后应解除教学局强约束: %s" % round_two_gate.error)

	_restore_globals(snapshot)
	return Result.success()

static func _build_state(round_number: int, phase: String, sub_phase: String, current_player_id: int) -> GameState:
	var state := GameState.new()
	state.round_number = round_number
	state.phase = phase
	state.sub_phase = sub_phase
	state.turn_order = [0, 1]
	state.current_player_index = maxi(0, state.turn_order.find(current_player_id))
	state.players = [
		{
			"id": 0,
			"restaurants": [],
			"reserve_employees": [],
			"employees": ["ceo"],
			"company_structure": {"structure": []},
		},
		{
			"id": 1,
			"restaurants": [],
			"reserve_employees": [],
			"employees": ["ceo"],
			"company_structure": {"structure": []},
		},
	]
	state.round_state = {
		"order_of_business": {"picks": [-1, -1]},
	}
	return state

static func _make_history_command(action_id: String, actor: int, round_number: int, phase: String, sub_phase: String) -> Command:
	var command := Command.create(action_id, actor, {})
	command.phase = phase
	command.sub_phase = sub_phase
	command.timestamp = round_number * 1000
	return command

static func _restore_globals(snapshot: Dictionary) -> void:
	if Globals == null:
		return
	Globals.tutorial_enabled = bool(snapshot.get("tutorial_enabled", true))
	Globals.tutorial_match_enabled = bool(snapshot.get("tutorial_match_enabled", false))
