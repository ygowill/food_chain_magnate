# 员工使用事件工具（里程碑 UseEmployee）
# 目的：将“触发 UseEmployee 并在失败时追加 warning”的样板代码集中到一处，避免在多个动作中重复。
class_name EmployeeUsageHelper
extends RefCounted

const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

static func append_use_employee_warning(warnings: Array[String], state: GameState, player_id: int, employee_id: String) -> void:
	var use_r := MilestoneSystemClass.process_event(state, "UseEmployee", {"player_id": player_id, "id": employee_id})
	if not use_r.ok:
		warnings.append("里程碑触发失败(UseEmployee/%s): %s" % [employee_id, use_r.error])

static func get_active_employee_types_for_usage_tag(state: GameState, player_id: int, usage_tag: String) -> Array[String]:
	if state == null or usage_tag.is_empty():
		return []
	if not EmployeeRegistryClass.is_loaded():
		return []
	var player := state.get_player(player_id)
	if player.is_empty():
		return []
	var employees_read := PlayerStateAccessClass.require_employees(player, "player[%d]" % player_id, "EmployeeUsageHelper.get_active_employee_types_for_usage_tag")
	if not employees_read.ok:
		return []
	var employees: Array = employees_read.value
	var seen := {}
	for emp_val in employees:
		if not (emp_val is String):
			continue
		var emp_id := str(emp_val).strip_edges()
		if emp_id.is_empty():
			continue
		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if not def.has_usage_tag(usage_tag):
			continue
		seen[emp_id] = true
	var ids: Array[String] = []
	for key in seen.keys():
		ids.append(str(key))
	ids.sort()
	return ids

static func has_active_employee_with_usage_tag(state: GameState, player_id: int, employee_type: String, usage_tag: String) -> bool:
	if state == null:
		return false
	var emp_id := str(employee_type).strip_edges()
	if emp_id.is_empty() or usage_tag.is_empty():
		return false
	if not EmployeeRegistryClass.is_loaded():
		return false
	var player := state.get_player(player_id)
	if player.is_empty():
		return false
	var def_val = EmployeeRegistryClass.get_def(emp_id)
	if def_val == null or not (def_val is EmployeeDef):
		return false
	var def: EmployeeDef = def_val
	if not def.has_usage_tag(usage_tag):
		return false
	var employees_read := PlayerStateAccessClass.require_employees(player, "player[%d]" % player_id, "EmployeeUsageHelper.has_active_employee_with_usage_tag")
	if not employees_read.ok:
		return false
	var employees: Array = employees_read.value
	for emp_val in employees:
		if not (emp_val is String):
			return false
		if str(emp_val).strip_edges().is_empty():
			return false
	var active_count := EmployeeRulesClass.count_active_for_working(state, player, player_id, emp_id)
	return active_count > 0
