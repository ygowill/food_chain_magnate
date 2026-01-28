# 选择银行储备卡动作（Setup）
# 规则：储备卡对其他玩家保密；进入游戏后、起始餐厅放置前，每位玩家必须秘密选择一次。
class_name SelectReserveCardAction
extends ActionExecutor

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SETUP_SUB_PHASE := DefsClass.SUB_PHASE_RESERVE_CARDS

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

	# 找下一位未选择的玩家（按 turn_order 顺序）。若全员已选，则进入起始餐厅放置阶段。
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
