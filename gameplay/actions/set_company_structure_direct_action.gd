# 重组阶段：设置 CEO 直属卡槽（hotseat）
# 通过拖拽把员工放入 CEO 直属槽，写入 player.company_structure.structure
# 注意：这是内部动作（不在 ActionPanel 中显示），用于 UI 拖拽交互。
class_name SetCompanyStructureDirectAction
extends ActionExecutor

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

func _init() -> void:
	action_id = "set_company_structure_direct"
	display_name = "设置公司结构（直属）"
	description = "设置 CEO 直属卡槽的员工"
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

	var slot_index_r := require_int_param(command, "slot_index")
	if not slot_index_r.ok:
		return slot_index_r
	var slot_index: int = int(slot_index_r.value)
	if slot_index < 0:
		return Result.failure("slot_index 不能为负数: %d" % slot_index)

	var employee_id_r := require_string_param(command, "employee_id")
	if not employee_id_r.ok:
		return employee_id_r
	var employee_id: String = employee_id_r.value
	if employee_id == "ceo":
		return Result.failure("CEO 不能被放入直属卡槽")
	if not EmployeeRegistryClass.has(employee_id):
		return Result.failure("未知员工: %s" % employee_id)

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
		return Result.failure("忙碌营销员不能被放入公司结构: %s" % employee_id)
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
	if ceo_slots < 0:
		return Result.failure("player.company_structure.ceo_slots 不能为负数: %d" % ceo_slots)
	if ceo_slots == 0:
		return Result.failure("CEO 卡槽数为 0，无法放置员工")
	if slot_index >= ceo_slots:
		return Result.failure("slot_index 超出范围: %d >= %d" % [slot_index, ceo_slots])

	return Result.success({
		"slot_index": slot_index,
		"employee_id": employee_id
	})

func _apply_changes(state: GameState, command: Command) -> Result:
	var slot_index_r := require_int_param(command, "slot_index")
	assert(slot_index_r.ok, "set_company_structure_direct: 缺少/错误参数: slot_index")
	var slot_index: int = int(slot_index_r.value)

	var employee_id_r := require_string_param(command, "employee_id")
	assert(employee_id_r.ok, "set_company_structure_direct: 缺少/错误参数: employee_id")
	var employee_id: String = employee_id_r.value
	assert(employee_id != "ceo", "set_company_structure_direct: validate 应已阻止 CEO")

	var player_id: int = command.actor
	var player_val = state.players[player_id]
	assert(player_val is Dictionary, "set_company_structure_direct: player 类型错误（期望 Dictionary）")
	var player: Dictionary = player_val

	# 确保员工在岗（放入直属槽视为在岗）
	var employees_val = player.get("employees", null)
	var reserve_val = player.get("reserve_employees", null)
	assert(employees_val is Array, "set_company_structure_direct: player.employees 类型错误（期望 Array）")
	assert(reserve_val is Array, "set_company_structure_direct: player.reserve_employees 类型错误（期望 Array）")
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
	assert(cs_val is Dictionary, "set_company_structure_direct: player.company_structure 类型错误（期望 Dictionary）")
	var cs: Dictionary = cs_val

	var slots_raw = cs.get("ceo_slots", 0)
	var ceo_slots := 0
	if slots_raw is int:
		ceo_slots = int(slots_raw)
	elif slots_raw is float:
		var f: float = float(slots_raw)
		assert(f == floor(f), "set_company_structure_direct: ceo_slots 必须为整数")
		ceo_slots = int(f)
	assert(ceo_slots > 0, "set_company_structure_direct: ceo_slots 无效: %d" % ceo_slots)
	assert(slot_index >= 0 and slot_index < ceo_slots, "set_company_structure_direct: slot_index 超出范围: %d" % slot_index)

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

	# 移除员工在其它槽位的占用（去重）
	for i2 in range(normalized.size()):
		var e2_val = normalized[i2]
		if not (e2_val is Dictionary):
			continue
		var e2: Dictionary = e2_val
		if str(e2.get("employee_id", "")) == employee_id:
			e2["employee_id"] = ""
			e2["reports"] = []
			normalized[i2] = e2

	# 写入目标槽位（清空 reports，避免与后续分配混淆）
	var target: Dictionary = normalized[slot_index]
	target["employee_id"] = employee_id
	target["reports"] = []
	normalized[slot_index] = target

	cs["structure"] = normalized
	player["company_structure"] = cs
	state.players[player_id] = player

	return Result.success({
		"player_id": player_id,
		"slot_index": slot_index,
		"employee_id": employee_id
	})
