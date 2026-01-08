# 重组阶段：设置经理下属（hotseat）
# 将普通员工分配到某位经理的 reports 下（用于表达汇报关系）。
# 注意：这是内部动作（不在 ActionPanel 中显示），用于 UI 拖拽交互。
class_name SetCompanyStructureReportAction
extends ActionExecutor

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

func _init() -> void:
	action_id = "set_company_structure_report"
	display_name = "设置公司结构（下属）"
	description = "将员工分配为某位经理的下属"
	requires_actor = true
	is_mandatory = false
	is_internal = true
	allowed_phases = ["Restructuring"]

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if state.phase != "Restructuring":
		return Result.failure("当前不在 Restructuring")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if not EmployeeRegistryClass.is_loaded():
		return Result.failure("EmployeeRegistry 未初始化")

	# hotseat：必须是当前玩家
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	# 已提交后禁止修改
	var r_val = state.round_state.get("restructuring", null)
	if r_val is Dictionary:
		var r: Dictionary = r_val
		var submitted_val = r.get("submitted", null)
		if submitted_val is Dictionary:
			var submitted: Dictionary = submitted_val
			if bool(submitted.get(command.actor, false)):
				return Result.failure("已提交重组，无法再调整公司结构")

	var slot_index_r := require_int_param(command, "manager_slot_index")
	if not slot_index_r.ok:
		return slot_index_r
	var manager_slot_index: int = int(slot_index_r.value)
	if manager_slot_index < 0:
		return Result.failure("manager_slot_index 不能为负数: %d" % manager_slot_index)

	var employee_id_r := require_string_param(command, "employee_id")
	if not employee_id_r.ok:
		return employee_id_r
	var employee_id: String = employee_id_r.value
	if employee_id == "ceo":
		return Result.failure("CEO 不能成为下属")
	if not EmployeeRegistryClass.has(employee_id):
		return Result.failure("未知员工: %s" % employee_id)

	var emp_def: EmployeeDef = EmployeeRegistryClass.get_def(employee_id)
	var emp_ms := maxi(0, int(emp_def.manager_slots))
	if emp_ms > 0:
		return Result.failure("经理不能成为下属（必须直连 CEO）: %s" % employee_id)

	var player := state.get_player(command.actor)
	if player.is_empty():
		return Result.failure("玩家不存在: %d" % command.actor)
	if not player.has("employees") or not (player["employees"] is Array):
		return Result.failure("player.employees 缺失或类型错误（期望 Array）")
	if not player.has("reserve_employees") or not (player["reserve_employees"] is Array):
		return Result.failure("player.reserve_employees 缺失或类型错误（期望 Array）")
	if not player.has("busy_marketers") or not (player["busy_marketers"] is Array):
		return Result.failure("player.busy_marketers 缺失或类型错误（期望 Array）")
	if not player.has("company_structure") or not (player["company_structure"] is Dictionary):
		return Result.failure("player.company_structure 缺失或类型错误（期望 Dictionary）")

	var employees: Array = player["employees"]
	var reserve: Array = player["reserve_employees"]
	var busy: Array = player["busy_marketers"]
	if busy.has(employee_id):
		return Result.failure("忙碌营销员不能成为下属: %s" % employee_id)
	if not employees.has(employee_id) and not reserve.has(employee_id):
		return Result.failure("员工不属于当前玩家: %s" % employee_id)

	var cs: Dictionary = player["company_structure"]
	if not cs.has("ceo_slots"):
		return Result.failure("player.company_structure.ceo_slots 缺失")
	var slots_val = cs.get("ceo_slots", null)
	if not (slots_val is int) and not (slots_val is float):
		return Result.failure("player.company_structure.ceo_slots 类型错误（期望 int/float）")
	if slots_val is float and float(slots_val) != floor(float(slots_val)):
		return Result.failure("player.company_structure.ceo_slots 必须为整数（不允许小数）")
	var ceo_slots := int(slots_val)
	if ceo_slots <= 0:
		return Result.failure("CEO 卡槽数无效: %d" % ceo_slots)
	if manager_slot_index >= ceo_slots:
		return Result.failure("manager_slot_index 超出范围: %d >= %d" % [manager_slot_index, ceo_slots])

	# 要求该槽位已明确放置“经理”（先做直属槽，再做下属分配）
	var struct_val = cs.get("structure", null)
	if not (struct_val is Array):
		return Result.failure("请先设置 CEO 直属槽（company_structure.structure 未初始化）")
	var structure: Array = struct_val
	if manager_slot_index >= structure.size():
		return Result.failure("请先设置 CEO 直属槽（目标槽位不存在）")
	var entry_val = structure[manager_slot_index]
	if not (entry_val is Dictionary):
		return Result.failure("company_structure.structure[%d] 类型错误（期望 Dictionary）" % manager_slot_index)
	var entry: Dictionary = entry_val
	var manager_id: String = str(entry.get("employee_id", ""))
	if manager_id.is_empty():
		return Result.failure("请先在该 CEO 直属槽放置经理")
	if not employees.has(manager_id):
		return Result.failure("目标经理不在在岗区: %s" % manager_id)
	var m_def: EmployeeDef = EmployeeRegistryClass.get_def(manager_id)
	var cap := maxi(0, int(m_def.manager_slots))
	if cap <= 0:
		return Result.failure("目标槽位不是经理（无下属卡槽）: %s" % manager_id)

	# 检查容量（按当前已分配的有效下属计数）
	var reports_val = entry.get("reports", [])
	var raw_reports: Array = reports_val if reports_val is Array else []
	var seen := {}
	var current_reports: Array[String] = []
	for i in range(raw_reports.size()):
		var rep_val = raw_reports[i]
		if not (rep_val is String):
			continue
		var rep_id: String = str(rep_val)
		if rep_id.is_empty() or rep_id == "ceo":
			continue
		if rep_id == employee_id:
			continue
		if seen.has(rep_id):
			continue
		if not employees.has(rep_id):
			continue
		var rep_def: EmployeeDef = EmployeeRegistryClass.get_def(rep_id)
		if maxi(0, int(rep_def.manager_slots)) > 0:
			continue
		seen[rep_id] = true
		current_reports.append(rep_id)

	if current_reports.size() >= cap:
		return Result.failure("该经理下属卡槽已满（%d/%d）" % [current_reports.size(), cap])

	return Result.success({
		"manager_slot_index": manager_slot_index,
		"employee_id": employee_id
	})

