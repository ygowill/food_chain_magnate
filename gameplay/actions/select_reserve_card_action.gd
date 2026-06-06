# 选择银行储备卡动作（Setup）
# 规则：储备卡对其他玩家保密；进入游戏后、起始餐厅放置前，每位玩家必须秘密选择一次。
class_name SelectReserveCardAction
extends ActionExecutor

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")
const SETUP_SUB_PHASE := DefsClass.SUB_PHASE_RESERVE_CARDS
const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"
const ONLINE_MARKETING_CONFIRM_KEY := "online_require_marketing_confirm"

func _init() -> void:
	action_id = "select_reserve_card"
	display_name = "选择储备卡"
	description = "在设置阶段秘密选择银行储备卡"
	requires_actor = true
	is_mandatory = false
	is_internal = true # 由强制弹窗驱动，不在 ActionPanel 中展示
	allowed_phases = [DefsClass.PHASE_SETUP]
	allowed_sub_phases = [SETUP_SUB_PHASE]

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if state.phase != DefsClass.PHASE_SETUP:
		return Result.failure("当前不在 Setup，无法选择储备卡")
	if state.sub_phase != SETUP_SUB_PHASE:
		return Result.failure("当前不在储备卡选择阶段")

	if not _is_parallel_reserve_selection_enabled(state):
		var current_player_id := state.get_current_player_id()
		if command.actor != current_player_id:
			return Result.failure("不是你的回合")

	if command.actor < 0 or command.actor >= state.players.size():
		return Result.failure("无效的玩家ID: %d" % command.actor)
	var p_val = state.players[command.actor]
	if not (p_val is Dictionary):
		return Result.failure("players[%d] 类型错误（期望 Dictionary）" % command.actor)
	var player: Dictionary = p_val

	var cards_val = player.get("reserve_cards", null)
	if not (cards_val is Array):
		return Result.failure("player.reserve_cards 缺失或类型错误（期望 Array）")
	var cards: Array = cards_val
	if cards.is_empty():
		return Result.failure("player.reserve_cards 不能为空")

	var pending_read := _get_reserve_card_pending_players(state)
	if not pending_read.ok:
		return pending_read
	var pending: Array[int] = pending_read.value
	if not pending.has(command.actor):
		if _has_selected(player):
			return Result.failure("你已选择过储备卡")
		return Result.failure("玩家 %d 当前无需选择储备卡" % command.actor)

	if _has_selected(player):
		return Result.failure("你已选择过储备卡")

	var sel_result := require_int_param(command, "selected_index")
	if not sel_result.ok:
		return sel_result
	var selected_index: int = sel_result.value
	if selected_index < 0 or selected_index >= cards.size():
		return Result.failure("selected_index 越界: %d (cards=%d)" % [selected_index, cards.size()])

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var parallel_selection := _is_parallel_reserve_selection_enabled(state)
	var has_explicit_pending := _has_explicit_setup_pending(state)
	var pending_read := _get_reserve_card_pending_players(state)
	if not pending_read.ok:
		return pending_read
	var pending: Array[int] = pending_read.value
	if not pending.has(command.actor):
		return Result.failure("玩家 %d 当前无需选择储备卡" % command.actor)

	var sel_result := require_int_param(command, "selected_index")
	if not sel_result.ok:
		return sel_result
	var selected_index: int = sel_result.value

	var player: Dictionary = state.get_player(command.actor)
	if player.is_empty():
		return Result.failure("player 不存在: %d" % command.actor)
	var cards_val = player.get("reserve_cards", null)
	if not (cards_val is Array):
		return Result.failure("player.reserve_cards 缺失或类型错误（期望 Array）")
	var cards: Array = cards_val
	if selected_index < 0 or selected_index >= cards.size():
		return Result.failure("selected_index 越界: %d (cards=%d)" % [selected_index, cards.size()])

	player["reserve_card_selected"] = selected_index
	player["reserve_card_revealed"] = false
	state.players[command.actor] = player

	var remaining := _remove_pending_player(pending, command.actor)
	if parallel_selection or has_explicit_pending:
		var set_pending := RoundStatePendingPhaseActionsClass.set_phase_pending_players(
			state.round_state,
			DefsClass.PHASE_SETUP,
			remaining,
			"select_reserve_card"
		)
		if not set_pending.ok:
			return set_pending

	if not remaining.is_empty():
		if parallel_selection:
			var pending_idx := _find_first_pending_turn_index(state, remaining)
			if pending_idx != -1:
				state.current_player_index = pending_idx
		else:
			var next_idx := _find_next_unselected_turn_index(state, int(state.current_player_index))
			if next_idx != -1:
				state.current_player_index = next_idx
		return Result.success({
			"player_id": command.actor,
			"selected_index": selected_index,
			"next_player_id": state.get_current_player_id(),
		})

	state.sub_phase = ""
	state.current_player_index = max(0, state.turn_order.size() - 1)
	return Result.success({
		"player_id": command.actor,
		"selected_index": selected_index,
		"all_selected": true,
	})

