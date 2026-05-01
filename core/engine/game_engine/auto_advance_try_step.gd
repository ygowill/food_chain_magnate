extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const PhaseBlockingClass = preload("res://core/engine/game_engine/auto_advance_phase_blocking.gd")
const OrderOfBusinessRound1Class = preload("res://core/engine/game_engine/auto_advance_order_of_business_round1.gd")
const WorkingMandatoryClass = preload("res://core/engine/game_engine/auto_advance_working_mandatory.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")
const AutoloadAccessClass = preload("res://core/utils/autoload_access.gd")

const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"
const ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY := "online_dinnertime_confirmed_players"
const KIND_CONFIRM_DINNERTIME := "confirm_dinnertime"

static func try_advance_one(state_in: GameState, phase_manager: PhaseManager, action_registry: ActionRegistry) -> Result:
	if state_in == null:
		return Result.failure("auto_advance: state 为空")
	if phase_manager == null:
		return Result.failure("auto_advance: phase_manager 为空")
	if action_registry == null:
		return Result.failure("auto_advance: action_registry 为空")

	# 首轮自动跳过：Restructuring / OrderOfBusiness（保留未来扩展空间）
	if state_in.round_number == 1 and state_in.phase == DefsClass.PHASE_RESTRUCTURING:
		var blocked_r: Result = PhaseBlockingClass.is_phase_blocked_by_pending_actions(state_in, DefsClass.PHASE_RESTRUCTURING)
		if not blocked_r.ok:
			return blocked_r
		if bool(blocked_r.value):
			return Result.success(false)

		var adv: Result = phase_manager.advance_phase(state_in)
		if not adv.ok:
			return adv
		return Result.success(true).with_warnings(adv.warnings)

	if state_in.round_number == 1 and state_in.phase == DefsClass.PHASE_ORDER_OF_BUSINESS:
		var blocked_r2: Result = PhaseBlockingClass.is_phase_blocked_by_pending_actions(state_in, DefsClass.PHASE_ORDER_OF_BUSINESS)
		if not blocked_r2.ok:
			return blocked_r2
		if bool(blocked_r2.value):
			return Result.success(false)

		var fin: Result = OrderOfBusinessRound1Class.auto_finalize_order_of_business_round1(state_in)
		if not fin.ok:
			return fin

		var adv2: Result = phase_manager.advance_phase(state_in)
		if not adv2.ok:
			return adv2

		var warnings2: Array[String] = []
		warnings2.append_array(fin.warnings)
		warnings2.append_array(adv2.warnings)
		return Result.success(true).with_warnings(warnings2)

	# Restructuring：所有玩家都确认后，自动进入下一阶段（避免动作内 advance_phase 导致日志归属错乱）。
	if state_in.phase == DefsClass.PHASE_RESTRUCTURING:
		var blocked_r4: Result = PhaseBlockingClass.is_phase_blocked_by_pending_actions(state_in, DefsClass.PHASE_RESTRUCTURING)
		if not blocked_r4.ok:
			return blocked_r4
		if bool(blocked_r4.value):
			return Result.success(false)

		var finalized_r := false
		if state_in.round_state is Dictionary:
			var r_val = Dictionary(state_in.round_state).get("restructuring", null)
			if r_val is Dictionary:
				var r: Dictionary = r_val
				if r.has("finalized") and (r["finalized"] is bool):
					finalized_r = bool(r["finalized"])
		if not finalized_r:
			return Result.success(false)

		var adv_r4: Result = phase_manager.advance_phase(state_in)
		if not adv_r4.ok:
			return adv_r4
		return Result.success(true).with_warnings(adv_r4.warnings)

	# OrderOfBusiness：行动顺序落地后，自动进入 Working（保证日志顺序为“选择顺序 -> 进入 Working”）。
	if state_in.phase == DefsClass.PHASE_ORDER_OF_BUSINESS:
		var blocked_r5: Result = PhaseBlockingClass.is_phase_blocked_by_pending_actions(state_in, DefsClass.PHASE_ORDER_OF_BUSINESS)
		if not blocked_r5.ok:
			return blocked_r5
		if bool(blocked_r5.value):
			return Result.success(false)

		var finalized_oob := false
		if state_in.round_state is Dictionary:
			var oob_val = Dictionary(state_in.round_state).get("order_of_business", null)
			if oob_val is Dictionary:
				var oob: Dictionary = oob_val
				if oob.has("finalized") and (oob["finalized"] is bool):
					finalized_oob = bool(oob["finalized"])
		if not finalized_oob:
			return Result.success(false)

		var adv_r5: Result = phase_manager.advance_phase(state_in)
		if not adv_r5.ok:
			return adv_r5
		return Result.success(true).with_warnings(adv_r5.warnings)

	# 结算阶段默认自动跳过（无玩家交互）
	if PhaseBlockingClass.is_auto_skip_settlement_phase(state_in.phase):
		if state_in.phase == DefsClass.PHASE_DINNERTIME:
			var dinnertime_guard_r: Result = _ensure_online_dinnertime_pending_guard(state_in)
			if not dinnertime_guard_r.ok:
				return dinnertime_guard_r
		var blocked_r3: Result = PhaseBlockingClass.is_phase_blocked_by_pending_actions(state_in, str(state_in.phase))
		if not blocked_r3.ok:
			return blocked_r3
		if bool(blocked_r3.value):
			return Result.success(false)

		var adv3: Result
		if not state_in.sub_phase.is_empty():
			adv3 = phase_manager.advance_sub_phase(state_in)
		else:
			adv3 = phase_manager.advance_phase(state_in)
		if not adv3.ok:
			return adv3
		return Result.success(true).with_warnings(adv3.warnings)

	# Working：若当前玩家在当前子阶段无可做动作，则自动推进到下一子阶段
	if state_in.phase == DefsClass.PHASE_WORKING:
		# 先自动执行“可无参补完”的强制动作（避免其阻断子阶段 auto-advance：issue #62/#discount_manager）。
		var mandatory_r: Result = WorkingMandatoryClass.try_auto_complete_working_mandatory_actions(state_in, action_registry)
		if not mandatory_r.ok:
			return mandatory_r
		if bool(mandatory_r.value):
			return Result.success(true).with_warnings(mandatory_r.warnings)

		var order_names := phase_manager.get_working_sub_phase_order_names()
		if order_names.is_empty():
			return Result.failure("auto_advance: working_sub_phase_order 未初始化")

		var last_sub_phase: String = str(order_names[order_names.size() - 1])
		if state_in.sub_phase != last_sub_phase:
			var pid := state_in.get_current_player_id()
			if pid < 0:
				return Result.failure("auto_advance: Working 当前玩家无效")

			var initiatable: Array[String] = action_registry.get_player_initiatable_actions(state_in, pid)
			var has_real_actions := false
			for aid in initiatable:
				if aid == ActionIdsClass.SKIP or aid == ActionIdsClass.SKIP_SUB_PHASE or aid == ActionIdsClass.END_TURN or aid == ActionIdsClass.ADVANCE_PHASE:
					continue
				has_real_actions = true
				break

			if not has_real_actions:
				var adv4: Result = phase_manager.advance_sub_phase(state_in)
				if not adv4.ok:
					return adv4
				return Result.success(true).with_warnings(adv4.warnings)

	return Result.success(false)

