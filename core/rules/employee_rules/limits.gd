extends RefCounted

const EmployeeArrayHelpers = preload("res://core/rules/employee_rules/employee_array_helpers.gd")
const WorkingMultiplier = preload("res://core/rules/employee_rules/working_multiplier.gd")

static func _get_limit_from_player(
	state: GameState,
	player_id: int,
	player: Dictionary,
	capacity_getter: Callable,
	include_working_multiplier: bool
) -> int:
	var employees := EmployeeArrayHelpers.require_string_array_field(player, "employees", "player")

	var limit := 0
	for emp_id in employees:
		var def := EmployeeArrayHelpers.require_employee_def(emp_id)
		var cap := int(capacity_getter.call(def))
		if cap <= 0:
			continue
		var m := 1
		if include_working_multiplier:
			m = WorkingMultiplier.get_working_employee_multiplier(state, player_id, emp_id)
		limit += cap * m
	return limit

static func get_recruit_limit(player: Dictionary) -> int:
	# 规则：招聘次数由员工数据驱动（use:recruit + recruit_capacity）。
	return _get_limit_from_player(null, -1, player, func(def: EmployeeDef) -> int: return int(def.recruit_capacity), false)

static func get_recruit_limit_for_working(state: GameState, player_id: int) -> int:
	assert(state != null, "get_recruit_limit_for_working: state 为空")
	var player := state.get_player(player_id)
	assert(not player.is_empty(), "get_recruit_limit_for_working: player 不存在: %d" % player_id)
	return _get_limit_from_player(state, player_id, player, func(def: EmployeeDef) -> int: return int(def.recruit_capacity), true)

static func get_train_limit(player: Dictionary) -> int:
	# 规则：训练次数由“培训能力”提供（避免硬编码仅 trainer）。
	return _get_limit_from_player(null, -1, player, func(def: EmployeeDef) -> int: return int(def.train_capacity), false)

static func get_train_limit_for_working(state: GameState, player_id: int) -> int:
	assert(state != null, "get_train_limit_for_working: state 为空")
	var player := state.get_player(player_id)
	assert(not player.is_empty(), "get_train_limit_for_working: player 不存在: %d" % player_id)
	return _get_limit_from_player(state, player_id, player, func(def: EmployeeDef) -> int: return int(def.train_capacity), true)
