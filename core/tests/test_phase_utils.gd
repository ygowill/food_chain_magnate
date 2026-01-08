# 测试辅助：阶段推进工具
# 目标：让 core/tests 中的用例以“真实规则”推进阶段（尤其是 OrderOfBusiness 需要完成选择）。
class_name TestPhaseUtils
extends RefCounted

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

static func _is_transient_auto_skipped_phase(phase_name: String) -> bool:
	match phase_name:
		"Dinnertime":
			return true
		"Marketing":
			return true
		"Cleanup":
			return true
		_:
			return false

static func _get_working_sub_phase_order(state: GameState) -> Result:
	if state == null:
		return Result.failure("working_sub_phase_order: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("working_sub_phase_order: round_state 类型错误（期望 Dictionary）")
	if not state.round_state.has("working_sub_phase_order") or not (state.round_state["working_sub_phase_order"] is Array):
		# 兼容：部分测试会手动写入 state.phase/sub_phase 而不经过 PhaseManager（此时 fallback 到基础顺序）
		var base_order: Array[String] = []
		base_order.append("Recruit")
		base_order.append("Train")
		base_order.append("Marketing")
		base_order.append("GetFood")
		base_order.append("GetDrinks")
		base_order.append("PlaceHouses")
		base_order.append("PlaceRestaurants")
		return Result.success(base_order)
	var order_val: Array = state.round_state["working_sub_phase_order"]
	var order: Array[String] = []
	for i in range(order_val.size()):
		var v = order_val[i]
		if not (v is String):
			return Result.failure("working_sub_phase_order[%d] 类型错误（期望 String）" % i)
		var s: String = str(v)
		if s.is_empty():
			return Result.failure("working_sub_phase_order[%d] 不能为空" % i)
		order.append(s)
	return Result.success(order)

static func _get_last_working_sub_phase(state: GameState) -> Result:
	var order_r := _get_working_sub_phase_order(state)
	if not order_r.ok:
		return order_r
	var order_val = order_r.value
	if not (order_val is Array):
		return Result.failure("working_sub_phase_order 类型错误（期望 Array）")
	var order: Array = order_val
	return Result.success(str(order[order.size() - 1]) if order.size() > 0 else "")

static func advance_current_player_working_sub_phase(engine: GameEngine) -> Result:
	var state := engine.get_state()
	if state.phase != "Working":
		return Result.failure("当前不在 Working，无法推进子阶段")
	if state.sub_phase.is_empty():
		return Result.failure("Working 子阶段为空")

	var pid := state.get_current_player_id()
	var adv := engine.execute_command(Command.create("skip_sub_phase", pid))
	if not adv.ok:
		return Result.failure("skip_sub_phase 失败: %s" % adv.error)
	return Result.success()

static func pass_all_players_in_working_sub_phase(engine: GameEngine) -> Result:
	# 兼容旧测试工具名：
	# - 非最后子阶段：等价于“跳过子阶段”（推进到下一子阶段）
	# - 最后子阶段：等价于“确认结束”（结束该玩家 Working 回合，必要时离开 Working）
	var state := engine.get_state()
	if state.phase != "Working" or state.sub_phase.is_empty():
		return Result.failure("当前不在 Working 子阶段，无法 pass_all_players")

	var last_r := _get_last_working_sub_phase(state)
	if not last_r.ok:
		return last_r
	var last_sub_phase: String = str(last_r.value)
	if last_sub_phase.is_empty():
		return Result.failure("working_sub_phase_order 为空")

	var pid := state.get_current_player_id()
	if state.sub_phase == last_sub_phase:
		var sk := engine.execute_command(Command.create("skip", pid))
		if not sk.ok:
			return Result.failure("skip 失败: %s" % sk.error)
		return Result.success()

	var adv := engine.execute_command(Command.create("skip_sub_phase", pid))
	if not adv.ok:
		return Result.failure("skip_sub_phase 失败: %s" % adv.error)
	return Result.success()

static func end_current_player_working_turn(engine: GameEngine, safety_limit: int = 50) -> Result:
	var state := engine.get_state()
	if state.phase != "Working":
		return Result.failure("当前不在 Working，无法结束玩家回合")

	var last_r := _get_last_working_sub_phase(state)
	if not last_r.ok:
		return last_r
	var last_sub_phase: String = last_r.value
	if last_sub_phase.is_empty():
		return Result.failure("working_sub_phase_order 为空")

	var safety := 0
	while engine.get_state().phase == "Working" and engine.get_state().sub_phase != last_sub_phase:
		safety += 1
		if safety > safety_limit:
			return Result.failure("推进到最后子阶段超出安全上限: %s" % last_sub_phase)
		var pid := engine.get_state().get_current_player_id()
		var adv := engine.execute_command(Command.create("skip_sub_phase", pid))
		if not adv.ok:
			return Result.failure("skip_sub_phase 失败: %s" % adv.error)

	if engine.get_state().phase != "Working":
		return Result.success()
	if engine.get_state().sub_phase != last_sub_phase:
		return Result.failure("未到最后子阶段: %s" % engine.get_state().sub_phase)

	var pid2 := engine.get_state().get_current_player_id()
	var sk := engine.execute_command(Command.create("skip", pid2))
	if not sk.ok:
		return Result.failure("skip 失败: %s" % sk.error)

	return Result.success()

static func complete_working_phase(engine: GameEngine, safety_limit: int = 200) -> Result:
	var safety := 0
	while engine.get_state().phase == "Working":
		safety += 1
		if safety > safety_limit:
			return Result.failure("结束 Working 阶段超出安全上限")
		var end_turn := end_current_player_working_turn(engine, 50)
		if not end_turn.ok:
			return end_turn

	return Result.success()

static func complete_setup(engine: GameEngine, scan_limit: int = 4000) -> Result:
	# Setup 阶段：每位玩家必须先放置 1 个餐厅才能确认结束
	if engine.get_state().phase != "Setup":
		return Result.success()

	var safety := 0
	while engine.get_state().phase == "Setup":
		safety += 1
		if safety > engine.get_state().players.size() + 5:
			return Result.failure("Setup 结束循环超出安全上限")

		var state := engine.get_state()
		var pid := state.get_current_player_id()
		var placed := false

		var world_min := MapRuntimeClass.get_world_min(state)
		var world_max := MapRuntimeClass.get_world_max(state)
		var tries := 0

		for y in range(world_min.y, world_max.y + 1):
			for x in range(world_min.x, world_max.x + 1):
				for r in range(4):
					tries += 1
					if tries > scan_limit:
						break
					var cmd := Command.create("place_restaurant", pid, {"position": [x, y], "rotation": r})
					var exec := engine.execute_command(cmd)
					if exec.ok:
						placed = true
						break
				if placed or tries > scan_limit:
					break
			if placed or tries > scan_limit:
				break

		if not placed:
			return Result.failure("Setup：未找到可放置餐厅的位置（player=%d）" % pid)

		var sk := engine.execute_command(Command.create("skip", pid))
		if not sk.ok:
			return Result.failure("Setup：skip 失败: %s" % sk.error)

	return Result.success()

static func complete_order_of_business(engine: GameEngine) -> Result:
	var state := engine.get_state()
	if state.phase != "OrderOfBusiness":
		return Result.success()

	var safety := 0
	while state.phase == "OrderOfBusiness":
		safety += 1
		if safety > state.players.size() + 5:
			return Result.failure("OrderOfBusiness 选择循环超出安全上限")

		if not (state.round_state is Dictionary):
			return Result.failure("OrderOfBusiness 未初始化(round_state)")
		var oob: Dictionary = state.round_state.get("order_of_business", {})
		if not (oob is Dictionary) or oob.is_empty():
			return Result.failure("OrderOfBusiness 未初始化(order_of_business)")

		if bool(oob.get("finalized", false)):
			return Result.success()

		var picks: Array = oob.get("picks", [])
		if picks.size() != state.players.size():
			return Result.failure("OrderOfBusiness picks 长度不匹配")

		var pos := picks.find(-1)
		if pos < 0:
			return Result.failure("OrderOfBusiness picks 未包含空位")

		var actor := state.get_current_player_id()
		var pick := engine.execute_command(Command.create("choose_turn_order", actor, {"position": pos}))
		if not pick.ok:
			return Result.failure("选择顺序失败: %s" % pick.error)

		state = engine.get_state()

	# 新规则：choose_turn_order 最后一手会自动推进到 Working；此时已离开 OrderOfBusiness，视为成功
	return Result.success()

static func complete_restructuring(engine: GameEngine) -> Result:
	var state := engine.get_state()
	if state.phase != "Restructuring":
		return Result.success()

	var safety := 0
	while state.phase == "Restructuring":
		safety += 1
		if safety > state.players.size() + 8:
			return Result.failure("Restructuring 提交循环超出安全上限")

		var actor := state.get_current_player_id()
		if actor < 0:
			return Result.failure("Restructuring 当前玩家无效")

		var submit := engine.execute_command(Command.create("submit_restructuring", actor, {}))
		if not submit.ok:
			return Result.failure("提交重组失败: %s" % submit.error)

		state = engine.get_state()

	return Result.success()

static func advance_until_phase(engine: GameEngine, target_phase: String, safety_limit: int = 50) -> Result:
	if _is_transient_auto_skipped_phase(target_phase):
		return Result.failure("目标阶段为自动跳过阶段：%s（请改为检查结算结果或推进到下一个可停留阶段）" % target_phase)

	var safety := 0
	while engine.get_state().phase != target_phase:
		safety += 1
		if safety > safety_limit:
			return Result.failure("推进到 %s 超出安全上限" % target_phase)

		# Setup：必须先放置餐厅才能离开
		if engine.get_state().phase == "Setup" and target_phase != "Setup":
			var setup := complete_setup(engine)
			if not setup.ok:
				return setup
			continue

		if engine.get_state().phase == "OrderOfBusiness":
			var oob := complete_order_of_business(engine)
			if not oob.ok:
				return oob
			continue
		if engine.get_state().phase == "Restructuring" and target_phase != "Restructuring":
			var restruct := complete_restructuring(engine)
			if not restruct.ok:
				return restruct
			continue

		# Working 阶段：结束所有玩家的 Working 回合后离开阶段
		if engine.get_state().phase == "Working" and target_phase != "Working":
			var done := complete_working_phase(engine, 200)
			if not done.ok:
				return done
			continue

		# 非 Working：通过“全员确认结束(skip)”自动推进阶段
		var phase_before := engine.get_state().phase
		var max_players := engine.get_state().players.size()
		for _i in range(max_players):
			var pid2 := engine.get_state().get_current_player_id()
			var sk2 := engine.execute_command(Command.create("skip", pid2))
			if not sk2.ok:
				return Result.failure("skip 失败: %s" % sk2.error)
			if engine.get_state().phase != phase_before:
				break
		if engine.get_state().phase == phase_before:
			return Result.failure("阶段未自动推进（phase=%s）" % phase_before)

	return Result.success()

static func advance_until_working_sub_phase(engine: GameEngine, target_sub_phase: String, safety_limit: int = 30) -> Result:
	if target_sub_phase.is_empty():
		return Result.failure("target_sub_phase 不能为空")

	if engine.get_state().phase != "Working":
		return Result.failure("当前不在 Working，无法推进到子阶段: %s" % target_sub_phase)

	var safety := 0
	while engine.get_state().phase == "Working" and engine.get_state().sub_phase != target_sub_phase:
		safety += 1
		if safety > safety_limit:
			return Result.failure("推进到 Working/%s 超出安全上限（当前=%s）" % [target_sub_phase, engine.get_state().sub_phase])

		var pid := engine.get_state().get_current_player_id()
		var before_sub := engine.get_state().sub_phase
		var adv := engine.execute_command(Command.create("skip_sub_phase", pid))
		if not adv.ok:
			return Result.failure("skip_sub_phase 失败: %s" % adv.error)

		var after := engine.get_state()
		if after.phase != "Working":
			return Result.failure("推进到 Working/%s 失败：已离开 Working（sub_phase=%s）" % [target_sub_phase, before_sub])
		if after.get_current_player_id() != pid:
			return Result.failure("推进到 Working/%s 失败：玩家回合发生切换（可能已到最后子阶段）" % target_sub_phase)

	if engine.get_state().phase != "Working":
		return Result.failure("当前不在 Working，无法推进到子阶段: %s" % target_sub_phase)

	return Result.success()
