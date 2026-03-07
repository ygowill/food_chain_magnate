extends RefCounted

const Impl = preload("res://core/rules/employee_rules/train_slot_usage_impl.gd")

static func reset_train_slot_usage(state: GameState) -> void:
	Impl.reset_train_slot_usage(state)

static func get_train_slot_usage_round_state_key() -> String:
	return Impl.get_train_slot_usage_round_state_key()

static func try_get_max_train_steps_for_single_employee_for_working(state: GameState, player_id: int) -> Result:
	return Impl.try_get_max_train_steps_for_single_employee_for_working(state, player_id)

static func get_max_train_steps_for_single_employee_for_working(state: GameState, player_id: int) -> int:
	return Impl.get_max_train_steps_for_single_employee_for_working(state, player_id)

static func can_allocate_train_slots_for_working(
	state: GameState,
	player_id: int,
	slots_needed: int,
	preferred_trainer_id: String = "",
	preferred_instance_idx: int = -1
) -> Result:
	return Impl.can_allocate_train_slots_for_working(state, player_id, slots_needed, preferred_trainer_id, preferred_instance_idx)

static func allocate_train_slots_for_working(
	state: GameState,
	player_id: int,
	slots_needed: int,
	preferred_trainer_id: String = "",
	preferred_instance_idx: int = -1
) -> Result:
	return Impl.allocate_train_slots_for_working(state, player_id, slots_needed, preferred_trainer_id, preferred_instance_idx)
