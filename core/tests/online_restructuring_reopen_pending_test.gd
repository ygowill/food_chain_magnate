class_name OnlineRestructuringReopenPendingTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const GameStateClass = preload("res://core/state/game_state.gd")
const OnlinePhaseInteractionClass = preload("res://core/utils/online_phase_interaction.gd")

static func run() -> Result:
	_reset_net_context()
	if NetContext == null:
		return Result.failure("NetContext autoload missing")

	NetContext.mode = NetContext.Mode.ONLINE_CLIENT
	NetContext.local_player_id = 0

	var state := _build_restructuring_state([1])
	var reopen := OnlinePhaseInteractionClass.clear_player_restructuring_submission_for_online_reopen(state, 0)
	if not reopen.ok:
		_reset_net_context()
		return reopen

	var submitted_read := _read_submitted(state, 0)
	if not submitted_read.ok:
		_reset_net_context()
		return submitted_read
	if bool(submitted_read.value):
		_reset_net_context()
		return Result.failure("重新编辑后玩家 0 的 submitted 应被清为 false")

	var pending_read := _read_pending(state)
	if not pending_read.ok:
		_reset_net_context()
		return pending_read
	var pending: Array = pending_read.value
	if pending != [0, 1]:
		_reset_net_context()
		return Result.failure("重新编辑后 pending_phase_actions[Restructuring] 应恢复玩家 0，实际: %s" % str(pending))

	var finalized := false
	var restructuring_val = state.round_state.get("restructuring", null)
	if restructuring_val is Dictionary:
		var restructuring: Dictionary = restructuring_val
		finalized = bool(restructuring.get("finalized", false))
	if finalized:
		_reset_net_context()
		return Result.failure("重新编辑后 restructuring.finalized 应为 false")

	var bad_state := _build_restructuring_state([1])
	bad_state.round_state["pending_phase_actions"] = []
	var bad_reopen := OnlinePhaseInteractionClass.clear_player_restructuring_submission_for_online_reopen(bad_state, 0)
	if bad_reopen.ok:
		_reset_net_context()
		return Result.failure("pending_phase_actions 类型错误时应失败")
	var bad_submitted_read := _read_submitted(bad_state, 0)
	if not bad_submitted_read.ok:
		_reset_net_context()
		return bad_submitted_read
	if not bool(bad_submitted_read.value):
		_reset_net_context()
		return Result.failure("失败时不应提前清除 submitted")

	_reset_net_context()
	return Result.success({})

static func _build_restructuring_state(pending: Array) -> GameState:
	var state := GameStateClass.new()
	state.phase = DefsClass.PHASE_RESTRUCTURING
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.round_number = 2
	state.players = [
		{"id": 0},
		{"id": 1},
	]
	state.round_state = {
		"restructuring": {
			"submitted": {0: true, 1: false},
			"finalized": false,
		},
		"pending_phase_actions": {
			DefsClass.PHASE_RESTRUCTURING: pending.duplicate(true),
		},
	}
	return state

static func _read_submitted(state: GameState, player_id: int) -> Result:
	var restructuring_val = state.round_state.get("restructuring", null)
	if not (restructuring_val is Dictionary):
		return Result.failure("round_state.restructuring 类型错误（期望 Dictionary）")
	var restructuring: Dictionary = restructuring_val
	var submitted_val = restructuring.get("submitted", null)
	if not (submitted_val is Dictionary):
		return Result.failure("round_state.restructuring.submitted 类型错误（期望 Dictionary）")
	var submitted: Dictionary = submitted_val
	return Result.success(bool(submitted.get(player_id, false)))

static func _read_pending(state: GameState) -> Result:
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("round_state.pending_phase_actions 类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val
	var pending_val = ppa.get(DefsClass.PHASE_RESTRUCTURING, null)
	if not (pending_val is Array):
		return Result.failure("round_state.pending_phase_actions[Restructuring] 类型错误（期望 Array）")
	var pending: Array = pending_val
	return Result.success(pending.duplicate(true))

static func _reset_net_context() -> void:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
