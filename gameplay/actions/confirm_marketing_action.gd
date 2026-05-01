# 确认营销结算动作
# 清除 marketing pending_phase_action，允许 auto-advance 继续推进
class_name ConfirmMarketingAction
extends ActionExecutor

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")
const KIND_CONFIRM_MARKETING := "confirm_marketing"
const ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY := "online_marketing_confirmed_players"

func _init() -> void:
	action_id = "confirm_marketing"
	display_name = "确认营销结算"
	description = "确认营销广告结算结果，推进到下一阶段"
	requires_actor = false
	is_mandatory = false
	ui_hide_if_not_initiatable = true
	allowed_phases = [DefsClass.PHASE_MARKETING]

func _validate_specific(state: GameState, command: Command) -> Result:
	if str(state.phase) != DefsClass.PHASE_MARKETING:
		return Result.failure("当前不在营销阶段")

	var pending_read := _read_marketing_pending_list(state)
	if not pending_read.ok:
		return pending_read
	var pending: Array = pending_read.value
	if pending.is_empty():
		return Result.failure("当前无需确认营销结算")
	if _is_legacy_global_confirm_pending(pending):
		return Result.failure("round_state.pending_phase_actions[Marketing] 不再支持 legacy global confirm")

	var actor_read := _read_actor_id(command)
	if not actor_read.ok:
		return actor_read
	var actor_id := int(actor_read.value)
	var pending_plan := _plan_pending_after_confirm(pending, actor_id)
	if not pending_plan.ok:
		return pending_plan
	var pending_update: Dictionary = pending_plan.value
	var confirmed_read := _read_online_marketing_confirmed_players(state)
	if not confirmed_read.ok:
		return confirmed_read
	if confirmed_read.value is Array:
		var confirmed: Array = confirmed_read.value
		if confirmed.size() == state.players.size():
			var pending_match_r := _validate_pending_matches_confirmed_players(pending, confirmed)
			if not pending_match_r.ok:
				return pending_match_r
			if actor_id >= 0 and actor_id < confirmed.size() and bool(confirmed[actor_id]):
				return Result.failure("玩家 %d 当前无需确认营销结算" % actor_id)
	if not bool(pending_update.get("has_actor_pending", false)):
		return Result.failure("玩家 %d 当前无需确认营销结算" % actor_id)
	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var pending_read := _read_marketing_pending_list(state)
	if not pending_read.ok:
		return pending_read
	var pending: Array = pending_read.value

	if _is_legacy_global_confirm_pending(pending):
		return Result.failure("round_state.pending_phase_actions[Marketing] 不再支持 legacy global confirm")

	var actor_read := _read_actor_id(command)
	if not actor_read.ok:
		return actor_read
	var actor_id := int(actor_read.value)
	var pending_plan := _plan_pending_after_confirm(pending, actor_id)
	if not pending_plan.ok:
		return pending_plan
	var pending_update: Dictionary = pending_plan.value
	if not bool(pending_update.get("has_actor_pending", false)):
		return Result.failure("玩家 %d 当前无需确认营销结算" % actor_id)

	var confirmed_read := _read_online_marketing_confirmed_players(state)
	if not confirmed_read.ok:
		return confirmed_read
	if confirmed_read.value is Array:
		var confirmed: Array = confirmed_read.value
		if confirmed.size() == state.players.size():
			var pending_match_r := _validate_pending_matches_confirmed_players(pending, confirmed)
			if not pending_match_r.ok:
				return pending_match_r
			if actor_id < 0 or actor_id >= confirmed.size():
				return Result.failure("玩家 %d 当前无需确认营销结算" % actor_id)
			if bool(confirmed[actor_id]):
				return Result.failure("玩家 %d 当前无需确认营销结算" % actor_id)
			confirmed[actor_id] = true
			var set_pending := RoundStatePendingPhaseActionsClass.set_phase_pending_players(
				state.round_state, DefsClass.PHASE_MARKETING, pending_update.get("remaining", []), KIND_CONFIRM_MARKETING
			)
			if not set_pending.ok:
				return set_pending
			state.round_state[ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY] = confirmed
			return Result.success()

	var remaining: Array = pending_update.get("remaining", [])
	return RoundStatePendingPhaseActionsClass.set_phase_pending_players(
		state.round_state, DefsClass.PHASE_MARKETING, remaining, KIND_CONFIRM_MARKETING
	)

