extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

const PaydaySettlementClass = preload("res://core/rules/phase/payday_settlement.gd")
const CleanupSettlementClass = preload("res://core/rules/phase/cleanup_settlement.gd")
const DinnertimeSettlementClass = preload("res://core/rules/phase/dinnertime_settlement.gd")
const MarketingSettlementClass = preload("res://core/rules/phase/marketing_settlement.gd")
const MapDefClass = preload("res://core/map/map_def.gd")
const MapOptionDefClass = preload("res://core/map/map_option_def.gd")
const WorkingFlowClass = preload("res://core/engine/phase_manager/working_flow.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")

const Phase = PhaseDefsClass.Phase
const WorkingSubPhase = PhaseDefsClass.WorkingSubPhase
const HookType = PhaseManagerClass.HookType

func register(registrar) -> Result:
	var r = registrar.register_primary_settlement(Phase.DINNERTIME, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_dinnertime_enter"))
	if not r.ok:
		return r
	r = registrar.register_primary_settlement(Phase.PAYDAY, SettlementRegistryClass.Point.EXIT, Callable(self, "_on_payday_exit"))
	if not r.ok:
		return r
	r = registrar.register_primary_settlement(Phase.MARKETING, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_marketing_enter"))
	if not r.ok:
		return r
	r = registrar.register_primary_settlement(Phase.CLEANUP, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_cleanup_enter"))
	if not r.ok:
		return r
	r = registrar.register_primary_map_generator(Callable(self, "_generate_map_def"))
	if not r.ok:
		return r

	# Phase/SubPhase hooks（避免 PhaseManager 中写死规则分支）
	r = registrar.register_phase_hook(Phase.RESTRUCTURING, HookType.BEFORE_ENTER, Callable(self, "_on_restructuring_before_enter"))
	if not r.ok:
		return r
	r = registrar.register_phase_hook(Phase.RESTRUCTURING, HookType.BEFORE_EXIT, Callable(self, "_on_restructuring_before_exit"))
	if not r.ok:
		return r
	r = registrar.register_phase_hook(Phase.ORDER_OF_BUSINESS, HookType.BEFORE_ENTER, Callable(self, "_on_order_of_business_before_enter"))
	if not r.ok:
		return r
	r = registrar.register_phase_hook(Phase.WORKING, HookType.BEFORE_ENTER, Callable(self, "_on_working_before_enter"))
	if not r.ok:
		return r
	r = registrar.register_phase_hook(Phase.WORKING, HookType.BEFORE_EXIT, Callable(self, "_on_working_before_exit"))
	if not r.ok:
		return r
	r = registrar.register_sub_phase_hook(WorkingSubPhase.TRAIN, HookType.BEFORE_EXIT, Callable(self, "_on_train_before_exit"))
	if not r.ok:
		return r
	r = registrar.register_phase_hook(Phase.DINNERTIME, HookType.BEFORE_EXIT, Callable(self, "_on_dinnertime_before_exit"))
	if not r.ok:
		return r

	return Result.success()

func _on_restructuring_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("base_rules:restructuring_before_enter: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("base_rules:restructuring_before_enter: state.round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = state.round_state
	var prev_phase: String = str(rs.get("prev_phase", ""))
	if prev_phase == "Setup" or prev_phase == "Cleanup":
		WorkingFlowClass.start_new_round(state)

	# 重组阶段（hotseat）：要求所有玩家提交后才能离开本阶段（首回合默认自动跳过，避免无操作卡住流程）
	if not (state.round_state is Dictionary):
		return Result.failure("base_rules:restructuring_before_enter: state.round_state 类型错误（期望 Dictionary）")
	var submitted := {}
	var pending: Array = []
	for pid in range(state.players.size()):
		submitted[pid] = false
		if state.round_number > 1:
			pending.append(pid)

	state.round_state["restructuring"] = {
		"submitted": submitted,
		"finalized": false
	}

	# 进入重组时清空上一回合结构（本回合以提交时的结构为准）
	for pid2 in range(state.players.size()):
		var p_val = state.players[pid2]
		if not (p_val is Dictionary):
			return Result.failure("base_rules:restructuring_before_enter: players[%d] 类型错误（期望 Dictionary）" % pid2)
		var p: Dictionary = p_val
		var cs_val = p.get("company_structure", null)
		if cs_val is Dictionary:
			var cs: Dictionary = cs_val
			cs["structure"] = []
			p["company_structure"] = cs
			state.players[pid2] = p

	# 固定从 turn_order[0] 开始（重组为同时阶段；hotseat 顺序仅为 UI/输入便利）
	state.current_player_index = 0

	if state.round_number > 1:
		if not state.round_state.has("pending_phase_actions"):
			state.round_state["pending_phase_actions"] = {}
		var ppa_val = state.round_state.get("pending_phase_actions", null)
		if not (ppa_val is Dictionary):
			return Result.failure("base_rules:restructuring_before_enter: round_state.pending_phase_actions 类型错误（期望 Dictionary）")
		var ppa: Dictionary = ppa_val
		ppa["Restructuring"] = pending
		state.round_state["pending_phase_actions"] = ppa
	return Result.success()

func _on_restructuring_before_exit(state: GameState) -> Result:
	# 对齐 rules.md：若公司结构超限（包含“经理数量超过 CEO 卡槽”），则除 CEO 外全部转为待命。
	if state == null:
		return Result.failure("base_rules:restructuring_before_exit: state 为空")

	var warnings: Array[String] = []
	if state.round_number > 1:
		if not (state.round_state is Dictionary):
			return Result.failure("base_rules:restructuring_before_exit: state.round_state 类型错误（期望 Dictionary）")
		if not state.round_state.has("restructuring") or not (state.round_state["restructuring"] is Dictionary):
			return Result.failure("base_rules:restructuring_before_exit: 重组阶段未初始化（round_state.restructuring 缺失或类型错误）")
		var r: Dictionary = state.round_state["restructuring"]
		if not r.has("submitted") or not (r["submitted"] is Dictionary):
			return Result.failure("base_rules:restructuring_before_exit: restructuring.submitted 缺失或类型错误（期望 Dictionary）")
		var submitted: Dictionary = r["submitted"]
		var missing: Array[int] = []
		for pid in range(state.players.size()):
			if not bool(submitted.get(pid, false)):
				missing.append(pid)
		if not missing.is_empty():
			return Result.failure("重组尚未提交完成，无法离开阶段: %s" % str(missing))

	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("base_rules:restructuring_before_exit: players[%d] 类型错误（期望 Dictionary）" % pid)
		var p: Dictionary = p_val

		if not p.has("employees") or not (p["employees"] is Array):
			return Result.failure("base_rules:restructuring_before_exit: player[%d].employees 缺失或类型错误（期望 Array）" % pid)
		if not p.has("reserve_employees") or not (p["reserve_employees"] is Array):
			return Result.failure("base_rules:restructuring_before_exit: player[%d].reserve_employees 缺失或类型错误（期望 Array）" % pid)
		if not p.has("company_structure") or not (p["company_structure"] is Dictionary):
			return Result.failure("base_rules:restructuring_before_exit: player[%d].company_structure 缺失或类型错误（期望 Dictionary）" % pid)

		var employees: Array = p["employees"]
		var reserve: Array = p["reserve_employees"]

		if not employees.has("ceo"):
			# 容错：若 CEO 被错误放到待命区，纠正回在岗（Fail Fast：若两边都没有 CEO 则直接失败）
			if reserve.has("ceo"):
				var removed := StateUpdater.remove_from_array(p, "reserve_employees", "ceo")
				if removed:
					StateUpdater.append_to_array(p, "employees", "ceo")
					employees = p["employees"]
					reserve = p["reserve_employees"]
				else:
					return Result.failure("base_rules:restructuring_before_exit: player[%d] CEO 修复失败" % pid)
			else:
				return Result.failure("base_rules:restructuring_before_exit: player[%d].employees 缺少 CEO" % pid)

		var cs: Dictionary = p["company_structure"]
		if not cs.has("ceo_slots"):
			return Result.failure("base_rules:restructuring_before_exit: player[%d].company_structure.ceo_slots 缺失" % pid)
		var slots_val = cs.get("ceo_slots", null)
		var ceo_slots := 0
		if slots_val is int:
			ceo_slots = int(slots_val)
		elif slots_val is float:
			var f: float = float(slots_val)
			if f != floor(f):
				return Result.failure("base_rules:restructuring_before_exit: player[%d].company_structure.ceo_slots 必须为整数，实际: %s" % [pid, str(slots_val)])
			ceo_slots = int(f)
		else:
			return Result.failure("base_rules:restructuring_before_exit: player[%d].company_structure.ceo_slots 类型错误（期望 int/float）" % pid)
		if ceo_slots < 0:
			return Result.failure("base_rules:restructuring_before_exit: player[%d].company_structure.ceo_slots 不能为负数: %d" % [pid, ceo_slots])

		var used_slots := 0
		var manager_count := 0
		var manager_slots_total := 0
		for i in range(employees.size()):
			var emp_val = employees[i]
			if not (emp_val is String):
				return Result.failure("base_rules:restructuring_before_exit: player[%d].employees[%d] 类型错误（期望 String）" % [pid, i])
			var emp_id: String = str(emp_val)
			if emp_id.is_empty():
				return Result.failure("base_rules:restructuring_before_exit: player[%d].employees[%d] 不能为空" % [pid, i])
			if emp_id == "ceo":
				continue
			used_slots += 1
			var def_val = EmployeeRegistryClass.get_def(emp_id)
			if def_val == null or not (def_val is EmployeeDef):
				return Result.failure("base_rules:restructuring_before_exit: 未知员工: %s" % emp_id)
			var def: EmployeeDef = def_val
			var m_slots := maxi(0, int(def.manager_slots))
			if m_slots > 0:
				manager_count += 1
				manager_slots_total += m_slots

		var total_slots := ceo_slots + manager_slots_total
		var overflow := (manager_count > ceo_slots) or (used_slots > total_slots)
		if overflow:
			var moved: Array[String] = []
			for emp_val2 in employees:
				var emp_id2: String = str(emp_val2)
				if emp_id2 == "ceo":
					continue
				moved.append(emp_id2)

			p["employees"] = ["ceo"]
			reserve.append_array(moved)
			p["reserve_employees"] = reserve
			var cs2_val = p.get("company_structure", null)
			if cs2_val is Dictionary:
				var cs2: Dictionary = cs2_val
				cs2["structure"] = []
				p["company_structure"] = cs2
			state.players[pid] = p
			warnings.append("Restructuring overflow: player %d, all employees except CEO moved to reserve" % pid)

	return Result.success().with_warnings(warnings)

func _on_order_of_business_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("base_rules:order_of_business_before_enter: state 为空")
	WorkingFlowClass.start_order_of_business(state)
	return Result.success()

func _on_working_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("base_rules:working_before_enter: state 为空")
	WorkingFlowClass.reset_working_phase_state(state)
	return Result.success()

func _on_working_before_exit(state: GameState) -> Result:
	if state == null:
		return Result.failure("base_rules:working_before_exit: state 为空")

	# 招聘缺货预支约束：若存在待清账的“紧接培训”，则禁止跳过 Working 阶段。
	if EmployeeRulesClass.has_any_immediate_train_pending(state):
		return Result.failure("存在缺货预支待培训员工，必须在 Train 子阶段紧接完成培训")

	# 强制动作检查：离开 Working 阶段前，检查所有玩家是否完成了必须的强制动作
	var mandatory_check := MandatoryActionsRulesClass.check_mandatory_actions_completed(state)
	if not mandatory_check.ok:
		return mandatory_check
	return Result.success()

func _on_train_before_exit(state: GameState) -> Result:
	if state == null:
		return Result.failure("base_rules:train_before_exit: state 为空")
	if EmployeeRulesClass.has_any_immediate_train_pending(state):
		return Result.failure("存在缺货预支待培训员工，无法推进子阶段（需先在 Train 完成培训）")
	return Result.success()

func _on_dinnertime_before_exit(state: GameState) -> Result:
	if state == null:
		return Result.failure("base_rules:dinnertime_before_exit: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("base_rules:dinnertime_before_exit: state.round_state 类型错误（期望 Dictionary）")
	if not (state.bank is Dictionary):
		return Result.failure("base_rules:dinnertime_before_exit: state.bank 类型错误（期望 Dictionary）")

	# 银行第二次破产：晚餐阶段结束后立刻终局（跳过 Payday 等后续阶段）
	if int(state.bank.get("broke_count", 0)) >= 2:
		state.round_state["force_next_phase"] = "GameOver"
	return Result.success()

func _on_dinnertime_enter(state: GameState, phase_manager: PhaseManager) -> Result:
	return DinnertimeSettlementClass.apply(state, phase_manager)

func _on_payday_exit(state: GameState, phase_manager: PhaseManager) -> Result:
	return PaydaySettlementClass.apply(state, phase_manager)

func _on_cleanup_enter(state: GameState, _phase_manager: PhaseManager) -> Result:
	return CleanupSettlementClass.apply(state)

func _on_marketing_enter(state: GameState, phase_manager: PhaseManager) -> Result:
	var rounds_read := phase_manager.get_marketing_rounds(state)
	if not rounds_read.ok:
		return rounds_read
	var marketing_rounds: int = int(rounds_read.value)
	return MarketingSettlementClass.apply(state, phase_manager.get_marketing_range_calculator(), marketing_rounds, phase_manager)

func _generate_map_def(player_count: int, catalog, map_option, rng_manager) -> Result:
	if player_count <= 0:
		return Result.failure("base_rules:map_generator: player_count 无效: %d" % player_count)
	if player_count == 6:
		return Result.failure("base_rules:map_generator: 6人地图尚未实现（需要后续扩展模块）")
	if rng_manager == null or not rng_manager.has_method("shuffle") or not rng_manager.has_method("randi_range"):
		return Result.failure("base_rules:map_generator: 必须提供可用的 RandomManager（用于确定性地图生成）")
	if catalog == null or not (catalog.tiles is Dictionary):
		return Result.failure("base_rules:map_generator: catalog.tiles 缺失或类型错误（期望 Dictionary）")
	if map_option == null or not (map_option is MapOptionDefClass):
		return Result.failure("base_rules:map_generator: map_option 类型错误（期望 MapOptionDef）")

	var opt = map_option
	var grid := _get_grid_size_for_player_count(player_count)
	if grid.x <= 0 or grid.y <= 0:
		return Result.failure("base_rules:map_generator: grid_size 无效: %s" % str(grid))

	if opt.layout_mode == "fixed":
		var map_def := MapDefClass.create_fixed(opt.id, opt.tiles)
		if map_def == null:
			return Result.failure("base_rules:map_generator: create_fixed 失败")
		if map_def.grid_size != grid:
			return Result.failure("base_rules:map_generator: fixed map grid_size 不符合规则: got=%s expected=%s" % [str(map_def.grid_size), str(grid)])
		map_def.display_name = opt.display_name
		map_def.min_players = opt.min_players
		map_def.max_players = opt.max_players
		return Result.success(map_def)

	if opt.layout_mode != "random_all_tiles":
		return Result.failure("base_rules:map_generator: 未支持的 layout_mode: %s" % opt.layout_mode)

	var required: int = grid.x * grid.y
	var tile_ids: Array[String] = []
	for k in catalog.tiles.keys():
		if not (k is String):
			return Result.failure("base_rules:map_generator: catalog.tiles key 类型错误（期望 String）")
		var tid: String = str(k)
		if tid.is_empty():
			return Result.failure("base_rules:map_generator: catalog.tiles key 不能为空")
		tile_ids.append(tid)
	tile_ids.sort()

	if tile_ids.size() < required:
		return Result.failure("base_rules:map_generator: tile 数量不足：need=%d have=%d" % [required, tile_ids.size()])

	# 规则：pool = catalog 所有 tiles（按文件夹枚举），不放回随机选。
	rng_manager.shuffle(tile_ids)

	var rotations: Array[int] = [0, 90, 180, 270]
	var out := MapDefClass.create_empty(opt.id, grid)
	out.display_name = opt.display_name
	out.min_players = opt.min_players
	out.max_players = opt.max_players

	var index: int = 0
	for y in range(grid.y):
		for x in range(grid.x):
			var tile_id: String = tile_ids[index]
			index += 1
			var rotation: int = 0
			if opt.random_rotation:
				var r_index: int = int(rng_manager.randi_range(0, rotations.size() - 1))
				rotation = int(rotations[r_index])
			out.add_tile(tile_id, Vector2i(x, y), rotation)

	return Result.success(out)

func _get_grid_size_for_player_count(player_count: int) -> Vector2i:
	match player_count:
		2:
			return Vector2i(3, 3)
		3:
			return Vector2i(3, 4)
		4:
			return Vector2i(4, 4)
		5:
			return Vector2i(5, 4)
	return Vector2i.ZERO
