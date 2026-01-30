# Rewind turn-start setup turn-switch test
# 目的：Setup 阶段中同一玩家会经历多次“轮到我”（ReserveCards 选择 → 起始餐厅放置）。
# 此时“回退到当前玩家回合开始”应回到“最近一次 turn start”，而不是回退到更早的 ReserveCards 选择点。
class_name RewindTurnStartSetupTurnSwitchTest
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")

static func run(seed: int = 12345) -> Result:
	if EventBus == null:
		return Result.failure("EventBus is not available")

	_clear_event_history()

	var engine := GameEngine.new()
	var init := engine.initialize(2, seed)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("state 为空")
	if str(state.phase) != DefsClass.PHASE_SETUP:
		return Result.failure("初始 phase 非 Setup（当前=%s）" % str(state.phase))
	if str(state.sub_phase) != DefsClass.SUB_PHASE_RESERVE_CARDS:
		return Result.failure("初始 sub_phase 非 ReserveCards（当前=%s）" % str(state.sub_phase))

	# 2P：依次完成 ReserveCards
	var pid_a := int(state.get_current_player_id())
	var pick_a := engine.execute_command(Command.create("select_reserve_card", pid_a, {"selected_index": 0}))
	if not pick_a.ok:
		return Result.failure("select_reserve_card(P%d) 失败: %s" % [pid_a + 1, pick_a.error])

	state = engine.get_state()
	var pid_b := int(state.get_current_player_id())
	if pid_b == pid_a:
		return Result.failure("ReserveCards 未切换当前玩家（pid=%d）" % pid_a)

	var pick_b := engine.execute_command(Command.create("select_reserve_card", pid_b, {"selected_index": 0}))
	if not pick_b.ok:
		return Result.failure("select_reserve_card(P%d) 失败: %s" % [pid_b + 1, pick_b.error])

	state = engine.get_state()
	if state == null:
		return Result.failure("state 为空（after ReserveCards）")
	if str(state.phase) != DefsClass.PHASE_SETUP:
		return Result.failure("完成 ReserveCards 后仍应在 Setup（当前=%s）" % str(state.phase))
	if str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
		return Result.failure("完成 ReserveCards 后应离开 ReserveCards（仍为 %s）" % str(state.sub_phase))

	# 此时刚进入“起始餐厅放置”流程：应视为 turn start。
	var expected_turn_start := int(engine.current_command_index)

	var idx_r: Result = engine.find_current_player_turn_start_command_index()
	if not idx_r.ok:
		return Result.failure("find_current_player_turn_start_command_index 失败: %s" % idx_r.error)
	if int(idx_r.value) != expected_turn_start:
		return Result.failure("turn_start_index 错误（before place）：got=%d want=%d" % [int(idx_r.value), expected_turn_start])

	# 放置 1 个餐厅后，turn_start 不应回退到 ReserveCards，而应仍是该放置回合的起点。
	var pid_place := int(state.get_current_player_id())
	var place_r := _try_place_restaurant(engine, pid_place, 4000)
	if not place_r.ok:
		return place_r

	var idx_r2: Result = engine.find_current_player_turn_start_command_index()
	if not idx_r2.ok:
		return Result.failure("find_current_player_turn_start_command_index 失败（after place）: %s" % idx_r2.error)
	if int(idx_r2.value) != expected_turn_start:
		return Result.failure("turn_start_index 错误（after place）：got=%d want=%d" % [int(idx_r2.value), expected_turn_start])

	return Result.success()

static func _try_place_restaurant(engine: GameEngine, player_id: int, scan_limit: int) -> Result:
	if engine == null:
		return Result.failure("engine 为空")
	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("state 为空")

	var world_min := CoordsClass.get_world_min(state)
	var world_max := CoordsClass.get_world_max(state)
	var tries := 0

	for y in range(world_min.y, world_max.y + 1):
		for x in range(world_min.x, world_max.x + 1):
			for r in range(4):
				tries += 1
				if tries > scan_limit:
					return Result.failure("未找到可放置餐厅的位置（scan_limit=%d）" % scan_limit)
				var cmd := Command.create("place_restaurant", player_id, {"position": [x, y], "rotation": r})
				var exec := engine.execute_command(cmd)
				if exec.ok:
					return Result.success()

	return Result.failure("未找到可放置餐厅的位置")

static func _clear_event_history() -> void:
	if EventBus == null:
		return
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()

