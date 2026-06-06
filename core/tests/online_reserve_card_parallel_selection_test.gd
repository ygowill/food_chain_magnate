# Online reserve cards: players may choose their own starting reserve card in parallel.
class_name OnlineReserveCardParallelSelectionTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ONLINE_DINNERTIME_CONFIRM_KEY := "online_require_dinnertime_confirm"
const ONLINE_MARKETING_CONFIRM_KEY := "online_require_marketing_confirm"

static func run(seed_val: int = 12345) -> Result:
	_reset_net_context()

	var local_serial_r := _test_local_reserve_cards_still_follow_current_player(seed_val)
	if not local_serial_r.ok:
		_reset_net_context()
		return local_serial_r

	var online_parallel_r := _test_online_reserve_cards_allow_non_current_pending_player(seed_val)
	_reset_net_context()
	return online_parallel_r

static func _test_local_reserve_cards_still_follow_current_player(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("local 初始化失败: %s" % init.error)
	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("local state 为空")
	var current_pid := int(state.get_current_player_id())
	var other_pid := 1 if current_pid == 0 else 0
	var out_of_turn := engine.execute_command(Command.create("select_reserve_card", other_pid, {"selected_index": 0}))
	if out_of_turn.ok:
		return Result.failure("本地热座模式不应允许非当前玩家先选储备卡")
	if str(out_of_turn.error).find("不是你的回合") < 0:
		return Result.failure("本地非当前玩家错误信息不明确: %s" % out_of_turn.error)
	return Result.success()

static func _test_online_reserve_cards_allow_non_current_pending_player(seed_val: int) -> Result:
	if NetContext != null:
		NetContext.mode = NetContext.Mode.ONLINE_CLIENT
		NetContext.local_player_id = 1

	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("online 初始化失败: %s" % init.error)
	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("online state 为空")
	state.rules[ONLINE_DINNERTIME_CONFIRM_KEY] = 1
	state.rules[ONLINE_MARKETING_CONFIRM_KEY] = 1
	state.round_state["pending_phase_actions"] = {
		DefsClass.PHASE_SETUP: Array(state.turn_order).duplicate(),
	}

	if not OnlinePhaseInteraction.is_online_parallel_phase(state):
		return Result.failure("Setup/ReserveCards 应被视为联机并行阶段")

	var current_pid := int(state.get_current_player_id())
	var other_pid := 1 if current_pid == 0 else 0
	if NetContext != null:
		NetContext.local_player_id = other_pid
	if not OnlinePhaseInteraction.can_local_player_act_in_online_phase(state):
		return Result.failure("联机本地玩家在储备卡 pending 中时应可操作")

	var other_pick := engine.execute_command(Command.create("select_reserve_card", other_pid, {"selected_index": 0}))
	if not other_pick.ok:
		return Result.failure("联机非当前 pending 玩家应可先选择储备卡: %s" % other_pick.error)

	state = engine.get_state()
	if int(Dictionary(state.players[other_pid]).get("reserve_card_selected", -1)) != 0:
		return Result.failure("非当前玩家储备卡选择未落地")
	if OnlinePhaseInteraction.can_player_act_in_online_reserve_cards(state, other_pid):
		return Result.failure("已选择玩家不应仍可操作储备卡选择")
	if str(state.sub_phase) != DefsClass.SUB_PHASE_RESERVE_CARDS:
		return Result.failure("仍有玩家未选时应停留在 ReserveCards，实际: %s" % str(state.sub_phase))

	var current_pick := engine.execute_command(Command.create("select_reserve_card", current_pid, {"selected_index": 1}))
	if not current_pick.ok:
		return Result.failure("剩余玩家选择储备卡失败: %s" % current_pick.error)

	state = engine.get_state()
	if str(state.phase) != DefsClass.PHASE_SETUP:
		return Result.failure("完成储备卡后仍应处于 Setup，实际: %s" % str(state.phase))
	if str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
		return Result.failure("全员选择后应离开 ReserveCards")
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if ppa_val is Dictionary and Dictionary(ppa_val).has(DefsClass.PHASE_SETUP):
		return Result.failure("全员选择后不应残留 pending_phase_actions[Setup]")
	return Result.success()

static func _reset_net_context() -> void:
	if NetContext != null and NetContext.has_method("reset"):
		NetContext.reset()
