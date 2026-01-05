# PhaseManager：回合/工作阶段状态维护（非结算规则）
# 负责：进入新回合、OrderOfBusiness 初始化、Working 子阶段计数重置、公司容量约束等状态维护。
extends RefCounted

const CompanyStructureRulesClass = preload("res://core/rules/company_structure_rules.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")

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

static func reset_working_sub_phase_state(state: GameState) -> void:
	state.current_player_index = 0
	if state.round_state is Dictionary:
		state.round_state["action_counts"] = {}
		reset_sub_phase_passed(state)

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
	assert(MilestoneRegistryClass.is_loaded(), "WorkingFlow: MilestoneRegistry 未初始化")

	var bonus := 0

	for i in range(milestones.size()):
		var mid_val = milestones[i]
		assert(mid_val is String, "WorkingFlow: milestones[%d] 类型错误（期望 String）" % i)
		var mid: String = str(mid_val)
		assert(not mid.is_empty(), "WorkingFlow: milestones 不应包含空字符串")

		var def_val = MilestoneRegistryClass.get_def(mid)
		assert(def_val != null, "WorkingFlow: 未知里程碑定义: %s" % mid)
		assert(def_val is MilestoneDefClass, "WorkingFlow: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			assert(eff_val is Dictionary, "WorkingFlow: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
			var eff: Dictionary = eff_val
			assert(eff.has("type") and (eff["type"] is String), "WorkingFlow: %s.effects[%d].type 缺失或类型错误（期望 String）" % [mid, e_i])
			var t: String = str(eff["type"])
			if t != "turnorder_empty_slots":
				continue

			var value_val = eff.get("value", null)
			var v := _parse_non_negative_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
			bonus += v

	return bonus

static func _parse_non_negative_int_value(value, path: String) -> int:
	if value is int:
		var i: int = int(value)
		assert(i >= 0, "%s 必须 >= 0，实际: %d" % [path, i])
		return i
	if value is float:
		var f: float = float(value)
		assert(f == int(f), "%s 必须为整数（不允许小数）" % path)
		var i2: int = int(f)
		assert(i2 >= 0, "%s 必须 >= 0，实际: %d" % [path, i2])
		return i2
	assert(false, "%s 必须为非负整数" % path)
	return 0

static func _enforce_company_capacity(player: Dictionary) -> void:
	CompanyStructureRulesClass.enforce_capacity(player)
