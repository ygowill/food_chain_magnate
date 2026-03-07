extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const EmployeeUsageHelperClass = preload("res://gameplay/actions/employee_usage_helper.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const RoundStatePlayerStringListsClass = preload("res://core/utils/round_state_player_string_lists.gd")

const ACTION_ID := "train"

static func read_employee_used_before_training(state: GameState, player_id: int, employee_id: String) -> Result:
	if state == null or not (state.round_state is Dictionary):
		return Result.success(false)
	if employee_id.is_empty():
		return Result.success(false)

	# 生产
	var production_read := RoundStateCountersClass.get_player_key_count(state.round_state, "production_counts", player_id, employee_id)
	if not production_read.ok:
		return production_read
	if int(production_read.value) > 0:
		return Result.success(true)

	# 采购
	var procurement_read := RoundStateCountersClass.get_player_key_count(state.round_state, "procurement_counts", player_id, employee_id)
	if not procurement_read.ok:
		return procurement_read
	if int(procurement_read.value) > 0:
		return Result.success(true)

	# 营销发起
	var marketing_read := RoundStateCountersClass.get_player_key_count(state.round_state, "marketing_used", player_id, employee_id)
	if not marketing_read.ok:
		return marketing_read
	if int(marketing_read.value) > 0:
		return Result.success(true)

	# 价格强制动作
	var def_val_ma = EmployeeRegistryClass.get_def(employee_id)
	if def_val_ma is EmployeeDef:
		var def_ma: EmployeeDef = def_val_ma
		if not def_ma.mandatory_action_id.is_empty():
			var completed_read := RoundStatePlayerStringListsClass.has_value(
				state.round_state,
				"mandatory_actions_completed",
				player_id,
				def_ma.mandatory_action_id,
				"train: mandatory_actions_completed"
			)
			if not completed_read.ok:
				return completed_read
			if bool(completed_read.value):
				return Result.success(true)

	# 招聘：按“是否必然消耗了该员工的招聘容量”推导
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val is EmployeeDef:
		var def: EmployeeDef = def_val
		if def.recruit_capacity > 0 and def.has_usage_tag("use:recruit"):
			var used_read := RoundStateCountersClass.get_player_count(state.round_state, "recruit_used", player_id)
			if not used_read.ok:
				return used_read
			var used := int(used_read.value)
			var total_cap := EmployeeRulesClass.get_recruit_limit_for_working(state, player_id)
			var mult_read := EmployeeRulesClass.try_get_working_employee_multiplier(state, player_id, employee_id)
			if not mult_read.ok:
				return mult_read
			var mult := int(mult_read.value)
			var emp_cap := int(def.recruit_capacity) * mult * EmployeeRulesClass.count_active(state.get_player(player_id), employee_id)
			var cap_without := total_cap - emp_cap
			if used > cap_without:
				return Result.success(true)

		# 培训：同理推导（基于 Train 子阶段 action_count）
		if def.train_capacity > 0 and def.has_usage_tag("use:train"):
			var used_train := EmployeeRulesClass.get_action_count(state, player_id, ACTION_ID)
			var total_cap := EmployeeRulesClass.get_train_limit_for_working(state, player_id)
			var mult_read := EmployeeRulesClass.try_get_working_employee_multiplier(state, player_id, employee_id)
			if not mult_read.ok:
				return mult_read
			var mult := int(mult_read.value)
			var emp_cap := int(def.train_capacity) * mult * EmployeeRulesClass.count_active(state.get_player(player_id), employee_id)
			var cap_without := total_cap - emp_cap
			if used_train > cap_without:
				return Result.success(true)

	return Result.success(false)

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
		var mult_read := EmployeeRulesClass.try_get_working_employee_multiplier(state, player_id, emp_id)
		if not mult_read.ok:
			return mult_read
		var mult := int(mult_read.value)
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
			EmployeeUsageHelperClass.append_use_employee_warning(warnings, state, player_id, emp_id)

	return Result.success().with_warnings(warnings)
