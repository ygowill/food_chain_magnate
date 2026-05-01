# 回归：replay/archive/timeline rebuild 不应通过 force execution 跳过 action-specific validation。
class_name StepTimelineForceExecuteActorMismatchTest
extends RefCounted

const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")
const EventHistoryRebuildClass = preload("res://core/engine/game_engine/event_history_rebuild.gd")

static func run(seed_val: int = 12345) -> Result:
	var replay_debug_r := _test_replay_execute_rejects_debug_force_invalid_param(seed_val)
	if not replay_debug_r.ok:
		return replay_debug_r
	var rebuild_r := _test_rebuild_paths_reject_out_of_turn_debug_force(seed_val)
	if not rebuild_r.ok:
		return rebuild_r
	return _test_archive_load_rejects_out_of_turn_parallel_command(seed_val)

static func _test_replay_execute_rejects_debug_force_invalid_param(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化 replay debug_force 测试失败: %s" % init.error)
	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("初始化 replay debug_force 测试成功但 state 为空")

	var cmd := Command.create("select_reserve_card", 0, {"selected_index": 999})
	cmd.metadata = {"debug_force": true}
	cmd.timestamp = PhaseManager.compute_timestamp(state)

	var exec := engine.execute_command(cmd, true)
	if exec.ok:
		return Result.failure("replay execute 不应因 debug_force 跳过 selected_index 校验")
	return Result.success()

static func _test_rebuild_paths_reject_out_of_turn_debug_force(seed_val: int) -> Result:
	var engine_r := _build_engine_with_out_of_turn_debug_force_command(seed_val)
	if not engine_r.ok:
		return engine_r
	var engine: GameEngine = engine_r.value

	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if build_r.ok:
		return Result.failure("StepTimelineBuild.build_full 不应接受 out-of-turn debug_force 命令")

	var event_r: Result = EventHistoryRebuildClass.build(engine, 0)
	if event_r.ok:
		return Result.failure("EventHistoryRebuild 不应接受 out-of-turn debug_force 命令")

	var replay_r := engine.full_replay()
	if replay_r.ok:
		return Result.failure("engine.full_replay 不应接受 out-of-turn debug_force 命令")

	var rewind_r := engine.rewind_to_command(0)
	if rewind_r.ok:
		return Result.failure("engine.rewind_to_command 不应接受 out-of-turn debug_force 命令")

	return Result.success()

static func _test_archive_load_rejects_out_of_turn_parallel_command(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化 archive 基线失败: %s" % init.error)

	var archive_r := engine.create_archive()
	if not archive_r.ok:
		return Result.failure("创建 archive 基线失败: %s" % archive_r.error)
	var archive: Dictionary = Dictionary(archive_r.value).duplicate(true)
	var initial_state: Dictionary = Dictionary(archive.get("initial_state", {})).duplicate(true)
	initial_state["turn_order"] = [0, 1]
	initial_state["current_player_index"] = 0
	initial_state["phase"] = "Setup"
	initial_state["sub_phase"] = "ReserveCards"
	archive["initial_state"] = initial_state
	archive["commands"] = [_build_out_of_turn_command_dict()]
	archive["current_index"] = 0

	var replay_engine := GameEngine.new()
	var load_r := replay_engine.load_from_archive(archive)
	if load_r.ok:
		return Result.failure("archive load_from_archive 不应接受 out-of-turn parallel command")
	return Result.success()

static func _build_engine_with_out_of_turn_debug_force_command(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化 out-of-turn rebuild 测试失败: %s" % init.error)
	var state: GameState = engine.get_state()
	if state == null:
		return Result.failure("初始化 out-of-turn rebuild 测试成功但 state 为空")
	state.turn_order.clear()
	state.turn_order.append(0)
	state.turn_order.append(1)
	state.current_player_index = 0
	state.phase = "Setup"
	state.sub_phase = "ReserveCards"
	if engine.checkpoints.is_empty() or not (engine.checkpoints[0] is Dictionary):
		return Result.failure("out-of-turn rebuild 测试缺少初始 checkpoint")
	var cp0: Dictionary = Dictionary(engine.checkpoints[0]).duplicate(true)
	cp0["state_dict"] = state.to_dict().duplicate(true)
	cp0["hash"] = state.compute_hash()
	engine.checkpoints[0] = cp0

	var cmd := Command.create("select_reserve_card", 1, {"selected_index": 0})
	cmd.metadata = {"debug_force": true}
	cmd.phase = "Setup"
	cmd.sub_phase = "ReserveCards"
	cmd.timestamp = 0
	cmd.index = 0
	engine.command_history.clear()
	engine.command_history.append(cmd)
	engine.current_command_index = 0
	return Result.success(engine)

static func _build_out_of_turn_command_dict() -> Dictionary:
	return {
		"index": 0,
		"action_id": "select_reserve_card",
		"actor": 1,
		"params": {"selected_index": 0},
		"phase": "Setup",
		"sub_phase": "ReserveCards",
		"timestamp": 0,
		"metadata": {"debug_force": true},
	}
