class_name ReserveCardsOverviewAccessTest
extends RefCounted

const ReserveCardsViewDataClass = preload("res://ui/components/reserve_cards/reserve_cards_view_data.gd")
const FIRST_HAVE_20_SAVE_PATH := "res://testdata/saves/manual_cases/milestones/first_have_20.json"

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

	var manual_r := _validate_first_have_20_manual_save(prev_mode, prev_local_player_id)
	if not manual_r.ok:
		return _finish(manual_r, engine, prev_mode, prev_local_player_id)

	return _finish(Result.success({}), engine, prev_mode, prev_local_player_id)

static func _validate_first_have_20_manual_save(prev_mode, prev_local_player_id: int) -> Result:
	var engine := GameEngine.new()
	var load_r := engine.load_from_file(ProjectSettings.globalize_path(FIRST_HAVE_20_SAVE_PATH))
	if not load_r.ok:
		return _finish(Result.failure("first_have_20 手工存档加载失败: %s" % load_r.error), engine, prev_mode, prev_local_player_id)
	var state := engine.get_state()
	if state == null:
		return _finish(Result.failure("first_have_20 手工存档 state 为空"), engine, prev_mode, prev_local_player_id)
	if not bool(state.players[0].get("can_peek_all_reserve_cards", false)):
		return _finish(Result.failure("first_have_20 手工存档玩家0 应可查看全部储备卡"), engine, prev_mode, prev_local_player_id)

	var sections := ReserveCardsViewDataClass.build_player_sections(state, 0)
	if sections.size() != state.players.size():
		return _finish(Result.failure("first_have_20 储备卡总览玩家区块数量错误: %d" % sections.size()), engine, prev_mode, prev_local_player_id)
	for section_val in sections:
		if not (section_val is Dictionary):
			return _finish(Result.failure("first_have_20 储备卡区块类型错误"), engine, prev_mode, prev_local_player_id)
		var section: Dictionary = section_val
		var cards_val = section.get("cards", null)
		if not (cards_val is Array) or Array(cards_val).is_empty():
			return _finish(Result.failure("first_have_20 储备卡区块缺少卡片: %s" % str(section)), engine, prev_mode, prev_local_player_id)
		var card_val = Array(cards_val)[0]
		if not (card_val is Dictionary):
			return _finish(Result.failure("first_have_20 储备卡条目类型错误"), engine, prev_mode, prev_local_player_id)
		var card: Dictionary = card_val
		if not bool(card.get("visible", false)):
			return _finish(Result.failure("first_have_20 玩家0 视角应看到玩家 %d 储备卡" % int(section.get("player_id", -1))), engine, prev_mode, prev_local_player_id)
		if str(card.get("image_path", "")).strip_edges().is_empty():
			return _finish(Result.failure("first_have_20 可见储备卡应带卡图路径"), engine, prev_mode, prev_local_player_id)
	return _finish(Result.success({}), engine, prev_mode, prev_local_player_id)

static func _finish(result: Result, engine, prev_mode, prev_local_player_id: int) -> Result:
	if engine != null and engine.has_method("dispose"):
		engine.dispose()
	if NetContext != null:
		NetContext.mode = prev_mode
		NetContext.local_player_id = prev_local_player_id
	return result
