# 员工使用事件工具（里程碑 UseEmployee）
# 目的：将“触发 UseEmployee 并在失败时追加 warning”的样板代码集中到一处，避免在多个动作中重复。
class_name EmployeeUsageHelper
extends RefCounted

const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")

static func append_use_employee_warning(warnings: Array[String], state: GameState, player_id: int, employee_id: String) -> void:
	var use_r := MilestoneSystemClass.process_event(state, "UseEmployee", {"player_id": player_id, "id": employee_id})
	if not use_r.ok:
		warnings.append("里程碑触发失败(UseEmployee/%s): %s" % [employee_id, use_r.error])

