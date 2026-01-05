# Determinism smoke test (M1)
# Builds and replays a 20+ command sequence and verifies final state hash matches.
class_name ReplayDeterminismTest
extends RefCounted

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
	# === Setup: 每位玩家放置 1 个餐厅（确定性扫描找合法点）===
	var placed := {}
	for p in range(engine.get_state().players.size()):
		placed[p] = false

	var safety := 0
	while true:
		var done := true
		for p in placed.keys():
			if not placed[p]:
				done = false
				break
		if done:
			break

		safety += 1
		if safety > 50:
			return Result.failure("Setup 放置餐厅循环超出安全上限")

		var current_player := engine.get_state().get_current_player_id()
		if not placed[current_player]:
			var cmd_place := _find_first_valid_placement(engine, "place_restaurant", current_player)
			if cmd_place == null:
				return Result.failure("找不到玩家 %d 的合法餐厅放置点" % current_player)
			var exec_place := engine.execute_command(cmd_place)
			if not exec_place.ok:
				return Result.failure("放置餐厅失败: %s (%s)" % [exec_place.error, str(cmd_place)])
			placed[current_player] = true

		# 放置后手动结束回合
		var cmd_skip := Command.create("skip", current_player)
		var exec_skip := engine.execute_command(cmd_skip)
		if not exec_skip.ok:
			return Result.failure("skip 失败: %s (%s)" % [exec_skip.error, str(cmd_skip)])

	# === 推进到 Working ===
	while engine.get_state().phase != "Working":
		if engine.get_state().phase == "OrderOfBusiness":
			var oob := _complete_order_of_business(engine)
			if not oob.ok:
				return oob
		var cmd_adv := Command.create_system("advance_phase")
		var exec_adv := engine.execute_command(cmd_adv)
		if not exec_adv.ok:
			return Result.failure("推进阶段失败: %s" % exec_adv.error)
		if engine.get_command_history().size() > 200:
			return Result.failure("推进到 Working 超出安全上限")

	# === Round 1 / Working / Recruit：每位玩家招聘 1 名新业务开发员 ===
	if engine.get_state().sub_phase != "Recruit":
		return Result.failure("Working 初始子阶段应为 Recruit，实际: %s" % engine.get_state().sub_phase)

	var nbd_recruited := {}
	for p in range(engine.get_state().players.size()):
		nbd_recruited[p] = false

	var safety_recruit := 0
	while true:
		var done_recruit := true
		for p in nbd_recruited.keys():
			if not nbd_recruited[p]:
				done_recruit = false
				break
		if done_recruit:
			break

		safety_recruit += 1
		if safety_recruit > 50:
			return Result.failure("Recruit 新业务开发员循环超出安全上限")

		var current_player := engine.get_state().get_current_player_id()
		if not nbd_recruited[current_player]:
			var cmd_recruit := Command.create("recruit", current_player, {"employee_type": "new_business_dev"})
			var exec_recruit := engine.execute_command(cmd_recruit)
			if not exec_recruit.ok:
				return Result.failure("招聘 new_business_dev 失败: %s (%s)" % [exec_recruit.error, str(cmd_recruit)])
			nbd_recruited[current_player] = true

		var cmd_skip2 := Command.create("skip", current_player)
		var exec_skip2 := engine.execute_command(cmd_skip2)
		if not exec_skip2.ok:
			return Result.failure("skip 失败: %s (%s)" % [exec_skip2.error, str(cmd_skip2)])

	# === Round 1：推进子阶段直到离开 Working（让待命员工在下一回合 Restructuring 自动激活）===
	var subphase_safety := 0
	while engine.get_state().phase == "Working":
		subphase_safety += 1
		if subphase_safety > 30:
			return Result.failure("Round1 推进子阶段超出安全上限")

		for _k in range(engine.get_state().players.size()):
			var pid := engine.get_state().get_current_player_id()
			var cmd_s := Command.create("skip", pid)
			var exec_s := engine.execute_command(cmd_s)
			if not exec_s.ok:
				return Result.failure("skip 失败: %s (%s)" % [exec_s.error, str(cmd_s)])

		var cmd_sub := Command.create_system("advance_phase", {"target": "sub_phase"})
		var exec_sub := engine.execute_command(cmd_sub)
		if not exec_sub.ok:
			return Result.failure("推进子阶段失败: %s" % exec_sub.error)

	# === Round 2：推进到 Working ===
	var safety_round2 := 0
	while engine.get_state().phase != "Working":
		safety_round2 += 1
		if safety_round2 > 50:
			return Result.failure("推进到 Round2 Working 超出安全上限")
		if engine.get_state().phase == "OrderOfBusiness":
			var oob2 := _complete_order_of_business(engine)
			if not oob2.ok:
				return oob2
		var cmd_adv2 := Command.create_system("advance_phase")
		var exec_adv2 := engine.execute_command(cmd_adv2)
		if not exec_adv2.ok:
			return Result.failure("推进阶段失败: %s" % exec_adv2.error)

	# === Round 2 / Working / Recruit：每位玩家招聘 1 名本地经理（使其在 Round 3 在岗，用于 PlaceRestaurants） ===
	if engine.get_state().sub_phase != "Recruit":
		return Result.failure("Round2 Working 初始子阶段应为 Recruit，实际: %s" % engine.get_state().sub_phase)

	var lm_recruited := {}
	for p in range(engine.get_state().players.size()):
		lm_recruited[p] = false

	var safety_recruit2 := 0
	while true:
		var done_recruit2 := true
		for p in lm_recruited.keys():
			if not lm_recruited[p]:
				done_recruit2 = false
				break
		if done_recruit2:
			break

		safety_recruit2 += 1
		if safety_recruit2 > 50:
			return Result.failure("Recruit 本地经理循环超出安全上限")

		var current_player2 := engine.get_state().get_current_player_id()
		if not lm_recruited[current_player2]:
			var cmd_recruit2 := Command.create("recruit", current_player2, {"employee_type": "local_manager"})
			var exec_recruit2 := engine.execute_command(cmd_recruit2)
			if not exec_recruit2.ok:
				return Result.failure("招聘 local_manager 失败: %s (%s)" % [exec_recruit2.error, str(cmd_recruit2)])
			lm_recruited[current_player2] = true

		var cmd_skip_r2 := Command.create("skip", current_player2)
		var exec_skip_r2 := engine.execute_command(cmd_skip_r2)
		if not exec_skip_r2.ok:
			return Result.failure("skip 失败: %s (%s)" % [exec_skip_r2.error, str(cmd_skip_r2)])

	# === Round 2：推进子阶段直到 PlaceHouses ===
	var subphase_safety2 := 0
	while engine.get_state().sub_phase != "PlaceHouses":
		subphase_safety2 += 1
		if subphase_safety2 > 20:
			return Result.failure("推进到 PlaceHouses 超出安全上限")

		for _k in range(engine.get_state().players.size()):
			var pid := engine.get_state().get_current_player_id()
			var cmd_s := Command.create("skip", pid)
			var exec_s := engine.execute_command(cmd_s)
			if not exec_s.ok:
				return Result.failure("skip 失败: %s (%s)" % [exec_s.error, str(cmd_s)])

		var cmd_sub2 := Command.create_system("advance_phase", {"target": "sub_phase"})
		var exec_sub2 := engine.execute_command(cmd_sub2)
		if not exec_sub2.ok:
			return Result.failure("推进子阶段失败: %s" % exec_sub2.error)

	# === PlaceHouses: 每位玩家放置 1 个房屋 ===
	var house_placed := {}
	for p in range(engine.get_state().players.size()):
		house_placed[p] = false

	var safety_house := 0
	while true:
		var done_house := true
		for p in house_placed.keys():
			if not house_placed[p]:
				done_house = false
				break
		if done_house:
			break

		safety_house += 1
		if safety_house > 80:
			return Result.failure("PlaceHouses 放置房屋循环超出安全上限")

		var current_p := engine.get_state().get_current_player_id()
		if not house_placed[current_p]:
			var cmd_house := _find_first_valid_placement(engine, "place_house", current_p)
			if cmd_house == null:
				return Result.failure("找不到玩家 %d 的合法房屋放置点" % current_p)
			var exec_house := engine.execute_command(cmd_house)
			if not exec_house.ok:
				return Result.failure("放置房屋失败: %s (%s)" % [exec_house.error, str(cmd_house)])
			house_placed[current_p] = true

		var cmd_hs := Command.create("skip", current_p)
		var exec_hs := engine.execute_command(cmd_hs)
		if not exec_hs.ok:
			return Result.failure("skip 失败: %s (%s)" % [exec_hs.error, str(cmd_hs)])

	# === Round 2：推进子阶段直到离开 Working（让本地经理在下一回合 Restructuring 自动激活）===
	var subphase_safety3 := 0
	while engine.get_state().phase == "Working":
		subphase_safety3 += 1
		if subphase_safety3 > 40:
			return Result.failure("Round2 推进子阶段超出安全上限")

		for _k in range(engine.get_state().players.size()):
			var pid3 := engine.get_state().get_current_player_id()
			var cmd_s3 := Command.create("skip", pid3)
			var exec_s3 := engine.execute_command(cmd_s3)
			if not exec_s3.ok:
				return Result.failure("skip 失败: %s (%s)" % [exec_s3.error, str(cmd_s3)])

		var cmd_sub3 := Command.create_system("advance_phase", {"target": "sub_phase"})
		var exec_sub3 := engine.execute_command(cmd_sub3)
		if not exec_sub3.ok:
			return Result.failure("推进子阶段失败: %s" % exec_sub3.error)

	# === Round 3：推进到 Working ===
	var safety_round3 := 0
	while engine.get_state().phase != "Working":
		safety_round3 += 1
		if safety_round3 > 60:
			return Result.failure("推进到 Round3 Working 超出安全上限")
		if engine.get_state().phase == "OrderOfBusiness":
			var oob3 := _complete_order_of_business(engine)
			if not oob3.ok:
				return oob3
		var cmd_adv3 := Command.create_system("advance_phase")
		var exec_adv3 := engine.execute_command(cmd_adv3)
		if not exec_adv3.ok:
			return Result.failure("推进阶段失败: %s" % exec_adv3.error)

	# === 推进到 PlaceRestaurants，并放置一次额外餐厅（Working 阶段）===
	var subphase_safety4 := 0
	while engine.get_state().sub_phase != "PlaceRestaurants":
		subphase_safety4 += 1
		if subphase_safety4 > 30:
			return Result.failure("推进到 PlaceRestaurants 超出安全上限")

		for _k in range(engine.get_state().players.size()):
			var pid4 := engine.get_state().get_current_player_id()
			var cmd_s4 := Command.create("skip", pid4)
			var exec_s4 := engine.execute_command(cmd_s4)
			if not exec_s4.ok:
				return Result.failure("skip 失败: %s (%s)" % [exec_s4.error, str(cmd_s4)])

		var cmd_sub4 := Command.create_system("advance_phase", {"target": "sub_phase"})
		var exec_sub4 := engine.execute_command(cmd_sub4)
		if not exec_sub4.ok:
			return Result.failure("推进子阶段失败: %s" % exec_sub4.error)
		if engine.get_state().phase != "Working":
			return Result.failure("推进到 PlaceRestaurants 失败：已离开 Working")

	var current_actor := engine.get_state().get_current_player_id()
	var cmd_extra_rest := _find_first_valid_placement(engine, "place_restaurant", current_actor)
	if cmd_extra_rest == null:
		return Result.failure("Working 阶段找不到额外餐厅放置点")
	var exec_r := engine.execute_command(cmd_extra_rest)
	if not exec_r.ok:
		return Result.failure("放置餐厅失败: %s (%s)" % [exec_r.error, str(cmd_extra_rest)])
	var cmd_rs := Command.create("skip", current_actor)
	var exec_rs := engine.execute_command(cmd_rs)
	if not exec_rs.ok:
		return Result.failure("skip 失败: %s (%s)" % [exec_rs.error, str(cmd_rs)])

	# 补足命令数（只追加确定性的 skip）
	while engine.get_command_history().size() < min_commands:
		var pid2 := engine.get_state().get_current_player_id()
		var cmd_pad := Command.create("skip", pid2)
		var exec_pad := engine.execute_command(cmd_pad)
		if not exec_pad.ok:
			return Result.failure("补足命令 skip 失败: %s (%s)" % [exec_pad.error, str(cmd_pad)])

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
