# 重组阶段：提交公司结构（hotseat）
# - 要求每位玩家提交后才能离开 Restructuring
# - 以 player.company_structure.structure 作为本回合“在岗/公司结构”的真值：
#   - 只有放入 structure（CEO 直属 + 经理下属）中的员工才算在岗（player.employees）
#   - 未放入 structure 的员工停留在 reserve_employees（仍可能需要支付薪资）
class_name SubmitRestructuringAction
extends ActionExecutor

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

var phase_manager: PhaseManager = null

func _init(manager: PhaseManager = null) -> void:
	action_id = "submit_restructuring"
	display_name = "确认重组"
	description = "提交本回合公司结构"
	requires_actor = true
	is_mandatory = false
	allowed_phases = [DefsClass.PHASE_RESTRUCTURING]
	phase_manager = manager

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if state.phase != DefsClass.PHASE_RESTRUCTURING:
		return Result.failure("当前不在 Restructuring")
	if not EmployeeRegistryClass.is_loaded():
		return Result.failure("EmployeeRegistry 未初始化")
	if command.actor < 0 or command.actor >= state.players.size():
		return Result.failure("玩家不存在: %d" % command.actor)

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
	var cs_read := PlayerStateAccessClass.require_company_structure(player, "player", "")
	if not cs_read.ok:
		return cs_read
	var cs: Dictionary = cs_read.value
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

	# 严格校验：employees 必须为有效员工列表（允许非唯一员工出现重复）
	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			return Result.failure("player.employees[%d] 类型错误（期望 String）" % i)
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("player.employees[%d] 不能为空" % i)
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

	# === Normalize + prune structure based on manager capacity and owned employees ===
	var owned_counts: Dictionary = {} # employee_id -> count (employees+reserve, excluding CEO)
	for arr in [employees, reserve]:
		for v in Array(arr):
			if not (v is String):
				continue
			var eid := str(v).strip_edges()
			if eid.is_empty() or eid == "ceo":
				continue
			owned_counts[eid] = int(owned_counts.get(eid, 0)) + 1

	var raw_struct_val = cs.get("structure", null)
	var raw_struct: Array = raw_struct_val if raw_struct_val is Array else []

	var used_counts: Dictionary = {} # employee_id -> count (placed in structure after pruning)
	var normalized: Array = []

	for i_slot in range(ceo_slots):
		var entry := {"employee_id": "", "reports": []}
		if i_slot < raw_struct.size():
			var e_val = raw_struct[i_slot]
			if e_val is Dictionary:
				var e: Dictionary = e_val
				var direct_id := ""
				var id_val = e.get("employee_id", null)
				if id_val is String:
					direct_id = str(id_val).strip_edges()
				if direct_id == "ceo":
					direct_id = ""

				if not direct_id.is_empty():
					if not EmployeeRegistryClass.has(direct_id):
						warnings.append("重组提交：未知员工已从结构移除: %s" % direct_id)
						direct_id = ""
					else:
						var owned: int = int(owned_counts.get(direct_id, 0))
						var used: int = int(used_counts.get(direct_id, 0))
						if used >= owned:
							warnings.append("重组提交：员工数量不足，已从结构移除: %s" % direct_id)
							direct_id = ""
						else:
							used_counts[direct_id] = used + 1

				entry["employee_id"] = direct_id

				var cap := 0
				if not direct_id.is_empty():
					var def_val = EmployeeRegistryClass.get_def(direct_id)
					if def_val != null and (def_val is EmployeeDef):
						var def: EmployeeDef = def_val
						cap = maxi(0, int(def.manager_slots))

				var reps_val = e.get("reports", null)
				var reps_any: Array = reps_val if reps_val is Array else []
				var reports: Array[String] = []

				if cap > 0:
					for rep_val in reps_any:
						if reports.size() >= cap:
							break
						if not (rep_val is String):
							continue
						var rep_id := str(rep_val).strip_edges()
						if rep_id.is_empty() or rep_id == "ceo":
							continue
						if not EmployeeRegistryClass.has(rep_id):
							warnings.append("重组提交：未知员工已从下属移除: %s" % rep_id)
							continue
						var rep_def_val = EmployeeRegistryClass.get_def(rep_id)
						if rep_def_val == null or not (rep_def_val is EmployeeDef):
							continue
						var rep_def: EmployeeDef = rep_def_val
						var rep_is_manager := (str(rep_def.role) == "manager") or (maxi(0, int(rep_def.manager_slots)) > 0)
						if rep_is_manager:
							warnings.append("重组提交：经理不能作为下属，已移除: %s" % rep_id)
							continue
						var owned_rep: int = int(owned_counts.get(rep_id, 0))
						var used_rep: int = int(used_counts.get(rep_id, 0))
						if used_rep >= owned_rep:
							warnings.append("重组提交：员工数量不足，已从下属移除: %s" % rep_id)
							continue
						used_counts[rep_id] = used_rep + 1
						reports.append(rep_id)
				else:
					if not reps_any.is_empty() and not direct_id.is_empty():
						warnings.append("重组提交：%s 无下属卡槽，已清空下属列表" % direct_id)

				entry["reports"] = reports
		normalized.append(entry)

	# === Sync active employees from normalized structure ===
	var need_counts: Dictionary = {}
	for k in used_counts.keys():
		need_counts[str(k)] = int(used_counts.get(k, 0))

	var new_employees: Array[String] = ["ceo"]
	var new_reserve: Array[String] = []

	for v2 in Array(employees):
		if not (v2 is String):
			continue
		var eid2 := str(v2).strip_edges()
		if eid2.is_empty() or eid2 == "ceo":
			continue
		var need: int = int(need_counts.get(eid2, 0))
		if need > 0:
			new_employees.append(eid2)
			need_counts[eid2] = need - 1
		else:
			new_reserve.append(eid2)

	for v3 in Array(reserve):
		if not (v3 is String):
			continue
		var eid3 := str(v3).strip_edges()
		if eid3.is_empty() or eid3 == "ceo":
			continue
		var need2: int = int(need_counts.get(eid3, 0))
		if need2 > 0:
			new_employees.append(eid3)
			need_counts[eid3] = need2 - 1
		else:
			new_reserve.append(eid3)

	player["employees"] = new_employees
	player["reserve_employees"] = new_reserve

	cs["structure"] = normalized
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
			if ppa.has(DefsClass.PHASE_RESTRUCTURING) and (ppa[DefsClass.PHASE_RESTRUCTURING] is Array):
				var pending: Array = ppa[DefsClass.PHASE_RESTRUCTURING]
				pending.erase(player_id)
				ppa[DefsClass.PHASE_RESTRUCTURING] = pending
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
			ppa2.erase(DefsClass.PHASE_RESTRUCTURING)
			state.round_state["pending_phase_actions"] = ppa2

		# Restructuring 为“同时进行”：不推进 current_player_index（避免隐式顺序/误导 UI）。

	# 所有人都提交后，自动进入下一阶段
	# NOTE: 阶段推进由 AutoAdvance 负责（确保“确认重组”日志先出现，再出现阶段标题切换）。

	return Result.success({
		"player_id": player_id,
		"overflow": false
	}).with_warnings(warnings)
