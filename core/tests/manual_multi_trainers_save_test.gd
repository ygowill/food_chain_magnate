# Manual multiple-trainers archive test
# Guards the hand-review save that combines duplicate and mixed trainer providers.
class_name ManualMultiTrainersSaveTest
extends RefCounted

const SAVE_RES_PATH := "res://testdata/saves/manual_cases/employees/multi_trainers.json"
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")
const TrainActionClass = preload("res://gameplay/actions/train_action.gd")

static func run() -> Result:
	var engine := GameEngine.new()
	var load := engine.load_from_file(ProjectSettings.globalize_path(SAVE_RES_PATH))
	if not load.ok:
		return Result.failure("load failed: %s" % load.error)
	var state := engine.get_state()
	if state == null:
		return Result.failure("load succeeded but state is null")
	if str(state.phase) != DefsClass.PHASE_WORKING or str(state.sub_phase) != DefsClass.SUB_PHASE_TRAIN:
		return Result.failure("expected Working/Train, got: %s/%s" % [str(state.phase), str(state.sub_phase)])
	if state.get_current_player_id() != 0:
		return Result.failure("expected current_player=0, got: %d" % state.get_current_player_id())

	var player := state.get_player(0)
	if bool(player.get("multi_trainer_on_one", false)):
		return Result.failure("multi_trainers save should start without multi_trainer_on_one milestone")

	var count_check := _assert_employee_counts(player)
	if not count_check.ok:
		return count_check
	var provider_check := _assert_train_providers(state)
	if not provider_check.ok:
		return provider_check
	var behavior_check := _assert_training_rule_behaviors(engine)
	if not behavior_check.ok:
		return behavior_check
	return Result.success({})

static func _assert_employee_counts(player: Dictionary) -> Result:
	var employees: Array = Array(player.get("employees", []))
	var reserve: Array = Array(player.get("reserve_employees", []))
	var expected_active := {
		"trainer": 2,
		"coach": 2,
		"guru": 1,
	}
	for emp_id in expected_active.keys():
		var actual := _count_in_array(employees, str(emp_id))
		var expected := int(expected_active[emp_id])
		if actual != expected:
			return Result.failure("expected active %s count=%d, got=%d employees=%s" % [str(emp_id), expected, actual, str(employees)])

	var expected_reserve := {
		"marketing_trainee": 3,
		"management_trainee": 2,
		"kitchen_trainee": 2,
	}
	for emp_id2 in expected_reserve.keys():
		var actual2 := _count_in_array(reserve, str(emp_id2))
		var expected2 := int(expected_reserve[emp_id2])
		if actual2 != expected2:
			return Result.failure("expected reserve %s count=%d, got=%d reserve=%s" % [str(emp_id2), expected2, actual2, str(reserve)])
	return Result.success()

static func _assert_train_providers(state: GameState) -> Result:
	var providers_read := EmployeeRulesClass.try_get_trainers_for_working(state, 0)
	if not providers_read.ok:
		return providers_read
	var providers: Array = providers_read.value
	var summary := {}
	for provider_val in providers:
		if not (provider_val is Dictionary):
			return Result.failure("provider is not Dictionary: %s" % str(provider_val))
		var p: Dictionary = provider_val
		var emp_id := str(p.get("employee_type", "")).strip_edges()
		if emp_id.is_empty():
			return Result.failure("provider missing employee_type: %s" % str(p))
		if not summary.has(emp_id):
			summary[emp_id] = []
		(summary[emp_id] as Array).append(int(p.get("remaining", -1)))

	var expected := {
		"trainer": [1, 1],
		"coach": [2, 2],
		"guru": [3],
	}
	for emp_id2 in expected.keys():
		var actual_arr: Array = Array(summary.get(emp_id2, []))
		actual_arr.sort()
		var expected_arr: Array = Array(expected[emp_id2])
		expected_arr.sort()
		if actual_arr != expected_arr:
			return Result.failure("provider remaining mismatch for %s expected=%s actual=%s providers=%s" % [str(emp_id2), str(expected_arr), str(actual_arr), str(providers)])

	var train_limit_read := EmployeeRulesClass.try_get_train_limit_for_working(state, 0)
	if not train_limit_read.ok:
		return train_limit_read
	if int(train_limit_read.value) != 9:
		return Result.failure("expected train_limit=9 (2 trainers + 2 coaches + 1 guru), got=%s" % str(train_limit_read.value))

	var max_steps_read := EmployeeRulesClass.try_get_max_train_steps_for_single_employee_for_working(state, 0)
	if not max_steps_read.ok:
		return max_steps_read
	if int(max_steps_read.value) != 3:
		return Result.failure("expected max steps for one employee=3 because guru is available, got=%s" % str(max_steps_read.value))
	return Result.success()

