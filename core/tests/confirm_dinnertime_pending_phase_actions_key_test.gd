# ConfirmDinnertimeAction：pending_phase_actions 的 key 必须与阶段名一致（Dinnertime），否则会导致 auto-advance 误跳过
class_name ConfirmDinnertimePendingPhaseActionsKeyTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ConfirmDinnertimeActionClass = preload("res://gameplay/actions/confirm_dinnertime_action.gd")
const ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY := "online_dinnertime_confirmed_players"

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var legacy_r := _case_legacy_global_confirm_rejected(player_count, seed_val)
	if not legacy_r.ok:
		return legacy_r
	var online_like_r := _case_per_player_confirm(player_count, seed_val)
	if not online_like_r.ok:
		return online_like_r
	var missing_pending_r := _case_confirmed_players_rejects_missing_pending(player_count, seed_val)
	if not missing_pending_r.ok:
		return missing_pending_r
	return Result.success()

static func _case_legacy_global_confirm_rejected(player_count: int, seed_val: int) -> Result:
	var state_read := _build_dinnertime_state(player_count, seed_val)
	if not state_read.ok:
		return state_read
	var state: GameState = state_read.value
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_DINNERTIME: ["confirm_dinnertime"],
	}

	var action := ConfirmDinnertimeActionClass.new()
	var cmd := Command.create_system("confirm_dinnertime")
	var new_state_r: Result = action.compute_new_state(state, cmd)
	if new_state_r.ok:
		return Result.failure("legacy global confirm_dinnertime pending 应被拒绝")
	if str(new_state_r.error).find("legacy global") < 0:
		return Result.failure("legacy global confirm_dinnertime 错误信息不明确: %s" % new_state_r.error)

	return Result.success()

static func _case_per_player_confirm(player_count: int, seed_val: int) -> Result:
	var state_read := _build_dinnertime_state(player_count, seed_val)
	if not state_read.ok:
		return state_read
	var state: GameState = state_read.value
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_DINNERTIME: [
			{"kind": "confirm_dinnertime", "player_id": 0},
			{"kind": "confirm_dinnertime", "player_id": 1},
		],
	}

	var action := ConfirmDinnertimeActionClass.new()
	var first_r: Result = action.compute_new_state(state, Command.create("confirm_dinnertime", 0, {}))
	if not first_r.ok:
		return Result.failure("per_player confirm_dinnertime(0) 失败: %s" % first_r.error)

	var first_state: GameState = first_r.value
	if not (first_state.round_state is Dictionary):
		return Result.failure("per_player 第一次确认后 round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = first_state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("per_player 第一次确认后 pending_phase_actions 类型错误（期望 Dictionary）")
	var ppa: Dictionary = ppa_val
	if not ppa.has(DefsClass.PHASE_DINNERTIME):
		return Result.failure("per_player 第一次确认后应保留 Dinnertime pending（等待其它玩家）")
	var list_val = ppa.get(DefsClass.PHASE_DINNERTIME, null)
	if not (list_val is Array):
		return Result.failure("per_player 第一次确认后 pending_phase_actions[Dinnertime] 类型错误（期望 Array）")
	var list: Array = list_val
	if list.size() != 1 or not (list[0] is Dictionary):
		return Result.failure("per_player 第一次确认后应仅剩 1 条玩家待确认，实际: %s" % str(list))
	var item: Dictionary = list[0]
	if str(item.get("kind", "")) != "confirm_dinnertime":
		return Result.failure("per_player 第一次确认后 kind 错误: %s" % str(item.get("kind", null)))
	if int(item.get("player_id", -1)) != 1:
		return Result.failure("per_player 第一次确认后应剩 player_id=1，实际: %s" % str(item.get("player_id", null)))

	var second_r: Result = action.compute_new_state(first_state, Command.create("confirm_dinnertime", 1, {}))
	if not second_r.ok:
		return Result.failure("per_player confirm_dinnertime(1) 失败: %s" % second_r.error)

	return _assert_dinnertime_pending_phase_key_cleared(second_r.value, "per_player")

static func _case_confirmed_players_rejects_missing_pending(player_count: int, seed_val: int) -> Result:
	if player_count < 2:
		return Result.success()
	var state_read := _build_dinnertime_state(player_count, seed_val)
	if not state_read.ok:
		return state_read
	var state: GameState = state_read.value
	var confirmed: Array = []
	for _i in range(player_count):
		confirmed.append(false)
	state.round_state[ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY] = confirmed
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_DINNERTIME: [
			{"kind": "confirm_dinnertime", "player_id": 0},
		],
	}
	var pending_before := str(state.round_state.get("pending_phase_actions", null))
	var confirmed_before := str(state.round_state.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null))

	var action := ConfirmDinnertimeActionClass.new()
	var first_r: Result = action.compute_new_state(state, Command.create("confirm_dinnertime", 0, {}))
	if first_r.ok:
		return Result.failure("confirmed_players 与 pending 不一致时不应恢复 missing pending")
	if str(first_r.error).find("缺少未确认玩家 pending") < 0:
		return Result.failure("missing pending 错误信息不明确: %s" % first_r.error)
	if str(state.round_state.get("pending_phase_actions", null)) != pending_before:
		return Result.failure("失败时不应改写 pending_phase_actions")
	if str(state.round_state.get(ONLINE_DINNERTIME_CONFIRMED_PLAYERS_KEY, null)) != confirmed_before:
		return Result.failure("失败时不应改写 online_dinnertime_confirmed_players")
	return Result.success()

static func _build_dinnertime_state(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	var state: GameState = engine.state
	state.phase = DefsClass.PHASE_DINNERTIME
	state.sub_phase = ""
	if not (state.round_state is Dictionary):
		state.round_state = {}
	return Result.success(state)

static func _assert_dinnertime_pending_phase_key_cleared(state: GameState, case_name: String) -> Result:
	if not (state.round_state is Dictionary):
		return Result.failure("%s: confirm_dinnertime 后 round_state 类型错误（期望 Dictionary）" % case_name)
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("%s: confirm_dinnertime 后 pending_phase_actions 类型错误（期望 Dictionary）" % case_name)
	var ppa: Dictionary = ppa_val
	if ppa.has(DefsClass.PHASE_DINNERTIME):
		return Result.failure("%s: confirm_dinnertime 后 pending_phase_actions[Dinnertime] 应被清除" % case_name)
	if ppa.has("dinnertime"):
		return Result.failure("%s: confirm_dinnertime 不应写入 pending_phase_actions[dinnertime]（大小写错误）" % case_name)
	return Result.success()