static func _ensure_online_dinnertime_pending_guard(state_in: GameState) -> Result:
	if state_in == null:
		return Result.failure("online dinnertime guard: state 为空")
	if not _is_online_dinnertime_confirm_enabled(state_in):
		return Result.success()
	if not (state_in.players is Array):
		return Result.failure("online dinnertime guard: state.players 类型错误（期望 Array）")
	if not (state_in.round_state is Dictionary):
		return Result.failure("online dinnertime guard: state.round_state 类型错误（期望 Dictionary）")
	var players: Array = state_in.players
	var rs: Dictionary = state_in.round_state

	var confirmed_r := _read_online_dinnertime_confirmed_players_strict(state_in, players, rs)
	if not confirmed_r.ok:
		return confirmed_r
	var confirmed: Array[bool] = Array(confirmed_r.value, TYPE_BOOL, "", null)

	var expected_pending_players: Array[int] = []
	for pid in range(players.size()):
		if _is_player_forfeited(state_in, pid):
			if not bool(confirmed[pid]):
				return Result.failure("online dinnertime guard: forfeited player %d must be confirmed" % pid)
			continue
		if not bool(confirmed[pid]):
			expected_pending_players.append(pid)

	var ppa_val = rs.get("pending_phase_actions", null)
	if ppa_val != null and not (ppa_val is Dictionary):
		return Result.failure("online dinnertime guard: round_state.pending_phase_actions 类型错误（期望 Dictionary）")

	var list_val = null
	if ppa_val is Dictionary:
		list_val = Dictionary(ppa_val).get(DefsClass.PHASE_DINNERTIME, null)

	if expected_pending_players.is_empty():
		if list_val == null:
			return Result.success()
		if not (list_val is Array):
			return Result.failure("online dinnertime guard: round_state.pending_phase_actions[Dinnertime] 类型错误（期望 Array）")
		var done_list: Array = Array(list_val)
		if not done_list.is_empty():
			return Result.failure("online dinnertime guard: 全员已确认但 Dinnertime pending 仍存在: %s" % _pending_preview(done_list))
		return Result.success()

	if list_val == null:
		return Result.failure("online dinnertime guard: 缺少 round_state.pending_phase_actions[Dinnertime]")
	if not (list_val is Array):
		return Result.failure("online dinnertime guard: round_state.pending_phase_actions[Dinnertime] 类型错误（期望 Array）")

	var list: Array = Array(list_val)
	var match_r := _validate_online_dinnertime_confirm_pending_list(list, expected_pending_players)
	if not match_r.ok:
		return match_r
	return Result.success()

