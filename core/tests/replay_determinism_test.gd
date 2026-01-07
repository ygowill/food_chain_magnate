# Determinism smoke test (M1)
# Builds and replays a 20+ command sequence and verifies final state hash matches.
class_name ReplayDeterminismTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run(player_count: int = 2, seed: int = 12345, min_commands: int = 20) -> Result:
	var engine_a := GameEngine.new()
	var init_a := engine_a.initialize(player_count, seed)
	if not init_a.ok:
		return Result.failure("初始化失败: %s" % init_a.error)

	# 为避免测试序列在尚未产生收入前因薪水不足而中断，给每位玩家少量起始现金（保持现金守恒）。
	var s := engine_a.get_state()
	# 注：测试允许通过 bank.reserve_added_total 注入额外现金（对齐现金守恒不变量）。
	var per_player_grant := 200
	var extra_total := player_count * per_player_grant
	s.bank["total"] = int(s.bank.get("total", 0)) + extra_total
	s.bank["reserve_added_total"] = int(s.bank.get("reserve_added_total", 0)) + extra_total
	for pid in range(player_count):
		var grant := StateUpdater.player_receive_from_bank(s, pid, per_player_grant)
		if not grant.ok:
			return Result.failure("发放起始现金失败: %s" % grant.error)
	# 同步到初始 checkpoint（archive.initial_state 来自 checkpoints[0].state_dict）
	if engine_a.checkpoints.size() > 0:
		var cp0_val = engine_a.checkpoints[0]
		if cp0_val is Dictionary:
			var cp0: Dictionary = cp0_val
			cp0["state_dict"] = s.to_dict().duplicate(true)
			cp0["hash"] = s.compute_hash()
			engine_a.checkpoints[0] = cp0

	var build := _build_and_execute_command_sequence(engine_a, min_commands)
	if not build.ok:
		return build

	if engine_a.get_command_history().size() < min_commands:
		return Result.failure("命令数量不足: %d < %d" % [engine_a.get_command_history().size(), min_commands])

	var final_hash_a := engine_a.get_state().compute_hash()
	var checkpoint_verify_a := engine_a.verify_checkpoints()
	if not checkpoint_verify_a.ok:
		return Result.failure("A 校验点验证失败: %s" % checkpoint_verify_a.error)

	var archive_result := engine_a.create_archive()
	if not archive_result.ok:
		return Result.failure("创建存档失败: %s" % archive_result.error)
	var archive: Dictionary = archive_result.value

	var engine_b := GameEngine.new()
	var load_b := engine_b.load_from_archive(archive)
	if not load_b.ok:
		return Result.failure("从存档回放失败: %s" % load_b.error)

	var final_hash_b := engine_b.get_state().compute_hash()
	if final_hash_a != final_hash_b:
		return Result.failure("回放哈希不一致: A=%s, B=%s" % [final_hash_a.substr(0, 12), final_hash_b.substr(0, 12)])

	var checkpoint_verify_b := engine_b.verify_checkpoints()
	if not checkpoint_verify_b.ok:
		return Result.failure("B 校验点验证失败: %s" % checkpoint_verify_b.error)

	var replay_b := engine_b.full_replay()
	if not replay_b.ok:
		return Result.failure("B 完整重放失败: %s" % replay_b.error)

	var final_hash_b2 := engine_b.get_state().compute_hash()
	if final_hash_a != final_hash_b2:
		return Result.failure("完整重放哈希不一致: A=%s, B2=%s" % [final_hash_a.substr(0, 12), final_hash_b2.substr(0, 12)])

	return Result.success({
		"player_count": player_count,
		"seed": seed,
		"command_count": engine_a.get_command_history().size(),
		"final_hash": final_hash_a
	})

static func _build_and_execute_command_sequence(engine: GameEngine, min_commands: int) -> Result:
	# Setup：放置起始餐厅 + 全员确认结束（并触发首轮自动跳过 Restructuring/OOB）
	var setup := TestPhaseUtilsClass.complete_setup(engine)
	if not setup.ok:
		return setup

	# 推进到 Working（若已在 Working 则直接通过）
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 80)
	if not to_working.ok:
		return to_working

	# Round 1：完整走完 Working（单玩家走完整子阶段序列）
	var w1 := TestPhaseUtilsClass.complete_working_phase(engine, 200)
	if not w1.ok:
		return w1

	# Round 2：推进到 Working（Restructuring / OrderOfBusiness 需要显式确认/选择）
	var to_working2 := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 120)
	if not to_working2.ok:
		return to_working2

	# 补足命令数：只追加确定性的 skip_sub_phase
	var safety_pad := 0
	while engine.get_command_history().size() < min_commands:
		safety_pad += 1
		if safety_pad > min_commands + 100:
			return Result.failure("补足命令循环超出安全上限")
		if engine.get_state().phase != "Working":
			var back_to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 120)
			if not back_to_working.ok:
				return back_to_working
		var pid := engine.get_state().get_current_player_id()
		var cmd_pad := Command.create("skip_sub_phase", pid)
		var exec_pad := engine.execute_command(cmd_pad)
		if not exec_pad.ok:
			return Result.failure("补足命令 skip_sub_phase 失败: %s (%s)" % [exec_pad.error, str(cmd_pad)])

	return Result.success()

static func _complete_order_of_business(engine: GameEngine) -> Result:
	var state := engine.get_state()
	var player_count := state.players.size()
	var safety := 0
	while state.phase == "OrderOfBusiness":
		safety += 1
		if safety > player_count + 2:
			return Result.failure("OrderOfBusiness 选择循环超出安全上限")

		var oob: Dictionary = state.round_state.get("order_of_business", {})
		var picks: Array = oob.get("picks", [])
		if picks.size() != player_count:
			return Result.failure("OrderOfBusiness picks 长度不匹配")
		if bool(oob.get("finalized", false)):
			return Result.success()

		var actor := state.get_current_player_id()
		var pos := picks.find(-1)
		if pos < 0:
			return Result.failure("OrderOfBusiness picks 未包含空位")

		var pick := engine.execute_command(Command.create("choose_turn_order", actor, {"position": pos}))
		if not pick.ok:
			return Result.failure("选择顺序失败: %s" % pick.error)

		state = engine.get_state()

	return Result.success()


static func _find_first_valid_placement(engine: GameEngine, action_id: String, actor: int) -> Command:
	var state := engine.get_state()
	var executor := engine.action_registry.get_executor(action_id)
	if executor == null:
		return null

	var grid_size: Vector2i = state.map.get("grid_size", Vector2i.ZERO)
	var rotations := [0, 90, 180, 270]

	for y in range(grid_size.y):
		for x in range(grid_size.x):
			for rot in rotations:
				var cmd := Command.create(action_id, actor, {
					"position": [x, y],
					"rotation": rot
				})
				var vr := executor.validate(state, cmd)
				if vr.ok:
					return cmd

	return null
