# 确认晚餐结算动作
# 清除 dinnertime pending_phase_action，允许 auto-advance 继续推进
class_name ConfirmDinnertimeAction
extends ActionExecutor

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")
const KIND_CONFIRM_DINNERTIME := "confirm_dinnertime"
const ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY := "online_dinnertime_confirmed_players"

func _init() -> void:
	action_id = "confirm_dinnertime"
	display_name = "确认晚餐结算"
	description = "确认晚餐结算结果，推进到下一阶段"
	requires_actor = false
	is_mandatory = false

func _validate_specific(state: GameState, command: Command) -> Result:
	if str(state.phase) != DefsClass.PHASE_DINNERTIME:
		return Result.failure("当前不在晚餐阶段")

	var pending_read := _read_dinnertime_pending_list(state)
	if not pending_read.ok:
		return pending_read
	var pending: Array = pending_read.value
	if pending.is_empty():
		return Result.failure("当前无需确认晚餐结算")
	if _is_legacy_global_confirm_pending(pending):
		return Result.success()

	var actor_read := _read_actor_id(command)
	if not actor_read.ok:
		return actor_read
	var actor_id := int(actor_read.value)
	var confirmed_read := _read_online_dinnertime_confirmed_players(state)
	if confirmed_read.ok and (confirmed_read.value is Array):
		var confirmed: Array = confirmed_read.value
		if confirmed.size() == state.players.size():
			if actor_id >= 0 and actor_id < confirmed.size() and bool(confirmed[actor_id]):
				return Result.failure("玩家 %d 当前无需确认晚餐结算" % actor_id)
	if not _has_player_pending_confirm(pending, actor_id):
		return Result.failure("玩家 %d 当前无需确认晚餐结算" % actor_id)
	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var pending_read := _read_dinnertime_pending_list(state)
	if not pending_read.ok:
		return pending_read
	var pending: Array = pending_read.value

	if _is_legacy_global_confirm_pending(pending):
		return RoundStatePendingPhaseActionsClass.set_phase_pending_players(
			state.round_state, DefsClass.PHASE_DINNERTIME, [], KIND_CONFIRM_DINNERTIME
		)

	var actor_read := _read_actor_id(command)
	if not actor_read.ok:
		return actor_read
	var actor_id := int(actor_read.value)
	var confirmed_read := _read_online_dinnertime_confirmed_players(state)
	if confirmed_read.ok and (confirmed_read.value is Array):
		var confirmed: Array = confirmed_read.value
		if confirmed.size() == state.players.size():
			if actor_id < 0 or actor_id >= confirmed.size():
				return Result.failure("玩家 %d 当前无需确认晚餐结算" % actor_id)
			if bool(confirmed[actor_id]):
				return Result.failure("玩家 %d 当前无需确认晚餐结算" % actor_id)
			confirmed[actor_id] = true
			state.round_state[ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY] = confirmed
			var remaining_by_confirmed := _build_pending_from_confirmed_players(confirmed)
			return RoundStatePendingPhaseActionsClass.set_phase_pending_players(
				state.round_state, DefsClass.PHASE_DINNERTIME, remaining_by_confirmed, KIND_CONFIRM_DINNERTIME
			)
	if not _has_player_pending_confirm(pending, actor_id):
		return Result.failure("玩家 %d 当前无需确认晚餐结算" % actor_id)

	var remaining := _remove_player_pending_confirm(pending, actor_id)
	return RoundStatePendingPhaseActionsClass.set_phase_pending_players(
		state.round_state, DefsClass.PHASE_DINNERTIME, remaining, KIND_CONFIRM_DINNERTIME
	)

static func _read_dinnertime_pending_list(state: GameState) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if ppa_val == null:
		return Result.success([])
	if not (ppa_val is Dictionary):
		return Result.failure("round_state.pending_phase_actions 类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val
	var list_val = ppa.get(DefsClass.PHASE_DINNERTIME, null)
	if list_val == null:
		return Result.success([])
	if not (list_val is Array):
		return Result.failure("round_state.pending_phase_actions[Dinnertime] 类型错误（期望 Array）")
	return Result.success(Array(list_val).duplicate(true))

static func _read_actor_id(command: Command) -> Result:
	if command == null:
		return Result.failure("command 为空")
	var actor_id := int(command.actor)
	if actor_id < 0:
		return Result.failure("确认晚餐结算需要有效 actor_id")
	return Result.success(actor_id)

static func _is_legacy_global_confirm_pending(pending: Array) -> bool:
	return pending.size() == 1 and (pending[0] is String) and str(pending[0]) == KIND_CONFIRM_DINNERTIME

static func _has_player_pending_confirm(pending: Array, actor_id: int) -> bool:
	for item_val in pending:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var kind := str(item.get("kind", "")).strip_edges()
		if kind != KIND_CONFIRM_DINNERTIME:
			continue
		var pid_read := _read_pending_player_id(item.get("player_id", null))
		if not pid_read.ok:
			continue
		if int(pid_read.value) == actor_id:
			return true
	return false

static func _remove_player_pending_confirm(pending: Array, actor_id: int) -> Array:
	var remaining: Array = []
	for item_val in pending:
		if not (item_val is Dictionary):
			remaining.append(item_val)
			continue
		var item: Dictionary = item_val
		var kind := str(item.get("kind", "")).strip_edges()
		if kind != KIND_CONFIRM_DINNERTIME:
			remaining.append(item)
			continue
		var pid_read := _read_pending_player_id(item.get("player_id", null))
		if not pid_read.ok:
			remaining.append(item)
			continue
		if int(pid_read.value) == actor_id:
			continue
		remaining.append(item)
	return remaining

static func _read_online_dinnertime_confirmed_players(state: GameState) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.players is Array):
		return Result.failure("players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = state.round_state
	var val = rs.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)
	if val == null:
		return Result.success([])
	if not (val is Array):
		return Result.failure("round_state.%s 类型错误（期望 Array）" % ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY)
	var raw: Array = Array(val)
	if raw.size() != state.players.size():
		return Result.success([])
	var out: Array = []
	for i in range(raw.size()):
		var v = raw[i]
		if v is bool:
			out.append(bool(v))
			continue
		if v is int:
			out.append(int(v) != 0)
			continue
		if v is float:
			var f: float = float(v)
			if f == floor(f):
				out.append(int(f) != 0)
				continue
		return Result.failure("round_state.%s[%d] 类型错误（期望 bool/int/float）" % [ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, i])
	return Result.success(out)

static func _build_pending_from_confirmed_players(confirmed: Array) -> Array:
	var remaining: Array[Dictionary] = []
	for pid in range(confirmed.size()):
		if bool(confirmed[pid]):
			continue
		remaining.append({
			"kind": KIND_CONFIRM_DINNERTIME,
			"player_id": pid,
		})
	return remaining

static func _read_pending_player_id(value) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return Result.success(int(f))
	return Result.failure("player_id 类型错误（期望 int/float）")