static func _repair_online_dinnertime_pending_guard_for_resume(state_in: GameState) -> Result:
	if state_in == null:
		return Result.failure("online dinnertime resume repair: state 为空")
	if not _is_online_dinnertime_confirm_enabled(state_in):
		return Result.success()
	if not (state_in.players is Array):
		return Result.failure("online dinnertime resume repair: state.players 类型错误（期望 Array）")
	if not (state_in.round_state is Dictionary):
		return Result.failure("online dinnertime resume repair: state.round_state 类型错误（期望 Dictionary）")
	var players: Array = state_in.players
	var rs: Dictionary = state_in.round_state

	var existing_kind := "missing"
	var existing_list: Array = []
	var ppa_val = rs.get("pending_phase_actions", null)
	if ppa_val is Dictionary:
		var ppa: Dictionary = Dictionary(ppa_val)
		var list_val = ppa.get(DefsClass.PHASE_DINNERTIME, null)
		if list_val == null:
			existing_kind = "missing"
		elif not (list_val is Array):
			existing_kind = "invalid"
		else:
			existing_list = Array(list_val)
			if existing_list.is_empty():
				existing_kind = "empty"
			elif _is_legacy_confirm_dinnertime_pending(existing_list):
				existing_kind = "legacy"
			elif _is_only_player_confirm_dinnertime_pending(existing_list):
				existing_kind = "per_player"
			else:
				existing_kind = "other"
	else:
		existing_kind = "missing"

	# 存在其它模块注入的 Dinnertime pending 时，不强行覆盖。
	if existing_kind == "other":
		return Result.success()

	var confirmed := _read_or_build_online_dinnertime_confirmed_players_for_resume(state_in, players, rs)
	if confirmed.is_empty():
		return Result.failure("online dinnertime resume repair: 无法构造 confirmed players")

	var repaired_pending: Array[Dictionary] = []
	for pid in range(players.size()):
		if bool(confirmed[pid]):
			continue
		repaired_pending.append({
			"kind": KIND_CONFIRM_DINNERTIME,
			"player_id": pid,
		})

	# 全员已确认/弃权：pending 为空是正常状态（允许 auto-advance 离开 Dinnertime）
	if repaired_pending.is_empty():
		return Result.success()

	# 若已有正确的 per-player 列表且 confirmed 同步无误，则无需写回
	if existing_kind == "per_player":
		if _list_matches_pending_players(existing_list, repaired_pending):
			var c_val = rs.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)
			if c_val is Array and _array_matches_confirmed_players(Array(c_val), confirmed):
				return Result.success()

	# 写回 confirmed + pending_phase_actions[Dinnertime]
	rs[ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY] = confirmed

	var set_r := RoundStatePendingPhaseActionsClass.set_phase_pending_players(
		rs, DefsClass.PHASE_DINNERTIME, repaired_pending, "auto_advance:dinnertime_guard"
	)
	if not set_r.ok:
		return Result.failure("online dinnertime resume repair: %s" % str(set_r.error))

	if existing_kind != "per_player":
		AutoloadAccessClass.log_warn(
			"AutoAdvance",
			"Repaired online dinnertime pending (kind=%s) round=%d confirmed=%s pending=%s"
				% [
					existing_kind,
					int(state_in.round_number),
					_bool_array_preview(confirmed),
					_pending_preview(repaired_pending),
				]
		)
	return Result.success()

