# OnlinePhaseInteraction：Dinnertime 必须按 pending_phase_actions 判断本地是否可操作
class_name OnlinePhaseInteractionDinnertimeTest
extends RefCounted

const OnlinePhaseInteractionClass = preload("res://core/utils/online_phase_interaction.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const GameStateClass = preload("res://core/state/game_state.gd")

const KIND_CONFIRM_DINNERTIME := "confirm_dinnertime"

static func run() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")

	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.local_player_id = 1

	var confirm_pending_state := _build_dinnertime_state([
		{"kind": KIND_CONFIRM_DINNERTIME, "player_id": 0},
		{"kind": KIND_CONFIRM_DINNERTIME, "player_id": 1},
	])
	if not OnlinePhaseInteractionClass.is_online_parallel_phase(confirm_pending_state):
		_reset_net_context()
		return Result.failure("Dinnertime 应被视为联机并行阶段")
	if not OnlinePhaseInteractionClass.can_local_player_act_in_online_phase(confirm_pending_state):
		_reset_net_context()
		return Result.failure("本地玩家仍在 Dinnertime pending 中时应可操作")

	var other_only_state := _build_dinnertime_state([
		{"kind": KIND_CONFIRM_DINNERTIME, "player_id": 0},
	])
	if OnlinePhaseInteractionClass.can_local_player_act_in_online_phase(other_only_state):
		_reset_net_context()
		return Result.failure("本地玩家不在 Dinnertime pending 中时不应可操作")

	var legacy_state := _build_dinnertime_state([KIND_CONFIRM_DINNERTIME])
	if not OnlinePhaseInteractionClass.can_local_player_act_in_online_phase(legacy_state):
		_reset_net_context()
		return Result.failure("legacy confirm_dinnertime pending 下所有联机玩家都应可操作")

	var pizza_pending_state := _build_dinnertime_state([
		{"seller": 1, "board_number": 3},
		{"seller": 0, "board_number": 4},
	])
	if not OnlinePhaseInteractionClass.can_local_player_act_in_online_phase(pizza_pending_state):
		_reset_net_context()
		return Result.failure("Dinnertime 串行 pending 的当前卖家应可操作")

	var pizza_other_state := _build_dinnertime_state([
		{"seller": 0, "board_number": 3},
		{"seller": 1, "board_number": 4},
	])
	if OnlinePhaseInteractionClass.can_local_player_act_in_online_phase(pizza_other_state):
		_reset_net_context()
		return Result.failure("Dinnertime 串行 pending 的非当前卖家不应可操作")

	_reset_net_context()
	return Result.success({})

static func _build_dinnertime_state(pending: Array) -> GameState:
	var state := GameStateClass.new()
	state.phase = DefsClass.PHASE_DINNERTIME
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.players = [
		{"id": 0},
		{"id": 1},
	]
	state.round_state = {
		"pending_phase_actions": {
			DefsClass.PHASE_DINNERTIME: pending.duplicate(true),
		}
	}
	return state

static func _reset_net_context() -> void:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
