class_name ReserveCardsOverviewAccessTest
extends RefCounted

const ReserveCardsViewDataClass = preload("res://ui/components/reserve_cards/reserve_cards_view_data.gd")

static func run(seed_val: int = 12345) -> Result:
	var prev_mode = NetContext.mode if NetContext != null else 0
	var prev_local_player_id := int(NetContext.local_player_id) if NetContext != null else -1

	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return _finish(Result.failure("初始化失败: %s" % init.error), engine, prev_mode, prev_local_player_id)

	var state := engine.get_state()
	if state == null:
		return _finish(Result.failure("state 为空"), engine, prev_mode, prev_local_player_id)

	state.phase = "Payday"
	state.turn_order = [0, 1]
	state.current_player_index = 0
	state.players[0]["can_peek_all_reserve_cards"] = false
	state.players[1]["can_peek_all_reserve_cards"] = false

	if not ReserveCardsViewDataClass.viewer_has_overview_access(state):
		return _finish(Result.failure("非晚餐阶段应允许打开储备卡总览"), engine, prev_mode, prev_local_player_id)

	state.players[0]["can_peek_all_reserve_cards"] = true
	if not ReserveCardsViewDataClass.viewer_has_overview_access(state):
		return _finish(Result.failure("触发里程碑后应允许当前玩家打开储备卡总览"), engine, prev_mode, prev_local_player_id)

	state.phase = "Dinnertime"
	if ReserveCardsViewDataClass.viewer_has_overview_access(state):
		return _finish(Result.failure("晚餐阶段中不应允许打开储备卡总览"), engine, prev_mode, prev_local_player_id)

	if NetContext != null:
		NetContext.mode = NetContext.Mode.ONLINE_CLIENT
		NetContext.local_player_id = 1
	state.phase = "Payday"
	state.players[1]["can_peek_all_reserve_cards"] = false
	if not ReserveCardsViewDataClass.viewer_has_overview_access(state):
		return _finish(Result.failure("联机下本地玩家未触发里程碑时仍应允许打开储备卡总览"), engine, prev_mode, prev_local_player_id)

	if NetContext != null:
		NetContext.local_player_id = 0
	if not ReserveCardsViewDataClass.viewer_has_overview_access(state):
		return _finish(Result.failure("联机下本地玩家触发里程碑后应允许打开储备卡总览"), engine, prev_mode, prev_local_player_id)

	return _finish(Result.success({}), engine, prev_mode, prev_local_player_id)

static func _finish(result: Result, engine, prev_mode, prev_local_player_id: int) -> Result:
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	if NetContext != null:
		NetContext.mode = prev_mode
		NetContext.local_player_id = prev_local_player_id
	return result
