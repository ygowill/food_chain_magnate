# PhaseManager：回合/工作阶段状态维护（非结算规则）
# 负责：进入新回合、OrderOfBusiness 初始化、Working 子阶段计数重置、公司容量约束等状态维护。
extends RefCounted

const CompanyStructureRulesClass = preload("res://core/rules/company_structure_rules.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const IntValueParseHelpersClass = preload("res://core/utils/int_value_parse_helpers.gd")

static func start_new_round(state: GameState) -> void:
	# 重建回合状态（避免残留旧回合的计数/完成记录）
	var mandatory := {}
	var passed := {}
	for i in range(state.players.size()):
		mandatory[i] = []
		passed[i] = false
	state.round_state = {
		"mandatory_actions_completed": mandatory,
		"actions_this_round": [],
		"action_counts": {},
		"sub_phase_passed": passed
	}

static func auto_activate_reserve_employees(state: GameState) -> void:
	# 简化策略：进入重组阶段时将上一回合招募/训练得到的员工自动变为“在岗”。
	for i in range(state.players.size()):
		var player: Dictionary = state.players[i]
		assert(player.has("reserve_employees") and (player["reserve_employees"] is Array), "WorkingFlow.auto_activate_reserve_employees: player.reserve_employees 缺失或类型错误（期望 Array）")
		var reserve: Array = player["reserve_employees"]
		if reserve.is_empty():
			continue
		assert(player.has("employees") and (player["employees"] is Array), "WorkingFlow.auto_activate_reserve_employees: player.employees 缺失或类型错误（期望 Array）")
		var active: Array = player["employees"]
		active.append_array(reserve)
		player["employees"] = active
		player["reserve_employees"] = []
		_enforce_company_capacity(player)
		state.players[i] = player

static func start_order_of_business(state: GameState) -> void:
	assert(state.round_state is Dictionary, "WorkingFlow.start_order_of_business: state.round_state 类型错误（期望 Dictionary）")

	var previous_turn_order: Array[int] = []
	for pid in state.turn_order:
		previous_turn_order.append(int(pid))

	var selection := _compute_order_of_business_selection(state, previous_turn_order)
	state.selection_order = selection

	# OrderOfBusiness 阶段期间，用 turn_order 表示“选择顺序”，复用现有的 current_player_index / get_current_player_id 逻辑。
	state.turn_order = selection
	state.current_player_index = 0

	var picks: Array = []
	for _i in range(state.players.size()):
		picks.append(-1)

	state.round_state["order_of_business"] = {
		"previous_turn_order": previous_turn_order,
		"selection_order": selection,
		"picks": picks,
		"finalized": false
	}

static func reset_working_phase_state(state: GameState) -> void:
	# 进入 Working：重置子阶段动作计数并从顺序第一位开始
	state.current_player_index = 0
	reset_working_sub_phase_state(state)
	reset_sub_phase_passed(state)

static func reset_working_sub_phase_state(state: GameState) -> void:
	if state.round_state is Dictionary:
		state.round_state["action_counts"] = {}
		# Train 子阶段：记录“培训员 slot 使用情况”（用于 coach/guru 多步培训）也需随子阶段重置。
		state.round_state["train_slot_usage"] = {}
		state.round_state["train_slot_usage_instances"] = {}
		# Train 子阶段：记录“员工培训锁”（同一员工不可更换培训员继续培训，除非里程碑允许）。
		state.round_state["train_employee_locks"] = {}

static func reset_sub_phase_passed(state: GameState) -> void:
	if state == null:
		return
	if not (state.round_state is Dictionary):
		return
	var passed := {}
	for i in range(state.players.size()):
		passed[i] = false
	state.round_state["sub_phase_passed"] = passed

static func _compute_order_of_business_selection(state: GameState, previous_turn_order: Array[int]) -> Array[int]:
	var ids: Array[int] = []
	for i in range(state.players.size()):
		ids.append(i)

	var prev_index := {}
	for i in range(previous_turn_order.size()):
		prev_index[int(previous_turn_order[i])] = i

	ids.sort_custom(func(a: int, b: int) -> bool:
		var a_slots := _compute_order_of_business_empty_slots(state, state.players[a])
		var b_slots := _compute_order_of_business_empty_slots(state, state.players[b])
		if a_slots != b_slots:
			return a_slots > b_slots
		assert(prev_index.has(a), "WorkingFlow: previous_turn_order 缺少玩家: %d" % a)
		assert(prev_index.has(b), "WorkingFlow: previous_turn_order 缺少玩家: %d" % b)
		return int(prev_index[a]) < int(prev_index[b])
	)

	return ids

static func _compute_order_of_business_empty_slots(state: GameState, player: Dictionary) -> int:
	var empty_slots := CompanyStructureRulesClass.get_empty_slots(player)

	assert(player.has("milestones") and (player["milestones"] is Array), "WorkingFlow: player.milestones 缺失或类型错误（期望 Array）")
	var milestones: Array = player["milestones"]
	empty_slots += _get_turnorder_empty_slots_bonus_from_milestones(milestones)

	return empty_slots

static func _get_turnorder_empty_slots_bonus_from_milestones(milestones: Array) -> int:
	var bonus_read := MilestoneEffectQueriesClass.sum_non_negative_int_values(
		milestones,
		"turnorder_empty_slots",
		"WorkingFlow: ",
		"milestones"
	)
	assert(bonus_read.ok, str(bonus_read.error))
	return int(bonus_read.value)

static func _enforce_company_capacity(player: Dictionary) -> void:
	CompanyStructureRulesClass.enforce_capacity(player)