static func _has_selected(player: Dictionary) -> bool:
	if not player.has("reserve_card_selected"):
		return false
	var v = player.get("reserve_card_selected", -1)
	if v is int:
		return int(v) >= 0
	if v is float:
		var f: float = float(v)
		return f == floor(f) and int(f) >= 0
	return false

static func _get_reserve_card_pending_players(state: GameState) -> Result:
	if state == null:
		return Result.failure("select_reserve_card: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("select_reserve_card: round_state 类型错误（期望 Dictionary）")

	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if ppa_val != null:
		if not (ppa_val is Dictionary):
			return Result.failure("select_reserve_card: round_state.pending_phase_actions 类型错误（期望 Dictionary）")
		var ppa: Dictionary = ppa_val
		if ppa.has(DefsClass.PHASE_SETUP):
			var list_val = ppa.get(DefsClass.PHASE_SETUP, null)
			if not (list_val is Array):
				return Result.failure("select_reserve_card: round_state.pending_phase_actions[Setup] 类型错误（期望 Array）")
			return _parse_pending_player_list(state, list_val)

	return Result.success(_build_unselected_players_in_turn_order(state))

static func _has_explicit_setup_pending(state: GameState) -> bool:
	if state == null or not (state.round_state is Dictionary):
		return false
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	return ppa_val is Dictionary and Dictionary(ppa_val).has(DefsClass.PHASE_SETUP)

static func _parse_pending_player_list(state: GameState, list_val: Array) -> Result:
	var out: Array[int] = []
	var seen := {}
	for i in range(list_val.size()):
		var item_val = list_val[i]
		if not (item_val is int or item_val is float):
			return Result.failure("select_reserve_card: round_state.pending_phase_actions[Setup][%d] 类型错误（期望 int/float）" % i)
		if item_val is float and float(item_val) != floor(float(item_val)):
			return Result.failure("select_reserve_card: round_state.pending_phase_actions[Setup][%d] 必须为整数" % i)
		var pid := int(item_val)
		if pid < 0 or pid >= state.players.size():
			return Result.failure("select_reserve_card: round_state.pending_phase_actions[Setup][%d] 玩家越界: %d" % [i, pid])
		if seen.has(pid):
			return Result.failure("select_reserve_card: round_state.pending_phase_actions[Setup] 重复玩家: %d" % pid)
		seen[pid] = true
		out.append(pid)
	return Result.success(out)

static func _build_unselected_players_in_turn_order(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if state == null:
		return out
	var seen := {}
	for pid_val in Array(state.turn_order):
		if not (pid_val is int or pid_val is float):
			continue
		if pid_val is float and float(pid_val) != floor(float(pid_val)):
			continue
		var pid := int(pid_val)
		if pid < 0 or pid >= state.players.size() or seen.has(pid):
			continue
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			continue
		if not _has_selected(p_val):
			seen[pid] = true
			out.append(pid)
	for pid2 in range(state.players.size()):
		if seen.has(pid2):
			continue
		var p2_val = state.players[pid2]
		if not (p2_val is Dictionary):
			continue
		if not _has_selected(p2_val):
			seen[pid2] = true
			out.append(pid2)
	return out

static func _remove_pending_player(pending: Array[int], player_id: int) -> Array[int]:
	var remaining: Array[int] = []
	for pid in pending:
		if int(pid) == int(player_id):
			continue
		remaining.append(int(pid))
	return remaining

static func _find_first_pending_turn_index(state: GameState, pending: Array[int]) -> int:
	if state == null or pending.is_empty():
		return -1
	for i in range(state.turn_order.size()):
		var pid_val = state.turn_order[i]
		if pid_val is int or pid_val is float:
			var pid := int(pid_val)
			if pending.has(pid):
				return i
	return -1

static func _is_parallel_reserve_selection_enabled(state: GameState) -> bool:
	if state != null and state.rules is Dictionary:
		var rules: Dictionary = state.rules
		if _is_truthy_marker(rules.get(ONLINE_DINNERTIME_CONFIRM_KEY, null)) and _is_truthy_marker(rules.get(ONLINE_MARKETING_CONFIRM_KEY, null)):
			return true
	if NetContext != null:
		return NetContext.mode == NetContext.Mode.ONLINE_CLIENT or NetContext.mode == NetContext.Mode.ONLINE_SERVER
	return false

static func _is_truthy_marker(value) -> bool:
	if value is bool:
		return bool(value)
	if value is int:
		return int(value) > 0
	if value is float:
		var f: float = float(value)
		return f == floor(f) and int(f) > 0
	return false

static func _find_next_unselected_turn_index(state: GameState, current_index: int) -> int:
	if state == null:
		return -1
	if not (state.turn_order is Array):
		return -1
	var size := state.turn_order.size()
	if size <= 0:
		return -1
	if current_index < 0 or current_index >= size:
		current_index = 0

	for offset in range(1, size + 1):
		var idx := current_index + offset
		if idx >= size:
			idx = idx % size
		var pid_val = state.turn_order[idx]
		if not (pid_val is int):
			continue
		var pid: int = int(pid_val)
		if pid < 0 or pid >= state.players.size():
			continue
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			continue
		var player: Dictionary = p_val
		if not _has_selected(player):
			return idx

	return -1
