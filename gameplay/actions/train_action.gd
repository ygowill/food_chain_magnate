# 培训动作（M3 起步）
# 将"待命"员工培训为更高级的职位。
class_name TrainAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const CompanyStructureValidatorClass = preload("res://gameplay/validators/company_structure_validator.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

func _init() -> void:
	action_id = "train"
	display_name = "培训"
	description = "将待命员工培训为更高级职位"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Train"]

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var from_result := require_string_param(command, "from_employee")
	if not from_result.ok:
		return from_result
	var to_result := require_string_param(command, "to_employee")
	if not to_result.ok:
		return to_result
	var from_employee: String = from_result.value
	var to_employee: String = to_result.value

	# 检查训练次数
	var player := state.get_player(command.actor)
	# 禁用员工（ban_card）：不能再获得/培训该员工
	var banned_val = player.get("banned_employee_ids", [])
	if banned_val is Array:
		var banned: Array = banned_val
		if banned.find(to_employee) >= 0:
			return Result.failure("该员工已被禁用，不能培训: %s" % to_employee)

	var limit := EmployeeRulesClass.get_train_limit_for_working(state, command.actor)
	if limit <= 0:
		return Result.failure("没有可用的培训员")
	var used := EmployeeRulesClass.get_action_count(state, command.actor, action_id)
	if used >= limit:
		return Result.failure("本子阶段培训次数已用完: %d/%d" % [used, limit])

	# 仅允许培训“待命”员工
	assert(player.has("reserve_employees") and (player["reserve_employees"] is Array), "train: player.reserve_employees 缺失或类型错误（期望 Array[String]）")
	var reserve: Array = player["reserve_employees"]
	for i in range(reserve.size()):
		assert(reserve[i] is String, "train: player.reserve_employees[%d] 类型错误（期望 String）" % i)
	var pending_total := EmployeeRulesClass.get_immediate_train_pending_total(state, command.actor)
	var pending_count := EmployeeRulesClass.get_immediate_train_pending_count(state, command.actor, from_employee)
	var has_reserve := reserve.find(from_employee) >= 0
	var has_pending := pending_count > 0
	var has_active := EmployeeRulesClass.count_active(player, from_employee) > 0
	var can_train_from_active := bool(player.get("train_from_active_same_color", false))

	# 若存在“缺货预支”待培训员工，则必须优先清账（避免占用培训次数导致无法离开 Train 子阶段）
	if pending_total > 0 and not has_pending:
		return Result.failure("存在缺货预支待培训员工，必须先在 Train 子阶段完成培训")

	if not has_reserve and not has_pending and not has_active:
		return Result.failure("待命区不存在员工: %s" % from_employee)
	if has_active and not has_reserve and not has_pending and not can_train_from_active:
		return Result.failure("该员工在岗，且未启用“在岗同色培训”能力: %s" % from_employee)

	# 默认：不能在同一 Train 子阶段连续培训“本子阶段新培训得到”的员工（里程碑允许例外）
	var multi_val = player.get("multi_trainer_on_one", false)
	if not (multi_val is bool):
		return Result.failure("train: player.multi_trainer_on_one 类型错误（期望 bool）")
	var multi: bool = bool(multi_val)
	if not multi:
		# 默认：不能使用“本子阶段通过培训获得的职位”继续培训（由于按 employee_type 选择，无法区分具体卡，保守禁止链式培训）
		var gained_read := RoundStateCountersClass.get_player_key_count(state.round_state, "train_to_gained", command.actor, from_employee)
		if not gained_read.ok:
			return gained_read
		if int(gained_read.value) > 0:
			return Result.failure("默认规则下不应允许链式培训（%s -> %s）" % [from_employee, to_employee])

		var start_count_read := _get_train_phase_start_count(state, command.actor, reserve, from_employee)
		if not start_count_read.ok:
			return start_count_read
		var start_count: int = int(start_count_read.value)

		var used_from_read := RoundStateCountersClass.get_player_key_count(state.round_state, "train_from_used", command.actor, from_employee)
		if not used_from_read.ok:
			return used_from_read
		var used_from: int = int(used_from_read.value)

		if used_from >= start_count:
			return Result.failure("本子阶段不能连续培训同一员工（需要里程碑允许）: %s" % from_employee)

	# 目标职位必须有卡可用（当前仅检查最终职位堆）
	var available: int = state.employee_pool.get(to_employee, 0)
	if available <= 0:
		return Result.failure("员工池中没有 %s" % to_employee)

	# 公司结构校验（唯一员工约束等）- 校验培训后的目标员工
	var validator = CompanyStructureValidatorClass.new()
	var to_reserve := true
	if can_train_from_active and has_active and not has_reserve and not has_pending:
		# FIRST LEMONADE SOLD：在岗同色培训时，若旧员工未被使用，则新员工可立刻在岗
		var from_used := _is_employee_used_before_training(state, command.actor, from_employee)
		to_reserve = from_used

		# 同色限制：不允许颜色变化
		var color_ok := _is_same_role_color(from_employee, to_employee)
		if not color_ok.ok:
			return color_ok
		if not bool(color_ok.value):
			return Result.failure("在岗培训不允许改变颜色: %s -> %s" % [from_employee, to_employee])

		if not to_reserve:
			var cap_check := _validate_company_structure_replacing_active(state, command.actor, from_employee, to_employee)
			if not cap_check.ok:
				return cap_check

	var validation: Result = validator.validate(state, command.actor, {
		"employee_id": to_employee,
		"to_reserve": to_reserve
	})
	if not validation.ok:
		return validation

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = command.actor
	var from_result := require_string_param(command, "from_employee")
	if not from_result.ok:
		return from_result
	var to_result := require_string_param(command, "to_employee")
	if not to_result.ok:
		return to_result
	var from_employee: String = from_result.value
	var to_employee: String = to_result.value

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("train: player 类型错误: players[%d]（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var multi_val = player.get("multi_trainer_on_one", false)
	if not (multi_val is bool):
		return Result.failure("train: player.multi_trainer_on_one 类型错误（期望 bool）")
	var multi: bool = bool(multi_val)
	var can_train_from_active := bool(player.get("train_from_active_same_color", false))
	var from_used_before := _is_employee_used_before_training(state, player_id, from_employee)
	var target_to_reserve := true
	if can_train_from_active and EmployeeRulesClass.count_active(player, from_employee) > 0 and int(EmployeeRulesClass.get_immediate_train_pending_count(state, player_id, from_employee)) <= 0:
		target_to_reserve = from_used_before
	if not multi:
		var reserve_read := _require_player_string_array(player, "reserve_employees", "train: player.reserve_employees")
		if not reserve_read.ok:
			return reserve_read
		var reserve: Array = reserve_read.value
		var write_start := _ensure_train_phase_start_counts(state, player_id, reserve)
		if not write_start.ok:
			return write_start

		var inc_used := RoundStateCountersClass.increment_player_key_count(state.round_state, "train_from_used", player_id, from_employee, 1)
		if not inc_used.ok:
			return inc_used

	var use_pending := EmployeeRulesClass.get_immediate_train_pending_count(state, player_id, from_employee) > 0
	if use_pending:
		var consumed := EmployeeRulesClass.consume_immediate_train_pending(state, player_id, from_employee)
		if not consumed:
			return Result.failure("缺货预支待清账员工不存在: %s" % from_employee)
	else:
		# 优先从待命区移除；否则允许从在岗移除（FIRST LEMONADE SOLD）
		var removed := StateUpdater.remove_from_array(state.players[player_id], "reserve_employees", from_employee)
		if not removed:
			if can_train_from_active:
				removed = StateUpdater.remove_from_array(state.players[player_id], "employees", from_employee)
		if not removed:
			return Result.failure("待命区/在岗区不存在员工: %s" % from_employee)

		# 原卡回供应区（简化：假设培训会归还原卡）
		StateUpdater.return_to_pool(state, from_employee, 1)

	# 取出目标员工
	var take_result := StateUpdater.take_from_pool(state, to_employee, 1)
	if not take_result.ok:
		return take_result

	# 培训后的员工：默认进待命；FIRST LEMONADE SOLD 且旧员工未使用时可直接在岗
	var add_result := StateUpdater.add_employee(state, player_id, to_employee, target_to_reserve)
	if not add_result.ok:
		return add_result

	# 记录“本子阶段通过培训获得的职位类型”，用于默认禁止链式培训（multi_trainer_on_one 例外）
	var gained_write := RoundStateCountersClass.increment_player_key_count(state.round_state, "train_to_gained", player_id, to_employee, 1)
	if not gained_write.ok:
		return gained_write

	EmployeeRulesClass.increment_action_count(state, player_id, action_id)

	# 记录训练事件（供模块在 Train 子阶段注入“训练后可选动作窗口”等逻辑使用）
	if state.round_state is Dictionary:
		if not state.round_state.has("train_events"):
			state.round_state["train_events"] = []
		var te_val = state.round_state.get("train_events", null)
		if not (te_val is Array):
			return Result.failure("train: round_state.train_events 类型错误（期望 Array）")
		var train_events: Array = te_val
		train_events.append({
			"player_id": player_id,
			"from_employee": from_employee,
			"to_employee": to_employee,
			"from_pending": use_pending,
		})
		state.round_state["train_events"] = train_events

	var ms := MilestoneSystemClass.process_event(state, "Train", {"player_id": player_id})

	# 使用员工：按“培训次数/容量”推导哪些培训员必然被使用，并对每次推导出的使用调用一次 UseEmployee。
	var warnings: Array[String] = []
	var train_used_now := EmployeeRulesClass.get_action_count(state, player_id, action_id)
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
		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if int(def.train_capacity) <= 0:
			continue
		if not def.has_usage_tag("use:train"):
			continue
		candidates.append(emp_id)
	candidates.sort()

	for emp_id in candidates:
		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		var active_count := EmployeeRulesClass.count_active(player_now, emp_id)
		if active_count <= 0:
			continue
		var mult := EmployeeRulesClass.get_working_employee_multiplier(state, player_id, emp_id)
		var cap := active_count * int(def.train_capacity) * mult
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

	var result := Result.success({
		"player_id": player_id,
		"from_employee": from_employee,
		"to_employee": to_employee,
		"from_pending": use_pending
	})
	if not ms.ok:
		result.with_warning("里程碑触发失败(Train): %s" % ms.error)
	result.with_warnings(warnings)
	return result

static func _require_player_string_array(player: Dictionary, key: String, path: String) -> Result:
	if not player.has(key):
		return Result.failure("%s 缺失" % path)
	var value = player.get(key, null)
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var arr: Array = value
	for i in range(arr.size()):
		if not (arr[i] is String):
			return Result.failure("%s[%d] 类型错误（期望 String）" % [path, i])
	return Result.success(arr)

static func _ensure_train_phase_start_counts(state: GameState, player_id: int, reserve: Array) -> Result:
	if state == null:
		return Result.failure("train: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("train: round_state 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("train: player_id 越界: %d" % player_id)

	if not state.round_state.has("train_phase_start_counts"):
		state.round_state["train_phase_start_counts"] = {}
	var all_val = state.round_state.get("train_phase_start_counts", null)
	if not (all_val is Dictionary):
		return Result.failure("train: round_state.train_phase_start_counts 类型错误（期望 Dictionary）")
	var all: Dictionary = all_val
	assert(not all.has(str(player_id)), "round_state.train_phase_start_counts 不应包含字符串玩家 key: %s" % str(player_id))

	if all.has(player_id):
		return Result.success()

	var counts_read := _compute_train_phase_start_counts(state, player_id, reserve)
	if not counts_read.ok:
		return counts_read
	all[player_id] = counts_read.value
	state.round_state["train_phase_start_counts"] = all
	return Result.success()

static func _get_train_phase_start_count(state: GameState, player_id: int, reserve: Array, employee_type: String) -> Result:
	if employee_type.is_empty():
		return Result.failure("train: from_employee 不能为空")
	if state == null:
		return Result.failure("train: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("train: round_state 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("train: player_id 越界: %d" % player_id)

	var all_val = state.round_state.get("train_phase_start_counts", null)
	if all_val != null:
		if not (all_val is Dictionary):
			return Result.failure("train: round_state.train_phase_start_counts 类型错误（期望 Dictionary）")
		var all: Dictionary = all_val
		assert(not all.has(str(player_id)), "round_state.train_phase_start_counts 不应包含字符串玩家 key: %s" % str(player_id))
		if all.has(player_id):
			var per_val = all.get(player_id, null)
			if not (per_val is Dictionary):
				return Result.failure("train: round_state.train_phase_start_counts[%d] 类型错误（期望 Dictionary）" % player_id)
			var per: Dictionary = per_val
			if per.has(employee_type):
				var v = per.get(employee_type, null)
				if not (v is int):
					return Result.failure("train: round_state.train_phase_start_counts[%d].%s 类型错误（期望 int）" % [player_id, employee_type])
				return Result.success(int(v))
			return Result.success(0)

	var counts_read := _compute_train_phase_start_counts(state, player_id, reserve)
	if not counts_read.ok:
		return counts_read
	var counts: Dictionary = counts_read.value
	var v = counts.get(employee_type, 0)
	if not (v is int):
		return Result.failure("train: start_counts.%s 类型错误（期望 int）" % employee_type)
	return Result.success(int(v))

static func _compute_train_phase_start_counts(state: GameState, player_id: int, reserve: Array) -> Result:
	if state == null:
		return Result.failure("train: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("train: round_state 类型错误（期望 Dictionary）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("train: player_id 越界: %d" % player_id)

	var counts: Dictionary = {}
	# 待命区
	for emp_val in reserve:
		assert(emp_val is String, "train: reserve_employees 元素类型错误（期望 String）")
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("train: reserve_employees 不应包含空字符串")
		counts[emp_id] = int(counts.get(emp_id, 0)) + 1

	# 在岗区（FIRST LEMONADE SOLD 需要用到；并用于“本子阶段新获得员工不可连续培训”的一致性）
	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("train: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	if not player.has("employees") or not (player["employees"] is Array):
		return Result.failure("train: player.employees 缺失或类型错误（期望 Array）")
	var employees: Array = player["employees"]
	for emp_val in employees:
		assert(emp_val is String, "train: employees 元素类型错误（期望 String）")
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("train: employees 不应包含空字符串")
		counts[emp_id] = int(counts.get(emp_id, 0)) + 1

	# 加上“缺货预支”待培训员工（视为本子阶段开始时就存在的可培训来源）
	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val != null:
		if not (pending_val is Dictionary):
			return Result.failure("train: round_state.immediate_train_pending 类型错误（期望 Dictionary）")
		var pending_all: Dictionary = pending_val
		assert(not pending_all.has(str(player_id)), "round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))
		if pending_all.has(player_id):
			var per_val = pending_all.get(player_id, null)
			if not (per_val is Dictionary):
				return Result.failure("train: round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
			var per: Dictionary = per_val
			for k in per.keys():
				if not (k is String):
					return Result.failure("train: round_state.immediate_train_pending[%d] key 类型错误（期望 String）" % player_id)
				var emp_id: String = str(k)
				if emp_id.is_empty():
					return Result.failure("train: round_state.immediate_train_pending[%d] 不应包含空字符串 key" % player_id)
				var v = per.get(k, null)
				if not (v is int):
					return Result.failure("train: round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, emp_id])
				if int(v) <= 0:
					continue
				counts[emp_id] = int(counts.get(emp_id, 0)) + int(v)

	return Result.success(counts)

static func _is_same_role_color(from_employee: String, to_employee: String) -> Result:
	if from_employee.is_empty() or to_employee.is_empty():
		return Result.failure("train: employee_id 不能为空")
	var from_def_val = EmployeeRegistryClass.get_def(from_employee)
	if from_def_val == null or not (from_def_val is EmployeeDef):
		return Result.failure("train: 未知员工定义: %s" % from_employee)
	var to_def_val = EmployeeRegistryClass.get_def(to_employee)
	if to_def_val == null or not (to_def_val is EmployeeDef):
		return Result.failure("train: 未知员工定义: %s" % to_employee)
	var from_def: EmployeeDef = from_def_val
	var to_def: EmployeeDef = to_def_val
	return Result.success(from_def.get_role() == to_def.get_role())

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
			var used_train := EmployeeRulesClass.get_action_count(state, player_id, "train")
			var total_cap := EmployeeRulesClass.get_train_limit_for_working(state, player_id)
			var mult := EmployeeRulesClass.get_working_employee_multiplier(state, player_id, employee_id)
			var emp_cap := int(def.train_capacity) * mult * EmployeeRulesClass.count_active(state.get_player(player_id), employee_id)
			var cap_without := total_cap - emp_cap
			if used_train > cap_without:
				return true

	return false

static func _validate_company_structure_replacing_active(state: GameState, player_id: int, remove_employee_id: String, add_employee_id: String) -> Result:
	if state == null:
		return Result.failure("train: state 为空")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("train: player_id 越界: %d" % player_id)
	if remove_employee_id.is_empty() or add_employee_id.is_empty():
		return Result.failure("train: employee_id 不能为空")

	var old_val = state.players[player_id]
	if not (old_val is Dictionary):
		return Result.failure("train: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var old_player: Dictionary = old_val

	var tmp: Dictionary = old_player.duplicate(true)
	if not tmp.has("employees") or not (tmp["employees"] is Array):
		return Result.failure("train: player.employees 缺失或类型错误（期望 Array）")
	var emps: Array = tmp["employees"]
	var idx := emps.find(remove_employee_id)
	if idx == -1:
		return Result.failure("train: 在岗区不存在员工: %s" % remove_employee_id)
	emps.remove_at(idx)
	tmp["employees"] = emps

	state.players[player_id] = tmp
	var validator = CompanyStructureValidatorClass.new()
	var r := validator.validate(state, player_id, {"employee_id": add_employee_id, "to_reserve": false})
	state.players[player_id] = old_player
	return r

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var from_result := require_string_param(command, "from_employee")
	assert(from_result.ok, "train 缺少/错误参数: from_employee")
	var to_result := require_string_param(command, "to_employee")
	assert(to_result.ok, "train 缺少/错误参数: to_employee")
	events.append({
		"type": EventBus.EventType.EMPLOYEE_TRAINED,
		"data": {
			"player_id": command.actor,
			"from_employee": from_result.value,
			"to_employee": to_result.value
		}
	})
	return events
