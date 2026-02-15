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

	return Result.success()

