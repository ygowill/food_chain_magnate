# 重组阶段：设置 CEO 直属卡槽（hotseat）
# 通过拖拽把员工放入 CEO 直属槽，写入 player.company_structure.structure
# 注意：这是内部动作（不在 ActionPanel 中显示），用于 UI 拖拽交互。
class_name SetCompanyStructureDirectAction
extends ActionExecutor

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const OnlinePhaseInteractionClass = preload("res://core/utils/online_phase_interaction.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

func _init() -> void:
	action_id = "set_company_structure_direct"
	display_name = "设置公司结构（直属）"
	description = "设置 CEO 直属卡槽的员工"
	requires_actor = true
	is_mandatory = false
	is_internal = true
	allowed_phases = [DefsClass.PHASE_RESTRUCTURING]

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if state.phase != DefsClass.PHASE_RESTRUCTURING:
		return Result.failure("当前不在 Restructuring")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if not EmployeeRegistryClass.is_loaded():
		return Result.failure("EmployeeRegistry 未初始化")
	if command.actor < 0 or command.actor >= state.players.size():
		return Result.failure("玩家不存在: %d" % command.actor)

	# 已提交后禁止修改
	var r_val = state.round_state.get("restructuring", null)
	if r_val is Dictionary:
		var r: Dictionary = r_val
		var submitted_val = r.get("submitted", null)
		if submitted_val is Dictionary:
			var submitted: Dictionary = submitted_val
			var submitted_flag = submitted.get(command.actor, null)
			if submitted_flag == null and submitted.has(str(command.actor)):
				submitted_flag = submitted.get(str(command.actor), null)
			if bool(submitted_flag) and not OnlinePhaseInteractionClass.can_player_reopen_online_restructuring(state, command.actor):
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
	var cs_read := PlayerStateAccessClass.require_company_structure(player, "player", "")
	if not cs_read.ok:
		return cs_read

	var employees_read := PlayerStateAccessClass.require_employees(player, "player", "")
	if not employees_read.ok:
		return employees_read
	var employees: Array = employees_read.value

	var reserve_read := PlayerStateAccessClass.require_reserve_employees(player, "player", "")
	if not reserve_read.ok:
		return reserve_read
	var reserve: Array = reserve_read.value

	var busy_read := PlayerStateAccessClass.require_busy_marketers(player, "player", "")
	if not busy_read.ok:
		return busy_read
	var busy: Array = busy_read.value

	if not employees.has(employee_id) and not reserve.has(employee_id):
		if busy.has(employee_id):
			return Result.failure("忙碌营销员不能被放入公司结构: %s" % employee_id)
		return Result.failure("员工不属于当前玩家: %s" % employee_id)

	var cs: Dictionary = cs_read.value
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
	var payload_read := _require_apply_payload(command)
	if not payload_read.ok:
		return payload_read
	var payload: Dictionary = payload_read.value
	var slot_index: int = int(payload.get("slot_index", -1))
	var employee_id: String = str(payload.get("employee_id", ""))

	var context_read := _require_apply_context(state, command.actor, slot_index)
	if not context_read.ok:
		return context_read
	OnlinePhaseInteractionClass.clear_player_restructuring_submission_for_online_reopen(state, command.actor)
	var context: Dictionary = context_read.value
	var player: Dictionary = context.get("player", {})
	var employees: Array = context.get("employees", [])
	var reserve: Array = context.get("reserve", [])
	var cs: Dictionary = context.get("company_structure", {})
	var ceo_slots: int = int(context.get("ceo_slots", 0))

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

	# 写入目标槽位（清空 reports，避免与后续分配混淆）
	var target: Dictionary = normalized[slot_index]
	target["employee_id"] = employee_id
	target["reports"] = []
	normalized[slot_index] = target

	# 直属槽中的员工必须为在岗：若当前直属+下属占用数量超过在岗数量，
	# 则优先从 reserve_employees 补齐到 employees（支持同名员工多张/多实例）。
	var assigned_count := _count_employee_in_structure(normalized, employee_id)
	var active_count := _count_employee_in_array(employees, employee_id)
	if assigned_count > active_count:
		var need := assigned_count - active_count
		for _i in range(need):
			if not reserve.has(employee_id):
				break
			var moved := StateUpdater.remove_from_array(player, "reserve_employees", employee_id)
			if not moved:
				break
			StateUpdater.append_to_array(player, "employees", employee_id)
			employees = player["employees"]
			reserve = player["reserve_employees"]
		active_count = _count_employee_in_array(employees, employee_id)

	# 允许“非唯一员工”重复出现在多个槽位，但不允许超过在岗数量。
	# 若超过，则从其它位置（优先 reports，再直属槽）移除多余占用（相当于移动一个实例）。
	if assigned_count > active_count:
		var to_remove := assigned_count - active_count
		_remove_employee_from_structure(normalized, employee_id, to_remove, slot_index)

	cs["structure"] = normalized
	player["company_structure"] = cs
	state.players[command.actor] = player

	return Result.success({
		"player_id": command.actor,
		"slot_index": slot_index,
		"employee_id": employee_id
	})

func _require_apply_payload(command: Command) -> Result:
	var slot_index_r := require_int_param(command, "slot_index")
	if not slot_index_r.ok:
		return Result.failure("set_company_structure_direct: 缺少/错误参数: slot_index")
	var slot_index: int = int(slot_index_r.value)
	if slot_index < 0:
		return Result.failure("set_company_structure_direct: slot_index 不能为负数: %d" % slot_index)

	var employee_id_r := require_string_param(command, "employee_id")
	if not employee_id_r.ok:
		return Result.failure("set_company_structure_direct: 缺少/错误参数: employee_id")
	var employee_id: String = employee_id_r.value
	if employee_id == "ceo":
		return Result.failure("set_company_structure_direct: CEO 不能被放入直属卡槽")

	return Result.success({
		"slot_index": slot_index,
		"employee_id": employee_id
	})

func _require_apply_context(state: GameState, player_id: int, slot_index: int) -> Result:
	var player_read := PlayerStateAccessClass.require_player(state, player_id, "set_company_structure_direct")
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var player_label := "player[%d]" % player_id

	var employees_read := PlayerStateAccessClass.require_employees(player, player_label, "set_company_structure_direct")
	if not employees_read.ok:
		return employees_read
	var reserve_read := PlayerStateAccessClass.require_reserve_employees(player, player_label, "set_company_structure_direct")
	if not reserve_read.ok:
		return reserve_read
	var cs_read := PlayerStateAccessClass.require_company_structure(player, player_label, "set_company_structure_direct")
	if not cs_read.ok:
		return cs_read
	var ceo_slots_read := _require_apply_ceo_slots(cs_read.value)
	if not ceo_slots_read.ok:
		return ceo_slots_read
	var ceo_slots: int = int(ceo_slots_read.value)
	if slot_index >= ceo_slots:
		return Result.failure("set_company_structure_direct: slot_index 超出范围: %d >= %d" % [slot_index, ceo_slots])

	return Result.success({
		"player": player,
		"employees": employees_read.value,
		"reserve": reserve_read.value,
		"company_structure": cs_read.value,
		"ceo_slots": ceo_slots,
	})

func _require_apply_ceo_slots(company_structure: Dictionary) -> Result:
	if not company_structure.has("ceo_slots"):
		return Result.failure("set_company_structure_direct: player.company_structure.ceo_slots 缺失")
	var slots_raw = company_structure.get("ceo_slots", null)
	if not (slots_raw is int) and not (slots_raw is float):
		return Result.failure("set_company_structure_direct: player.company_structure.ceo_slots 类型错误（期望 int/float）")
	if slots_raw is float:
		var f: float = float(slots_raw)
		if f != floor(f):
			return Result.failure("set_company_structure_direct: player.company_structure.ceo_slots 必须为整数")
	var ceo_slots := int(slots_raw)
	if ceo_slots <= 0:
		return Result.failure("set_company_structure_direct: ceo_slots 无效: %d" % ceo_slots)
	return Result.success(ceo_slots)

static func _count_employee_in_array(list: Array, employee_id: String) -> int:
	if list == null:
		return 0
	var emp_id := str(employee_id)
	if emp_id.is_empty():
		return 0
	var count := 0
	for v in list:
		if v is String and str(v) == emp_id:
			count += 1
	return count

static func _count_employee_in_structure(structure: Array, employee_id: String) -> int:
	if structure == null:
		return 0
	var emp_id := str(employee_id)
	if emp_id.is_empty():
		return 0
	var count := 0
	for i in range(structure.size()):
		var entry_val = structure[i]
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		if str(entry.get("employee_id", "")) == emp_id:
			count += 1
		var reps_val = entry.get("reports", null)
		if reps_val is Array:
			var reps: Array = reps_val
			for rep_val in reps:
				if rep_val is String and str(rep_val) == emp_id:
					count += 1
	return count

static func _remove_employee_from_structure(structure: Array, employee_id: String, remove_count: int, skip_slot_index: int) -> int:
	if structure == null:
		return 0
	var emp_id := str(employee_id)
	if emp_id.is_empty() or remove_count <= 0:
		return 0

	var removed := 0

	# 1) 优先从 reports 移除（尽量不影响直属槽布局）
	for i in range(structure.size()):
		if removed >= remove_count:
			break
		if i == skip_slot_index:
			continue
		var entry_val = structure[i]
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		var reps_val = entry.get("reports", null)
		if reps_val is Array:
			var reps: Array = reps_val
			while removed < remove_count and reps.has(emp_id):
				reps.erase(emp_id)
				removed += 1
			entry["reports"] = reps
			structure[i] = entry

	# 2) 再从其它直属槽移除（清空 employee_id 与 reports）
	for i2 in range(structure.size()):
		if removed >= remove_count:
			break
		if i2 == skip_slot_index:
			continue
		var entry_val2 = structure[i2]
		if not (entry_val2 is Dictionary):
			continue
		var entry2: Dictionary = entry_val2
		if str(entry2.get("employee_id", "")) == emp_id:
			entry2["employee_id"] = ""
			entry2["reports"] = []
			structure[i2] = entry2
			removed += 1

	return removed