static func _is_online_dinnertime_confirm_enabled(state: GameState) -> bool:
	if state == null:
		return false
	if state.rules is Dictionary:
		var rules: Dictionary = state.rules
		if rules.has(ONLINE_DINNERTIME_CONFIRM_KEY):
			return _is_truthy_marker(rules.get(ONLINE_DINNERTIME_CONFIRM_KEY, null))
	if state.round_state is Dictionary:
		var rs: Dictionary = state.round_state
		if rs.has(ONLINE_DINNERTIME_CONFIRM_KEY):
			return _is_truthy_marker(rs.get(ONLINE_DINNERTIME_CONFIRM_KEY, null))
	return false

static func _is_truthy_marker(value) -> bool:
	if value is bool:
		return bool(value)
	if value is int:
		return int(value) > 0
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return int(f) > 0
	return false

static func _read_online_dinnertime_confirmed_players_strict(state_in: GameState, players: Array, rs: Dictionary) -> Result:
	if state_in == null:
		return Result.failure("online dinnertime guard: state 为空")
	if not (players is Array):
		return Result.failure("online dinnertime guard: state.players 类型错误（期望 Array）")
	if not (rs is Dictionary):
		return Result.failure("online dinnertime guard: state.round_state 类型错误（期望 Dictionary）")
	if not rs.has(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY):
		return Result.failure("online dinnertime guard: 缺少 round_state.%s" % ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY)
	var confirmed: Array[bool] = []
	var val = rs.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)
	if not (val is Array):
		return Result.failure("online dinnertime guard: round_state.%s 类型错误（期望 Array）" % ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY)
	var raw: Array = Array(val)
	if raw.size() != players.size():
		return Result.failure("online dinnertime guard: round_state.%s 长度错误（期望 %d，实际 %d）" % [ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, players.size(), raw.size()])
	for i in range(raw.size()):
		var v = raw[i]
		if v is bool:
			confirmed.append(bool(v))
			continue
		if v is int:
			confirmed.append(int(v) != 0)
			continue
		if v is float:
			var f: float = float(v)
			if f == floor(f):
				confirmed.append(int(f) != 0)
				continue
		return Result.failure("online dinnertime guard: round_state.%s[%d] 类型错误（期望 bool/int/float）" % [ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, i])
	return Result.success(confirmed)

static func _read_or_build_online_dinnertime_confirmed_players_for_resume(state_in: GameState, players: Array, rs: Dictionary) -> Array[bool]:
	var confirmed: Array[bool] = []
	var val = rs.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)
	if val is Array:
		var raw: Array = Array(val)
		if raw.size() == players.size():
			var ok := true
			for v in raw:
				if v is bool:
					confirmed.append(bool(v))
				elif v is int:
					confirmed.append(int(v) != 0)
				elif v is float:
					var f: float = float(v)
					if f == floor(f):
						confirmed.append(int(f) != 0)
					else:
						ok = false
						break
				else:
					ok = false
					break
			if not ok:
				confirmed.clear()
	if confirmed.size() != players.size():
		confirmed.clear()
		for pid in range(players.size()):
			confirmed.append(_is_player_forfeited(state_in, pid))

	for pid2 in range(players.size()):
		if _is_player_forfeited(state_in, pid2):
			confirmed[pid2] = true
	return confirmed