func _apply_changes(state: GameState, command: Command) -> Result:
	var slot_index_r := require_int_param(command, "manager_slot_index")
	assert(slot_index_r.ok, "set_company_structure_report: 缺少/错误参数: manager_slot_index")
	var manager_slot_index: int = int(slot_index_r.value)

	var employee_id_r := require_string_param(command, "employee_id")
	assert(employee_id_r.ok, "set_company_structure_report: 缺少/错误参数: employee_id")
	var employee_id: String = employee_id_r.value
	assert(employee_id != "ceo", "set_company_structure_report: validate 应已阻止 CEO")

	var player_id: int = command.actor
	var player_val = state.players[player_id]
	assert(player_val is Dictionary, "set_company_structure_report: player 类型错误（期望 Dictionary）")
	var player: Dictionary = player_val

	# 确保员工在岗（成为下属视为在岗）
	var employees_val = player.get("employees", null)
	var reserve_val = player.get("reserve_employees", null)
	assert(employees_val is Array, "set_company_structure_report: player.employees 类型错误（期望 Array）")
	assert(reserve_val is Array, "set_company_structure_report: player.reserve_employees 类型错误（期望 Array）")
	var employees: Array = employees_val
	var reserve: Array = reserve_val

	if reserve.has(employee_id) and not employees.has(employee_id):
		var removed := StateUpdater.remove_from_array(player, "reserve_employees", employee_id)
		if not removed:
			return Result.failure("移动员工到在岗失败（未在待命区找到）: %s" % employee_id)
		StateUpdater.append_to_array(player, "employees", employee_id)
		employees = player["employees"]
		reserve = player["reserve_employees"]

	var cs_val = player.get("company_structure", null)
	assert(cs_val is Dictionary, "set_company_structure_report: player.company_structure 类型错误（期望 Dictionary）")
	var cs: Dictionary = cs_val

	var slots_raw = cs.get("ceo_slots", 0)
	var ceo_slots := 0
	if slots_raw is int:
		ceo_slots = int(slots_raw)
	elif slots_raw is float:
		var f: float = float(slots_raw)
		assert(f == floor(f), "set_company_structure_report: ceo_slots 必须为整数")
		ceo_slots = int(f)
	assert(ceo_slots > 0, "set_company_structure_report: ceo_slots 无效: %d" % ceo_slots)
	assert(manager_slot_index >= 0 and manager_slot_index < ceo_slots, "set_company_structure_report: manager_slot_index 超出范围: %d" % manager_slot_index)

	var struct_val = cs.get("structure", null)
	var structure: Array = struct_val if struct_val is Array else []

	# 规范化结构长度与字段
	var normalized: Array = []
	for i in range(ceo_slots):
		var entry := {"employee_id": "", "reports": []}
		if i < structure.size():
			var e_val = structure[i]
			if e_val is Dictionary:
				var e: Dictionary = e_val
				if e.has("employee_id") and (e["employee_id"] is String):
					entry["employee_id"] = str(e["employee_id"])
				if e.has("reports") and (e["reports"] is Array):
					entry["reports"] = Array(e["reports"]).duplicate()
		normalized.append(entry)

	# 移除员工在其它位置的占用（直属/下属）
	for i2 in range(normalized.size()):
		var e2_val = normalized[i2]
		if not (e2_val is Dictionary):
			continue
		var e2: Dictionary = e2_val
		if str(e2.get("employee_id", "")) == employee_id:
			e2["employee_id"] = ""
		var reps_val = e2.get("reports", [])
		var reps: Array = reps_val if reps_val is Array else []
		if reps.has(employee_id):
			while reps.has(employee_id):
				reps.erase(employee_id)
			e2["reports"] = reps
		normalized[i2] = e2

	# 追加到目标经理的 reports（按容量）
	var target_val = normalized[manager_slot_index]
	assert(target_val is Dictionary, "set_company_structure_report: 目标槽位类型错误")
	var target: Dictionary = target_val
	var manager_id: String = str(target.get("employee_id", ""))
	if manager_id.is_empty():
		return Result.failure("目标槽位未放置经理")
	if not employees.has(manager_id):
		return Result.failure("目标经理不在在岗区: %s" % manager_id)
	var m_def: EmployeeDef = EmployeeRegistryClass.get_def(manager_id)
	var cap := maxi(0, int(m_def.manager_slots))
	if cap <= 0:
		return Result.failure("目标槽位不是经理（无下属卡槽）: %s" % manager_id)

	var reps_val2 = target.get("reports", [])
	var raw_reports2: Array = reps_val2 if reps_val2 is Array else []
	var seen2 := {}
	var reports2: Array[String] = []
	for i3 in range(raw_reports2.size()):
		var rep_val2 = raw_reports2[i3]
		if not (rep_val2 is String):
			continue
		var rep_id2: String = str(rep_val2)
		if rep_id2.is_empty() or rep_id2 == "ceo":
			continue
		if rep_id2 == employee_id:
			continue
		if seen2.has(rep_id2):
			continue
		if not employees.has(rep_id2):
			continue
		var rep_def2: EmployeeDef = EmployeeRegistryClass.get_def(rep_id2)
		if maxi(0, int(rep_def2.manager_slots)) > 0:
			continue
		seen2[rep_id2] = true
		reports2.append(rep_id2)

	if reports2.size() >= cap:
		return Result.failure("该经理下属卡槽已满（%d/%d）" % [reports2.size(), cap])
	reports2.append(employee_id)
	target["reports"] = reports2
	normalized[manager_slot_index] = target

	cs["structure"] = normalized
	player["company_structure"] = cs
	state.players[player_id] = player

	return Result.success({
		"player_id": player_id,
		"manager_slot_index": manager_slot_index,
		"employee_id": employee_id
	})