static func _assert_training_rule_behaviors(engine: GameEngine) -> Result:
	var state := engine.get_state()
	var trainer_ids_read := StaffStateClass.find_staff_ids_by_employee_type(state, 0, "trainer", ["employees"])
	if not trainer_ids_read.ok:
		return trainer_ids_read
	var trainer_ids: Array = trainer_ids_read.value
	if trainer_ids.size() < 2:
		return Result.failure("expected at least two trainer staff ids, got=%s" % str(trainer_ids))
	trainer_ids.sort()

	var marketing_ids_read := StaffStateClass.find_staff_ids_by_employee_type(state, 0, "marketing_trainee", ["reserve_employees"])
	if not marketing_ids_read.ok:
		return marketing_ids_read
	var marketing_ids: Array = marketing_ids_read.value
	if marketing_ids.size() < 3:
		return Result.failure("expected at least three marketing_trainee staff ids, got=%s" % str(marketing_ids))
	marketing_ids.sort()

	var t1 := engine.execute_command(Command.create("train", 0, {
		"trainer_staff_id": int(trainer_ids[0]),
		"source_staff_id": int(marketing_ids[0]),
		"from_employee": "marketing_trainee",
		"to_employee": "campaign_manager",
	}))
	if not t1.ok:
		return Result.failure("first explicit trainer step should succeed: %s" % t1.error)

	var blocked := engine.execute_command(Command.create("train", 0, {
		"trainer_staff_id": int(trainer_ids[1]),
		"source_staff_id": int(marketing_ids[0]),
		"from_employee": "campaign_manager",
		"to_employee": "brand_manager",
	}))
	if blocked.ok:
		return Result.failure("without milestone, another trainer should not continue training the same staff card")

	var coach_ids_read := StaffStateClass.find_staff_ids_by_employee_type(state, 0, "coach", ["employees"])
	if not coach_ids_read.ok:
		return coach_ids_read
	var coach_ids: Array = coach_ids_read.value
	if coach_ids.is_empty():
		return Result.failure("expected coach staff ids")
	coach_ids.sort()

	var coach_multi := engine.execute_command(Command.create("train", 0, {
		"trainer_staff_id": int(coach_ids[0]),
		"source_staff_id": int(marketing_ids[1]),
		"from_employee": "marketing_trainee",
		"to_employee": "brand_manager",
	}))
	if not coach_multi.ok:
		return Result.failure("coach should allow one staff card to advance two levels: %s" % coach_multi.error)

	var guru_ids_read := StaffStateClass.find_staff_ids_by_employee_type(state, 0, "guru", ["employees"])
	if not guru_ids_read.ok:
		return guru_ids_read
	var guru_ids: Array = guru_ids_read.value
	if guru_ids.is_empty():
		return Result.failure("expected guru staff id")
	guru_ids.sort()

	var management_ids_read := StaffStateClass.find_staff_ids_by_employee_type(state, 0, "management_trainee", ["reserve_employees"])
	if not management_ids_read.ok:
		return management_ids_read
	var management_ids: Array = management_ids_read.value
	if management_ids.is_empty():
		return Result.failure("expected management_trainee staff ids")
	management_ids.sort()

	var guru_multi := engine.execute_command(Command.create("train", 0, {
		"trainer_staff_id": int(guru_ids[0]),
		"source_staff_id": int(management_ids[0]),
		"from_employee": "management_trainee",
		"to_employee": "senior_vice_president",
	}))
	if not guru_multi.ok:
		return Result.failure("guru should allow one staff card to advance three levels: %s" % guru_multi.error)

	return Result.success()

static func _count_in_array(arr: Array, value: String) -> int:
	var count := 0
	for item in arr:
		if item is String and str(item) == value:
			count += 1
	return count