static func _validate_online_dinnertime_confirm_pending_list(list: Array, expected_pending_players: Array[int]) -> Result:
	var expected := {}
	for pid in expected_pending_players:
		expected[int(pid)] = true
	var seen := {}
	for i in range(list.size()):
		var item_val = list[i]
		if not (item_val is Dictionary):
			return Result.failure("online dinnertime guard: round_state.pending_phase_actions[Dinnertime][%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val
		var kind_val = item.get("kind", null)
		if not (kind_val is String):
			return Result.failure("online dinnertime guard: round_state.pending_phase_actions[Dinnertime][%d].kind 类型错误（期望 String）" % i)
		var kind := str(kind_val).strip_edges()
		if kind != KIND_CONFIRM_DINNERTIME:
			return Result.failure("online dinnertime guard: round_state.pending_phase_actions[Dinnertime][%d].kind 非法: %s" % [i, kind])
		var pid_val = item.get("player_id", null)
		var pid := -1
		if pid_val is int:
			pid = int(pid_val)
		elif pid_val is float and float(pid_val) == floor(float(pid_val)):
			pid = int(pid_val)
		else:
			return Result.failure("online dinnertime guard: round_state.pending_phase_actions[Dinnertime][%d].player_id 类型错误（期望 int/float）" % i)
		if not expected.has(pid):
			return Result.failure("online dinnertime guard: round_state.pending_phase_actions[Dinnertime][%d].player_id 非预期: %d" % [i, pid])
		if seen.has(pid):
			return Result.failure("online dinnertime guard: round_state.pending_phase_actions[Dinnertime] 重复 player_id: %d" % pid)
		seen[pid] = true
	for pid2 in expected_pending_players:
		if not seen.has(int(pid2)):
			return Result.failure("online dinnertime guard: round_state.pending_phase_actions[Dinnertime] 缺少未确认玩家 pending: %d" % int(pid2))
	return Result.success()

static func _is_player_forfeited(state_in: GameState, player_id: int) -> bool:
	if state_in == null or not (state_in.players is Array):
		return false
	if player_id < 0 or player_id >= state_in.players.size():
		return false
	var p_val = state_in.players[player_id]
	if not (p_val is Dictionary):
		return false
	return bool(Dictionary(p_val).get("forfeited", false))

static func _is_legacy_confirm_dinnertime_pending(list: Array) -> bool:
	return list.size() == 1 and (list[0] is String) and str(list[0]) == KIND_CONFIRM_DINNERTIME

static func _is_only_player_confirm_dinnertime_pending(list: Array) -> bool:
	if list.is_empty():
		return false
	for item_val in list:
		if not (item_val is Dictionary):
			return false
		var item: Dictionary = item_val
		if str(item.get("kind", "")).strip_edges() != KIND_CONFIRM_DINNERTIME:
			return false
		var pid_val = item.get("player_id", null)
		if not (pid_val is int):
			if not (pid_val is float and float(pid_val) == floor(float(pid_val))):
				return false
	return true

static func _list_matches_pending_players(existing_list: Array, expected_list: Array) -> bool:
	if existing_list.size() != expected_list.size():
		return false
	var want := {}
	for it in expected_list:
		if not (it is Dictionary):
			continue
		var d: Dictionary = it
		want[int(d.get("player_id", -1))] = true
	for it2 in existing_list:
		if not (it2 is Dictionary):
			return false
		var d2: Dictionary = it2
		if str(d2.get("kind", "")).strip_edges() != KIND_CONFIRM_DINNERTIME:
			return false
		var pid_val2 = d2.get("player_id", null)
		var pid := -1
		if pid_val2 is int:
			pid = int(pid_val2)
		elif pid_val2 is float and float(pid_val2) == floor(float(pid_val2)):
			pid = int(pid_val2)
		if pid < 0 or not want.has(pid):
			return false
	return true

static func _array_matches_confirmed_players(raw: Array, expected: Array[bool]) -> bool:
	if raw.size() != expected.size():
		return false
	for i in range(raw.size()):
		var v = raw[i]
		var b := false
		if v is bool:
			b = bool(v)
		elif v is int:
			b = int(v) != 0
		elif v is float:
			var f: float = float(v)
			if f == floor(f):
				b = int(f) != 0
			else:
				return false
		else:
			return false
		if b != bool(expected[i]):
			return false
	return true

static func _bool_array_preview(arr: Array, limit: int = 12) -> String:
	if arr == null:
		return "null"
	var parts: Array[String] = []
	for i in range(min(arr.size(), limit)):
		parts.append("1" if bool(arr[i]) else "0")
	var suffix := "..." if arr.size() > parts.size() else ""
	return "%d[%s%s]" % [arr.size(), "".join(parts), suffix]

static func _pending_preview(pending: Array, limit: int = 6) -> String:
	if pending == null:
		return "null"
	var parts: Array[String] = []
	for i in range(min(pending.size(), limit)):
		var it = pending[i]
		if it is String:
			parts.append(str(it))
		elif it is Dictionary:
			var d: Dictionary = it
			parts.append("%s:%s" % [str(d.get("kind", "?")), str(d.get("player_id", "?"))])
		else:
			parts.append(str(typeof(it)))
	var suffix := "..." if pending.size() > parts.size() else ""
	return "len=%d [%s%s]" % [pending.size(), ", ".join(parts), suffix]
