extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

const ACTION_ID := "train"

static func _is_employee_used_before_training(state: GameState, player_id: int, employee_id: String) -> bool:
	if state == null or not (state.round_state is Dictionary):
		return false
	if employee_id.is_empty():
		return false

	# 生产
	var prod_val = state.round_state.get("production_counts", null)
	if prod_val is Dictionary:
		var all: Dictionary = prod_val
		if all.has(player_id) and all[player_id] is Dictionary:
			var per: Dictionary = all[player_id]
			if per.has(employee_id) and int(per.get(employee_id, 0)) > 0:
				return true

	# 采购
	var proc_val = state.round_state.get("procurement_counts", null)
	if proc_val is Dictionary:
		var all: Dictionary = proc_val
		if all.has(player_id) and all[player_id] is Dictionary:
			var per: Dictionary = all[player_id]
			if per.has(employee_id) and int(per.get(employee_id, 0)) > 0:
				return true

	# 营销发起
	var mk_val = state.round_state.get("marketing_used", null)
	if mk_val is Dictionary:
		var all: Dictionary = mk_val
		if all.has(player_id) and all[player_id] is Dictionary:
			var per: Dictionary = all[player_id]
			if per.has(employee_id) and int(per.get(employee_id, 0)) > 0:
				return true

	# 价格强制动作
	var mac_val = state.round_state.get("mandatory_actions_completed", null)
	if mac_val is Dictionary and mac_val.has(player_id) and mac_val[player_id] is Array:
		var completed: Array = mac_val[player_id]
		var def_val_ma = EmployeeRegistryClass.get_def(employee_id)
		if def_val_ma is EmployeeDef:
			var def_ma: EmployeeDef = def_val_ma
			if not def_ma.mandatory_action_id.is_empty() and completed.has(def_ma.mandatory_action_id):
				return true

	# 招聘：按“是否必然消耗了该员工的招聘容量”推导
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val is EmployeeDef:
		var def: EmployeeDef = def_val
		if def.recruit_capacity > 0 and def.has_usage_tag("use:recruit"):
			var used := 0
			var ru_val = state.round_state.get("recruit_used", null)
			if ru_val is Dictionary and ru_val.has(player_id) and (ru_val[player_id] is int):
				used = int(ru_val[player_id])
			var total_cap := EmployeeRulesClass.get_recruit_limit_for_working(state, player_id)
			var mult := EmployeeRulesClass.get_working_employee_multiplier(state, player_id, employee_id)
			var emp_cap := int(def.recruit_capacity) * mult * EmployeeRulesClass.count_active(state.get_player(player_id), employee_id)
			var cap_without := total_cap - emp_cap
			if used > cap_without:
				return true

		# 培训：同理推导（基于 Train 子阶段 action_count）
		if def.train_capacity > 0 and def.has_usage_tag("use:train"):
			var used_train := EmployeeRulesClass.get_action_count(state, player_id, ACTION_ID)
			var total_cap := EmployeeRulesClass.get_train_limit_for_working(state, player_id)
			var mult := EmployeeRulesClass.get_working_employee_multiplier(state, player_id, employee_id)
			var emp_cap := int(def.train_capacity) * mult * EmployeeRulesClass.count_active(state.get_player(player_id), employee_id)
			var cap_without := total_cap - emp_cap
			if used_train > cap_without:
				return true

	return false

static func apply_inferred_use_employee_train(state: GameState, player_id: int) -> Result:
	if state == null:
		return Result.failure("train: inferred_use: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("train: inferred_use: round_state 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("train: inferred_use: player_id 越界: %d" % player_id)

	var warnings: Array[String] = []
	var train_used_now := EmployeeRulesClass.get_action_count(state, player_id, ACTION_ID)
	var player_now := state.get_player(player_id)
	var total_cap := EmployeeRulesClass.get_train_limit_for_working(state, player_id)
	var seen := {}
	var candidates: Array[String] = []
	for emp_val in Array(player_now.get("employees", [])):
		if not (emp_val is String):
			continue
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			continue
		if seen.has(emp_id):
			continue
		seen[emp_id] = true
		var def_val2 = EmployeeRegistryClass.get_def(emp_id)
		if def_val2 == null or not (def_val2 is EmployeeDef):
			continue
		var def2: EmployeeDef = def_val2
		if int(def2.train_capacity) <= 0:
			continue
		if not def2.has_usage_tag("use:train"):
			continue
		candidates.append(emp_id)
	candidates.sort()

	for emp_id in candidates:
		var def_val3 = EmployeeRegistryClass.get_def(emp_id)
		if def_val3 == null or not (def_val3 is EmployeeDef):
			continue
		var def3: EmployeeDef = def_val3
		var active_count := EmployeeRulesClass.count_active(player_now, emp_id)
		if active_count <= 0:
			continue
		var mult := EmployeeRulesClass.get_working_employee_multiplier(state, player_id, emp_id)
		var cap := active_count * int(def3.train_capacity) * mult
		if cap <= 0:
			continue
		var cap_without := total_cap - cap
		var inferred := mini(cap, maxi(0, train_used_now - cap_without))

		var prev_read := RoundStateCountersClass.get_player_key_count(state.round_state, "inferred_use_employee_train", player_id, emp_id)
		if not prev_read.ok:
			return prev_read
		var prev: int = int(prev_read.value)
		var delta := inferred - prev
		if delta <= 0:
			continue

		var inc := RoundStateCountersClass.increment_player_key_count(state.round_state, "inferred_use_employee_train", player_id, emp_id, delta)
		if not inc.ok:
			return inc

		for _k in range(delta):
			var use_r := MilestoneSystemClass.process_event(state, "UseEmployee", {"player_id": player_id, "id": emp_id})
			if not use_r.ok:
				warnings.append("里程碑触发失败(UseEmployee/%s): %s" % [emp_id, use_r.error])

	return Result.success().with_warnings(warnings)
