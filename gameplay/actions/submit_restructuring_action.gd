# 重组阶段：提交公司结构（hotseat）
# - 要求每位玩家提交后才能离开 Restructuring
# - 提交时将玩家的“在岗员工”自动生成严格金字塔结构写入 company_structure.structure
# - 若在岗员工超出容量（含经理数量 > CEO 卡槽），则允许提交，但离开阶段时触发“除 CEO 外全部转待命”
class_name SubmitRestructuringAction
extends ActionExecutor

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

var phase_manager: PhaseManager = null

func _init(manager: PhaseManager = null) -> void:
	action_id = "submit_restructuring"
	display_name = "确认重组"
	description = "提交本回合公司结构"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Restructuring"]
	phase_manager = manager

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if state.phase != "Restructuring":
		return Result.failure("当前不在 Restructuring")
	if not EmployeeRegistryClass.is_loaded():
		return Result.failure("EmployeeRegistry 未初始化")

	# hotseat：必须是当前玩家
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var r_val = state.round_state.get("restructuring", null)
	if not (r_val is Dictionary):
		return Result.failure("重组阶段未初始化（round_state.restructuring 缺失或类型错误）")
	var r: Dictionary = r_val
	if not r.has("submitted") or not (r["submitted"] is Dictionary):
		return Result.failure("restructuring.submitted 缺失或类型错误（期望 Dictionary）")
	var submitted: Dictionary = r["submitted"]
	if bool(submitted.get(command.actor, false)):
		return Result.failure("你已提交重组")

	# 基础字段校验（提交时写入 structure，需要读取 company_structure.ceo_slots 与在岗员工列表）
	var player := state.get_player(command.actor)
	if player.is_empty():
		return Result.failure("玩家不存在: %d" % command.actor)
	if not player.has("employees") or not (player["employees"] is Array):
		return Result.failure("player.employees 缺失或类型错误（期望 Array）")
	if not player.has("reserve_employees") or not (player["reserve_employees"] is Array):
		return Result.failure("player.reserve_employees 缺失或类型错误（期望 Array）")
	if not player.has("company_structure") or not (player["company_structure"] is Dictionary):
		return Result.failure("player.company_structure 缺失或类型错误（期望 Dictionary）")
	var cs: Dictionary = player["company_structure"]
	if not cs.has("ceo_slots"):
		return Result.failure("player.company_structure.ceo_slots 缺失")
	var slots_val = cs.get("ceo_slots", null)
	if not (slots_val is int) and not (slots_val is float):
		return Result.failure("player.company_structure.ceo_slots 类型错误（期望 int/float）")
	if slots_val is float and float(slots_val) != floor(float(slots_val)):
		return Result.failure("player.company_structure.ceo_slots 必须为整数（不允许小数）")
	if int(slots_val) < 0:
		return Result.failure("player.company_structure.ceo_slots 不能为负数: %d" % int(slots_val))

	var employees: Array = player["employees"]
	var reserve: Array = player["reserve_employees"]
	var has_ceo_active := employees.has("ceo")
	var has_ceo_reserve := reserve.has("ceo")
	if not has_ceo_active and not has_ceo_reserve:
		return Result.failure("玩家缺少 CEO（在岗/待命均未找到）")

	# 严格校验：employees 必须为去重的有效员工列表（CEO 可在 apply 时被自动纠正回在岗）
	var seen := {}
	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			return Result.failure("player.employees[%d] 类型错误（期望 String）" % i)
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("player.employees[%d] 不能为空" % i)
		if seen.has(emp_id):
			return Result.failure("player.employees 包含重复员工: %s" % emp_id)
		seen[emp_id] = true
		if not EmployeeRegistryClass.has(emp_id):
			return Result.failure("未知员工: %s" % emp_id)

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var warnings: Array[String] = []

	var player_id: int = command.actor
	var player_val = state.players[player_id]
	assert(player_val is Dictionary, "submit_restructuring: player 类型错误（期望 Dictionary）")
	var player: Dictionary = player_val

	var employees_val = player.get("employees", null)
	assert(employees_val is Array, "submit_restructuring: player.employees 类型错误（期望 Array）")
	var employees: Array = employees_val
	var reserve_val = player.get("reserve_employees", null)
	assert(reserve_val is Array, "submit_restructuring: player.reserve_employees 类型错误（期望 Array）")
	var reserve: Array = reserve_val

	# 容错：若 CEO 在待命区，自动纠正回在岗（对齐 base_rules:restructuring_before_exit 的修复策略）
	if employees.has("ceo") and reserve.has("ceo"):
		while reserve.has("ceo"):
			StateUpdater.remove_from_array(player, "reserve_employees", "ceo")
		reserve = player["reserve_employees"]
		warnings.append("重组提交：检测到 CEO 同时在待命区，已自动移除待命区中的 CEO")
	if not employees.has("ceo"):
		if reserve.has("ceo"):
			var removed := StateUpdater.remove_from_array(player, "reserve_employees", "ceo")
			if removed:
				StateUpdater.append_to_array(player, "employees", "ceo")
				employees = player["employees"]
				reserve = player["reserve_employees"]
				warnings.append("重组提交：检测到 CEO 在待命区，已自动纠正回在岗")
			else:
				return Result.failure("重组提交：CEO 修复失败（从待命区移除失败）")
		else:
			return Result.failure("重组提交：玩家缺少 CEO（在岗/待命均未找到）")

	var cs_val = player.get("company_structure", null)
	assert(cs_val is Dictionary, "submit_restructuring: player.company_structure 类型错误（期望 Dictionary）")
	var cs: Dictionary = cs_val

	var slots_raw = cs.get("ceo_slots", 0)
	var ceo_slots := 0
	if slots_raw is int:
		ceo_slots = int(slots_raw)
	elif slots_raw is float:
		var f: float = float(slots_raw)
		assert(f == floor(f), "submit_restructuring: ceo_slots 必须为整数")
		ceo_slots = int(f)
	assert(ceo_slots >= 0, "submit_restructuring: ceo_slots 不能为负数: %d" % ceo_slots)

	var non_ceo: Array[String] = []
	var managers: Array[String] = []
	var non_managers: Array[String] = []

	for i in range(employees.size()):
		var emp_val = employees[i]
		assert(emp_val is String, "submit_restructuring: employees[%d] 类型错误（期望 String）" % i)
		var emp_id: String = str(emp_val)
		assert(not emp_id.is_empty(), "submit_restructuring: employees[%d] 不能为空" % i)
		if emp_id == "ceo":
			continue
		non_ceo.append(emp_id)
		var def_val = EmployeeRegistryClass.get_def(emp_id)
		assert(def_val != null and (def_val is EmployeeDef), "submit_restructuring: 未知员工: %s" % emp_id)
		var def: EmployeeDef = def_val
		var ms := maxi(0, int(def.manager_slots))
		if ms > 0:
			managers.append(emp_id)
		else:
			non_managers.append(emp_id)

	var used_slots := non_ceo.size()
	var manager_count := managers.size()
	var manager_slots_total := 0
	for m_id in managers:
		var m_def: EmployeeDef = EmployeeRegistryClass.get_def(m_id)
		manager_slots_total += maxi(0, int(m_def.manager_slots))
	var total_slots := ceo_slots + manager_slots_total
	var overflow := (manager_count > ceo_slots) or (used_slots > total_slots)
	if overflow:
		warnings.append("重组提交：公司结构超限（离开重组阶段时将触发“除 CEO 外全部转待命”）")

	# 自动生成“严格金字塔结构”（用于展示/存档；支持玩家在重组阶段预先设置 CEO 直属槽）
	var structure: Array = []
	for _i in range(ceo_slots):
		structure.append({"employee_id": "", "reports": []})

	# 读取玩家已设置的直属槽偏好（仅 employee_id；reports 由本动作统一生成）
	var preferred_direct: Array[String] = []
	for _i2 in range(ceo_slots):
		preferred_direct.append("")
	var preferred_reports_by_manager := {}
	if cs.has("structure") and (cs["structure"] is Array):
		var pref_arr: Array = cs["structure"]
		for i_pref in range(min(pref_arr.size(), ceo_slots)):
			var e_val = pref_arr[i_pref]
			if e_val is Dictionary:
				var e: Dictionary = e_val
				var id_val = e.get("employee_id", null)
				if id_val is String:
					var pid: String = str(id_val)
					preferred_direct[i_pref] = pid
					var reps_val = e.get("reports", null)
					if reps_val is Array:
						preferred_reports_by_manager[pid] = Array(reps_val).duplicate()

	var used := {}
	for i_slot in range(ceo_slots):
		var pick: String = preferred_direct[i_slot]
		if pick.is_empty() or pick == "ceo":
			continue
		if not non_ceo.has(pick):
			continue
		if used.has(pick):
			continue
		structure[i_slot] = {"employee_id": pick, "reports": []}
		used[pick] = true

	# 确保尽量放入经理（经理必须直连 CEO；必要时会替换非经理直属）
	for m in managers:
		if used.has(m):
			continue

		var placed := false
		for i_empty in range(structure.size()):
			var slot_val = structure[i_empty]
			if not (slot_val is Dictionary):
				continue
			var slot: Dictionary = slot_val
			if str(slot.get("employee_id", "")).is_empty():
				structure[i_empty] = {"employee_id": m, "reports": []}
				used[m] = true
				placed = true
				break

		if placed:
			continue

		# 无空位：找一个非经理直属槽替换
		var replace_index := -1
		var replaced_emp := ""
		for i_rep in range(structure.size() - 1, -1, -1):
			var slot_val2 = structure[i_rep]
			if not (slot_val2 is Dictionary):
				continue
			var slot2: Dictionary = slot_val2
			var direct2: String = str(slot2.get("employee_id", ""))
			if direct2.is_empty():
				continue
			var direct_def2: EmployeeDef = EmployeeRegistryClass.get_def(direct2)
			if direct_def2 == null:
				continue
			var cap2 := maxi(0, int(direct_def2.manager_slots))
			if cap2 <= 0:
				replace_index = i_rep
				replaced_emp = direct2
				break

		if replace_index < 0:
			# 直属槽全为经理：无法再放入更多经理（必然超限）
			break

		structure[replace_index] = {"employee_id": m, "reports": []}
		used[m] = true
		if not replaced_emp.is_empty():
			used.erase(replaced_emp)
			warnings.append("重组提交：已将 %s 从 CEO 直属槽移除以安置经理 %s" % [replaced_emp, m])

	# 补齐剩余空槽：放入普通员工（不强制必须填满）
	for emp_nm in non_managers:
		if used.has(emp_nm):
			continue
		var empty_index := -1
		for i_empty2 in range(structure.size()):
			var slot_val3 = structure[i_empty2]
			if not (slot_val3 is Dictionary):
				continue
			var slot3: Dictionary = slot_val3
			if str(slot3.get("employee_id", "")).is_empty():
				empty_index = i_empty2
				break
		if empty_index < 0:
			break
		structure[empty_index] = {"employee_id": emp_nm, "reports": []}
		used[emp_nm] = true

	# 计算剩余普通员工（用于分配到经理 reports）
	var remaining_non_managers: Array[String] = []
	# 1) 优先放入“手动分配”的下属（按 manager_id 匹配）
	for s_i in range(structure.size()):
		var slot_val = structure[s_i]
		if not (slot_val is Dictionary):
			continue
		var slot: Dictionary = slot_val
		var direct: String = str(slot.get("employee_id", ""))
		if direct.is_empty():
			continue
		var direct_def: EmployeeDef = EmployeeRegistryClass.get_def(direct)
		if direct_def == null:
			continue
		var cap := maxi(0, int(direct_def.manager_slots))
		if cap <= 0:
			continue

		var reps: Array[String] = []
		var pref_val = preferred_reports_by_manager.get(direct, null)
		if pref_val is Array:
			var pref: Array = pref_val
			for p_i in range(pref.size()):
				var rep_val = pref[p_i]
				if not (rep_val is String):
					continue
				var rep_id: String = str(rep_val)
				if rep_id.is_empty() or rep_id == "ceo":
					continue
				if used.has(rep_id):
					continue
				if not non_managers.has(rep_id):
					continue
				reps.append(rep_id)
				used[rep_id] = true
				if reps.size() >= cap:
					break
		slot["reports"] = reps
		structure[s_i] = slot

	# 2) 自动补齐剩余普通员工到经理卡槽（经理只能直接向 CEO 汇报，且下属不能是经理）
	for emp_nm2 in non_managers:
		if not used.has(emp_nm2):
			remaining_non_managers.append(emp_nm2)

	var nm_index := 0
	for s_i2 in range(structure.size()):
		var slot_val2 = structure[s_i2]
		if not (slot_val2 is Dictionary):
			continue
		var slot2: Dictionary = slot_val2
		var direct2: String = str(slot2.get("employee_id", ""))
		if direct2.is_empty():
			continue
		var direct_def2: EmployeeDef = EmployeeRegistryClass.get_def(direct2)
		if direct_def2 == null:
			continue
		var cap2 := maxi(0, int(direct_def2.manager_slots))
		if cap2 <= 0:
			continue
		var reps2_val = slot2.get("reports", [])
		var reps2: Array[String] = reps2_val if reps2_val is Array else []
		while reps2.size() < cap2 and nm_index < remaining_non_managers.size():
			reps2.append(remaining_non_managers[nm_index])
			nm_index += 1
		slot2["reports"] = reps2
		structure[s_i2] = slot2

	cs["structure"] = structure
	player["company_structure"] = cs
	state.players[player_id] = player

	# 标记已提交
	assert(state.round_state is Dictionary, "submit_restructuring: round_state 类型错误（期望 Dictionary）")
	var r: Dictionary = state.round_state.get("restructuring", {})
	var submitted: Dictionary = r.get("submitted", {})
	submitted[player_id] = true
	r["submitted"] = submitted
	state.round_state["restructuring"] = r

	# 更新阻断器
	if state.round_state.has("pending_phase_actions"):
		var ppa_val = state.round_state.get("pending_phase_actions", null)
		if ppa_val is Dictionary:
			var ppa: Dictionary = ppa_val
			if ppa.has("Restructuring") and (ppa["Restructuring"] is Array):
				var pending: Array = ppa["Restructuring"]
				pending.erase(player_id)
				ppa["Restructuring"] = pending
				state.round_state["pending_phase_actions"] = ppa
	state.round_state["restructuring"] = r

	# 计算是否全部提交（不依赖 pending_phase_actions 是否存在）
	var all_submitted := true
	for pid2 in range(state.players.size()):
		if not bool(submitted.get(pid2, false)):
			all_submitted = false
			break
	r["finalized"] = all_submitted
	state.round_state["restructuring"] = r

	# 若已全部提交，清理阻断器 key（避免残留空数组）
	if all_submitted and state.round_state.has("pending_phase_actions"):
		var ppa_val2 = state.round_state.get("pending_phase_actions", null)
		if ppa_val2 is Dictionary:
			var ppa2: Dictionary = ppa_val2
			ppa2.erase("Restructuring")
			state.round_state["pending_phase_actions"] = ppa2

	# 推进到下一位未提交玩家
	var size := state.turn_order.size()
	if size > 0 and not all_submitted:
		for offset in range(1, size + 1):
			var idx := state.current_player_index + offset
			if idx >= size:
				idx = idx % size
			var pid_val = state.turn_order[idx]
			if not (pid_val is int):
				continue
			var pid: int = int(pid_val)
			if not bool(submitted.get(pid, false)):
				state.current_player_index = idx
				break

	# 所有人都提交后，自动进入下一阶段
	if all_submitted and phase_manager != null:
		var adv := phase_manager.advance_phase(state)
		if not adv.ok:
			return adv
		warnings.append_array(adv.warnings)

	return Result.success({
		"player_id": player_id,
		"overflow": overflow
	}).with_warnings(warnings)
