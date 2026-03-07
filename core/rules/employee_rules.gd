# 员工规则与行动额度（M3 起步）
# 说明：通过 EmployeeRegistry 读取 JSON 定义的员工数据。
class_name EmployeeRules
extends RefCounted

const Salary = preload("res://core/rules/employee_rules/salary.gd")
const Counts = preload("res://core/rules/employee_rules/counts.gd")
const WorkingMultiplier = preload("res://core/rules/employee_rules/working_multiplier.gd")
const Limits = preload("res://core/rules/employee_rules/limits.gd")
const ActionCounts = preload("res://core/rules/employee_rules/action_counts.gd")
const ImmediateTrainPending = preload("res://core/rules/employee_rules/immediate_train_pending.gd")
const TrainSlotUsage = preload("res://core/rules/employee_rules/train_slot_usage.gd")

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

static func count_active_by_tag(player: Dictionary, tag: String) -> int:
	return Counts.count_active_by_tag(player, tag)

static func try_get_working_employee_multiplier(state: GameState, player_id: int, employee_id: String) -> Result:
	return WorkingMultiplier.try_get_working_employee_multiplier(state, player_id, employee_id)

static func get_working_employee_multiplier(state: GameState, player_id: int, employee_id: String) -> int:
	return WorkingMultiplier.get_working_employee_multiplier(state, player_id, employee_id)

static func count_active_for_working(state: GameState, player: Dictionary, player_id: int, employee_id: String) -> int:
	return Counts.count_active_for_working(state, player, player_id, employee_id)

static func count_active_by_usage_tag_for_working(state: GameState, player: Dictionary, player_id: int, usage_tag: String) -> int:
	return Counts.count_active_by_usage_tag_for_working(state, player, player_id, usage_tag)

static func get_recruit_limit(player: Dictionary) -> int:
	return Limits.get_recruit_limit(player)

static func try_get_recruit_limit_for_working(state: GameState, player_id: int) -> Result:
	return Limits.try_get_recruit_limit_for_working(state, player_id)

static func get_recruit_limit_for_working(state: GameState, player_id: int) -> int:
	return Limits.get_recruit_limit_for_working(state, player_id)

static func get_train_limit(player: Dictionary) -> int:
	return Limits.get_train_limit(player)

static func try_get_train_limit_for_working(state: GameState, player_id: int) -> Result:
	return Limits.try_get_train_limit_for_working(state, player_id)

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

static func reset_train_slot_usage(state: GameState) -> void:
	TrainSlotUsage.reset_train_slot_usage(state)

# === Recruit 缺货预支 / 紧接培训约束（docs/design.md）===

static func try_get_immediate_train_pending_count(state: GameState, player_id: int, employee_type: String) -> Result:
	return ImmediateTrainPending.try_get_immediate_train_pending_count(state, player_id, employee_type)

static func get_immediate_train_pending_count(state: GameState, player_id: int, employee_type: String) -> int:
	return ImmediateTrainPending.get_immediate_train_pending_count(state, player_id, employee_type)

static func try_get_immediate_train_pending_total(state: GameState, player_id: int) -> Result:
	return ImmediateTrainPending.try_get_immediate_train_pending_total(state, player_id)

static func get_immediate_train_pending_total(state: GameState, player_id: int) -> int:
	return ImmediateTrainPending.get_immediate_train_pending_total(state, player_id)

static func try_has_any_immediate_train_pending(state: GameState) -> Result:
	return ImmediateTrainPending.try_has_any_immediate_train_pending(state)

static func has_any_immediate_train_pending(state: GameState) -> bool:
	return ImmediateTrainPending.has_any_immediate_train_pending(state)

static func try_add_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> Result:
	return ImmediateTrainPending.try_add_immediate_train_pending(state, player_id, employee_type)

static func add_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> void:
	ImmediateTrainPending.add_immediate_train_pending(state, player_id, employee_type)

static func try_consume_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> Result:
	return ImmediateTrainPending.try_consume_immediate_train_pending(state, player_id, employee_type)

static func consume_immediate_train_pending(state: GameState, player_id: int, employee_type: String) -> bool:
	return ImmediateTrainPending.consume_immediate_train_pending(state, player_id, employee_type)

static func try_get_max_train_steps_for_single_employee_for_working(state: GameState, player_id: int) -> Result:
	return TrainSlotUsage.try_get_max_train_steps_for_single_employee_for_working(state, player_id)

static func get_max_train_steps_for_single_employee_for_working(state: GameState, player_id: int) -> int:
	return TrainSlotUsage.get_max_train_steps_for_single_employee_for_working(state, player_id)

static func can_allocate_train_slots_for_working(
	state: GameState,
	player_id: int,
	slots_needed: int,
	preferred_trainer_id: String = "",
	preferred_instance_idx: int = -1
) -> Result:
	return TrainSlotUsage.can_allocate_train_slots_for_working(state, player_id, slots_needed, preferred_trainer_id, preferred_instance_idx)

static func allocate_train_slots_for_working(
	state: GameState,
	player_id: int,
	slots_needed: int,
	preferred_trainer_id: String = "",
	preferred_instance_idx: int = -1
) -> Result:
	return TrainSlotUsage.allocate_train_slots_for_working(state, player_id, slots_needed, preferred_trainer_id, preferred_instance_idx)

static func get_train_slot_usage_round_state_key() -> String:
	return TrainSlotUsage.get_train_slot_usage_round_state_key()
