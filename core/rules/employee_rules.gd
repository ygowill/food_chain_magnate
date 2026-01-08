# 员工规则与行动额度（M3 起步）
# 说明：通过 EmployeeRegistry 读取 JSON 定义的员工数据。
class_name EmployeeRules
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const Salary = preload("res://core/rules/employee_rules/salary.gd")
const Counts = preload("res://core/rules/employee_rules/counts.gd")
const WorkingMultiplier = preload("res://core/rules/employee_rules/working_multiplier.gd")
const Limits = preload("res://core/rules/employee_rules/limits.gd")
const ActionCounts = preload("res://core/rules/employee_rules/action_counts.gd")
const ImmediateTrainPending = preload("res://core/rules/employee_rules/immediate_train_pending.gd")

static func is_entry_level(employee_id: String) -> bool:
	return Counts.is_entry_level(employee_id)

static func requires_salary(employee_id: String, player: Dictionary = {}) -> bool:
	return Salary.requires_salary(employee_id, player)

static func _is_marketing_employee_def(def: EmployeeDef) -> bool:
	return Salary.is_marketing_employee_def(def)

static func count_active(player: Dictionary, employee_id: String) -> int:
	return Counts.count_active(player, employee_id)

static func count_active_by_usage_tag(player: Dictionary, usage_tag: String) -> int:
	return Counts.count_active_by_usage_tag(player, usage_tag)

static func get_working_employee_multiplier(state: GameState, player_id: int, employee_id: String) -> int:
	return WorkingMultiplier.get_working_employee_multiplier(state, player_id, employee_id)

static func count_active_for_working(state: GameState, player: Dictionary, player_id: int, employee_id: String) -> int:
	return Counts.count_active_for_working(state, player, player_id, employee_id)

static func count_active_by_usage_tag_for_working(state: GameState, player: Dictionary, player_id: int, usage_tag: String) -> int:
	return Counts.count_active_by_usage_tag_for_working(state, player, player_id, usage_tag)

static func get_recruit_limit(player: Dictionary) -> int:
	return Limits.get_recruit_limit(player)

static func get_recruit_limit_for_working(state: GameState, player_id: int) -> int:
	return Limits.get_recruit_limit_for_working(state, player_id)

static func get_train_limit(player: Dictionary) -> int:
	return Limits.get_train_limit(player)

static func get_train_limit_for_working(state: GameState, player_id: int) -> int:
	return Limits.get_train_limit_for_working(state, player_id)

static func count_paid_employees(player: Dictionary) -> int:
	return Salary.count_paid_employees(player)

static func get_action_count(state: GameState, player_id: int, action_id: String) -> int:
	return ActionCounts.get_action_count(state, player_id, action_id)

static func increment_action_count(state: GameState, player_id: int, action_id: String) -> int:
	return ActionCounts.increment_action_count(state, player_id, action_id)

static func reset_action_counts(state: GameState) -> void:
	ActionCounts.reset_action_counts(state)

# === Recruit 缺货预支 / 紧接培训约束（docs/design.md）===

static func get_immediate_train_pending_count(state: GameState, player_id: int, employee_type: String) -> int:
	return ImmediateTrainPending.get_immediate_train_pending_count(state, player_id, employee_type)

static func get_immediate_train_pending_total(state: GameState, player_id: int) -> int:
	return ImmediateTrainPending.get_immediate_train_pending_total(state, player_id)

static func has_any_immediate_train_pending(state: GameState) -> bool:
	return ImmediateTrainPending.has_any_immediate_train_pending(state)

static func add_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> void:
	ImmediateTrainPending.add_immediate_train_pending(state, player_id, employee_type)

static func consume_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> bool:
	return ImmediateTrainPending.consume_immediate_train_pending(state, player_id, employee_type)
