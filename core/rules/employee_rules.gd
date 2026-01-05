# 员工规则与行动额度（M3 起步）
# 说明：通过 EmployeeRegistry 读取 JSON 定义的员工数据。
class_name EmployeeRules
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")

static func is_entry_level(employee_id: String) -> bool:
	if employee_id.is_empty():
		return false
	var def_val = EmployeeRegistryClass.get_def(employee_id)
	if def_val == null:
		return false
	if not (def_val is EmployeeDef):
		assert(false, "EmployeeRules.is_entry_level: EmployeeRegistry 返回类型错误（期望 EmployeeDef）")
		return false
	var def: EmployeeDef = def_val
	return def.is_entry_level()

static func requires_salary(employee_id: String, player: Dictionary = {}) -> bool:
	# 从 EmployeeRegistry 读取 salary 字段，并叠加里程碑效果。
	if employee_id.is_empty():
		return false

	var base_requires := EmployeeRegistryClass.check_requires_salary(employee_id)
	if not base_requires:
		return false

	# 持久效果：某些员工永久免薪（由里程碑 effects.type 设置到 player 上）
	var no_salary_val = player.get("no_salary_employee_ids", null)
	if no_salary_val is Array:
		var no_salary: Array = no_salary_val
		if no_salary.has(employee_id):
			return false

	# 里程碑效果：marketing_no_salary -> 营销员不再需要支付薪水（避免硬编码 first_billboard）
	var milestones_val = player.get("milestones", null)
	if milestones_val is Array:
		var milestones: Array = milestones_val
		var def_val = EmployeeRegistryClass.get_def(employee_id)
		if def_val != null and _is_marketing_employee_def(def_val):
			for i in range(milestones.size()):
				var mid_val = milestones[i]
				assert(mid_val is String, "EmployeeRules.requires_salary: player.milestones[%d] 类型错误（期望 String）" % i)
				var mid: String = str(mid_val)
				assert(not mid.is_empty(), "EmployeeRules.requires_salary: player.milestones 不应包含空字符串")
				var ms_def_val = MilestoneRegistryClass.get_def(mid)
				assert(ms_def_val != null, "EmployeeRules.requires_salary: 未知里程碑定义: %s" % mid)
				assert(ms_def_val is MilestoneDefClass, "EmployeeRules.requires_salary: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
				var ms_def = ms_def_val

				for e_i in range(ms_def.effects.size()):
					var eff_val = ms_def.effects[e_i]
					assert(eff_val is Dictionary, "EmployeeRules.requires_salary: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
					var eff: Dictionary = eff_val
					assert(eff.has("type") and (eff["type"] is String), "EmployeeRules.requires_salary: %s.effects[%d].type 缺失或类型错误（期望 String）" % [mid, e_i])
					if str(eff["type"]) == "marketing_no_salary":
						return false

	return true

static func _is_marketing_employee_def(def: EmployeeDef) -> bool:
	for t in def.usage_tags:
		var s: String = str(t)
		if s.begins_with("use:marketing:"):
			return true
	return false

static func count_active(player: Dictionary, employee_id: String) -> int:
	assert(not employee_id.is_empty(), "employee_id 不能为空")
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var count := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")
		if emp_id == employee_id:
			count += 1
	return count

static func count_active_by_usage_tag(player: Dictionary, usage_tag: String) -> int:
	assert(not usage_tag.is_empty(), "usage_tag 不能为空")
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var count := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")

		var def = EmployeeRegistryClass.get_def(emp_id)
		assert(def != null, "未知员工: %s" % emp_id)
		if def.has_usage_tag(usage_tag):
			count += 1

	return count

static func get_working_employee_multiplier(state: GameState, player_id: int, employee_id: String) -> int:
	# 扩展点：工作阶段中“有效员工数量”乘数（模块可写入 round_state.working_employee_multipliers）。
	# round_state.working_employee_multipliers: player_id -> { employee_id -> multiplier }
	if state == null:
		return 1
	assert(not employee_id.is_empty(), "employee_id 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")
	var val = state.round_state.get("working_employee_multipliers", null)
	if val == null:
		return 1
	assert(val is Dictionary, "round_state.working_employee_multipliers 类型错误（期望 Dictionary）")
	var all: Dictionary = val
	assert(not all.has(str(player_id)), "round_state.working_employee_multipliers 不应包含字符串玩家 key: %s" % str(player_id))
	if not all.has(player_id):
		return 1
	var per_val = all[player_id]
	assert(per_val is Dictionary, "round_state.working_employee_multipliers[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val
	if not per_player.has(employee_id):
		return 1
	var m_val = per_player[employee_id]
	assert(m_val is int, "round_state.working_employee_multipliers[%d].%s 类型错误（期望 int）" % [player_id, employee_id])
	var m: int = int(m_val)
	assert(m > 0, "round_state.working_employee_multipliers[%d].%s 必须 > 0" % [player_id, employee_id])
	return m

static func count_active_for_working(state: GameState, player: Dictionary, player_id: int, employee_id: String) -> int:
	var base := count_active(player, employee_id)
	var multiplier := get_working_employee_multiplier(state, player_id, employee_id)
	return base * multiplier

static func count_active_by_usage_tag_for_working(state: GameState, player: Dictionary, player_id: int, usage_tag: String) -> int:
	assert(not usage_tag.is_empty(), "usage_tag 不能为空")
	assert(state != null, "count_active_by_usage_tag_for_working: state 为空")
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var count := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")

		var def = EmployeeRegistryClass.get_def(emp_id)
		assert(def != null, "未知员工: %s" % emp_id)
		if def.has_usage_tag(usage_tag):
			count += get_working_employee_multiplier(state, player_id, emp_id)

	return count

static func get_recruit_limit(player: Dictionary) -> int:
	# 规则：招聘次数由员工数据驱动（use:recruit + recruit_capacity）。
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var limit := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		assert(def_val != null, "未知员工: %s" % emp_id)
		assert(def_val is EmployeeDef, "EmployeeRegistry 返回类型错误（期望 EmployeeDef）")
		var def: EmployeeDef = def_val

		var cap := int(def.recruit_capacity)
		if cap > 0:
			limit += cap
	return limit

static func get_recruit_limit_for_working(state: GameState, player_id: int) -> int:
	assert(state != null, "get_recruit_limit_for_working: state 为空")
	var player := state.get_player(player_id)
	assert(not player.is_empty(), "get_recruit_limit_for_working: player 不存在: %d" % player_id)
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var limit := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		assert(def_val != null, "未知员工: %s" % emp_id)
		assert(def_val is EmployeeDef, "EmployeeRegistry 返回类型错误（期望 EmployeeDef）")
		var def: EmployeeDef = def_val

		var cap := int(def.recruit_capacity)
		if cap > 0:
			limit += cap * get_working_employee_multiplier(state, player_id, emp_id)
	return limit

static func get_train_limit(player: Dictionary) -> int:
	# 规则：训练次数由“培训能力”提供（避免硬编码仅 trainer）。
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var limit := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		assert(def_val != null, "未知员工: %s" % emp_id)
		assert(def_val is EmployeeDef, "EmployeeRegistry 返回类型错误（期望 EmployeeDef）")
		var def: EmployeeDef = def_val

		var cap := int(def.train_capacity)
		if cap > 0:
			limit += cap
	return limit

static func get_train_limit_for_working(state: GameState, player_id: int) -> int:
	assert(state != null, "get_train_limit_for_working: state 为空")
	var player := state.get_player(player_id)
	assert(not player.is_empty(), "get_train_limit_for_working: player 不存在: %d" % player_id)
	assert(player.has("employees"), "player 缺少 employees")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	var employees: Array = player["employees"]

	var limit := 0
	for emp in employees:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		assert(def_val != null, "未知员工: %s" % emp_id)
		assert(def_val is EmployeeDef, "EmployeeRegistry 返回类型错误（期望 EmployeeDef）")
		var def: EmployeeDef = def_val

		var cap := int(def.train_capacity)
		if cap > 0:
			limit += cap * get_working_employee_multiplier(state, player_id, emp_id)
	return limit

static func count_paid_employees(player: Dictionary) -> int:
	assert(player.has("employees"), "player 缺少 employees")
	assert(player.has("reserve_employees"), "player 缺少 reserve_employees")
	assert(player.has("busy_marketers"), "player 缺少 busy_marketers")
	assert(player["employees"] is Array, "player.employees 类型错误（期望 Array）")
	assert(player["reserve_employees"] is Array, "player.reserve_employees 类型错误（期望 Array）")
	assert(player["busy_marketers"] is Array, "player.busy_marketers 类型错误（期望 Array）")

	var active: Array = player["employees"]
	var reserve: Array = player["reserve_employees"]
	var busy: Array = player["busy_marketers"]

	var count := 0
	for emp in active:
		assert(emp is String, "player.employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.employees 不应包含空字符串")
		if requires_salary(emp_id, player):
			count += 1
	for emp in reserve:
		assert(emp is String, "player.reserve_employees 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.reserve_employees 不应包含空字符串")
		if requires_salary(emp_id, player):
			count += 1
	for emp in busy:
		assert(emp is String, "player.busy_marketers 元素类型错误（期望 String）")
		var emp_id: String = emp
		assert(not emp_id.is_empty(), "player.busy_marketers 不应包含空字符串")
		if requires_salary(emp_id, player):
			count += 1
	return count

static func get_action_count(state: GameState, player_id: int, action_id: String) -> int:
	assert(not action_id.is_empty(), "action_id 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")
	assert(state.round_state.has("action_counts"), "round_state 缺少字段: action_counts")
	var counts_val = state.round_state["action_counts"]
	assert(counts_val is Dictionary, "round_state.action_counts 类型错误（期望 Dictionary）")
	var counts: Dictionary = counts_val
	assert(not counts.has(str(player_id)), "round_state.action_counts 不应包含字符串玩家 key: %s" % str(player_id))
	if not counts.has(player_id):
		return 0
	var per_val = counts[player_id]
	assert(per_val is Dictionary, "round_state.action_counts[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val
	if not per_player.has(action_id):
		return 0
	var v = per_player[action_id]
	assert(v is int, "round_state.action_counts[%d].%s 类型错误（期望 int）" % [player_id, action_id])
	assert(int(v) >= 0, "round_state.action_counts[%d].%s 不能为负数: %d" % [player_id, action_id, int(v)])
	return int(v)

static func increment_action_count(state: GameState, player_id: int, action_id: String) -> int:
	assert(not action_id.is_empty(), "action_id 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")
	assert(state.round_state.has("action_counts"), "round_state 缺少字段: action_counts")
	var counts_val = state.round_state["action_counts"]
	assert(counts_val is Dictionary, "round_state.action_counts 类型错误（期望 Dictionary）")
	var counts: Dictionary = counts_val
	assert(not counts.has(str(player_id)), "round_state.action_counts 不应包含字符串玩家 key: %s" % str(player_id))

	var per_player: Dictionary = {}
	if counts.has(player_id):
		var per_val = counts[player_id]
		assert(per_val is Dictionary, "round_state.action_counts[%d] 类型错误（期望 Dictionary）" % player_id)
		per_player = per_val

	var current := 0
	if per_player.has(action_id):
		var v = per_player[action_id]
		assert(v is int, "round_state.action_counts[%d].%s 类型错误（期望 int）" % [player_id, action_id])
		assert(int(v) >= 0, "round_state.action_counts[%d].%s 不能为负数: %d" % [player_id, action_id, int(v)])
		current = int(v)

	var new_value := current + 1
	per_player[action_id] = new_value
	counts[player_id] = per_player
	state.round_state["action_counts"] = counts
	return new_value

static func reset_action_counts(state: GameState) -> void:
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")
	state.round_state["action_counts"] = {}

# === Recruit 缺货预支 / 紧接培训约束（docs/design.md）===

static func get_immediate_train_pending_count(state: GameState, player_id: int, employee_type: String) -> int:
	assert(not employee_type.is_empty(), "employee_type 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return 0
	assert(pending_val is Dictionary, "round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val
	assert(not pending_all.has(str(player_id)), "round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))

	if not pending_all.has(player_id):
		return 0
	var per_val = pending_all[player_id]
	assert(per_val is Dictionary, "round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val

	if not per_player.has(employee_type):
		return 0
	var v = per_player[employee_type]
	assert(v is int, "round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, employee_type])
	assert(int(v) >= 0, "round_state.immediate_train_pending[%d].%s 不能为负数: %d" % [player_id, employee_type, int(v)])
	return int(v)

static func get_immediate_train_pending_total(state: GameState, player_id: int) -> int:
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return 0
	assert(pending_val is Dictionary, "round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val
	assert(not pending_all.has(str(player_id)), "round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))

	if not pending_all.has(player_id):
		return 0
	var per_val = pending_all[player_id]
	assert(per_val is Dictionary, "round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val

	var total := 0
	for k in per_player.keys():
		assert(k is String, "round_state.immediate_train_pending[%d] key 类型错误（期望 String）" % player_id)
		var emp_id: String = str(k)
		assert(not emp_id.is_empty(), "round_state.immediate_train_pending[%d] 不应包含空字符串 key" % player_id)
		var v = per_player[k]
		assert(v is int, "round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, emp_id])
		assert(int(v) >= 0, "round_state.immediate_train_pending[%d].%s 不能为负数: %d" % [player_id, emp_id, int(v)])
		total += int(v)
	return total

static func has_any_immediate_train_pending(state: GameState) -> bool:
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return false
	assert(pending_val is Dictionary, "round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val

	for pid in pending_all.keys():
		assert(pid is int, "round_state.immediate_train_pending key 类型错误（期望 int）")
		var per_val = pending_all.get(pid, null)
		assert(per_val is Dictionary, "round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % int(pid))
		var per_player: Dictionary = per_val
		for emp_id in per_player.keys():
			assert(emp_id is String, "round_state.immediate_train_pending[%d] key 类型错误（期望 String）" % int(pid))
			var emp_key: String = str(emp_id)
			assert(not emp_key.is_empty(), "round_state.immediate_train_pending[%d] 不应包含空字符串 key" % int(pid))
			var v = per_player[emp_id]
			assert(v is int, "round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [int(pid), emp_key])
			assert(int(v) >= 0, "round_state.immediate_train_pending[%d].%s 不能为负数: %d" % [int(pid), emp_key, int(v)])
			if int(v) > 0:
				return true
	return false

static func add_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> void:
	assert(not employee_type.is_empty(), "employee_type 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	var pending_all: Dictionary = {}
	if pending_val != null:
		assert(pending_val is Dictionary, "round_state.immediate_train_pending 类型错误（期望 Dictionary）")
		pending_all = pending_val

	assert(not pending_all.has(str(player_id)), "round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))

	var per_val = pending_all.get(player_id, null)
	var per_player: Dictionary = {}
	if per_val != null:
		assert(per_val is Dictionary, "round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
		per_player = per_val

	var current := 0
	if per_player.has(employee_type):
		var v = per_player[employee_type]
		assert(v is int, "round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, employee_type])
		assert(int(v) >= 0, "round_state.immediate_train_pending[%d].%s 不能为负数: %d" % [player_id, employee_type, int(v)])
		current = int(v)
	per_player[employee_type] = current + 1
	pending_all[player_id] = per_player
	state.round_state["immediate_train_pending"] = pending_all

static func consume_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> bool:
	assert(not employee_type.is_empty(), "employee_type 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")

	var pending_val = state.round_state.get("immediate_train_pending", null)
	if pending_val == null:
		return false
	assert(pending_val is Dictionary, "round_state.immediate_train_pending 类型错误（期望 Dictionary）")
	var pending_all: Dictionary = pending_val
	assert(not pending_all.has(str(player_id)), "round_state.immediate_train_pending 不应包含字符串玩家 key: %s" % str(player_id))

	if not pending_all.has(player_id):
		return false
	var per_val = pending_all[player_id]
	assert(per_val is Dictionary, "round_state.immediate_train_pending[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val

	if not per_player.has(employee_type):
		return false
	var current_val = per_player[employee_type]
	assert(current_val is int, "round_state.immediate_train_pending[%d].%s 类型错误（期望 int）" % [player_id, employee_type])
	var current: int = int(current_val)
	assert(current > 0, "round_state.immediate_train_pending[%d].%s 必须 > 0，实际: %d" % [player_id, employee_type, current])

	current -= 1
	if current <= 0:
		per_player.erase(employee_type)
	else:
		per_player[employee_type] = current

	if per_player.is_empty():
		pending_all.erase(player_id)
	else:
		pending_all[player_id] = per_player

	if pending_all.is_empty():
		state.round_state.erase("immediate_train_pending")
	else:
		state.round_state["immediate_train_pending"] = pending_all

	return true