static func _read_marketing_pending_list(state: GameState) -> Result:
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
	var list_val = ppa.get(DefsClass.PHASE_MARKETING, null)
	if list_val == null:
		return Result.success([])
	if not (list_val is Array):
		return Result.failure("round_state.pending_phase_actions[Marketing] 类型错误（期望 Array）")
	return Result.success(Array(list_val).duplicate(true))

static func _read_actor_id(command: Command) -> Result:
	if command == null:
		return Result.failure("command 为空")
	var actor_id := int(command.actor)
	if actor_id < 0:
		return Result.failure("确认营销结算需要有效 actor_id")
	return Result.success(actor_id)

static func _is_legacy_global_confirm_pending(pending: Array) -> bool:
	return pending.size() == 1 and (pending[0] is String) and str(pending[0]) == KIND_CONFIRM_MARKETING

static func _plan_pending_after_confirm(pending: Array, actor_id: int) -> Result:
	var remaining: Array = []
	var has_actor_pending := false
	for i in range(pending.size()):
		var item_val = pending[i]
		if not (item_val is Dictionary):
			return Result.failure("round_state.pending_phase_actions[Marketing][%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val
		var kind_read := _read_pending_kind(item, i)
		if not kind_read.ok:
			return kind_read
		var kind := str(kind_read.value)
		if kind != KIND_CONFIRM_MARKETING:
			remaining.append(item)
			continue
		var pid_read := _read_pending_confirm_player_id(item, i)
		if not pid_read.ok:
			return pid_read
		if int(pid_read.value) == actor_id:
			has_actor_pending = true
			continue
		remaining.append(item)
	return Result.success({
		"has_actor_pending": has_actor_pending,
		"remaining": remaining,
	})

static func _read_online_marketing_confirmed_players(state: GameState) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.players is Array):
		return Result.failure("players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = state.round_state
	var val = rs.get(ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY, null)
	if val == null:
		return Result.success([])
	if not (val is Array):
		return Result.failure("round_state.%s 类型错误（期望 Array）" % ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY)
	var raw: Array = Array(val)
	if raw.size() != state.players.size():
		return Result.failure("round_state.%s 长度错误（期望 %d，实际 %d）" % [ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY, state.players.size(), raw.size()])
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
		return Result.failure("round_state.%s[%d] 类型错误（期望 bool/int/float）" % [ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY, i])
	return Result.success(out)

static func _validate_pending_matches_confirmed_players(pending: Array, confirmed: Array) -> Result:
	var pending_by_player := {}
	for i in range(pending.size()):
		var item_val = pending[i]
		if not (item_val is Dictionary):
			return Result.failure("round_state.pending_phase_actions[Marketing][%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val
		var kind_read := _read_pending_kind(item, i)
		if not kind_read.ok:
			return kind_read
		if str(kind_read.value) != KIND_CONFIRM_MARKETING:
			continue
		var pid_read := _read_pending_confirm_player_id(item, i)
		if not pid_read.ok:
			return pid_read
		var pid := int(pid_read.value)
		if pid < 0 or pid >= confirmed.size():
			return Result.failure("round_state.pending_phase_actions[Marketing][%d].player_id 越界: %d" % [i, pid])
		if pending_by_player.has(pid):
			return Result.failure("round_state.pending_phase_actions[Marketing] 重复 player_id: %d" % pid)
		pending_by_player[pid] = true
	for pid2 in range(confirmed.size()):
		var is_confirmed := bool(confirmed[pid2])
		var has_pending := pending_by_player.has(pid2)
		if is_confirmed and has_pending:
			return Result.failure("round_state.pending_phase_actions[Marketing] 已确认玩家仍在 pending: %d" % pid2)
		if not is_confirmed and not has_pending:
			return Result.failure("round_state.pending_phase_actions[Marketing] 缺少未确认玩家 pending: %d" % pid2)
	return Result.success()

static func _read_pending_kind(item: Dictionary, index: int) -> Result:
	var kind_val = item.get("kind", null)
	if not (kind_val is String):
		return Result.failure("round_state.pending_phase_actions[Marketing][%d].kind 类型错误（期望 String）" % index)
	var kind := str(kind_val).strip_edges()
	if kind.is_empty():
		return Result.failure("round_state.pending_phase_actions[Marketing][%d].kind 不能为空" % index)
	return Result.success(kind)

static func _read_pending_confirm_player_id(item: Dictionary, index: int) -> Result:
	var value = item.get("player_id", null)
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return Result.success(int(f))
	return Result.failure("round_state.pending_phase_actions[Marketing][%d].player_id 类型错误（期望 int/float）" % index)
