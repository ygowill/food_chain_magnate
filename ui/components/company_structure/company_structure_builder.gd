# CompanyStructure：公司结构（显示/预览）生成逻辑
# 注意：该文件不依赖 Node/Control，只做纯数据结构生成。
extends RefCounted

func build_strict_structure_from_employees(ceo_slots: int, employees: Array, get_employee_def: Callable) -> Array:
	var empty_direct: Array[String] = []
	for _i in range(maxi(0, int(ceo_slots))):
		empty_direct.append("")
	return build_strict_structure_from_employees_with_preferred_direct(ceo_slots, employees, empty_direct, {}, get_employee_def)

func build_strict_structure_from_employees_with_preferred_direct(
	ceo_slots: int,
	employees: Array,
	preferred_direct: Array[String],
	preferred_reports_by_slot: Dictionary,
	get_employee_def: Callable
) -> Array:
	if employees.is_empty():
		return []

	var slots := maxi(0, int(ceo_slots))

	var managers: Array[String] = []
	var non_managers: Array[String] = []
	var available_counts: Dictionary = {}  # employee_id -> count（在岗）

	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			continue
		var emp_id: String = str(emp_val)
		if emp_id.is_empty() or emp_id == "ceo":
			continue
		var prev_val = available_counts.get(emp_id, 0)
		available_counts[emp_id] = int(prev_val) + 1

		var def: Dictionary = {}
		if get_employee_def != null and get_employee_def.is_valid():
			var def_val = get_employee_def.call(emp_id)
			def = def_val if (def_val is Dictionary) else {}

		var ms := maxi(0, int(def.get("manager_slots", 0)))
		var role := str(def.get("role", "")).strip_edges()
		var is_manager := role == "manager" or ms > 0
		if is_manager:
			managers.append(emp_id)
		else:
			non_managers.append(emp_id)

	var structure: Array = []
	for _i in range(slots):
		structure.append({"employee_id": "", "reports": []})

	var used_counts: Dictionary = {}  # employee_id -> used_count（直属 + 下属）

	# 1) 优先放入“手动分配”的 CEO 直属槽
	for i_slot in range(slots):
		var pick := ""
		if i_slot < preferred_direct.size():
			var v = preferred_direct[i_slot]
			if v is String:
				pick = str(v)
		if pick.is_empty() or pick == "ceo":
			continue
		var avail: int = int(available_counts.get(pick, 0))
		if avail <= 0:
			continue
		var used_now: int = int(used_counts.get(pick, 0))
		if used_now >= avail:
			continue
		structure[i_slot] = {"employee_id": pick, "reports": []}
		used_counts[pick] = used_now + 1

	# 2) 尽量放入经理（必要时替换非经理直属槽）
	for m in managers:
		var m_id: String = str(m)
		if m_id.is_empty() or m_id == "ceo":
			continue
		var avail_m: int = int(available_counts.get(m_id, 0))
		if avail_m <= 0:
			continue
		var used_m: int = int(used_counts.get(m_id, 0))
		if used_m >= avail_m:
			continue

		var placed := false
		for i_empty in range(structure.size()):
			var slot_val = structure[i_empty]
			if not (slot_val is Dictionary):
				continue
			var slot: Dictionary = slot_val
			if str(slot.get("employee_id", "")).is_empty():
				structure[i_empty] = {"employee_id": m_id, "reports": []}
				used_counts[m_id] = used_m + 1
				placed = true
				break

		if placed:
			continue

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

			var direct_def2: Dictionary = {}
			if get_employee_def != null and get_employee_def.is_valid():
				var direct_def2_val = get_employee_def.call(direct2)
				direct_def2 = direct_def2_val if (direct_def2_val is Dictionary) else {}

			var cap2 := maxi(0, int(direct_def2.get("manager_slots", 0)))
			var direct_role2 := str(direct_def2.get("role", "")).strip_edges()
			var direct_is_manager2 := direct_role2 == "manager" or cap2 > 0
			if not direct_is_manager2:
				replace_index = i_rep
				replaced_emp = direct2
				break

		if replace_index < 0:
			break

		structure[replace_index] = {"employee_id": m_id, "reports": []}
		used_counts[m_id] = used_m + 1
		if not replaced_emp.is_empty():
			var prev_used: int = int(used_counts.get(replaced_emp, 0))
			if prev_used > 0:
				used_counts[replaced_emp] = prev_used - 1

	# 3) 补齐剩余空槽：放入普通员工
	for emp_nm in non_managers:
		var emp_id: String = str(emp_nm)
		if emp_id.is_empty() or emp_id == "ceo":
			continue
		var avail_nm: int = int(available_counts.get(emp_id, 0))
		if avail_nm <= 0:
			continue
		var used_nm: int = int(used_counts.get(emp_id, 0))
		if used_nm >= avail_nm:
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
		structure[empty_index] = {"employee_id": emp_id, "reports": []}
		used_counts[emp_id] = used_nm + 1

	# 4) 分配剩余普通员工到经理卡槽
	var remaining_non_managers: Array[String] = []

	# 4.1) 优先放入“手动分配”的下属（按 slot_index 匹配）
	for s_i in range(structure.size()):
		var slot_val4 = structure[s_i]
		if not (slot_val4 is Dictionary):
			continue
		var slot4: Dictionary = slot_val4
		var direct: String = str(slot4.get("employee_id", ""))
		if direct.is_empty():
			continue

		var direct_def: Dictionary = {}
		if get_employee_def != null and get_employee_def.is_valid():
			var direct_def_val = get_employee_def.call(direct)
			direct_def = direct_def_val if (direct_def_val is Dictionary) else {}

		var cap := maxi(0, int(direct_def.get("manager_slots", 0)))
		if cap <= 0:
			continue

		var reps: Array[String] = []
		var pref_val = preferred_reports_by_slot.get(s_i, null)
		if pref_val is Array:
			var pref: Array = pref_val
			for p_i in range(pref.size()):
				var rep_val = pref[p_i]
				if not (rep_val is String):
					continue
				var rep_id: String = str(rep_val)
				if rep_id.is_empty() or rep_id == "ceo":
					continue
				var avail_rep: int = int(available_counts.get(rep_id, 0))
				if avail_rep <= 0:
					continue

				var rep_def: Dictionary = {}
				if get_employee_def != null and get_employee_def.is_valid():
					var rep_def_val = get_employee_def.call(rep_id)
					rep_def = rep_def_val if (rep_def_val is Dictionary) else {}

				var rep_ms := maxi(0, int(rep_def.get("manager_slots", 0)))
				var rep_role := str(rep_def.get("role", "")).strip_edges()
				var rep_is_manager := rep_role == "manager" or rep_ms > 0
				if rep_is_manager:
					continue
				var used_rep: int = int(used_counts.get(rep_id, 0))
				if used_rep >= avail_rep:
					continue
				reps.append(rep_id)
				used_counts[rep_id] = used_rep + 1
				if reps.size() >= cap:
					break
		slot4["reports"] = reps
		structure[s_i] = slot4

	# 4.2) 自动补齐剩余普通员工到经理卡槽（保序，允许同类型重复）
	var remaining_count_by_id: Dictionary = {}
	for emp_nm2 in non_managers:
		var emp_id2: String = str(emp_nm2)
		if emp_id2.is_empty() or emp_id2 == "ceo":
			continue
		if remaining_count_by_id.has(emp_id2):
			continue
		var avail2: int = int(available_counts.get(emp_id2, 0))
		var used2: int = int(used_counts.get(emp_id2, 0))
		remaining_count_by_id[emp_id2] = maxi(0, avail2 - used2)

	for emp_nm3 in non_managers:
		var emp_id3: String = str(emp_nm3)
		if emp_id3.is_empty() or emp_id3 == "ceo":
			continue
		var rem_val = remaining_count_by_id.get(emp_id3, 0)
		var rem: int = int(rem_val)
		if rem <= 0:
			continue
		remaining_non_managers.append(emp_id3)
		remaining_count_by_id[emp_id3] = rem - 1

	var nm_index := 0
	for s_i2 in range(structure.size()):
		var slot_val5 = structure[s_i2]
		if not (slot_val5 is Dictionary):
			continue
		var slot5: Dictionary = slot_val5
		var direct2: String = str(slot5.get("employee_id", ""))
		if direct2.is_empty():
			continue

		var direct_def2: Dictionary = {}
		if get_employee_def != null and get_employee_def.is_valid():
			var direct_def2_val = get_employee_def.call(direct2)
			direct_def2 = direct_def2_val if (direct_def2_val is Dictionary) else {}

		var cap2 := maxi(0, int(direct_def2.get("manager_slots", 0)))
		if cap2 <= 0:
			continue
		var reps_val2 = slot5.get("reports", [])
		var reps2: Array[String] = reps_val2 if reps_val2 is Array else []
		while reps2.size() < cap2 and nm_index < remaining_non_managers.size():
			reps2.append(remaining_non_managers[nm_index])
			nm_index += 1
		slot5["reports"] = reps2
		structure[s_i2] = slot5

	return structure

