class_name GameLocalAiController
extends RefCounted

const BotControllerClass = preload("res://core/ai/bot/bot_controller.gd")
const StrategyBotClass = preload("res://core/ai/bot/strategy_bot.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const DEFAULT_BUDGET_MS := 80
const DEFAULT_STRATEGY_PROFILE := "base_revenue_growth_v1"
const MAX_STEPS_PER_PUMP := 64

var _host: Node = null
var _get_game_engine: Callable = Callable()
var _execute_command: Callable = Callable()
var _set_input_locked: Callable = Callable()
var _after_command_executed: Callable = Callable()

var _bot_controller := BotControllerClass.new()
var _bots_by_player: Dictionary = {}
var _ai_player_ids: Array[int] = []
var _is_running: bool = false
var _pump_requested: bool = false
var _disposed: bool = false

func _init(
	host: Node,
	get_game_engine: Callable,
	execute_command: Callable,
	set_input_locked: Callable,
	after_command_executed: Callable = Callable()
) -> void:
	_host = host
	_get_game_engine = get_game_engine
	_execute_command = execute_command
	_set_input_locked = set_input_locked
	_after_command_executed = after_command_executed
	_rebuild_bots_from_globals()

func dispose() -> void:
	_disposed = true
	_host = null
	_get_game_engine = Callable()
	_execute_command = Callable()
	_after_command_executed = Callable()
	if _set_input_locked.is_valid():
		_set_input_locked.call(false)
	_set_input_locked = Callable()
	_bots_by_player.clear()
	_ai_player_ids.clear()
	_is_running = false
	_pump_requested = false

func has_ai_players() -> bool:
	return not _ai_player_ids.is_empty()

func is_ai_player(player_id: int) -> bool:
	return _ai_player_ids.has(int(player_id))

func is_running() -> bool:
	return _is_running

func request_pump() -> void:
	if _disposed:
		return
	if _host == null or not is_instance_valid(_host):
		return
	if _is_running or _pump_requested:
		return
	_pump_requested = true
	_host.call_deferred("_run_local_ai_turns")

func run_deferred() -> void:
	_pump_requested = false
	if _disposed or _is_running:
		return
	if not has_ai_players():
		_set_locked(false)
		return
	var engine := _get_engine()
	if engine == null:
		_set_locked(false)
		return
	if _is_terminal(engine):
		_set_locked(false)
		return

	var actor := _resolve_next_ai_actor(engine)
	if actor < 0:
		_set_locked(false)
		return

	_is_running = true
	_set_locked(true)
	await _drain_ai_turns()
	_set_locked(false)
	_is_running = false

func _drain_ai_turns() -> void:
	if _host == null or not is_instance_valid(_host):
		return
	await _host.get_tree().process_frame

	var steps := 0
	while not _disposed and _host != null and is_instance_valid(_host):
		var engine := _get_engine()
		if engine == null or _is_terminal(engine):
			return
		var actor := _resolve_next_ai_actor(engine)
		if actor < 0:
			return
		if not _bots_by_player.has(actor):
			GameLog.warn("GameLocalAiController", "缺少电脑玩家 bot: P%d" % (actor + 1))
			return

		var bot = _bots_by_player[actor]
		var choose_read: Result = _bot_controller.choose_command(engine, actor, bot, TimeBudget.start(DEFAULT_BUDGET_MS))
		if not choose_read.ok:
			GameLog.warn("GameLocalAiController", "电脑玩家 P%d 决策失败: %s" % [actor + 1, choose_read.error])
			return
		var payload: Dictionary = choose_read.value
		var command: Command = payload.get("command", null)
		if command == null:
			GameLog.warn("GameLocalAiController", "电脑玩家 P%d 未返回命令" % (actor + 1))
			return

		var result = _execute_command.call(command) if _execute_command.is_valid() else Result.failure("命令执行回调未就绪")
		if not (result is Result):
			GameLog.warn("GameLocalAiController", "电脑玩家 P%d 命令执行返回值类型错误" % (actor + 1))
			return
		if not result.ok:
			GameLog.warn("GameLocalAiController", "电脑玩家 P%d 执行失败: %s" % [actor + 1, result.error])
			return
		if _after_command_executed.is_valid():
			_after_command_executed.call(command)

		steps += 1
		if steps >= MAX_STEPS_PER_PUMP:
			GameLog.warn("GameLocalAiController", "电脑玩家连续执行达到上限 %d，暂停自动推进" % MAX_STEPS_PER_PUMP)
			return

		await _host.get_tree().process_frame

func _rebuild_bots_from_globals() -> void:
	_bots_by_player.clear()
	_ai_player_ids.clear()
	if Globals == null:
		return
	var count := int(Globals.player_count)
	for pid in range(count):
		if not Globals.is_local_player_ai(pid):
			continue
		_ai_player_ids.append(pid)
		var bot = StrategyBotClass.new()
		var profile_read: Result = bot.configure_profile(DEFAULT_STRATEGY_PROFILE)
		if not profile_read.ok:
			GameLog.warn("GameLocalAiController", "StrategyBot profile %s 加载失败，使用内置默认: %s" % [DEFAULT_STRATEGY_PROFILE, profile_read.error])
		_bots_by_player[pid] = bot

func _get_engine() -> GameEngine:
	if not _get_game_engine.is_valid():
		return null
	var engine_val = _get_game_engine.call()
	return engine_val if engine_val is GameEngine else null

func _resolve_next_ai_actor(engine: GameEngine) -> int:
	if engine == null:
		return -1
	var state := engine.get_state()
	if state == null:
		return -1
	var pending := _pending_players_for_current_phase(state)
	if not pending.is_empty():
		for pid in pending:
			if is_ai_player(pid):
				return pid
		return -1
	var actor := BotControllerClass.resolve_next_player_id(engine)
	return actor if actor >= 0 and is_ai_player(actor) else -1

func _pending_players_for_current_phase(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if state == null or not (state.round_state is Dictionary):
		return out
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return out
	var phase_pending_val = Dictionary(ppa_val).get(str(state.phase), null)
	if not (phase_pending_val is Array):
		return out
	for item in Array(phase_pending_val):
		var player_id := _read_pending_player_id(item)
		if player_id < 0 or player_id >= state.players.size():
			continue
		if out.has(player_id):
			continue
		out.append(player_id)
	return out

func _read_pending_player_id(item) -> int:
	if item is int or item is float:
		return int(item)
	if item is Dictionary:
		var dict: Dictionary = item
		var pid_val = dict.get("player_id", null)
		if pid_val is int or pid_val is float:
			return int(pid_val)
	return -1

func _is_terminal(engine: GameEngine) -> bool:
	if engine == null:
		return true
	var state := engine.get_state()
	if state == null:
		return true
	return str(state.phase) == DefsClass.PHASE_GAME_OVER

func _set_locked(locked: bool) -> void:
	if _set_input_locked.is_valid():
		_set_input_locked.call(bool(locked))
