# ConfirmMarketingAction：pending_phase_actions 的 key 必须与阶段名一致（Marketing），否则会导致 auto-advance 误跳过
class_name ConfirmMarketingPendingPhaseActionsKeyTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ConfirmMarketingActionClass = preload("res://gameplay/actions/confirm_marketing_action.gd")
const ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY := "online_marketing_confirmed_players"

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var legacy_r := _case_legacy_global_confirm(player_count, seed_val)
	if not legacy_r.ok:
		return legacy_r
	var online_like_r := _case_per_player_confirm(player_count, seed_val)
	if not online_like_r.ok:
		return online_like_r
	var recover_r := _case_confirmed_players_recovers_missing_pending(player_count, seed_val)
	if not recover_r.ok:
		return recover_r
	return Result.success()

static func _case_legacy_global_confirm(player_count: int, seed_val: int) -> Result:
	var state_read := _build_marketing_state(player_count, seed_val)
	if not state_read.ok:
		return state_read
	var state: GameState = state_read.value
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_MARKETING: ["confirm_marketing"],
	}

	var action := ConfirmMarketingActionClass.new()
	var cmd := Command.create_system("confirm_marketing")
	var new_state_r: Result = action.compute_new_state(state, cmd)
	if not new_state_r.ok:
		return Result.failure("legacy confirm_marketing 计算新状态失败: %s" % new_state_r.error)

	return _assert_marketing_pending_phase_key_cleared(new_state_r.value, "legacy")

static func _case_per_player_confirm(player_count: int, seed_val: int) -> Result:
	var state_read := _build_marketing_state(player_count, seed_val)
	if not state_read.ok:
		return state_read
	var state: GameState = state_read.value
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_MARKETING: [
			{"kind": "confirm_marketing", "player_id": 0},
			{"kind": "confirm_marketing", "player_id": 1},
		],
	}

	var action := ConfirmMarketingActionClass.new()
	var first_r: Result = action.compute_new_state(state, Command.create("confirm_marketing", 0, {}))
	if not first_r.ok:
		return Result.failure("per_player confirm_marketing(0) 失败: %s" % first_r.error)

	var first_state: GameState = first_r.value
	if not (first_state.round_state is Dictionary):
		return Result.failure("per_player 第一次确认后 round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = first_state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("per_player 第一次确认后 pending_phase_actions 类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val
	if not ppa.has(DefsClass.PHASE_MARKETING):
		return Result.failure("per_player 第一次确认后应保留 Marketing pending（等待其它玩家）")
	var list_val = ppa.get(DefsClass.PHASE_MARKETING, null)
	if not (list_val is Array):
		return Result.failure("per_player 第一次确认后 pending_phase_actions[Marketing] 类型错误（期望 Array）")
	var list: Array = list_val
	if list.size() != 1 or not (list[0] is Dictionary):
		return Result.failure("per_player 第一次确认后应仅剩 1 条玩家待确认，实际: %s" % str(list))
	var item: Dictionary = list[0]
	if str(item.get("kind", "")) != "confirm_marketing":
		return Result.failure("per_player 第一次确认后 kind 错误: %s" % str(item.get("kind", null)))
	if int(item.get("player_id", -1)) != 1:
		return Result.failure("per_player 第一次确认后应剩 player_id=1，实际: %s" % str(item.get("player_id", null)))

	var second_r: Result = action.compute_new_state(first_state, Command.create("confirm_marketing", 1, {}))
	if not second_r.ok:
		return Result.failure("per_player confirm_marketing(1) 失败: %s" % second_r.error)

	return _assert_marketing_pending_phase_key_cleared(second_r.value, "per_player")

static func _case_confirmed_players_recovers_missing_pending(player_count: int, seed_val: int) -> Result:
	if player_count < 2:
		return Result.success()
	var state_read := _build_marketing_state(player_count, seed_val)
	if not state_read.ok:
		return state_read
	var state: GameState = state_read.value
	var confirmed: Array = []
	for _i in range(player_count):
		confirmed.append(false)
	state.round_state[ONLINE_MARKETING_CONFIRMED_PLAYERS_KEY] = confirmed
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_MARKETING: [
			{"kind": "confirm_marketing", "player_id": 0},
		],
	}

	var action := ConfirmMarketingActionClass.new()
	var first_r: Result = action.compute_new_state(state, Command.create("confirm_marketing", 0, {}))
	if not first_r.ok:
		return Result.failure("recover_missing_pending confirm_marketing(0) 失败: %s" % first_r.error)

	var first_state: GameState = first_r.value
	if not (first_state.round_state is Dictionary):
		return Result.failure("recover_missing_pending 第一次确认后 round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = first_state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("recover_missing_pending 第一次确认后 pending_phase_actions 类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val
	if not ppa.has(DefsClass.PHASE_MARKETING):
		return Result.failure("recover_missing_pending 应恢复其它玩家的待确认项，但 Marketing key 缺失")
	var list_val = ppa.get(DefsClass.PHASE_MARKETING, null)
	if not (list_val is Array):
		return Result.failure("recover_missing_pending pending_phase_actions[Marketing] 类型错误（期望 Array）")
	var list: Array = list_val
	if list.size() != player_count - 1:
		return Result.failure(
			"recover_missing_pending 恢复后的待确认数量错误（期望 %d，实际 %d）"
				% [player_count - 1, list.size()]
		)
	for pid in range(1, player_count):
		if not _list_has_player_pending_confirm(list, pid):
			return Result.failure("recover_missing_pending 应包含 player_id=%d 的待确认项，实际: %s" % [pid, str(list)])

	var second_r: Result = action.compute_new_state(first_state, Command.create("confirm_marketing", 1, {}))
	if not second_r.ok:
		return Result.failure("recover_missing_pending confirm_marketing(1) 失败: %s" % second_r.error)
	return Result.success()

static func _build_marketing_state(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.state
	state.phase = DefsClass.PHASE_MARKETING
	state.sub_phase = ""
	if not (state.round_state is Dictionary):
		state.round_state = {}
	return Result.success(state)

static func _assert_marketing_pending_phase_key_cleared(state: GameState, case_name: String) -> Result:
	if not (state.round_state is Dictionary):
		return Result.failure("%s: confirm_marketing 后 round_state 类型错误（期望 Dictionary）" % case_name)
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("%s: confirm_marketing 后 pending_phase_actions 类型错误（期望 Dictionary）" % case_name)
	var ppa: Dictionary = ppa_val
	if ppa.has(DefsClass.PHASE_MARKETING):
		return Result.failure("%s: confirm_marketing 后 pending_phase_actions[Marketing] 应被清除" % case_name)
	if ppa.has("marketing"):
		return Result.failure("%s: confirm_marketing 不应写入 pending_phase_actions[marketing]（大小写错误）" % case_name)
	return Result.success()

static func _list_has_player_pending_confirm(list: Array, player_id: int) -> bool:
	for item_val in list:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("kind", "")) != "confirm_marketing":
			continue
		if int(item.get("player_id", -1)) == player_id:
			return true
	return false
