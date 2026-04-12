# 回归：debug_force 命令允许“非当前玩家”执行（actor mismatch），不应导致回放/倒带/日志时间线构建失败。
# 覆盖：Replay.full_replay / Replay.rewind_to_command / StepTimelineBuild.build_full 的强制命令 actor 校验一致性。
class_name StepTimelineForceExecuteActorMismatchTest
extends RefCounted

const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")

static func run(seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	if engine.get_state() == null:
		return Result.failure("初始化成功但 state 为空")

	# 构造一个“强制命令 actor != 当前玩家”的最小时间线：
	# - current_player_index=1（当前玩家=1）
	# - debug_force 的 select_reserve_card 由玩家0执行（actor=0）
	var state: GameState = engine.get_state()
	state.current_player_index = 1

	var cmd := Command.create("select_reserve_card", 0, {"selected_index": 0})
	cmd.metadata = {"debug_force": true}
	cmd.timestamp = PhaseManager.compute_timestamp(state)

	# 用回放模式执行，确保 debug_force 生效（不依赖 DebugFlags/AutoloadAccess 配置）。
	var exec := engine.execute_command(cmd, true)
	if not exec.ok:
		return Result.failure("执行强制命令失败: %s" % exec.error)

	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		return Result.failure("StepTimelineBuild.build_full 失败: %s" % build_r.error)

	var replay_r := engine.full_replay()
	if not replay_r.ok:
		return Result.failure("engine.full_replay 失败: %s" % replay_r.error)

	var rewind_r := engine.rewind_to_command(0)
	if not rewind_r.ok:
		return Result.failure("engine.rewind_to_command 失败: %s" % rewind_r.error)

	var replay_archive_r := _test_archive_load_replays_out_of_turn_parallel_command(seed_val)
	if not replay_archive_r.ok:
		return replay_archive_r

	return Result.success()

static func _test_archive_load_replays_out_of_turn_parallel_command(seed_val: int) -> Result:
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
	archive["commands"] = [{
		"index": 0,
		"action_id": "select_reserve_card",
		"actor": 1,
		"params": {"selected_index": 0},
		"phase": "Setup",
		"sub_phase": "ReserveCards",
		"timestamp": 0,
		"metadata": {}
	}]
	archive["current_index"] = 0

	var replay_engine := GameEngine.new()
	var load_r := replay_engine.load_from_archive(archive)
	if not load_r.ok:
		return Result.failure("out-of-turn archive load_from_archive 失败: %s" % load_r.error)

	var loaded_state := replay_engine.get_state()
	if loaded_state == null:
		return Result.failure("out-of-turn archive load_from_archive 成功但 state 为空")
	var player1 := loaded_state.get_player(1)
	if int(player1.get("reserve_card_selected", -1)) != 0:
		return Result.failure("out-of-turn archive 回放后玩家1储备卡选择未生效: %s" % str(player1))

	var build_r: Result = StepTimelineBuildClass.build_full(replay_engine)
	if not build_r.ok:
		return Result.failure("out-of-turn archive StepTimelineBuild.build_full 失败: %s" % build_r.error)

	var replay_r := replay_engine.full_replay()
	if not replay_r.ok:
		return Result.failure("out-of-turn archive engine.full_replay 失败: %s" % replay_r.error)

	var rewind_r := replay_engine.rewind_to_command(0)
	if not rewind_r.ok:
		return Result.failure("out-of-turn archive engine.rewind_to_command 失败: %s" % rewind_r.error)

	return Result.success()
